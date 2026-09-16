-- PASAKAY: explicit customer request → driver accept → booking → review flow.
-- No GPS / fare / dispatch. Server time is authoritative.

-- ---------------------------------------------------------------------------
-- Settings (minutes)
-- ---------------------------------------------------------------------------
insert into public.app_notification_settings (key, value) values
  ('request_expire_minutes', '30'),
  ('dispute_window_minutes', '20'),
  ('review_eligible_minutes', '25'),
  ('request_cooldown_minutes', '30')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.ride_requests (
  request_id uuid primary key default gen_random_uuid(),
  commuter_id uuid not null references public.commuters (commuter_id),
  driver_id uuid not null references public.drivers (driver_id),
  status text not null
    check (status in ('PENDING', 'ACCEPTED', 'REJECTED', 'EXPIRED', 'CANCELLED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null,
  responded_at timestamptz
);

create index if not exists ride_requests_driver_status_idx
  on public.ride_requests (driver_id, status, created_at desc);
create index if not exists ride_requests_commuter_status_idx
  on public.ride_requests (commuter_id, status, created_at desc);

-- At most one PENDING request per (commuter, driver)
create unique index if not exists ride_requests_one_pending_per_pair
  on public.ride_requests (commuter_id, driver_id)
  where status = 'PENDING';

create table if not exists public.bookings (
  booking_id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.ride_requests (request_id),
  commuter_id uuid not null references public.commuters (commuter_id),
  driver_id uuid not null references public.drivers (driver_id),
  status text not null
    check (status in ('BOOKED', 'FLAGGED', 'COMPLETED', 'CANCELLED')),
  confirmed_at timestamptz not null default now(),
  completed_at timestamptz,
  cancelled_at timestamptz,
  flagged_at timestamptz,
  flagged_by uuid references public.drivers (driver_id),
  flag_reason text,
  flag_details text,
  review_eligible_at timestamptz not null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists bookings_driver_status_idx
  on public.bookings (driver_id, status, confirmed_at desc);
create index if not exists bookings_commuter_status_idx
  on public.bookings (commuter_id, status, confirmed_at desc);
create index if not exists bookings_auto_complete_idx
  on public.bookings (status, confirmed_at)
  where status = 'BOOKED';
create index if not exists bookings_review_due_idx
  on public.bookings (status, review_eligible_at)
  where status = 'COMPLETED' and reviewed_at is null;

alter table public.reviews
  add column if not exists booking_id uuid references public.bookings (booking_id);

create unique index if not exists reviews_one_per_booking
  on public.reviews (booking_id)
  where booking_id is not null;

create table if not exists public.review_reports (
  report_id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.reviews (review_id) on delete cascade,
  driver_id uuid not null references public.drivers (driver_id),
  reason text not null,
  details text,
  status text not null default 'OPEN'
    check (status in ('OPEN', 'RESOLVED', 'DISMISSED')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.admins (admin_id)
);

create unique index if not exists review_reports_one_open_per_pair
  on public.review_reports (review_id, driver_id)
  where status = 'OPEN';

create table if not exists public.booking_events (
  event_id uuid primary key default gen_random_uuid(),
  event_type text not null,
  request_id uuid references public.ride_requests (request_id) on delete set null,
  booking_id uuid references public.bookings (booking_id) on delete set null,
  actor_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists booking_events_created_idx
  on public.booking_events (created_at desc);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.booking_setting_int(p_key text, p_default int)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare v text;
begin
  v := public.notif_setting(p_key, p_default::text);
  begin
    return greatest(1, coalesce(nullif(trim(v), '')::int, p_default));
  exception when others then
    return p_default;
  end;
end;
$$;

create or replace function public.log_booking_event(
  p_event_type text,
  p_request_id uuid default null,
  p_booking_id uuid default null,
  p_actor_id uuid default null,
  p_details jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.booking_events (event_type, request_id, booking_id, actor_id, details)
  values (p_event_type, p_request_id, p_booking_id, p_actor_id, coalesce(p_details, '{}'::jsonb));
end;
$$;

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
  -- Expire overdue PENDING requests
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

  -- Auto-complete BOOKED past dispute window
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
        updated_at = now()
    where booking_id = r.booking_id and status = 'BOOKED';
    if found then
      v_completed := v_completed + 1;
      perform public.log_booking_event('BOOKING_COMPLETED', null, r.booking_id, null, '{}'::jsonb);
    end if;
  end loop;

  -- Review-available notifications for completed eligible bookings
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
        'route', '/history',
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

-- ---------------------------------------------------------------------------
-- Customer: create request
-- ---------------------------------------------------------------------------
create or replace function public.create_ride_request(p_driver_id uuid)
returns public.ride_requests
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

  if v_commuter_id is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1 from public.commuters c
    where c.commuter_id = v_commuter_id and c.status = 'active'
  ) then
    raise exception 'Only active passengers can send requests';
  end if;

  select * into v_driver from public.drivers where driver_id = p_driver_id;
  if not found then
    raise exception 'Driver not found';
  end if;
  if v_driver.status is distinct from 'active' or v_driver.is_active is not true then
    raise exception 'Driver is not available for requests';
  end if;
  if not coalesce(public.is_driver_on_shift(p_driver_id), false) then
    raise exception 'Driver is outside their scheduled operating period';
  end if;

  -- Existing PENDING
  select * into v_existing
  from public.ride_requests
  where commuter_id = v_commuter_id and driver_id = p_driver_id and status = 'PENDING'
  limit 1;
  if found then
    return v_existing;
  end if;

  -- Cooldown after BOOKED/COMPLETED
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

  insert into public.ride_requests (
    commuter_id, driver_id, status, expires_at
  ) values (
    v_commuter_id, p_driver_id, 'PENDING', now() + make_interval(mins => v_expire)
  )
  returning * into v_row;

  perform public.log_booking_event(
    'REQUEST_CREATED', v_row.request_id, null, v_commuter_id, '{}'::jsonb
  );

  select full_name into v_name from public.commuters where commuter_id = v_commuter_id;
  perform public.emit_notification(
    p_driver_id, 'driver', 'NEW_REQUEST', 'New Passenger Request',
    coalesce(nullif(trim(v_name), ''), 'A passenger') || ' sent you a request.',
    'NEW_REQUEST:' || v_row.request_id::text,
    p_driver_id, null,
    jsonb_build_object(
      'route', '/bookings',
      'request_id', v_row.request_id::text,
      'commuter_id', v_commuter_id::text
    )
  );

  return v_row;
exception
  when unique_violation then
    select * into v_existing
    from public.ride_requests
    where commuter_id = v_commuter_id and driver_id = p_driver_id and status = 'PENDING'
    limit 1;
    if found then return v_existing; end if;
    raise;
end;
$$;

-- ---------------------------------------------------------------------------
-- Driver: accept
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

  -- Idempotent: already accepted with booking
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

  insert into public.bookings (
    request_id, commuter_id, driver_id, status, confirmed_at, review_eligible_at
  ) values (
    v_req.request_id, v_req.commuter_id, v_req.driver_id, 'BOOKED', now(),
    now() + make_interval(mins => v_review_mins)
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
  -- Alias event for clients expecting BOOKING_CONFIRMED
  perform public.emit_notification(
    v_req.commuter_id, 'commuter', 'BOOKING_CONFIRMED', 'Booking Confirmed',
    coalesce(nullif(trim(v_name), ''), 'The driver') || ' accepted your request.',
    'BOOKING_CONFIRMED:' || v_booking.booking_id::text,
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

-- ---------------------------------------------------------------------------
-- Driver: reject
-- ---------------------------------------------------------------------------
create or replace function public.reject_ride_request(p_request_id uuid)
returns public.ride_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_req public.ride_requests%rowtype;
  v_name text;
begin
  perform public.reconcile_ride_workflow();

  if v_driver_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_req from public.ride_requests where request_id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.driver_id is distinct from v_driver_id then
    raise exception 'Not authorized';
  end if;
  if v_req.status = 'REJECTED' then return v_req; end if;
  if v_req.status is distinct from 'PENDING' then
    raise exception 'Request is no longer pending';
  end if;
  if v_req.expires_at <= now() then
    update public.ride_requests
    set status = 'EXPIRED', updated_at = now(), responded_at = now()
    where request_id = p_request_id;
    raise exception 'This request has expired';
  end if;

  update public.ride_requests
  set status = 'REJECTED', responded_at = now(), updated_at = now()
  where request_id = p_request_id and status = 'PENDING'
  returning * into v_req;

  perform public.log_booking_event(
    'REQUEST_REJECTED', v_req.request_id, null, v_driver_id, '{}'::jsonb
  );

  select full_name into v_name from public.drivers where driver_id = v_driver_id;
  perform public.emit_notification(
    v_req.commuter_id, 'commuter', 'REQUEST_REJECTED', 'Request Declined',
    coalesce(nullif(trim(v_name), ''), 'The driver') || ' declined your request.',
    'REQUEST_REJECTED:' || v_req.request_id::text,
    v_driver_id, null,
    jsonb_build_object(
      'route', '/history',
      'request_id', v_req.request_id::text,
      'driver_id', v_driver_id::text
    )
  );

  return v_req;
end;
$$;

-- ---------------------------------------------------------------------------
-- Driver: flag booking
-- ---------------------------------------------------------------------------
create or replace function public.flag_booking(
  p_booking_id uuid,
  p_reason text,
  p_details text default null
) returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_dispute int := public.booking_setting_int('dispute_window_minutes', 20);
begin
  perform public.reconcile_ride_workflow();

  if v_driver_id is null then raise exception 'Not authenticated'; end if;
  if nullif(trim(p_reason), '') is null then
    raise exception 'A dispute reason is required';
  end if;

  select * into v_booking from public.bookings where booking_id = p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if v_booking.driver_id is distinct from v_driver_id then
    raise exception 'Not authorized';
  end if;
  if v_booking.status = 'FLAGGED' then return v_booking; end if;
  if v_booking.status is distinct from 'BOOKED' then
    raise exception 'Only booked trips can be disputed';
  end if;
  if now() >= v_booking.confirmed_at + make_interval(mins => v_dispute) then
    raise exception 'The dispute window for this booking has expired.';
  end if;

  update public.bookings
  set status = 'FLAGGED',
      flagged_at = now(),
      flagged_by = v_driver_id,
      flag_reason = trim(p_reason),
      flag_details = nullif(trim(coalesce(p_details, '')), ''),
      updated_at = now()
  where booking_id = p_booking_id and status = 'BOOKED'
  returning * into v_booking;

  perform public.log_booking_event(
    'BOOKING_FLAGGED', v_booking.request_id, v_booking.booking_id, v_driver_id,
    jsonb_build_object('reason', v_booking.flag_reason)
  );

  perform public.emit_notification(
    v_booking.commuter_id, 'commuter', 'BOOKING_FLAGGED', 'Booking Disputed',
    'The driver reported an issue with this booking.',
    'BOOKING_FLAGGED:' || v_booking.booking_id::text,
    v_booking.driver_id, null,
    jsonb_build_object(
      'route', '/history',
      'booking_id', v_booking.booking_id::text,
      'driver_id', v_booking.driver_id::text
    )
  );

  return v_booking;
end;
$$;

-- ---------------------------------------------------------------------------
-- Customer: submit booking review
-- ---------------------------------------------------------------------------
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
  if now() < v_booking.review_eligible_at then
    raise exception 'Review is not available yet';
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

-- ---------------------------------------------------------------------------
-- Driver: report review
-- ---------------------------------------------------------------------------
create or replace function public.report_review(
  p_review_id uuid,
  p_reason text,
  p_details text default null
) returns public.review_reports
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_review public.reviews%rowtype;
  v_report public.review_reports%rowtype;
begin
  if v_driver_id is null then raise exception 'Not authenticated'; end if;
  if nullif(trim(p_reason), '') is null then
    raise exception 'A report reason is required';
  end if;

  select * into v_review from public.reviews where review_id = p_review_id;
  if not found then raise exception 'Review not found'; end if;
  if v_review.driver_id is distinct from v_driver_id then
    raise exception 'Not authorized';
  end if;

  select * into v_report
  from public.review_reports
  where review_id = p_review_id and driver_id = v_driver_id and status = 'OPEN'
  limit 1;
  if found then return v_report; end if;

  insert into public.review_reports (review_id, driver_id, reason, details)
  values (
    p_review_id, v_driver_id, trim(p_reason),
    nullif(trim(coalesce(p_details, '')), '')
  )
  returning * into v_report;

  perform public.log_booking_event(
    'REVIEW_REPORTED', null, v_review.booking_id, v_driver_id,
    jsonb_build_object('report_id', v_report.report_id, 'review_id', p_review_id)
  );

  return v_report;
exception
  when unique_violation then
    select * into v_report
    from public.review_reports
    where review_id = p_review_id and driver_id = v_driver_id and status = 'OPEN'
    limit 1;
    if found then return v_report; end if;
    raise;
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: dispute / report resolution
-- ---------------------------------------------------------------------------
create or replace function public.admin_resolve_disputed_booking(
  p_booking_id uuid,
  p_action text
) returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
begin
  if not public.is_system_admin() then
    raise exception 'Admin only';
  end if;
  if p_action not in ('restore', 'cancel') then
    raise exception 'Action must be restore or cancel';
  end if;

  select * into v_booking from public.bookings where booking_id = p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if v_booking.status is distinct from 'FLAGGED' then
    raise exception 'Only FLAGGED bookings can be resolved here';
  end if;

  if p_action = 'restore' then
    update public.bookings
    set status = 'COMPLETED',
        completed_at = coalesce(completed_at, now()),
        updated_at = now()
    where booking_id = p_booking_id
    returning * into v_booking;
    perform public.log_booking_event(
      'BOOKING_COMPLETED', v_booking.request_id, p_booking_id, auth.uid(),
      jsonb_build_object('admin_action', 'restore')
    );
  else
    update public.bookings
    set status = 'CANCELLED',
        cancelled_at = now(),
        updated_at = now()
    where booking_id = p_booking_id
    returning * into v_booking;
    perform public.log_booking_event(
      'BOOKING_CANCELLED', v_booking.request_id, p_booking_id, auth.uid(),
      jsonb_build_object('admin_action', 'cancel')
    );
  end if;

  return v_booking;
end;
$$;

create or replace function public.admin_resolve_review_report(
  p_report_id uuid,
  p_action text
) returns public.review_reports
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report public.review_reports%rowtype;
begin
  if not public.is_system_admin() then
    raise exception 'Admin only';
  end if;
  if p_action not in ('resolve', 'dismiss') then
    raise exception 'Action must be resolve or dismiss';
  end if;

  select * into v_report from public.review_reports where report_id = p_report_id for update;
  if not found then raise exception 'Report not found'; end if;
  if v_report.status is distinct from 'OPEN' then return v_report; end if;

  update public.review_reports
  set status = case when p_action = 'resolve' then 'RESOLVED' else 'DISMISSED' end,
      resolved_at = now(),
      resolved_by = auth.uid()
  where report_id = p_report_id
  returning * into v_report;

  perform public.log_booking_event(
    'REVIEW_REPORT_RESOLVED', null, null, auth.uid(),
    jsonb_build_object('report_id', p_report_id, 'action', p_action)
  );

  return v_report;
end;
$$;

-- Context helpers for UI
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
begin
  perform public.reconcile_ride_workflow();

  v_on_shift := coalesce(public.is_driver_on_shift(p_driver_id), false);

  if v_commuter_id is null then
    return jsonb_build_object('on_shift', v_on_shift, 'can_request', false, 'reason', 'Not signed in');
  end if;

  select * into v_req
  from public.ride_requests
  where commuter_id = v_commuter_id and driver_id = p_driver_id
  order by created_at desc
  limit 1;

  if found and v_req.status = 'PENDING' then
    v_can_request := false;
    v_reason := 'Request pending';
  elsif found and v_req.status = 'ACCEPTED' then
    select * into v_booking from public.bookings where request_id = v_req.request_id;
  end if;

  if v_can_request then
    if exists (
      select 1 from public.bookings b
      where b.commuter_id = v_commuter_id
        and b.driver_id = p_driver_id
        and b.status in ('BOOKED', 'COMPLETED')
        and b.confirmed_at + make_interval(mins => v_cooldown) > now()
    ) then
      v_can_request := false;
      v_reason := 'Cooldown active';
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
    'call_sms_enabled', coalesce(v_booking.status in ('BOOKED', 'COMPLETED'), false),
    'server_now', now()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.ride_requests enable row level security;
alter table public.bookings enable row level security;
alter table public.review_reports enable row level security;
alter table public.booking_events enable row level security;

drop policy if exists "ride_requests_select_own" on public.ride_requests;
create policy "ride_requests_select_own" on public.ride_requests
  for select using (
    commuter_id = auth.uid()
    or driver_id = auth.uid()
    or public.is_system_admin()
  );

drop policy if exists "bookings_select_own" on public.bookings;
create policy "bookings_select_own" on public.bookings
  for select using (
    commuter_id = auth.uid()
    or driver_id = auth.uid()
    or public.is_system_admin()
  );

drop policy if exists "review_reports_select" on public.review_reports;
create policy "review_reports_select" on public.review_reports
  for select using (
    driver_id = auth.uid()
    or public.is_system_admin()
  );

drop policy if exists "booking_events_admin_select" on public.booking_events;
create policy "booking_events_admin_select" on public.booking_events
  for select using (public.is_system_admin());

-- Mutations go through security definer RPCs only
revoke all on function public.create_ride_request(uuid) from public;
grant execute on function public.create_ride_request(uuid) to authenticated;
revoke all on function public.accept_ride_request(uuid) from public;
grant execute on function public.accept_ride_request(uuid) to authenticated;
revoke all on function public.reject_ride_request(uuid) from public;
grant execute on function public.reject_ride_request(uuid) to authenticated;
revoke all on function public.flag_booking(uuid, text, text) from public;
grant execute on function public.flag_booking(uuid, text, text) to authenticated;
revoke all on function public.submit_booking_review(uuid, int, text) from public;
grant execute on function public.submit_booking_review(uuid, int, text) to authenticated;
revoke all on function public.report_review(uuid, text, text) from public;
grant execute on function public.report_review(uuid, text, text) to authenticated;
revoke all on function public.get_driver_request_context(uuid) from public;
grant execute on function public.get_driver_request_context(uuid) to authenticated;
revoke all on function public.admin_resolve_disputed_booking(uuid, text) from public;
grant execute on function public.admin_resolve_disputed_booking(uuid, text) to authenticated;
revoke all on function public.admin_resolve_review_report(uuid, text) from public;
grant execute on function public.admin_resolve_review_report(uuid, text) to authenticated;
revoke all on function public.reconcile_ride_workflow() from public;
grant execute on function public.reconcile_ride_workflow() to authenticated, service_role;

-- Cron: piggyback every minute with schedule notifications
select cron.schedule(
  'pasakay-reconcile-ride-workflow',
  '* * * * *',
  'select public.reconcile_ride_workflow()'
) where not exists (
  select 1 from cron.job where jobname = 'pasakay-reconcile-ride-workflow'
);
