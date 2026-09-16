-- FCM device tokens for drivers (live schema uses drivers.driver_id).
create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers (driver_id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('ios', 'android', 'web')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (driver_id, token)
);

create index if not exists device_tokens_driver_id_idx
  on public.device_tokens (driver_id);

alter table public.device_tokens enable row level security;

drop policy if exists "device_tokens_select_own" on public.device_tokens;
create policy "device_tokens_select_own"
  on public.device_tokens for select
  to authenticated
  using (driver_id = auth.uid());

drop policy if exists "device_tokens_insert_own" on public.device_tokens;
create policy "device_tokens_insert_own"
  on public.device_tokens for insert
  to authenticated
  with check (driver_id = auth.uid());

drop policy if exists "device_tokens_update_own" on public.device_tokens;
create policy "device_tokens_update_own"
  on public.device_tokens for update
  to authenticated
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

drop policy if exists "device_tokens_delete_own" on public.device_tokens;
create policy "device_tokens_delete_own"
  on public.device_tokens for delete
  to authenticated
  using (driver_id = auth.uid());

create or replace function public.notify_driver(
  p_driver_id uuid,
  p_message text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_message text := nullif(trim(coalesce(p_message, '')), '');
begin
  if v_message is null then
    raise exception 'Message is required';
  end if;
  if not exists (select 1 from public.drivers where driver_id = p_driver_id) then
    raise exception 'Driver not found';
  end if;

  insert into public.notifications (
    recipient_id,
    recipient_type,
    message_content
  ) values (
    p_driver_id,
    'driver',
    v_message
  )
  returning notification_id into v_id;

  return v_id;
end;
$$;

revoke all on function public.notify_driver(uuid, text) from public;
grant execute on function public.notify_driver(uuid, text) to authenticated, service_role;

create or replace function public.touch_device_token_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists device_tokens_set_updated_at on public.device_tokens;
create trigger device_tokens_set_updated_at
  before update on public.device_tokens
  for each row
  execute function public.touch_device_token_updated_at();
