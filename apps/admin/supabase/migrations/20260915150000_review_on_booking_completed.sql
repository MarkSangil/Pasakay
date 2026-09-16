-- Reviews unlock when a booking becomes COMPLETED; one review per booking.
update public.app_notification_settings
set value = '0'
where key = 'review_eligible_minutes';

update public.bookings
set review_eligible_at = least(review_eligible_at, coalesce(completed_at, now())),
    updated_at = now()
where status = 'COMPLETED'
  and reviewed_at is null;

create or replace function public.reconcile_ride_workflow()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expired int := 0;
  v_completed int := 0;
  v_reviews int := 0;
  r record;
  v_name text;
begin
  for r in
    select request_id, commuter_id, driver_id
    from public.ride_requests
    where status = 'PENDING' and expires_at <= now()
    for update skip locked
  loop
    update public.ride_requests
    set status = 'EXPIRED', updated_at = now(), responded_at = coalesce(responded_at, now())
    where request_id = r.request_id and status = 'PENDING';
    if found then
      v_expired := v_expired + 1;
      perform public.log_booking_event('REQUEST_EXPIRED', r.request_id, null, null, '{}'::jsonb);
      select full_name into v_name from public.drivers where driver_id = r.driver_id;
      perform public.emit_notification(
        r.commuter_id, 'commuter', 'REQUEST_EXPIRED', 'Request Expired',
        'Your request to ' || coalesce(nullif(trim(v_name), ''), 'the driver') || ' expired.',
        'REQUEST_EXPIRED:' || r.request_id::text,
        r.driver_id, null,
        jsonb_build_object('route', '/history', 'request_id', r.request_id::text, 'driver_id', r.driver_id::text)
      );
    end if;
  end loop;

  for r in
    select b.booking_id, b.commuter_id, b.driver_id, b.confirmed_at, b.review_eligible_at,
           d.full_name as driver_name
    from public.bookings b
    join public.drivers d on d.driver_id = b.driver_id
    where b.status = 'BOOKED'
      and b.confirmed_at + make_interval(mins => public.booking_setting_int('dispute_window_minutes', 20)) <= now()
    for update of b skip locked
  loop
    update public.bookings
    set status = 'COMPLETED',
        completed_at = now(),
        review_eligible_at = least(review_eligible_at, now()),
        updated_at = now()
    where booking_id = r.booking_id and status = 'BOOKED';
    if found then
      v_completed := v_completed + 1;
      perform public.log_booking_event('BOOKING_COMPLETED', null, r.booking_id, null, '{}'::jsonb);
    end if;
  end loop;

  for r in
    select b.booking_id, b.commuter_id, b.driver_id, d.full_name as driver_name
    from public.bookings b
    join public.drivers d on d.driver_id = b.driver_id
    where b.status = 'COMPLETED'
      and b.reviewed_at is null
      and b.review_eligible_at <= now()
      and not exists (select 1 from public.reviews rv where rv.booking_id = b.booking_id)
  loop
    if public.emit_notification(
      r.commuter_id, 'commuter', 'REVIEW_AVAILABLE', 'Review Available',
      'You can now review ' || coalesce(nullif(trim(r.driver_name), ''), 'your driver') || '.',
      'REVIEW_AVAILABLE:' || r.booking_id::text,
      r.driver_id, null,
      jsonb_build_object(
        'route', '/review',
        'booking_id', r.booking_id::text,
        'driver_id', r.driver_id::text
      )
    ) is not null then
      v_reviews := v_reviews + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'expired_requests', v_expired,
    'completed_bookings', v_completed,
    'review_notifications', v_reviews,
    'checked_at', now()
  );
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
  v_name text;
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

  select full_name into v_name from public.commuters where commuter_id = v_commuter_id;
  perform public.emit_notification(
    v_booking.driver_id, 'driver', 'NEW_DRIVER_REVIEW', 'New Review',
    coalesce(nullif(trim(v_name), ''), 'A passenger') || ' left you a review.',
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
