-- Drivers can see ratings/comments but not who left the review.
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

-- Scrub older notifications that named the reviewer.
update public.notifications
set message_content = 'A passenger left you a review.'
where event_type = 'NEW_DRIVER_REVIEW'
  and message_content ~* ' left you a review\.?$';
