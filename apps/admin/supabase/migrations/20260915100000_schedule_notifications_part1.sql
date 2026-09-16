-- Schedule-based push notifications for PASAKAY (drivers + passengers).
-- Availability remains shift-assignment based (3 global blocks), Asia/Manila.

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
create table if not exists public.app_notification_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

insert into public.app_notification_settings (key, value) values
  ('shift_reminder_lead_minutes', '30'),
  ('timezone', 'Asia/Manila')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Extend notifications for typed events + deep link metadata
-- ---------------------------------------------------------------------------
alter table public.notifications
  add column if not exists event_type text,
  add column if not exists title text,
  add column if not exists related_driver_id uuid,
  add column if not exists related_shift_id uuid,
  add column if not exists dedupe_key text,
  add column if not exists data jsonb not null default '{}'::jsonb;

create unique index if not exists notifications_dedupe_key_uidx
  on public.notifications (dedupe_key)
  where dedupe_key is not null;

create index if not exists notifications_recipient_date_idx
  on public.notifications (recipient_id, date_sent desc);

-- ---------------------------------------------------------------------------
-- Idempotency ledger (survives even if notification row is deleted)
-- ---------------------------------------------------------------------------
create table if not exists public.notification_event_log (
  dedupe_key text primary key,
  event_type text not null,
  recipient_id uuid not null,
  related_driver_id uuid,
  related_shift_id uuid,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Preferences (defaults = enabled)
-- ---------------------------------------------------------------------------
create table if not exists public.driver_notification_preferences (
  driver_id uuid primary key references public.drivers (driver_id) on delete cascade,
  schedule_reminders boolean not null default true,
  schedule_changes boolean not null default true,
  availability_changes boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.commuter_notification_preferences (
  commuter_id uuid primary key references public.commuters (commuter_id) on delete cascade,
  followed_driver_availability boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.driver_notification_preferences enable row level security;
alter table public.commuter_notification_preferences enable row level security;

drop policy if exists "driver_prefs_own" on public.driver_notification_preferences;
create policy "driver_prefs_own" on public.driver_notification_preferences
  for all to authenticated
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

drop policy if exists "commuter_prefs_own" on public.commuter_notification_preferences;
create policy "commuter_prefs_own" on public.commuter_notification_preferences
  for all to authenticated
  using (commuter_id = auth.uid())
  with check (commuter_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Follow / favorite drivers
-- ---------------------------------------------------------------------------
create table if not exists public.commuter_followed_drivers (
  commuter_id uuid not null references public.commuters (commuter_id) on delete cascade,
  driver_id uuid not null references public.drivers (driver_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (commuter_id, driver_id)
);

create index if not exists commuter_followed_drivers_driver_idx
  on public.commuter_followed_drivers (driver_id);

alter table public.commuter_followed_drivers enable row level security;

drop policy if exists "follows_select_own" on public.commuter_followed_drivers;
create policy "follows_select_own" on public.commuter_followed_drivers
  for select to authenticated
  using (commuter_id = auth.uid());

drop policy if exists "follows_insert_own" on public.commuter_followed_drivers;
create policy "follows_insert_own" on public.commuter_followed_drivers
  for insert to authenticated
  with check (commuter_id = auth.uid());

drop policy if exists "follows_delete_own" on public.commuter_followed_drivers;
create policy "follows_delete_own" on public.commuter_followed_drivers
  for delete to authenticated
  using (commuter_id = auth.uid());

-- Followers may also be read by service role for fan-out (bypasses RLS).

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.notif_setting(p_key text, p_default text)
returns text
language sql
stable
set search_path = public
as $$
  select coalesce(
    (select value from public.app_notification_settings where key = p_key),
    p_default
  );
$$;

create or replace function public.manila_now()
returns timestamp
language sql
stable
as $$
  select (timezone(public.notif_setting('timezone', 'Asia/Manila'), now()))::timestamp;
$$;

create or replace function public.manila_today()
returns date
language sql
stable
as $$
  select (public.manila_now())::date;
$$;

create or replace function public.shift_display_name(p_shift public.shifts)
returns text
language plpgsql
stable
as $$
begin
  if nullif(trim(coalesce(p_shift.label, '')), '') is not null then
    return trim(p_shift.label);
  end if;
  return to_char(p_shift.shift_start_time, 'HH12:MI AM')
    || ' - '
    || to_char(p_shift.shift_end_time, 'HH12:MI AM');
end;
$$;

create or replace function public.driver_pref_enabled(
  p_driver_id uuid,
  p_category text
) returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row public.driver_notification_preferences%rowtype;
begin
  select * into v_row from public.driver_notification_preferences where driver_id = p_driver_id;
  if not found then
    return true;
  end if;
  return case p_category
    when 'schedule_reminders' then v_row.schedule_reminders
    when 'schedule_changes' then v_row.schedule_changes
    when 'availability_changes' then v_row.availability_changes
    else true
  end;
end;
$$;

create or replace function public.commuter_pref_enabled(
  p_commuter_id uuid,
  p_category text
) returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row public.commuter_notification_preferences%rowtype;
begin
  select * into v_row
  from public.commuter_notification_preferences
  where commuter_id = p_commuter_id;
  if not found then
    return true;
  end if;
  return case p_category
    when 'followed_driver_availability' then v_row.followed_driver_availability
    else true
  end;
end;
$$;

-- Core emit: idempotent insert + optional skip by prefs
create or replace function public.emit_notification(
  p_recipient_id uuid,
  p_recipient_type public.user_role,
  p_event_type text,
  p_title text,
  p_body text,
  p_dedupe_key text,
  p_related_driver_id uuid default null,
  p_related_shift_id uuid default null,
  p_data jsonb default '{}'::jsonb,
  p_pref_category text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_recipient_id is null or nullif(trim(p_body), '') is null then
    return null;
  end if;

  if p_pref_category is not null then
    if p_recipient_type = 'driver'
       and not public.driver_pref_enabled(p_recipient_id, p_pref_category) then
      return null;
    end if;
    if p_recipient_type = 'commuter'
       and not public.commuter_pref_enabled(p_recipient_id, p_pref_category) then
      return null;
    end if;
  end if;

  if p_dedupe_key is not null then
    begin
      insert into public.notification_event_log (
        dedupe_key, event_type, recipient_id, related_driver_id, related_shift_id
      ) values (
        p_dedupe_key, p_event_type, p_recipient_id, p_related_driver_id, p_related_shift_id
      );
    exception
      when unique_violation then
        return null; -- already emitted
    end;
  end if;

  insert into public.notifications (
    recipient_id,
    recipient_type,
    message_content,
    event_type,
    title,
    related_driver_id,
    related_shift_id,
    dedupe_key,
    data
  ) values (
    p_recipient_id,
    p_recipient_type,
    p_body,
    p_event_type,
    coalesce(nullif(trim(p_title), ''), 'Pasakay'),
    p_related_driver_id,
    p_related_shift_id,
    p_dedupe_key,
    coalesce(p_data, '{}'::jsonb)
  )
  returning notification_id into v_id;

  return v_id;
end;
$$;

revoke all on function public.emit_notification(
  uuid, public.user_role, text, text, text, text, uuid, uuid, jsonb, text
) from public;
grant execute on function public.emit_notification(
  uuid, public.user_role, text, text, text, text, uuid, uuid, jsonb, text
) to service_role, authenticated;

-- Back-compat wrappers
create or replace function public.notify_driver(p_driver_id uuid, p_message text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.emit_notification(
    p_driver_id, 'driver', 'SYSTEM', 'Pasakay', p_message, null, p_driver_id, null,
    jsonb_build_object('route', '/notifications'), null
  );
end;
$$;

create or replace function public.notify_commuter(p_commuter_id uuid, p_message text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.emit_notification(
    p_commuter_id, 'commuter', 'SYSTEM', 'Pasakay', p_message, null, null, null,
    '{}'::jsonb, null
  );
end;
$$;
