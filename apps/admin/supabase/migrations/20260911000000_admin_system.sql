-- PASAKAY system admin
-- Supports the 7 scoped admin features. Limitations are enforced here, not only in the UI:
--   * license checks are a manual admin flag (no LTFRB / government lookup)
--   * no audit/change-log table
--   * terminals are a text list (no coordinates)
--   * deleting a terminal that still has drivers is blocked
--   * only the 3 existing shift rows may be edited (no insert/delete)
--   * no commuter blacklist distinct from suspend/deactivate
--   * reviews: hide or delete only (no report queue, no automated filter)
--   * device logs are select-only
--   * privacy requests are admin-logged (no self-service). Deletion anonymizes and
--     may be retained for the study.

create extension if not exists pgcrypto with schema extensions;

do $$ begin
  create type public.account_status as enum (
    'pending_verification',
    'active',
    'suspended',
    'deactivated'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.privacy_request_type as enum ('access', 'correction', 'deletion');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.privacy_request_status as enum (
    'received',
    'in_progress',
    'completed',
    'denied',
    'retained'
  );
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Profile columns the admin panel needs
-- ---------------------------------------------------------------------------
alter table public.drivers
  add column if not exists license_verified boolean not null default false,
  add column if not exists license_verified_at timestamptz,
  add column if not exists license_verified_by uuid,
  add column if not exists status public.account_status not null default 'pending_verification',
  add column if not exists status_reason text;

comment on column public.drivers.license_verified is
  'Manual visual check by a system admin. Not validated against LTFRB or any external database.';

alter table public.drivers
  alter column is_active set default false;

-- Drivers already operating before this migration stay usable.
update public.drivers
set
  license_verified = true,
  license_verified_at = coalesce(license_verified_at, created_at),
  status = case
    when is_active then 'active'::public.account_status
    else 'deactivated'::public.account_status
  end
where status = 'pending_verification';

alter table public.commuters
  add column if not exists status public.account_status not null default 'active',
  add column if not exists status_reason text;

alter table public.reviews
  add column if not exists is_hidden boolean not null default false,
  add column if not exists hidden_at timestamptz,
  add column if not exists hidden_by uuid,
  add column if not exists moderation_note text;

do $$ begin
  alter table public.drivers
    add constraint drivers_is_active_matches_status
    check (is_active = (status = 'active'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.drivers
    add constraint drivers_active_requires_license
    check (status <> 'active' or license_verified);
exception when duplicate_object then null; end $$;

create table if not exists public.admins (
  admin_id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  email text not null unique,
  username text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.privacy_requests (
  request_id uuid primary key default gen_random_uuid(),
  subject_user_id uuid,
  subject_role public.user_role,
  subject_name text not null,
  subject_contact text,
  request_type public.privacy_request_type not null,
  status public.privacy_request_status not null default 'received',
  details text,
  correction_payload jsonb,
  admin_notes text,
  retention_applies boolean not null default false,
  retention_reason text,
  handled_by uuid references public.admins (admin_id),
  received_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists drivers_status_idx on public.drivers (status);
create index if not exists commuters_status_idx on public.commuters (status);
create index if not exists reviews_hidden_idx on public.reviews (is_hidden, date_created desc);
create index if not exists device_logs_access_idx on public.device_logs (access_datetime desc);
create index if not exists privacy_requests_status_idx
  on public.privacy_requests (status, received_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists admins_set_updated_at on public.admins;
create trigger admins_set_updated_at
  before update on public.admins
  for each row execute function public.set_updated_at();

drop trigger if exists privacy_requests_set_updated_at on public.privacy_requests;
create trigger privacy_requests_set_updated_at
  before update on public.privacy_requests
  for each row execute function public.set_updated_at();

drop trigger if exists commuters_set_updated_at on public.commuters;
create trigger commuters_set_updated_at
  before update on public.commuters
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Auth helpers (not callable by the client)
-- ---------------------------------------------------------------------------
create or replace function public.is_system_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admins
    where admin_id = auth.uid()
      and is_active = true
  );
$$;

create or replace function public.assert_system_admin()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_system_admin() then
    raise exception 'System admin access required';
  end if;
end;
$$;

create or replace function public.normalize_ph_mobile(p_input text)
returns text
language plpgsql
immutable
as $$
declare
  digits text;
begin
  digits := regexp_replace(coalesce(p_input, ''), '\D', '', 'g');
  if digits like '63%' and length(digits) >= 12 then
    digits := '0' || substring(digits from 3);
  end if;
  return digits;
end;
$$;

create or replace function public.provision_auth_user(
  p_user_id uuid,
  p_email text,
  p_password text,
  p_full_name text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_email text := lower(trim(p_email));
begin
  if v_email is null or v_email = '' then
    raise exception 'Email is required';
  end if;
  if p_password is null or length(p_password) < 8 then
    raise exception 'Password must be at least 8 characters';
  end if;
  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'An account with this email already exists';
  end if;

  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change,
    email_change_token_new,
    email_change_token_current,
    is_sso_user,
    is_anonymous
  ) values (
    '00000000-0000-0000-0000-000000000000',
    p_user_id,
    'authenticated',
    'authenticated',
    v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', p_full_name),
    now(),
    now(),
    '',
    '',
    '',
    '',
    '',
    false,
    false
  );

  insert into auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    p_user_id,
    jsonb_build_object(
      'sub', p_user_id::text,
      'email', v_email,
      'email_verified', true
    ),
    'email',
    p_user_id::text,
    now(),
    now(),
    now()
  );

  return p_user_id;
end;
$$;

revoke all on function public.provision_auth_user(uuid, text, text, text) from public, anon, authenticated;

create or replace function public.set_auth_login_allowed(p_user_id uuid, p_allowed boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  update auth.users
  set
    banned_until = case when p_allowed then null else 'infinity'::timestamptz end,
    updated_at = now()
  where id = p_user_id;
end;
$$;

revoke all on function public.set_auth_login_allowed(uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Seed system admin
-- Email:    admin@pasakay.app
-- Username: sysadmin
-- Password: PasakayAdmin#2026
-- ---------------------------------------------------------------------------
do $$
declare
  v_id uuid := 'b0000000-0000-4000-8000-000000000001';
begin
  if not exists (select 1 from auth.users where email = 'admin@pasakay.app') then
    perform public.provision_auth_user(
      v_id,
      'admin@pasakay.app',
      'PasakayAdmin#2026',
      'PASAKAY System Admin'
    );
  end if;

  insert into public.admins (admin_id, full_name, email, username)
  select u.id, 'PASAKAY System Admin', 'admin@pasakay.app', 'sysadmin'
  from auth.users u
  where u.email = 'admin@pasakay.app'
  on conflict (admin_id) do update
    set
      full_name = excluded.full_name,
      email = excluded.email,
      username = excluded.username,
      is_active = true;
end $$;

-- ---------------------------------------------------------------------------
-- Drivers
-- ---------------------------------------------------------------------------
create or replace function public.admin_create_driver(
  p_full_name text,
  p_contact_number text,
  p_license_number text,
  p_plate_number text,
  p_toda_number text,
  p_username text,
  p_password text,
  p_terminal_id uuid,
  p_shift_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_mobile text := public.normalize_ph_mobile(p_contact_number);
  v_username text := nullif(trim(coalesce(p_username, '')), '');
  v_license text := nullif(trim(coalesce(p_license_number, '')), '');
  v_plate text := nullif(upper(trim(coalesce(p_plate_number, ''))), '');
begin
  perform public.assert_system_admin();

  if nullif(trim(coalesce(p_full_name, '')), '') is null then
    raise exception 'Full name is required';
  end if;
  if v_mobile = '' or length(v_mobile) < 10 then
    raise exception 'A valid contact number is required';
  end if;
  if v_license is null then
    raise exception 'License number is required';
  end if;
  if v_plate is null then
    raise exception 'Plate number is required';
  end if;
  if not exists (select 1 from public.terminals where terminal_id = p_terminal_id) then
    raise exception 'Select a terminal';
  end if;
  if not exists (select 1 from public.shifts where shift_id = p_shift_id) then
    raise exception 'Select one of the 3 shifts';
  end if;

  v_username := coalesce(v_username, v_mobile);
  if exists (select 1 from public.drivers where username = v_username) then
    raise exception 'Username is already taken';
  end if;

  -- Login email matches the driver app ({mobile}@pasakay.driver).
  -- Account stays pending until an admin visually verifies the license.
  perform public.provision_auth_user(
    v_id,
    v_mobile || '@pasakay.driver',
    p_password,
    trim(p_full_name)
  );
  perform public.set_auth_login_allowed(v_id, false);

  insert into public.drivers (
    driver_id,
    full_name,
    contact_number,
    driver_license_number,
    plate_number,
    toda_number,
    username,
    terminal_id,
    shift_id,
    is_active,
    license_verified,
    status
  ) values (
    v_id,
    trim(p_full_name),
    v_mobile,
    v_license,
    v_plate,
    nullif(trim(coalesce(p_toda_number, '')), ''),
    v_username,
    p_terminal_id,
    p_shift_id,
    false,
    false,
    'pending_verification'
  );

  return v_id;
end;
$$;

create or replace function public.admin_update_driver(
  p_driver_id uuid,
  p_full_name text,
  p_contact_number text,
  p_license_number text,
  p_plate_number text,
  p_toda_number text,
  p_username text,
  p_terminal_id uuid,
  p_shift_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_mobile text := public.normalize_ph_mobile(p_contact_number);
  v_username text := nullif(trim(coalesce(p_username, '')), '');
  v_license text := nullif(trim(coalesce(p_license_number, '')), '');
  v_plate text := nullif(upper(trim(coalesce(p_plate_number, ''))), '');
  v_old_license text;
  v_old_mobile text;
  v_auth_email text;
begin
  perform public.assert_system_admin();

  select driver_license_number, contact_number
  into v_old_license, v_old_mobile
  from public.drivers
  where driver_id = p_driver_id;

  if not found then
    raise exception 'Driver not found';
  end if;
  if nullif(trim(coalesce(p_full_name, '')), '') is null then
    raise exception 'Full name is required';
  end if;
  if v_mobile = '' or length(v_mobile) < 10 then
    raise exception 'A valid contact number is required';
  end if;
  if v_license is null then
    raise exception 'License number is required';
  end if;
  if v_plate is null then
    raise exception 'Plate number is required';
  end if;
  if not exists (select 1 from public.terminals where terminal_id = p_terminal_id) then
    raise exception 'Select a terminal';
  end if;
  if not exists (select 1 from public.shifts where shift_id = p_shift_id) then
    raise exception 'Select one of the 3 shifts';
  end if;

  v_username := coalesce(v_username, v_mobile);
  if exists (
    select 1 from public.drivers
    where username = v_username and driver_id <> p_driver_id
  ) then
    raise exception 'Username is already taken';
  end if;

  v_auth_email := v_mobile || '@pasakay.driver';
  if v_mobile <> v_old_mobile then
    if exists (
      select 1 from auth.users
      where lower(email) = v_auth_email and id <> p_driver_id
    ) then
      raise exception 'That contact number is already used for login';
    end if;
    update auth.users
    set email = v_auth_email, updated_at = now()
    where id = p_driver_id;
    update auth.identities
    set
      identity_data = jsonb_set(
        coalesce(identity_data, '{}'::jsonb),
        '{email}',
        to_jsonb(v_auth_email)
      ),
      updated_at = now()
    where user_id = p_driver_id and provider = 'email';
  end if;

  update public.drivers
  set
    full_name = trim(p_full_name),
    contact_number = v_mobile,
    driver_license_number = v_license,
    plate_number = v_plate,
    toda_number = nullif(trim(coalesce(p_toda_number, '')), ''),
    username = v_username,
    terminal_id = p_terminal_id,
    shift_id = p_shift_id,
    -- A changed license must be visually checked again before the account can stay active.
    license_verified = case when v_license = v_old_license then license_verified else false end,
    license_verified_at = case when v_license = v_old_license then license_verified_at else null end,
    license_verified_by = case when v_license = v_old_license then license_verified_by else null end,
    status = case
      when v_license = v_old_license then status
      else 'pending_verification'::public.account_status
    end,
    is_active = case
      when v_license = v_old_license then is_active
      else false
    end,
    status_reason = case
      when v_license = v_old_license then status_reason
      else 'License number changed. Visual verification required before activation.'
    end,
    updated_at = now()
  where driver_id = p_driver_id;

  if v_license <> v_old_license then
    perform public.set_auth_login_allowed(p_driver_id, false);
  end if;
end;
$$;

create or replace function public.admin_verify_driver_license(
  p_driver_id uuid,
  p_verified boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_system_admin();

  if not exists (select 1 from public.drivers where driver_id = p_driver_id) then
    raise exception 'Driver not found';
  end if;

  if p_verified then
    update public.drivers
    set
      license_verified = true,
      license_verified_at = now(),
      license_verified_by = auth.uid()
    where driver_id = p_driver_id;
  else
    update public.drivers
    set
      license_verified = false,
      license_verified_at = null,
      license_verified_by = null,
      status = 'pending_verification',
      is_active = false,
      status_reason = 'License verification cleared. Visual check required before activation.'
    where driver_id = p_driver_id;
    perform public.set_auth_login_allowed(p_driver_id, false);
  end if;
end;
$$;

create or replace function public.admin_set_driver_status(
  p_driver_id uuid,
  p_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_verified boolean;
  v_status public.account_status;
begin
  perform public.assert_system_admin();

  begin
    v_status := p_status::public.account_status;
  exception when invalid_text_representation then
    raise exception 'Unknown account status';
  end;

  select license_verified into v_verified
  from public.drivers
  where driver_id = p_driver_id;

  if not found then
    raise exception 'Driver not found';
  end if;

  if v_status = 'active' and not coalesce(v_verified, false) then
    raise exception 'License must be visually verified before activation. This is a manual check only — PASAKAY does not validate against a government database.';
  end if;

  if v_status in ('suspended', 'deactivated') and nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required to suspend or deactivate a driver';
  end if;

  update public.drivers
  set
    status = v_status,
    is_active = (v_status = 'active'),
    status_reason = nullif(trim(coalesce(p_reason, '')), ''),
    updated_at = now()
  where driver_id = p_driver_id;

  perform public.set_auth_login_allowed(p_driver_id, v_status = 'active');
end;
$$;

create or replace function public.admin_reset_driver_password(
  p_driver_id uuid,
  p_password text
)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
begin
  perform public.assert_system_admin();
  if p_password is null or length(p_password) < 8 then
    raise exception 'Password must be at least 8 characters';
  end if;
  if not exists (select 1 from public.drivers where driver_id = p_driver_id) then
    raise exception 'Driver not found';
  end if;

  update auth.users
  set
    encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
    updated_at = now()
  where id = p_driver_id;
end;
$$;

create or replace function public.admin_delete_driver(p_driver_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  perform public.assert_system_admin();
  if not exists (select 1 from public.drivers where driver_id = p_driver_id) then
    raise exception 'Driver not found';
  end if;
  -- Removes the login and profile. Reviews cascade. No change log is kept.
  delete from auth.users where id = p_driver_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Terminals (plain-text list; block delete while drivers are assigned)
-- ---------------------------------------------------------------------------
create or replace function public.admin_create_terminal(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_id uuid;
begin
  perform public.assert_system_admin();
  if v_name is null then
    raise exception 'Terminal name is required';
  end if;

  insert into public.terminals (terminal_name)
  values (v_name)
  returning terminal_id into v_id;
  return v_id;
exception
  when unique_violation then
    raise exception 'A terminal with that name already exists';
end;
$$;

create or replace function public.admin_update_terminal(p_terminal_id uuid, p_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := nullif(trim(coalesce(p_name, '')), '');
begin
  perform public.assert_system_admin();
  if v_name is null then
    raise exception 'Terminal name is required';
  end if;
  if not exists (select 1 from public.terminals where terminal_id = p_terminal_id) then
    raise exception 'Terminal not found';
  end if;

  update public.terminals
  set terminal_name = v_name
  where terminal_id = p_terminal_id;
exception
  when unique_violation then
    raise exception 'A terminal with that name already exists';
end;
$$;

create or replace function public.admin_delete_terminal(p_terminal_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  perform public.assert_system_admin();
  if not exists (select 1 from public.terminals where terminal_id = p_terminal_id) then
    raise exception 'Terminal not found';
  end if;

  select count(*) into v_count
  from public.drivers
  where terminal_id = p_terminal_id
     or current_terminal_id = p_terminal_id;

  if v_count > 0 then
    raise exception 'Cannot delete this terminal while % driver(s) are still assigned to it. Reassign them first.', v_count;
  end if;

  delete from public.terminals where terminal_id = p_terminal_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Shifts: edit the 3 existing blocks only. No create/delete.
-- ---------------------------------------------------------------------------
create or replace function public.admin_update_shift(
  p_shift_id uuid,
  p_label text,
  p_start_time text,
  p_end_time text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_label text := nullif(trim(coalesce(p_label, '')), '');
  v_start time;
  v_end time;
  v_warning text := '';
  r record;
  other_start time;
  other_end time;
begin
  perform public.assert_system_admin();
  if (select count(*) from public.shifts) <> 3 then
    raise exception 'Shift management only supports the 3 predefined blocks';
  end if;
  if not exists (select 1 from public.shifts where shift_id = p_shift_id) then
    raise exception 'Shift not found';
  end if;
  if v_label is null then
    raise exception 'Shift label is required';
  end if;

  begin
    v_start := p_start_time::time;
    v_end := p_end_time::time;
  exception when others then
    raise exception 'Start and end must be valid times (HH:MM)';
  end;

  if v_start = v_end then
    raise exception 'Start and end time cannot be the same';
  end if;

  update public.shifts
  set
    label = v_label,
    shift_start_time = v_start,
    shift_end_time = v_end
  where shift_id = p_shift_id;

  -- Warn when the 3 blocks overlap. Adjacent boundaries (end = next start) are allowed.
  -- This does not track attendance — it only checks the assigned windows.
  for r in
    select shift_id, label, shift_start_time, shift_end_time
    from public.shifts
    where shift_id <> p_shift_id
  loop
    other_start := r.shift_start_time;
    other_end := r.shift_end_time;
    if public.shift_windows_overlap(v_start, v_end, other_start, other_end) then
      v_warning := v_warning || case when v_warning = '' then '' else ' ' end
        || 'Overlaps "' || r.label || '".';
    end if;
  end loop;

  if v_warning = '' then
    return null;
  end if;
  return 'Saved, but this window overlaps another shift. A driver can still only be assigned to one shift. ' || v_warning;
exception
  when unique_violation then
    raise exception 'Another shift already uses that start and end time';
end;
$$;

create or replace function public.shift_windows_overlap(
  a_start time,
  a_end time,
  b_start time,
  b_end time
)
returns boolean
language sql
immutable
as $$
  with pieces as (
    select 'a'::text as src, a_start as s,
      case when a_end > a_start then a_end else '24:00:00'::time end as e
    union all
    select 'a', '00:00:00'::time, a_end
    where a_end <= a_start and a_end > '00:00:00'::time
    union all
    select 'b', b_start,
      case when b_end > b_start then b_end else '24:00:00'::time end
    union all
    select 'b', '00:00:00'::time, b_end
    where b_end <= b_start and b_end > '00:00:00'::time
  )
  select exists (
    select 1
    from pieces a
    join pieces b on a.src = 'a' and b.src = 'b'
    where a.s < b.e and b.s < a.e
  );
$$;

-- ---------------------------------------------------------------------------
-- Commuters: view + suspend/deactivate. No blacklist. No message content.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_commuter_status(
  p_commuter_id uuid,
  p_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status public.account_status;
begin
  perform public.assert_system_admin();

  begin
    v_status := p_status::public.account_status;
  exception when invalid_text_representation then
    raise exception 'Unknown account status';
  end;

  if v_status = 'pending_verification' then
    raise exception 'Commuter accounts do not use license verification';
  end if;
  if not exists (select 1 from public.commuters where commuter_id = p_commuter_id) then
    raise exception 'Commuter not found';
  end if;
  if v_status in ('suspended', 'deactivated') and nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required to suspend or deactivate a commuter';
  end if;

  update public.commuters
  set
    status = v_status,
    status_reason = nullif(trim(coalesce(p_reason, '')), '')
  where commuter_id = p_commuter_id;

  -- Suspend and deactivate both block login. Reactivate is allowed (no permanent ban).
  perform public.set_auth_login_allowed(p_commuter_id, v_status = 'active');
end;
$$;

-- ---------------------------------------------------------------------------
-- Reviews: manual hide or remove. No flagging queue.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_review_hidden(
  p_review_id uuid,
  p_hidden boolean,
  p_note text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_system_admin();
  if not exists (select 1 from public.reviews where review_id = p_review_id) then
    raise exception 'Review not found';
  end if;

  update public.reviews
  set
    is_hidden = p_hidden,
    hidden_at = case when p_hidden then now() else null end,
    hidden_by = case when p_hidden then auth.uid() else null end,
    moderation_note = nullif(trim(coalesce(p_note, '')), '')
  where review_id = p_review_id;
end;
$$;

create or replace function public.admin_delete_review(p_review_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_system_admin();
  delete from public.reviews where review_id = p_review_id;
  if not found then
    raise exception 'Review not found';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Privacy requests (admin intake only)
-- ---------------------------------------------------------------------------
create or replace function public.admin_log_privacy_request(
  p_subject_user_id uuid,
  p_subject_role text,
  p_subject_name text,
  p_subject_contact text,
  p_request_type text,
  p_details text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_role public.user_role;
  v_type public.privacy_request_type;
  v_name text := nullif(trim(coalesce(p_subject_name, '')), '');
begin
  perform public.assert_system_admin();
  if v_name is null then
    raise exception 'Subject name is required';
  end if;

  begin
    v_type := p_request_type::public.privacy_request_type;
  exception when invalid_text_representation then
    raise exception 'Request type must be access, correction, or deletion';
  end;

  if nullif(trim(coalesce(p_subject_role, '')), '') is not null then
    begin
      v_role := p_subject_role::public.user_role;
    exception when invalid_text_representation then
      raise exception 'Subject role must be commuter or driver';
    end;
  end if;

  insert into public.privacy_requests (
    subject_user_id,
    subject_role,
    subject_name,
    subject_contact,
    request_type,
    details,
    handled_by,
    status
  ) values (
    p_subject_user_id,
    v_role,
    v_name,
    nullif(trim(coalesce(p_subject_contact, '')), ''),
    v_type,
    nullif(trim(coalesce(p_details, '')), ''),
    auth.uid(),
    'received'
  )
  returning request_id into v_id;

  return v_id;
end;
$$;

create or replace function public.admin_set_privacy_status(
  p_request_id uuid,
  p_status text,
  p_notes text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status public.privacy_request_status;
begin
  perform public.assert_system_admin();
  begin
    v_status := p_status::public.privacy_request_status;
  exception when invalid_text_representation then
    raise exception 'Unknown request status';
  end;

  update public.privacy_requests
  set
    status = v_status,
    admin_notes = coalesce(nullif(trim(coalesce(p_notes, '')), ''), admin_notes),
    handled_by = auth.uid(),
    resolved_at = case
      when v_status in ('completed', 'denied', 'retained') then now()
      else resolved_at
    end
  where request_id = p_request_id;

  if not found then
    raise exception 'Privacy request not found';
  end if;
end;
$$;

create or replace function public.admin_subject_snapshot(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.privacy_requests%rowtype;
  v_profile jsonb;
  v_reviews jsonb;
  v_logs jsonb;
begin
  perform public.assert_system_admin();

  select * into v_req
  from public.privacy_requests
  where request_id = p_request_id;

  if not found then
    raise exception 'Privacy request not found';
  end if;
  if v_req.subject_user_id is null or v_req.subject_role is null then
    raise exception 'Link this request to a commuter or driver before generating a data snapshot';
  end if;

  if v_req.subject_role = 'commuter' then
    select to_jsonb(c) - 'commuter_id' into v_profile
    from public.commuters c
    where c.commuter_id = v_req.subject_user_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'review_id', r.review_id,
      'driver_id', r.driver_id,
      'rating', r.rating,
      'content', r.content,
      'date_created', r.date_created,
      'is_hidden', r.is_hidden
    ) order by r.date_created desc), '[]'::jsonb)
    into v_reviews
    from public.reviews r
    where r.commuter_id = v_req.subject_user_id;
  else
    select to_jsonb(d) - 'driver_id' into v_profile
    from public.drivers d
    where d.driver_id = v_req.subject_user_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'review_id', r.review_id,
      'commuter_id', r.commuter_id,
      'rating', r.rating,
      'content', r.content,
      'date_created', r.date_created,
      'is_hidden', r.is_hidden
    ) order by r.date_created desc), '[]'::jsonb)
    into v_reviews
    from public.reviews r
    where r.driver_id = v_req.subject_user_id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'log_id', l.log_id,
    'device_model', l.device_model,
    'os_version', l.os_version,
    'app_version', l.app_version,
    'access_datetime', l.access_datetime,
    'crash_error_log', l.crash_error_log
  ) order by l.access_datetime desc), '[]'::jsonb)
  into v_logs
  from public.device_logs l
  where l.user_id = v_req.subject_user_id;

  if v_profile is null then
    raise exception 'Linked account was not found';
  end if;

  update public.privacy_requests
  set status = case when status = 'received' then 'in_progress' else status end,
      handled_by = auth.uid()
  where request_id = p_request_id;

  return jsonb_build_object(
    'generated_at', now(),
    'request_id', p_request_id,
    'subject_role', v_req.subject_role,
    'note', 'Account data held by PASAKAY. Call and SMS content is not stored or monitored.',
    'profile', v_profile,
    'reviews', v_reviews,
    'device_logs', v_logs
  );
end;
$$;

create or replace function public.admin_apply_correction(
  p_request_id uuid,
  p_full_name text,
  p_contact_number text,
  p_email_address text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.privacy_requests%rowtype;
  v_name text := nullif(trim(coalesce(p_full_name, '')), '');
  v_mobile text := public.normalize_ph_mobile(p_contact_number);
  v_email text := nullif(trim(coalesce(p_email_address, '')), '');
  v_payload jsonb;
begin
  perform public.assert_system_admin();

  select * into v_req from public.privacy_requests where request_id = p_request_id;
  if not found then
    raise exception 'Privacy request not found';
  end if;
  if v_req.request_type <> 'correction' then
    raise exception 'This request is not a correction';
  end if;
  if v_req.subject_user_id is null or v_req.subject_role is null then
    raise exception 'Link this request to an account before applying a correction';
  end if;
  if v_name is null then
    raise exception 'Full name is required';
  end if;
  if v_mobile = '' then
    raise exception 'Contact number is required';
  end if;

  v_payload := jsonb_build_object(
    'full_name', v_name,
    'contact_number', v_mobile,
    'email_address', v_email
  );

  if v_req.subject_role = 'commuter' then
    update public.commuters
    set
      full_name = v_name,
      contact_number = v_mobile,
      email_address = v_email
    where commuter_id = v_req.subject_user_id;
  else
    update public.drivers
    set
      full_name = v_name,
      contact_number = v_mobile
    where driver_id = v_req.subject_user_id;
  end if;

  update public.privacy_requests
  set
    status = 'completed',
    correction_payload = v_payload,
    handled_by = auth.uid(),
    resolved_at = now(),
    subject_name = v_name,
    subject_contact = v_mobile
  where request_id = p_request_id;
end;
$$;

create or replace function public.admin_process_deletion(
  p_request_id uuid,
  p_retention_applies boolean,
  p_retention_reason text,
  p_confirm_name text
)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_req public.privacy_requests%rowtype;
  v_suffix text;
begin
  perform public.assert_system_admin();

  select * into v_req from public.privacy_requests where request_id = p_request_id;
  if not found then
    raise exception 'Privacy request not found';
  end if;
  if v_req.request_type <> 'deletion' then
    raise exception 'This request is not a deletion';
  end if;
  if v_req.subject_user_id is null or v_req.subject_role is null then
    raise exception 'Link this request to an account before processing deletion';
  end if;
  if lower(trim(coalesce(p_confirm_name, ''))) <> lower(v_req.subject_name) then
    raise exception 'Type the subject name exactly to confirm';
  end if;
  if p_retention_applies and nullif(trim(coalesce(p_retention_reason, '')), '') is null then
    raise exception 'A retention reason is required when research or legal retention applies';
  end if;

  v_suffix := left(replace(v_req.subject_user_id::text, '-', ''), 8);

  if v_req.subject_role = 'commuter' then
    update public.commuters
    set
      full_name = 'Deleted commuter',
      contact_number = '00000000000',
      email_address = null,
      username = 'deleted-' || v_suffix,
      status = 'deactivated',
      status_reason = 'Privacy deletion request'
    where commuter_id = v_req.subject_user_id;
  else
    update public.drivers
    set
      full_name = 'Deleted driver',
      contact_number = '00000000000',
      driver_license_number = 'REDACTED',
      plate_number = 'REDACTED',
      toda_number = null,
      username = 'deleted-' || v_suffix,
      license_verified = false,
      license_verified_at = null,
      license_verified_by = null,
      status = 'deactivated',
      is_active = false,
      status_reason = 'Privacy deletion request'
    where driver_id = v_req.subject_user_id;
  end if;

  -- Always cut off login. Full erasure is not guaranteed during the study.
  perform public.set_auth_login_allowed(v_req.subject_user_id, false);
  update auth.users
  set
    email = 'deleted-' || v_suffix || '@pasakay.invalid',
    encrypted_password = extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    updated_at = now()
  where id = v_req.subject_user_id;

  if not p_retention_applies then
    if v_req.subject_role = 'commuter' then
      delete from public.reviews where commuter_id = v_req.subject_user_id;
    else
      delete from public.reviews where driver_id = v_req.subject_user_id;
    end if;
    delete from public.device_logs where user_id = v_req.subject_user_id;
    delete from auth.users where id = v_req.subject_user_id;
  end if;

  update public.privacy_requests
  set
    status = case when p_retention_applies then 'retained' else 'completed' end,
    retention_applies = p_retention_applies,
    retention_reason = nullif(trim(coalesce(p_retention_reason, '')), ''),
    handled_by = auth.uid(),
    resolved_at = now(),
    admin_notes = case
      when p_retention_applies then
        'Identifiers anonymized. Account deactivated. Records kept because research or legal retention applies.'
      else
        'Identifiers removed and the login was deleted. This is not a certificate that every copy is gone.'
    end
  where request_id = p_request_id;
end;
$$;

create or replace function public.admin_change_password(p_password text)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
begin
  perform public.assert_system_admin();
  if p_password is null or length(p_password) < 8 then
    raise exception 'Password must be at least 8 characters';
  end if;

  update auth.users
  set
    encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
    updated_at = now()
  where id = auth.uid();
end;
$$;

create or replace function public.admin_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_system_admin();
  return jsonb_build_object(
    'drivers_total', (select count(*) from public.drivers),
    'drivers_pending', (select count(*) from public.drivers where status = 'pending_verification'),
    'drivers_active', (select count(*) from public.drivers where status = 'active'),
    'drivers_suspended', (select count(*) from public.drivers where status = 'suspended'),
    'commuters_total', (select count(*) from public.commuters),
    'commuters_suspended', (select count(*) from public.commuters where status in ('suspended', 'deactivated')),
    'terminals', (select count(*) from public.terminals),
    'shifts', (select count(*) from public.shifts),
    'reviews_visible', (select count(*) from public.reviews where is_hidden = false),
    'reviews_hidden', (select count(*) from public.reviews where is_hidden = true),
    'crash_logs', (select count(*) from public.device_logs where crash_error_log is not null and crash_error_log <> ''),
    'device_logs', (select count(*) from public.device_logs),
    'privacy_open', (select count(*) from public.privacy_requests where status in ('received', 'in_progress'))
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.admins enable row level security;
alter table public.privacy_requests enable row level security;

drop policy if exists "admins_select_own" on public.admins;
create policy "admins_select_own"
  on public.admins for select
  to authenticated
  using (admin_id = auth.uid());

drop policy if exists "commuters_select_admin" on public.commuters;
create policy "commuters_select_admin"
  on public.commuters for select
  to authenticated
  using (public.is_system_admin());

drop policy if exists "reviews_select_authenticated" on public.reviews;
drop policy if exists "reviews_select_visible" on public.reviews;
create policy "reviews_select_visible"
  on public.reviews for select
  to authenticated
  using (
    public.is_system_admin()
    or commuter_id = auth.uid()
    or is_hidden = false
  );

drop policy if exists "device_logs_select_admin" on public.device_logs;
create policy "device_logs_select_admin"
  on public.device_logs for select
  to authenticated
  using (public.is_system_admin());

drop policy if exists "privacy_requests_admin_all" on public.privacy_requests;
create policy "privacy_requests_admin_all"
  on public.privacy_requests for all
  to authenticated
  using (public.is_system_admin())
  with check (public.is_system_admin());

-- Client writes go through the admin_* functions. Direct table writes stay closed
-- except the policies the driver and commuter apps already use.

revoke all on function public.admin_create_driver(text, text, text, text, text, text, text, uuid, uuid) from public;
revoke all on function public.admin_update_driver(uuid, text, text, text, text, text, text, uuid, uuid) from public;
revoke all on function public.admin_verify_driver_license(uuid, boolean) from public;
revoke all on function public.admin_set_driver_status(uuid, text, text) from public;
revoke all on function public.admin_reset_driver_password(uuid, text) from public;
revoke all on function public.admin_delete_driver(uuid) from public;
revoke all on function public.admin_create_terminal(text) from public;
revoke all on function public.admin_update_terminal(uuid, text) from public;
revoke all on function public.admin_delete_terminal(uuid) from public;
revoke all on function public.admin_update_shift(uuid, text, text, text) from public;
revoke all on function public.admin_set_commuter_status(uuid, text, text) from public;
revoke all on function public.admin_set_review_hidden(uuid, boolean, text) from public;
revoke all on function public.admin_delete_review(uuid) from public;
revoke all on function public.admin_log_privacy_request(uuid, text, text, text, text, text) from public;
revoke all on function public.admin_set_privacy_status(uuid, text, text) from public;
revoke all on function public.admin_subject_snapshot(uuid) from public;
revoke all on function public.admin_apply_correction(uuid, text, text, text) from public;
revoke all on function public.admin_process_deletion(uuid, boolean, text, text) from public;
revoke all on function public.admin_change_password(text) from public;
revoke all on function public.admin_overview() from public;
revoke all on function public.assert_system_admin() from public;

grant execute on function public.admin_create_driver(text, text, text, text, text, text, text, uuid, uuid) to authenticated;
grant execute on function public.admin_update_driver(uuid, text, text, text, text, text, text, uuid, uuid) to authenticated;
grant execute on function public.admin_verify_driver_license(uuid, boolean) to authenticated;
grant execute on function public.admin_set_driver_status(uuid, text, text) to authenticated;
grant execute on function public.admin_reset_driver_password(uuid, text) to authenticated;
grant execute on function public.admin_delete_driver(uuid) to authenticated;
grant execute on function public.admin_create_terminal(text) to authenticated;
grant execute on function public.admin_update_terminal(uuid, text) to authenticated;
grant execute on function public.admin_delete_terminal(uuid) to authenticated;
grant execute on function public.admin_update_shift(uuid, text, text, text) to authenticated;
grant execute on function public.admin_set_commuter_status(uuid, text, text) to authenticated;
grant execute on function public.admin_set_review_hidden(uuid, boolean, text) to authenticated;
grant execute on function public.admin_delete_review(uuid) to authenticated;
grant execute on function public.admin_log_privacy_request(uuid, text, text, text, text, text) to authenticated;
grant execute on function public.admin_set_privacy_status(uuid, text, text) to authenticated;
grant execute on function public.admin_subject_snapshot(uuid) to authenticated;
grant execute on function public.admin_apply_correction(uuid, text, text, text) to authenticated;
grant execute on function public.admin_process_deletion(uuid, boolean, text, text) to authenticated;
grant execute on function public.admin_change_password(text) to authenticated;
grant execute on function public.admin_overview() to authenticated;
