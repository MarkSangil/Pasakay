-- Configurable booking timer, driver early complete, and booked status for lists.

-- ---------------------------------------------------------------------------
-- Public/admin booking settings
-- ---------------------------------------------------------------------------
create or replace function public.get_booking_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'dispute_window_minutes', public.booking_setting_int('dispute_window_minutes', 20),
    'request_expire_minutes', public.booking_setting_int('request_expire_minutes', 30),
    'request_cooldown_minutes', public.booking_setting_int('request_cooldown_minutes', 30),
    'review_eligible_minutes', public.booking_setting_int('review_eligible_minutes', 0)
  );
end;
$$;

revoke all on function public.get_booking_settings() from public;
grant execute on function public.get_booking_settings() to authenticated;

create or replace function public.admin_set_booking_settings(
  p_dispute_window_minutes int default null,
  p_request_expire_minutes int default null,
  p_request_cooldown_minutes int default null,
  p_review_eligible_minutes int default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_system_admin();

  if p_dispute_window_minutes is not null then
    if p_dispute_window_minutes < 1 or p_dispute_window_minutes > 240 then
      raise exception 'Dispute window must be between 1 and 240 minutes';
    end if;
    insert into public.app_notification_settings (key, value, updated_at)
    values ('dispute_window_minutes', p_dispute_window_minutes::text, now())
    on conflict (key) do update
      set value = excluded.value, updated_at = now();
  end if;

  if p_request_expire_minutes is not null then
    if p_request_expire_minutes < 1 or p_request_expire_minutes > 240 then
      raise exception 'Request expire must be between 1 and 240 minutes';
    end if;
    insert into public.app_notification_settings (key, value, updated_at)
    values ('request_expire_minutes', p_request_expire_minutes::text, now())
    on conflict (key) do update
      set value = excluded.value, updated_at = now();
  end if;

  if p_request_cooldown_minutes is not null then
    if p_request_cooldown_minutes < 0 or p_request_cooldown_minutes > 240 then
      raise exception 'Request cooldown must be between 0 and 240 minutes';
    end if;
    insert into public.app_notification_settings (key, value, updated_at)
    values ('request_cooldown_minutes', p_request_cooldown_minutes::text, now())
    on conflict (key) do update
      set value = excluded.value, updated_at = now();
  end if;

  if p_review_eligible_minutes is not null then
    if p_review_eligible_minutes < 0 or p_review_eligible_minutes > 240 then
      raise exception 'Review eligible minutes must be between 0 and 240';
    end if;
    insert into public.app_notification_settings (key, value, updated_at)
    values ('review_eligible_minutes', p_review_eligible_minutes::text, now())
    on conflict (key) do update
      set value = excluded.value, updated_at = now();
  end if;

  return public.get_booking_settings();
end;
$$;

revoke all on function public.admin_set_booking_settings(int, int, int, int) from public;
grant execute on function public.admin_set_booking_settings(int, int, int, int) to authenticated;

-- ---------------------------------------------------------------------------
-- Drivers for a terminal/shift with booked flag (for timeslot lists)
-- ---------------------------------------------------------------------------
-- Drivers for a terminal/shift with booked flag (for timeslot lists)
create or replace function public.list_terminal_shift_drivers(
  p_terminal_id uuid,
  p_shift_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.full_name)
    from (
      select
        d.driver_id,
        d.full_name,
        d.plate_number,
        d.toda_number,
        d.is_active,
        d.status::text as status,
        d.terminal_id,
        d.shift_id,
        exists (
          select 1
          from public.bookings b
          where b.driver_id = d.driver_id
            and b.status = 'BOOKED'
        ) as is_booked,
        t.terminal_name,
        s.label as shift_label
      from public.drivers d
      left join public.terminals t on t.terminal_id = d.terminal_id
      left join public.shifts s on s.shift_id = d.shift_id
      where d.terminal_id = p_terminal_id
        and d.is_active = true
        and d.status = 'active'
        and (p_shift_id is null or d.shift_id = p_shift_id)
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.list_terminal_shift_drivers(uuid, uuid) from public;
grant execute on function public.list_terminal_shift_drivers(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Driver finishes booking early so they can accept another
-- ---------------------------------------------------------------------------
create or replace function public.complete_booking(p_booking_id uuid)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_name text;
begin
  perform public.reconcile_ride_workflow();

  if v_driver_id is null then raise exception 'Not authenticated'; end if;

  select * into v_booking
  from public.bookings
  where booking_id = p_booking_id
  for update;

  if not found then raise exception 'Booking not found'; end if;
  if v_booking.driver_id is distinct from v_driver_id then
    raise exception 'Not authorized';
  end if;
  if v_booking.status = 'COMPLETED' then
    return v_booking;
  end if;
  if v_booking.status is distinct from 'BOOKED' then
    raise exception 'Only active bookings can be finished';
  end if;

  update public.bookings
  set
    status = 'COMPLETED',
    completed_at = now(),
    updated_at = now()
  where booking_id = p_booking_id
    and status = 'BOOKED'
  returning * into v_booking;

  perform public.log_booking_event(
    'BOOKING_COMPLETED',
    v_booking.request_id,
    v_booking.booking_id,
    v_driver_id,
    jsonb_build_object('by', 'driver')
  );

  select full_name into v_name from public.drivers where driver_id = v_driver_id;
  perform public.emit_notification(
    v_booking.commuter_id, 'commuter', 'BOOKING_COMPLETED', 'Trip Finished',
    coalesce(nullif(trim(v_name), ''), 'Your driver') || ' marked this booking as finished.',
    'BOOKING_COMPLETED:' || v_booking.booking_id::text,
    v_driver_id, null,
    jsonb_build_object(
      'route', '/history',
      'booking_id', v_booking.booking_id::text,
      'driver_id', v_driver_id::text
    )
  );

  return v_booking;
end;
$$;

revoke all on function public.complete_booking(uuid) from public;
grant execute on function public.complete_booking(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Accept: block while driver already has an active BOOKED trip
-- ---------------------------------------------------------------------------
create or replace function public.accept_ride_request(p_request_id uuid)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_req public.ride_requests%rowtype;
  v_booking public.bookings%rowtype;
  v_review_mins int := public.booking_setting_int('review_eligible_minutes', 0);
  v_name text;
  v_passenger text;
begin
  perform public.reconcile_ride_workflow();

  if v_driver_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_req
  from public.ride_requests
  where request_id = p_request_id
  for update;

  if not found then
    raise exception 'Request not found';
  end if;
  if v_req.driver_id is distinct from v_driver_id then
    raise exception 'Not authorized to accept this request';
  end if;

  if v_req.status = 'ACCEPTED' then
    select * into v_booking from public.bookings where request_id = p_request_id;
    if found then return v_booking; end if;
  end if;

  if v_req.status = 'EXPIRED' or (v_req.status = 'PENDING' and v_req.expires_at <= now()) then
    update public.ride_requests
    set status = 'EXPIRED', updated_at = now(), responded_at = coalesce(responded_at, now())
    where request_id = p_request_id and status = 'PENDING';
    raise exception 'This request has expired';
  end if;

  if v_req.status is distinct from 'PENDING' then
    raise exception 'Request is no longer pending';
  end if;

  if exists (
    select 1 from public.bookings b
    where b.driver_id = v_driver_id
      and b.status = 'BOOKED'
  ) then
    raise exception 'Finish your current booking before accepting another request';
  end if;

  update public.ride_requests
  set status = 'ACCEPTED', responded_at = now(), updated_at = now()
  where request_id = p_request_id and status = 'PENDING'
  returning * into v_req;

  if not found then
    raise exception 'Request is no longer pending';
  end if;

  select coalesce(
    nullif(trim(v_req.passenger_name), ''),
    (select full_name from public.commuters where commuter_id = v_req.commuter_id)
  ) into v_passenger;

  insert into public.bookings (
    request_id, commuter_id, driver_id, status, confirmed_at,
    review_eligible_at, passenger_name
  ) values (
    v_req.request_id, v_req.commuter_id, v_req.driver_id, 'BOOKED', now(),
    now() + make_interval(mins => v_review_mins),
    v_passenger
  )
  on conflict (request_id) do update
    set updated_at = excluded.updated_at
  returning * into v_booking;

  perform public.log_booking_event(
    'REQUEST_ACCEPTED', v_req.request_id, v_booking.booking_id, v_driver_id, '{}'::jsonb
  );

  select full_name into v_name from public.drivers where driver_id = v_driver_id;
  perform public.emit_notification(
    v_req.commuter_id, 'commuter', 'REQUEST_ACCEPTED', 'Request Accepted',
    coalesce(nullif(trim(v_name), ''), 'The driver') || ' accepted your request.',
    'REQUEST_ACCEPTED:' || v_req.request_id::text,
    v_driver_id, null,
    jsonb_build_object(
      'route', '/history',
      'booking_id', v_booking.booking_id::text,
      'request_id', v_req.request_id::text,
      'driver_id', v_driver_id::text
    )
  );
  perform public.emit_notification(
    v_req.commuter_id, 'commuter', 'BOOKING_CONFIRMED', 'Booking Confirmed',
    coalesce(nullif(trim(v_name), ''), 'The driver') || ' accepted your request.',
    'BOOKING_CONFIRMED:' || v_booking.booking_id::text,
    v_driver_id, null,
    jsonb_build_object(
      'route', '/history',
      'booking_id', v_booking.booking_id::text,
      'request_id', v_req.request_id::text,
      'driver_id', v_driver_id::text
    )
  );

  return v_booking;
end;
$$;
