-- Reliable, privacy-conscious driver foreground-usage monitoring.
--
-- Design (see feature notes in the admin app):
--  * The driver app opens one activity SESSION per foreground span
--    (client-generated session_id, login .. logout/background) and sends a
--    foreground HEARTBEAT every driver_heartbeat_seconds (default 30s).
--  * Heartbeats are rows, not counter increments: usage is derived from
--    persisted server timestamps, so totals never rely on client math.
--  * Identity always comes from auth.uid(); clients cannot log activity for
--    another driver. Ended sessions reject further heartbeats, so a delayed
--    beat can never revive a logged-out session.
--  * Staleness is computed on READ (no sweeper): a heartbeat older than
--    driver_activity_timeout_seconds (default 120s) never counts as active.
--  * No location, keystroke, or personal data is stored here — only
--    driver_id, session linkage, server timestamps, and end reason.

-- ---------------------------------------------------------------------------
-- 0. Tunables (admin-adjustable without a new migration).
-- ---------------------------------------------------------------------------
insert into public.app_notification_settings (key, value, updated_at)
values
  ('driver_heartbeat_seconds', '30', now()),
  ('driver_activity_timeout_seconds', '120', now())
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 1. Tables.
-- ---------------------------------------------------------------------------
create table if not exists public.driver_activity_sessions (
  session_id uuid primary key,
  driver_id uuid not null references public.drivers (driver_id) on delete cascade,
  started_at timestamptz not null default now(),
  last_heartbeat_at timestamptz not null default now(),
  ended_at timestamptz null,
  end_reason text null check (end_reason in ('logout', 'background'))
);

create table if not exists public.driver_activity_heartbeats (
  heartbeat_id uuid primary key,
  session_id uuid not null references public.driver_activity_sessions (session_id) on delete cascade,
  driver_id uuid not null references public.drivers (driver_id) on delete cascade,
  beat_at timestamptz not null default now()
);

create index if not exists driver_activity_sessions_driver_idx
  on public.driver_activity_sessions (driver_id, started_at desc);
create index if not exists driver_activity_heartbeats_driver_idx
  on public.driver_activity_heartbeats (driver_id, beat_at desc);
create index if not exists driver_activity_heartbeats_session_idx
  on public.driver_activity_heartbeats (session_id, beat_at);

comment on table public.driver_activity_sessions is
  'One row per driver-app foreground span. last_heartbeat_at is server time; '
  'staleness is computed on read, so no sweeper is required.';
comment on table public.driver_activity_heartbeats is
  'One row per delivered foreground heartbeat. heartbeat_id is client-generated '
  'so retries are idempotent (ON CONFLICT DO NOTHING).';

-- ---------------------------------------------------------------------------
-- 2. RLS: drivers touch only their own rows; everything else goes through
--    SECURITY DEFINER RPCs below (owner bypasses RLS).
-- ---------------------------------------------------------------------------
alter table public.driver_activity_sessions enable row level security;
alter table public.driver_activity_heartbeats enable row level security;

revoke all on public.driver_activity_sessions from anon, public;
revoke all on public.driver_activity_heartbeats from anon, public;
grant select, insert, update
  on public.driver_activity_sessions to authenticated;
grant select, insert
  on public.driver_activity_heartbeats to authenticated;

drop policy if exists "driver_activity_sessions_own" on public.driver_activity_sessions;
create policy "driver_activity_sessions_own"
  on public.driver_activity_sessions for all
  to authenticated
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

drop policy if exists "driver_activity_heartbeats_own" on public.driver_activity_heartbeats;
create policy "driver_activity_heartbeats_own"
  on public.driver_activity_heartbeats for all
  to authenticated
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3. Driver RPC: report session_start / heartbeat / session_end.
-- ---------------------------------------------------------------------------
create or replace function public.report_driver_activity(
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
  v_driver uuid := auth.uid();
  v_timeout int := public.booking_setting_int('driver_activity_timeout_seconds', 120);
  v_hb int := public.booking_setting_int('driver_heartbeat_seconds', 30);
  v_session public.driver_activity_sessions%rowtype;
  v_hb_id uuid;
  v_reason text;
begin
  if v_driver is null then
    raise exception 'Not authenticated';
  end if;
  if not exists (select 1 from public.drivers where driver_id = v_driver) then
    raise exception 'Driver account not found';
  end if;
  if p_event not in ('session_start', 'heartbeat', 'session_end') then
    raise exception 'Unknown activity event';
  end if;
  if p_session_id is null then
    raise exception 'Session id is required';
  end if;

  if p_event = 'session_start' then
    insert into public.driver_activity_sessions (session_id, driver_id)
    values (p_session_id, v_driver)
    on conflict (session_id) do nothing;

    select * into v_session
    from public.driver_activity_sessions
    where session_id = p_session_id;

    if v_session.driver_id is distinct from v_driver then
      raise exception 'Session belongs to another driver';
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
  from public.driver_activity_sessions
  where session_id = p_session_id;

  if not found then
    raise exception 'Unknown session. Start a new session.';
  end if;
  if v_session.driver_id is distinct from v_driver then
    raise exception 'Session belongs to another driver';
  end if;
  if v_session.ended_at is not null then
    raise exception 'Session is closed';
  end if;

  if p_event = 'heartbeat' then
    v_hb_id := coalesce(p_heartbeat_id, gen_random_uuid());
    insert into public.driver_activity_heartbeats (heartbeat_id, session_id, driver_id)
    values (v_hb_id, p_session_id, v_driver)
    on conflict (heartbeat_id) do nothing;

    update public.driver_activity_sessions
    set last_heartbeat_at = now()
    where session_id = p_session_id and ended_at is null;
  else
    v_reason := coalesce(nullif(trim(p_end_reason), ''), 'background');
    if v_reason not in ('logout', 'background') then
      raise exception 'Unknown session end reason';
    end if;
    update public.driver_activity_sessions
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

revoke all on function public.report_driver_activity(uuid, text, uuid, text) from public;
grant execute on function public.report_driver_activity(uuid, text, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Driver RPC: tracking tunables (client falls back to 30s / 120s).
-- ---------------------------------------------------------------------------
create or replace function public.get_driver_activity_config()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'heartbeat_seconds', public.booking_setting_int('driver_heartbeat_seconds', 30),
    'timeout_seconds', public.booking_setting_int('driver_activity_timeout_seconds', 120)
  );
end;
$$;

revoke all on function public.get_driver_activity_config() from public;
grant execute on function public.get_driver_activity_config() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Shared chain math: latest qualifying chain start inside one session.
--    A chain is a maximal run of beats with consecutive gaps <= timeout.
-- ---------------------------------------------------------------------------
create or replace function public.driver_session_chain_start(
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
    from public.driver_activity_heartbeats
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

revoke all on function public.driver_session_chain_start(uuid, int) from public;
grant execute on function public.driver_session_chain_start(uuid, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Admin RPC: one row per driver with the current activity state.
--
--    active_now: open session + heartbeat within timeout + account active.
--    offline:    latest session ended with 'logout', nothing after it.
--    inactive:   anything else with history (stale or background-ended).
--    unknown:    no session/heartbeat rows at all.
-- ---------------------------------------------------------------------------
create or replace function public.admin_driver_activity_list()
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
        d.driver_id,
        d.full_name,
        d.status::text as account_status,
        case
          when s.session_id is not null
            and (now() - s.last_heartbeat_at) <= make_interval(secs => v_timeout)
            and d.status = 'active'
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
            and (now() - s.last_heartbeat_at) <= make_interval(secs => v_timeout)
            and d.status = 'active'
            then greatest(0, extract(
              epoch from (now() - public.driver_session_chain_start(s.session_id, v_timeout))
            )::int)
          else null
        end as current_active_seconds,
        case
          when s.session_id is not null
            and (now() - s.last_heartbeat_at) <= make_interval(secs => v_timeout)
            and d.status = 'active' then 0
          when s.session_id is null and lb.last_beat is null then 3
          when s.ended_at is not null and s.end_reason = 'logout' then 2
          else 1
        end as sort_key
      from public.drivers d
      left join lateral (
        select *
        from public.driver_activity_sessions s2
        where s2.driver_id = d.driver_id
        order by s2.last_heartbeat_at desc
        limit 1
      ) s on true
      left join lateral (
        select max(beat_at) as last_beat
        from public.driver_activity_heartbeats h
        where h.driver_id = d.driver_id
      ) lb on true
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_driver_activity_list() from public;
grant execute on function public.admin_driver_activity_list() to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Admin RPC: usage summary for one driver over [p_from, p_to].
--
--    Foreground total = per chain: (last_beat - first_beat) + one heartbeat
--    interval. Gaps longer than the timeout split chains and are excluded;
--    duplicates collapse on heartbeat_id, so retries never inflate totals.
--    active_days uses Asia/Manila calendar dates (project locale).
-- ---------------------------------------------------------------------------
create or replace function public.admin_driver_usage_summary(
  p_driver_id uuid,
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

  if p_driver_id is null then
    raise exception 'Driver is required';
  end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'A valid reporting period is required';
  end if;

  -- Per-session chain totals.
  for r in
    select
      s.session_id,
      s.started_at,
      s.ended_at,
      s.end_reason,
      (select count(*) from public.driver_activity_heartbeats h
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
              from public.driver_activity_heartbeats h
              where h.session_id = s.session_id
                and h.beat_at >= p_from and h.beat_at <= p_to
            ) g0
          ) g1
          group by grp
        ) chains
      ), 0) as foreground_s
    from public.driver_activity_sessions s
    where s.driver_id = p_driver_id
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
  from public.driver_activity_heartbeats h
  where h.driver_id = p_driver_id
    and h.beat_at >= p_from and h.beat_at <= p_to;

  return jsonb_build_object(
    'driver_id', p_driver_id,
    'from', p_from,
    'to', p_to,
    'heartbeat_seconds', v_hb,
    'timeout_seconds', v_timeout,
    'total_foreground_seconds', v_total::int,
    'sessions', v_sessions,
    'active_days', coalesce(v_days, 0),
    'first_seen', (
      select min(beat_at) from public.driver_activity_heartbeats h
      where h.driver_id = p_driver_id and h.beat_at >= p_from and h.beat_at <= p_to
    ),
    'last_seen', (
      select max(beat_at) from public.driver_activity_heartbeats h
      where h.driver_id = p_driver_id and h.beat_at >= p_from and h.beat_at <= p_to
    ),
    'sessions_detail', coalesce((
      select jsonb_agg(to_jsonb(y) order by y.started_at desc)
      from (
        select
          s.session_id,
          s.started_at,
          s.ended_at,
          s.end_reason,
          (select count(*) from public.driver_activity_heartbeats h
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
                  from public.driver_activity_heartbeats h
                  where h.session_id = s.session_id
                    and h.beat_at >= p_from and h.beat_at <= p_to
                ) g0
              ) g1
              group by grp
            ) chains
          ), 0)::int as foreground_seconds
        from public.driver_activity_sessions s
        where s.driver_id = p_driver_id
          and s.started_at <= p_to
          and (s.ended_at is null or s.ended_at >= p_from)
        order by s.started_at desc
        limit 50
      ) y
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_driver_usage_summary(uuid, timestamptz, timestamptz) from public;
grant execute on function public.admin_driver_usage_summary(uuid, timestamptz, timestamptz) to authenticated;
