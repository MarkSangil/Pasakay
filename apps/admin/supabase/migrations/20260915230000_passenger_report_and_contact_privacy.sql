-- Passenger can report a driver during/after a booking (cancels the booking).
-- Contact numbers are only exposed while a booking is BOOKED (accepted).

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------
alter table public.ride_requests
  add column if not exists passenger_name text;

alter table public.bookings
  add column if not exists passenger_name text;

alter table public.bookings
  add column if not exists passenger_reported_at timestamptz;

-- Allow flagged_by to be either party (driver dispute or passenger report).
alter table public.bookings
  drop constraint if exists bookings_flagged_by_fkey;

create index if not exists bookings_passenger_reported_idx
  on public.bookings (passenger_reported_at desc)
  where passenger_reported_at is not null;

-- Snapshot passenger name on existing rows.
update public.ride_requests r
set passenger_name = c.full_name
from public.commuters c
where c.commuter_id = r.commuter_id
  and (r.passenger_name is null or r.passenger_name = '');

update public.bookings b
set passenger_name = coalesce(b.passenger_name, c.full_name)
from public.commuters c
where c.commuter_id = b.commuter_id
  and (b.passenger_name is null or b.passenger_name = '');

-- ---------------------------------------------------------------------------
-- Contact: only during BOOKED
-- ---------------------------------------------------------------------------
create or replace function public.peer_contact_for_active_booking(p_peer_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_contact text;
begin
  if v_uid is null or p_peer_id is null then
    return null;
  end if;

  if not exists (
    select 1
    from public.bookings b
    where b.status = 'BOOKED'
      and (
        (b.commuter_id = v_uid and b.driver_id = p_peer_id)
        or (b.driver_id = v_uid and b.commuter_id = p_peer_id)
      )
  ) then
    return null;
  end if;

  select d.contact_number into v_contact
  from public.drivers d
  where d.driver_id = p_peer_id;

  if v_contact is not null then
    return v_contact;
  end if;

  select c.contact_number into v_contact
  from public.commuters c
  where c.commuter_id = p_peer_id;

  return v_contact;
end;
$$;

revoke all on function public.peer_contact_for_active_booking(uuid) from public;
grant execute on function public.peer_contact_for_active_booking(uuid) to authenticated;

-- Drivers may read passenger rows only while BOOKED (for contact join).
-- Names for history/pending use passenger_name snapshots on requests/bookings.
drop policy if exists "commuters_select_related_driver" on public.commuters;
create policy "commuters_select_related_driver"
  on public.commuters
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.bookings b
      where b.commuter_id = commuters.commuter_id
        and b.driver_id = auth.uid()
        and b.status = 'BOOKED'
    )
  );

-- ---------------------------------------------------------------------------
-- create_ride_request: snapshot passenger name
-- ---------------------------------------------------------------------------
create or replace function public.create_ride_request(p_driver_id uuid)
returns ride_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commuter_id uuid := auth.uid();
  v_expire int := public.booking_setting_int('request_expire_minutes', 30);
  v_cooldown int := public.booking_setting_int('request_cooldown_minutes', 30);
  v_driver public.drivers%rowtype;
  v_existing public.ride_requests%rowtype;
  v_booking public.bookings%rowtype;
  v_row public.ride_requests%rowtype;
  v_name text;
begin
  perform public.reconcile_ride_workflow();
  if v_commuter_id is null then raise exception 'Not authenticated'; end if;

  if not exists (
    select 1 from public.commuters c
    where c.commuter_id = v_commuter_id and c.status = 'active'
  ) then
    raise exception 'Only active passengers can send requests';
  end if;

  select * into v_driver from public.drivers where driver_id = p_driver_id;
  if not found then raise exception 'Driver not found'; end if;
  if v_driver.status is distinct from 'active' or v_driver.is_active is not true then
    raise exception 'Driver is not available for requests';
  end if;
  if not coalesce(public.is_driver_on_shift(p_driver_id), false) then
    raise exception 'Driver is outside their scheduled operating period';
  end if;

  select * into v_existing
  from public.ride_requests
  where commuter_id = v_commuter_id
    and driver_id = p_driver_id
    and status = 'PENDING'
  limit 1;
  if found then return v_existing; end if;

  if exists (
    select 1 from public.bookings b
    where b.commuter_id = v_commuter_id
      and b.driver_id = p_driver_id
      and b.status = 'BOOKED'
  ) then
    raise exception 'You already have an active booking with this driver';
  end if;

  select * into v_booking
  from public.bookings
  where commuter_id = v_commuter_id
    and driver_id = p_driver_id
    and status in ('BOOKED', 'COMPLETED')
    and confirmed_at + make_interval(mins => v_cooldown) > now()
  order by confirmed_at desc
  limit 1;
  if found then
    raise exception 'Please wait before requesting this driver again';
  end if;

  select full_name into v_name from public.commuters where commuter_id = v_commuter_id;

  insert into public.ride_requests (
    commuter_id, driver_id, status, expires_at, passenger_name
  ) values (
    v_commuter_id, p_driver_id, 'PENDING',
    now() + make_interval(mins => v_expire),
    v_name
  )
  returning * into v_row;

  perform public.log_booking_event(
    'REQUEST_CREATED', v_row.request_id, null, v_commuter_id, '{}'::jsonb
  );

  perform public.emit_notification(
    p_driver_id, 'driver', 'NEW_REQUEST', 'New Passenger Request',
    coalesce(nullif(trim(v_name), ''), 'A passenger') || ' sent you a request.',
    'NEW_REQUEST:' || v_row.request_id::text, p_driver_id, null,
    jsonb_build_object(
      'route', '/bookings',
      'request_id', v_row.request_id::text,
      'commuter_id', v_commuter_id::text
    )
  );
  return v_row;
exception when unique_violation then
  select * into v_existing
  from public.ride_requests
  where commuter_id = v_commuter_id
    and driver_id = p_driver_id
    and status = 'PENDING'
  limit 1;
  if found then return v_existing; end if;
  raise;
end;
$$;

-- ---------------------------------------------------------------------------
-- accept_ride_request: snapshot passenger name onto booking
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
  v_review_mins int := public.booking_setting_int('review_eligible_minutes', 25);
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

-- ---------------------------------------------------------------------------
-- Request context: peer contact only while BOOKED; can_report flag
-- ---------------------------------------------------------------------------
create or replace function public.get_driver_request_context(p_driver_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commuter_id uuid := auth.uid();
  v_req public.ride_requests%rowtype;
  v_booking public.bookings%rowtype;
  v_on_shift boolean;
  v_cooldown int := public.booking_setting_int('request_cooldown_minutes', 30);
  v_can_request boolean := true;
  v_reason text := null;
  v_status text;
  v_peer_contact text := null;
  v_can_report boolean := false;
  v_report_booking_id uuid := null;
begin
  perform public.reconcile_ride_workflow();

  v_on_shift := coalesce(public.is_driver_on_shift(p_driver_id), false);

  if v_commuter_id is null then
    return jsonb_build_object(
      'on_shift', v_on_shift,
      'can_request', false,
      'reason', 'Not signed in',
      'call_sms_enabled', false,
      'can_report', false,
      'reportable_booking_id', null,
      'peer_contact', null,
      'server_now', now()
    );
  end if;

  select c.status::text into v_status
  from public.commuters c
  where c.commuter_id = v_commuter_id;

  if v_status is distinct from 'active' then
    v_can_request := false;
    v_reason := case
      when v_status = 'suspended' then 'Account suspended — booking disabled'
      when v_status = 'pending_verification' then 'Account pending approval'
      when v_status = 'deactivated' then 'Account deactivated'
      else 'Account cannot book'
    end;
  end if;

  select * into v_booking
  from public.bookings
  where commuter_id = v_commuter_id
    and driver_id = p_driver_id
    and status = 'BOOKED'
  order by confirmed_at desc
  limit 1;

  if found then
    v_can_request := false;
    v_reason := coalesce(v_reason, 'Booking confirmed');
    v_can_report := true;
    v_report_booking_id := v_booking.booking_id;
    v_peer_contact := public.peer_contact_for_active_booking(p_driver_id);
    select * into v_req
    from public.ride_requests
    where request_id = v_booking.request_id;
  else
    select * into v_req
    from public.ride_requests
    where commuter_id = v_commuter_id
      and driver_id = p_driver_id
      and status = 'PENDING'
    order by created_at desc
    limit 1;

    if found then
      v_can_request := false;
      v_reason := coalesce(v_reason, 'Request pending');
    elsif v_can_request then
      if exists (
        select 1 from public.bookings b
        where b.commuter_id = v_commuter_id
          and b.driver_id = p_driver_id
          and b.status in ('BOOKED', 'COMPLETED')
          and b.confirmed_at + make_interval(mins => v_cooldown) > now()
      ) then
        v_can_request := false;
        v_reason := 'Cooldown — try again later';
      end if;
    end if;

    -- After booking: allow report on latest COMPLETED (not already passenger-reported).
    select b.booking_id into v_report_booking_id
    from public.bookings b
    where b.commuter_id = v_commuter_id
      and b.driver_id = p_driver_id
      and b.status = 'COMPLETED'
      and b.passenger_reported_at is null
    order by b.confirmed_at desc
    limit 1;
    if v_report_booking_id is not null then
      v_can_report := true;
    end if;
  end if;

  if v_can_request and not v_on_shift then
    v_can_request := false;
    v_reason := 'Driver outside schedule';
  end if;

  return jsonb_build_object(
    'on_shift', v_on_shift,
    'can_request', v_can_request,
    'reason', v_reason,
    'request', case when v_req.request_id is null then null else to_jsonb(v_req) end,
    'booking', case when v_booking.booking_id is null then null else to_jsonb(v_booking) end,
    'call_sms_enabled', coalesce(v_booking.status = 'BOOKED', false),
    'can_report', v_can_report,
    'reportable_booking_id', v_report_booking_id,
    'peer_contact', v_peer_contact,
    'server_now', now()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Passenger reports driver → cancel booking
-- ---------------------------------------------------------------------------
create or replace function public.report_driver_booking(
  p_booking_id uuid,
  p_reason text,
  p_details text default null
) returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commuter_id uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_name text;
begin
  perform public.reconcile_ride_workflow();

  if v_commuter_id is null then raise exception 'Not authenticated'; end if;
  if nullif(trim(p_reason), '') is null then
    raise exception 'A report reason is required';
  end if;

  select * into v_booking
  from public.bookings
  where booking_id = p_booking_id
  for update;

  if not found then raise exception 'Booking not found'; end if;
  if v_booking.commuter_id is distinct from v_commuter_id then
    raise exception 'Not authorized';
  end if;
  if v_booking.passenger_reported_at is not null then
    return v_booking;
  end if;
  if v_booking.status not in ('BOOKED', 'COMPLETED', 'FLAGGED') then
    raise exception 'This booking cannot be reported';
  end if;

  update public.bookings
  set
    status = 'CANCELLED',
    cancelled_at = coalesce(cancelled_at, now()),
    passenger_reported_at = now(),
    flagged_at = coalesce(flagged_at, now()),
    flagged_by = v_commuter_id,
    flag_reason = trim(p_reason),
    flag_details = nullif(trim(coalesce(p_details, '')), ''),
    updated_at = now()
  where booking_id = p_booking_id
  returning * into v_booking;

  perform public.log_booking_event(
    'PASSENGER_REPORTED_DRIVER',
    v_booking.request_id,
    v_booking.booking_id,
    v_commuter_id,
    jsonb_build_object('reason', v_booking.flag_reason)
  );

  select full_name into v_name
  from public.commuters
  where commuter_id = v_commuter_id;

  perform public.emit_notification(
    v_booking.driver_id, 'driver', 'BOOKING_CANCELLED', 'Booking Cancelled',
    coalesce(nullif(trim(v_name), ''), 'A passenger')
      || ' reported this trip and the booking was cancelled.',
    'BOOKING_CANCELLED:' || v_booking.booking_id::text,
    v_booking.driver_id, null,
    jsonb_build_object(
      'route', '/bookings',
      'booking_id', v_booking.booking_id::text,
      'commuter_id', v_commuter_id::text
    )
  );

  return v_booking;
end;
$$;

revoke all on function public.report_driver_booking(uuid, text, text) from public;
grant execute on function public.report_driver_booking(uuid, text, text) to authenticated;
