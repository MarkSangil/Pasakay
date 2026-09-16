-- Post-trip report/review rules + allow rebooking after a finished booking.
-- - Report only on COMPLETED bookings that are not yet reviewed
-- - Review blocked if passenger already reported (and vice versa)
-- - No cooldown after COMPLETED (passenger may request the same driver again)

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
  v_can_request boolean := true;
  v_reason text := null;
  v_status text;
  v_peer_contact text := null;
  v_can_report boolean := false;
  v_can_review boolean := false;
  v_report_booking_id uuid := null;
  v_review_booking_id uuid := null;
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
      'can_review', false,
      'reportable_booking_id', null,
      'reviewable_booking_id', null,
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

  -- Active booking (in progress)
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
    end if;

    -- Latest finished booking for report/review (not cancelled via report)
    select * into v_booking
    from public.bookings b
    where b.commuter_id = v_commuter_id
      and b.driver_id = p_driver_id
      and b.status = 'COMPLETED'
    order by coalesce(b.completed_at, b.confirmed_at) desc
    limit 1;

    if found then
      if v_booking.passenger_reported_at is null
         and v_booking.reviewed_at is null then
        v_can_report := true;
        v_can_review := true;
        v_report_booking_id := v_booking.booking_id;
        v_review_booking_id := v_booking.booking_id;
      elsif v_booking.reviewed_at is not null then
        v_can_report := false;
        v_can_review := false;
      elsif v_booking.passenger_reported_at is not null then
        v_can_report := false;
        v_can_review := false;
      end if;
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
    'can_review', v_can_review,
    'reportable_booking_id', v_report_booking_id,
    'reviewable_booking_id', v_review_booking_id,
    'peer_contact', v_peer_contact,
    'server_now', now()
  );
end;
$$;

create or replace function public.create_ride_request(p_driver_id uuid)
returns public.ride_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commuter_id uuid := auth.uid();
  v_expire int := public.booking_setting_int('request_expire_minutes', 30);
  v_driver public.drivers%rowtype;
  v_existing public.ride_requests%rowtype;
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

  -- Finished bookings no longer block rebooking.

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
  if v_booking.status is distinct from 'COMPLETED' then
    raise exception 'You can only report after the booking is finished';
  end if;
  if v_booking.reviewed_at is not null
     or exists (select 1 from public.reviews r where r.booking_id = p_booking_id) then
    raise exception 'This booking was already reviewed and cannot be reported';
  end if;

  update public.bookings
  set
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
    v_booking.driver_id, 'driver', 'BOOKING_FLAGGED', 'Passenger Report',
    coalesce(nullif(trim(v_name), ''), 'A passenger')
      || ' reported a finished trip for review.',
    'BOOKING_FLAGGED:' || v_booking.booking_id::text,
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

create or replace function public.submit_booking_review(
  p_booking_id uuid,
  p_rating int,
  p_content text default null
) returns public.reviews
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commuter_id uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_review public.reviews%rowtype;
begin
  perform public.reconcile_ride_workflow();

  if v_commuter_id is null then raise exception 'Not authenticated'; end if;
  if p_rating < 1 or p_rating > 5 then raise exception 'Rating must be 1 to 5'; end if;

  select * into v_booking from public.bookings where booking_id = p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if v_booking.commuter_id is distinct from v_commuter_id then
    raise exception 'Not authorized';
  end if;
  if v_booking.status is distinct from 'COMPLETED' then
    raise exception 'Only completed bookings can be reviewed';
  end if;
  if v_booking.passenger_reported_at is not null then
    raise exception 'This booking was reported and cannot be reviewed';
  end if;
  if v_booking.reviewed_at is not null
     or exists (select 1 from public.reviews r where r.booking_id = p_booking_id) then
    raise exception 'This booking was already reviewed';
  end if;

  insert into public.reviews (commuter_id, driver_id, rating, content, booking_id)
  values (
    v_commuter_id,
    v_booking.driver_id,
    p_rating::smallint,
    nullif(trim(coalesce(p_content, '')), ''),
    p_booking_id
  )
  returning * into v_review;

  update public.bookings
  set reviewed_at = now(), updated_at = now()
  where booking_id = p_booking_id;

  perform public.log_booking_event(
    'REVIEW_SUBMITTED', v_booking.request_id, p_booking_id, v_commuter_id,
    jsonb_build_object('rating', p_rating)
  );

  perform public.emit_notification(
    v_booking.driver_id, 'driver', 'NEW_DRIVER_REVIEW', 'New Review',
    'A passenger left you a review.',
    'NEW_DRIVER_REVIEW:' || v_review.review_id::text,
    v_booking.driver_id, null,
    jsonb_build_object(
      'route', '/reviews',
      'review_id', v_review.review_id::text,
      'booking_id', p_booking_id::text
    )
  );

  return v_review;
end;
$$;
