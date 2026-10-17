-- Audit logs + commuter activity tracking.
--
-- AUDIT LOG (both roles):
--  * One row per recorded in-app action: a screen opened (screen_*) or a
--    key action (call/sms/submit/select). Scope agreed with the study team:
--    screens + actions — never raw taps, keystrokes, message text,
--    location, or device identifiers.
--  * Identity always comes from auth.uid(); the server decides the role by
--    looking up which account table holds that id. Clients cannot log
--    activity for another account.
--  * log_id is client-generated so network retries are idempotent
--    (ON CONFLICT DO NOTHING).
--
-- COMMUTER ACTIVITY (mirrors driver foreground tracking):
--  * One session per foreground span + heartbeat rows every
--    driver_heartbeat_seconds (same tunables as drivers). Admin sees
--    Active now / Inactive / Offline / Unknown and Today/7d/30d totals
--    computed from persisted server timestamps only.
--  * No location, keystroke, or personal content is stored here.

-- ---------------------------------------------------------------------------
-- 1. Audit log table.
-- ---------------------------------------------------------------------------
create table if not exists public.user_audit_logs (
  log_id uuid primary key,
  user_id uuid not null,
  user_role text not null check (user_role in ('driver', 'commuter')),
  action text not null check (length(trim(action)) between 1 and 64),
  detail jsonb null,
  occurred_at timestamptz not null default now()
);

create index if not exists user_audit_logs_user_idx
  on public.user_audit_logs (user_id, occurred_at desc);
create index if not exists user_audit_logs_action_idx
  on public.user_audit_logs (action, occurred_at desc);

comment on table public.user_audit_logs is
  'Screen-open and key-action audit trail for study accountability. '
  'Ids/names/labels only — never message content, keystrokes, or location.';

alter table public.user_audit_logs enable row level security;

revoke all on public.user_audit_logs from anon, public;
grant select, insert on public.user_audit_logs to authenticated;

drop policy if exists "user_audit_logs_own" on public.user_audit_logs;
create policy "user_audit_logs_own"
  on public.user_audit_logs for select
  to authenticated
  using (user_id = auth.uid());
-- Inserts happen through report_user_audit_log (SECURITY DEFINER), which
-- resolves the role server-side so clients cannot claim a role.

-- ---------------------------------------------------------------------------
-- 2. RPC: report one audit entry (any signed-in driver or commuter).
-- ---------------------------------------------------------------------------
create or replace function public.report_user_audit_log(
  p_log_id uuid,
  p_action text,
  p_detail jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_detail jsonb;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;
  if p_log_id is null then
    raise exception 'Log id is required';
  end if;
  if coalesce(p_action, '') is null
     or length(btrim(p_action)) not between 1 and 64 then
    raise exception 'Action is required (1-64 characters)';
  end if;

  select 'driver' into v_role from public.drivers where driver_id = v_user;
  if v_role is null then
    select 'commuter' into v_role from public.commuters where commuter_id = v_user;
  end if;
  if v_role is null then
    raise exception 'Account not found';
  end if;

  if p_detail is null then
    v_detail := null;
  else
    v_detail := jsonb_strip_nulls(p_detail);
    if length(v_detail::text) > 500 then
      raise exception 'Detail is too large';
    end if;
  end if;

  insert into public.user_audit_logs (log_id, user_id, user_role, action, detail)
  values (p_log_id, v_user, v_role, btrim(p_action), v_detail)
  on conflict (log_id) do nothing;

  return jsonb_build_object(
    'log_id', p_log_id,
    'occurred_at', now()
  );
end;
$$;

revoke all on function public.report_user_audit_log(uuid, text, jsonb) from public;
grant execute on function public.report_user_audit_log(uuid, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Admin RPC: recent audit entries for one account.
-- ---------------------------------------------------------------------------
create or replace function public.admin_user_audit_logs(
  p_role text,
  p_user_id uuid,
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_system_admin();
  if p_role not in ('driver', 'commuter') then
    raise exception 'Role must be driver or commuter';
  end if;
  if p_user_id is null then
    raise exception 'Account is required';
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(l) order by l.occurred_at desc, l.log_id)
    from (
      select
        log_id,
        action,
        detail,
        occurred_at
      from public.user_audit_logs
      where user_role = p_role
        and user_id = p_user_id
      order by occurred_at desc
      limit least(coalesce(p_limit, 50), 200)
      offset greatest(coalesce(p_offset, 0), 0)
    ) l
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_user_audit_logs(text, uuid, int, int) from public;
grant execute on function public.admin_user_audit_logs(text, uuid, int, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Commuter activity tables (mirror of driver_activity_*).
-- ---------------------------------------------------------------------------
create table if not exists public.commuter_activity_sessions (
  session_id uuid primary key,
  commuter_id uuid not null references public.commuters (commuter_id) on delete cascade,
  started_at timestamptz not null default now(),
  last_heartbeat_at timestamptz not null default now(),
  ended_at timestamptz null,
  end_reason text null check (end_reason in ('logout', 'background'))
);

create table if not exists public.commuter_activity_heartbeats (
  heartbeat_id uuid primary key,
  session_id uuid not null references public.commuter_activity_sessions (session_id) on delete cascade,
  commuter_id uuid not null references public.commuters (commuter_id) on delete cascade,
  beat_at timestamptz not null default now()
);

create index if not exists commuter_activity_sessions_commuter_idx
  on public.commuter_activity_sessions (commuter_id, started_at desc);
create index if not exists commuter_activity_heartbeats_commuter_idx
  on public.commuter_activity_heartbeats (commuter_id, beat_at desc);
create index if not exists commuter_activity_heartbeats_session_idx
  on public.commuter_activity_heartbeats (session_id, beat_at);

comment on table public.commuter_activity_sessions is
  'One row per passenger-app foreground span. Staleness is computed on read.';
comment on table public.commuter_activity_heartbeats is
  'One row per delivered foreground heartbeat (client-generated ids, idempotent).';

alter table public.commuter_activity_sessions enable row level security;
alter table public.commuter_activity_heartbeats enable row level security;

revoke all on public.commuter_activity_sessions from anon, public;
revoke all on public.commuter_activity_heartbeats from anon, public;
grant select, insert, update on public.commuter_activity_sessions to authenticated;
grant select, insert on public.commuter_activity_heartbeats to authenticated;

drop policy if exists "commuter_activity_sessions_own" on public.commuter_activity_sessions;
create policy "commuter_activity_sessions_own"
  on public.commuter_activity_sessions for all
  to authenticated
  using (commuter_id = auth.uid())
  with check (commuter_id = auth.uid());

drop policy if exists "commuter_activity_heartbeats_own" on public.commuter_activity_heartbeats;
create policy "commuter_activity_heartbeats_own"
  on public.commuter_activity_heartbeats for all
  to authenticated
  using (commuter_id = auth.uid())
  with check (commuter_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 5. RPC: report commuter session_start / heartbeat / session_end.
-- ---------------------------------------------------------------------------
create or replace function public.report_commuter_activity(
  p_session_id uuid,
  p_event text,
  p_heartbeat_id uuid default null,
  p_end_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commuter uuid := auth.uid();
  v_timeout int := public.booking_setting_int('driver_activity_timeout_seconds', 120);
  v_hb int := public.booking_setting_int('driver_heartbeat_seconds', 30);
  v_session public.commuter_activity_sessions%rowtype;
  v_hb_id uuid;
  v_reason text;
begin
  if v_commuter is null then
    raise exception 'Not authenticated';
  end if;
  if not exists (
    select 1 from public.commuters where commuter_id = v_commuter
  ) then
    raise exception 'Commuter account not found';
  end if;
  if p_event not in ('session_start', 'heartbeat', 'session_end') then
    raise exception 'Unknown activity event';
  end if;
  if p_session_id is null then
    raise exception 'Session id is required';
  end if;

  if p_event = 'session_start' then
    insert into public.commuter_activity_sessions (session_id, commuter_id)
    values (p_session_id, v_commuter)
    on conflict (session_id) do nothing;

    select * into v_session
    from public.commuter_activity_sessions
    where session_id = p_session_id;

    if v_session.commuter_id is distinct from v_commuter then
      raise exception 'Session belongs to another commuter';
    end if;
    if v_session.ended_at is not null then
      raise exception 'Session is closed';
    end if;

    return jsonb_build_object(
      'session_id', p_session_id,
      'heartbeat_seconds', v_hb,
      'timeout_seconds', v_timeout
    );
  end if;

  select * into v_session
  from public.commuter_activity_sessions
  where session_id = p_session_id;

  if not found then
    raise exception 'Unknown session. Start a new session.';
  end if;
  if v_session.commuter_id is distinct from v_commuter then
    raise exception 'Session belongs to another commuter';
  end if;
  if v_session.ended_at is not null then
    raise exception 'Session is closed';
  end if;

  if p_event = 'heartbeat' then
    v_hb_id := coalesce(p_heartbeat_id, gen_random_uuid());
    insert into public.commuter_activity_heartbeats (heartbeat_id, session_id, commuter_id)
    values (v_hb_id, p_session_id, v_commuter)
    on conflict (heartbeat_id) do nothing;

    update public.commuter_activity_sessions
    set last_heartbeat_at = now()
    where session_id = p_session_id and ended_at is null;
  else
    v_reason := coalesce(nullif(trim(p_end_reason), ''), 'background');
    if v_reason not in ('logout', 'background') then
      raise exception 'Unknown session end reason';
    end if;
    update public.commuter_activity_sessions
    set ended_at = now(), end_reason = v_reason
    where session_id = p_session_id and ended_at is null;
  end if;

  return jsonb_build_object(
    'session_id', p_session_id,
    'beat_at', now(),
    'heartbeat_seconds', v_hb,
    'timeout_seconds', v_timeout
  );
end;
$$;

revoke all on function public.report_commuter_activity(uuid, text, uuid, text) from public;
grant execute on function public.report_commuter_activity(uuid, text, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Latest qualifying heartbeat-chain start inside one commuter session.
-- ---------------------------------------------------------------------------
create or replace function public.commuter_session_chain_start(
  p_session_id uuid,
  p_timeout_seconds int
)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  with ordered as (
    select
      beat_at,
      extract(epoch from (beat_at - lag(beat_at) over (order by beat_at))) as gap_s
    from public.commuter_activity_heartbeats
    where session_id = p_session_id
  ),
  grouped as (
    select
      beat_at,
      count(*) filter (where gap_s is null or gap_s > p_timeout_seconds)
        over (order by beat_at) as grp
    from ordered
  )
  select min(beat_at) from grouped where grp = (select max(grp) from grouped);
$$;

revoke all on function public.commuter_session_chain_start(uuid, int) from public;
grant execute on function public.commuter_session_chain_start(uuid, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Admin RPC: one row per commuter with the current activity state.
--    Stat labels mirror admin_driver_activity_list.
-- ---------------------------------------------------------------------------
create or replace function public.admin_commuter_activity_list()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_timeout int := public.booking_setting_int('driver_activity_timeout_seconds', 120);
begin
  perform public.assert_system_admin();

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.sort_key, x.full_name)
    from (
      select
        c.commuter_id,
        c.full_name,
        c.status::text as account_status,
        case
          when s.session_id is not null
            and s.ended_at is null
            and (now() - s.last_heartbeat_at) <= make_interval(secs => v_timeout)
            and c.status = 'active'
            then 'active_now'
          when s.session_id is null and lb.last_beat is null
            then 'unknown'
          when s.ended_at is not null and s.end_reason = 'logout'
            then 'offline'
          else 'inactive'
        end as activity_state,
        lb.last_beat as last_seen,
        case
          when s.session_id is not null
            and s.ended_at is null
            and (now() - s.last_heartbeat_at) <= make_interval(secs => v_timeout)
            and c.status = 'active'
            then greatest(0, extract(
              epoch from (now() - public.commuter_session_chain_start(s.session_id, v_timeout))
            )::int)
          else null
        end as current_active_seconds,
        case
          when s.session_id is not null
            and s.ended_at is null
            and (now() - s.last_heartbeat_at) <= make_interval(secs => v_timeout)
            and c.status = 'active' then 0
          when s.session_id is null and lb.last_beat is null then 3
          when s.ended_at is not null and s.end_reason = 'logout' then 2
          else 1
        end as sort_key
      from public.commuters c
      left join lateral (
        select *
        from public.commuter_activity_sessions s2
        where s2.commuter_id = c.commuter_id
        order by s2.last_heartbeat_at desc
        limit 1
      ) s on true
      left join lateral (
        select max(beat_at) as last_beat
        from public.commuter_activity_heartbeats h
        where h.commuter_id = c.commuter_id
      ) lb on true
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_commuter_activity_list() from public;
grant execute on function public.admin_commuter_activity_list() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Admin RPC: commuter usage summary over [p_from, p_to].
--    Same chain math as admin_driver_usage_summary.
-- ---------------------------------------------------------------------------
create or replace function public.admin_commuter_usage_summary(
  p_commuter_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_timeout int := public.booking_setting_int('driver_activity_timeout_seconds', 120);
  v_hb int := public.booking_setting_int('driver_heartbeat_seconds', 30);
  v_total double precision := 0;
  v_sessions int := 0;
  v_days int := 0;
  r record;
begin
  perform public.assert_system_admin();

  if p_commuter_id is null then
    raise exception 'Commuter is required';
  end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'A valid reporting period is required';
  end if;

  for r in
    select
      s.session_id,
      s.started_at,
      s.ended_at,
      s.end_reason,
      (select count(*) from public.commuter_activity_heartbeats h
        where h.session_id = s.session_id
          and h.beat_at >= p_from and h.beat_at <= p_to) as beats,
      coalesce((
        select sum(chain_s) from (
          select
            extract(epoch from (max(beat_at) - min(beat_at))) + v_hb as chain_s
          from (
            select
              beat_at,
              count(*) filter (
                where gap_s is null or gap_s > v_timeout
              ) over (order by beat_at) as grp
            from (
              select
                beat_at,
                extract(epoch from (beat_at - lag(beat_at) over (order by beat_at))) as gap_s
              from public.commuter_activity_heartbeats h
              where h.session_id = s.session_id
                and h.beat_at >= p_from and h.beat_at <= p_to
            ) g0
          ) g1
          group by grp
        ) chains
      ), 0) as foreground_s
    from public.commuter_activity_sessions s
    where s.commuter_id = p_commuter_id
      and s.started_at <= p_to
      and (s.ended_at is null or s.ended_at >= p_from)
    order by s.started_at desc
    limit 500
  loop
    if r.beats > 0 then
      v_total := v_total + r.foreground_s;
      v_sessions := v_sessions + 1;
    end if;
  end loop;

  select count(distinct (h.beat_at at time zone 'Asia/Manila')::date)
  into v_days
  from public.commuter_activity_heartbeats h
  where h.commuter_id = p_commuter_id
    and h.beat_at >= p_from and h.beat_at <= p_to;

  return jsonb_build_object(
    'commuter_id', p_commuter_id,
    'from', p_from,
    'to', p_to,
    'heartbeat_seconds', v_hb,
    'timeout_seconds', v_timeout,
    'total_foreground_seconds', v_total::int,
    'sessions', v_sessions,
    'active_days', coalesce(v_days, 0),
    'first_seen', (
      select min(beat_at) from public.commuter_activity_heartbeats h
      where h.commuter_id = p_commuter_id and h.beat_at >= p_from and h.beat_at <= p_to
    ),
    'last_seen', (
      select max(beat_at) from public.commuter_activity_heartbeats h
      where h.commuter_id = p_commuter_id and h.beat_at >= p_from and h.beat_at <= p_to
    ),
    'sessions_detail', coalesce((
      select jsonb_agg(to_jsonb(y) order by y.started_at desc)
      from (
        select
          s.session_id,
          s.started_at,
          s.ended_at,
          s.end_reason,
          (select count(*) from public.commuter_activity_heartbeats h
            where h.session_id = s.session_id
              and h.beat_at >= p_from and h.beat_at <= p_to) as beats,
          coalesce((
            select sum(chain_s) from (
              select
                extract(epoch from (max(beat_at) - min(beat_at))) + v_hb as chain_s
              from (
                select
                  beat_at,
                  count(*) filter (
                    where gap_s is null or gap_s > v_timeout
                  ) over (order by beat_at) as grp
                from (
                  select
                    beat_at,
                    extract(epoch from (beat_at - lag(beat_at) over (order by beat_at))) as gap_s
                  from public.commuter_activity_heartbeats h
                  where h.session_id = s.session_id
                    and h.beat_at >= p_from and h.beat_at <= p_to
                ) g0
              ) g1
              group by grp
            ) chains
          ), 0)::int as foreground_seconds
        from public.commuter_activity_sessions s
        where s.commuter_id = p_commuter_id
          and s.started_at <= p_to
          and (s.ended_at is null or s.ended_at >= p_from)
        order by s.started_at desc
        limit 50
      ) y
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_commuter_usage_summary(uuid, timestamptz, timestamptz) from public;
grant execute on function public.admin_commuter_usage_summary(uuid, timestamptz, timestamptz) to authenticated;
