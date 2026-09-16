-- One FCM token belongs to the currently signed-in driver on that device.
alter table public.device_tokens
  drop constraint if exists device_tokens_driver_id_token_key;

create unique index if not exists device_tokens_token_uidx
  on public.device_tokens (token);

-- Allow drivers to claim an existing token row (switch accounts on same phone).
drop policy if exists "device_tokens_update_own" on public.device_tokens;
create policy "device_tokens_update_own"
  on public.device_tokens for update
  to authenticated
  using (true)
  with check (driver_id = auth.uid());

-- Prefer a security-definer upsert so account switches always succeed.
create or replace function public.register_driver_device_token(
  p_token text,
  p_platform text default 'android'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_platform text := lower(trim(coalesce(p_platform, 'android')));
  v_token text := nullif(trim(coalesce(p_token, '')), '');
begin
  if v_driver_id is null then
    raise exception 'Not authenticated';
  end if;
  if v_token is null then
    raise exception 'Token is required';
  end if;
  if v_platform not in ('ios', 'android', 'web') then
    v_platform := 'android';
  end if;
  if not exists (
    select 1 from public.drivers d
    where d.driver_id = v_driver_id
      and d.status in ('active', 'suspended')
  ) then
    raise exception 'Driver session is not eligible for push tokens';
  end if;

  insert into public.device_tokens (driver_id, token, platform, updated_at)
  values (v_driver_id, v_token, v_platform, now())
  on conflict (token) do update
    set driver_id = excluded.driver_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

revoke all on function public.register_driver_device_token(text, text) from public;
grant execute on function public.register_driver_device_token(text, text) to authenticated;
