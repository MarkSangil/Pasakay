create table if not exists public.commuter_device_tokens (
  id uuid primary key default gen_random_uuid(),
  commuter_id uuid not null references public.commuters (commuter_id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('ios', 'android', 'web')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (commuter_id, token)
);

create index if not exists commuter_device_tokens_commuter_id_idx
  on public.commuter_device_tokens (commuter_id);

alter table public.commuter_device_tokens enable row level security;

drop policy if exists "commuter_device_tokens_select_own" on public.commuter_device_tokens;
create policy "commuter_device_tokens_select_own"
  on public.commuter_device_tokens for select
  to authenticated
  using (commuter_id = auth.uid());

drop policy if exists "commuter_device_tokens_insert_own" on public.commuter_device_tokens;
create policy "commuter_device_tokens_insert_own"
  on public.commuter_device_tokens for insert
  to authenticated
  with check (commuter_id = auth.uid());

drop policy if exists "commuter_device_tokens_update_own" on public.commuter_device_tokens;
create policy "commuter_device_tokens_update_own"
  on public.commuter_device_tokens for update
  to authenticated
  using (commuter_id = auth.uid())
  with check (commuter_id = auth.uid());

drop policy if exists "commuter_device_tokens_delete_own" on public.commuter_device_tokens;
create policy "commuter_device_tokens_delete_own"
  on public.commuter_device_tokens for delete
  to authenticated
  using (commuter_id = auth.uid());

create or replace function public.touch_commuter_device_token_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists commuter_device_tokens_set_updated_at on public.commuter_device_tokens;
create trigger commuter_device_tokens_set_updated_at
  before update on public.commuter_device_tokens
  for each row
  execute function public.touch_commuter_device_token_updated_at();

create or replace function public.notify_commuter(
  p_commuter_id uuid,
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
  if not exists (select 1 from public.commuters where commuter_id = p_commuter_id) then
    raise exception 'Commuter not found';
  end if;

  insert into public.notifications (
    recipient_id,
    recipient_type,
    message_content
  ) values (
    p_commuter_id,
    'commuter',
    v_message
  )
  returning notification_id into v_id;

  return v_id;
end;
$$;

revoke all on function public.notify_commuter(uuid, text) from public;
grant execute on function public.notify_commuter(uuid, text) to authenticated, service_role;
