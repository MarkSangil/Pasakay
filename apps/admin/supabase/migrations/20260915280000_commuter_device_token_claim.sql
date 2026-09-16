-- Commuter device tokens: one FCM token → current signed-in passenger.
alter table public.commuter_device_tokens
  drop constraint if exists commuter_device_tokens_commuter_id_token_key;

create unique index if not exists commuter_device_tokens_token_uidx
  on public.commuter_device_tokens (token);

drop policy if exists "commuter_device_tokens_update_own" on public.commuter_device_tokens;
create policy "commuter_device_tokens_update_own"
  on public.commuter_device_tokens for update
  to authenticated
  using (true)
  with check (commuter_id = auth.uid());

create or replace function public.register_commuter_device_token(
  p_token text,
  p_platform text default 'android'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commuter_id uuid := auth.uid();
  v_platform text := lower(trim(coalesce(p_platform, 'android')));
  v_token text := nullif(trim(coalesce(p_token, '')), '');
begin
  if v_commuter_id is null then
    raise exception 'Not authenticated';
  end if;
  if v_token is null then
    raise exception 'Token is required';
  end if;
  if v_platform not in ('ios', 'android', 'web') then
    v_platform := 'android';
  end if;
  if not exists (
    select 1 from public.commuters c
    where c.commuter_id = v_commuter_id
      and c.status in ('active', 'suspended')
  ) then
    raise exception 'Passenger session is not eligible for push tokens';
  end if;

  insert into public.commuter_device_tokens (commuter_id, token, platform, updated_at)
  values (v_commuter_id, v_token, v_platform, now())
  on conflict (token) do update
    set commuter_id = excluded.commuter_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

revoke all on function public.register_commuter_device_token(text, text) from public;
grant execute on function public.register_commuter_device_token(text, text) to authenticated;
