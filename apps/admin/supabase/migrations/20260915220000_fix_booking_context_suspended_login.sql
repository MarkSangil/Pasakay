-- Suspended may log in; deactivated may not.
-- Active BOOKED blocks new requests; completed bookings are not shown as active context.

create or replace function public.admin_set_commuter_status(
  p_commuter_id uuid,
  p_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status public.account_status;
begin
  perform public.assert_system_admin();

  begin
    v_status := p_status::public.account_status;
  exception when invalid_text_representation then
    raise exception 'Unknown account status';
  end;

  if v_status = 'pending_verification' then
    raise exception 'Use Active to approve a passenger account';
  end if;
  if not exists (select 1 from public.commuters where commuter_id = p_commuter_id) then
    raise exception 'Commuter not found';
  end if;
  if v_status in ('suspended', 'deactivated') and nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required to suspend or deactivate a commuter';
  end if;

  update public.commuters
  set
    status = v_status,
    status_reason = case
      when v_status = 'active' then null
      else nullif(trim(coalesce(p_reason, '')), '')
    end
  where commuter_id = p_commuter_id;

  -- Deactivated blocks login; suspended may log in but cannot book.
  perform public.set_auth_login_allowed(
    p_commuter_id,
    v_status in ('active', 'suspended')
  );
end;
$$;

create or replace function public.admin_set_driver_status(
  p_driver_id uuid,
  p_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_verified boolean;
  v_status public.account_status;
begin
  perform public.assert_system_admin();

  begin
    v_status := p_status::public.account_status;
  exception when invalid_text_representation then
    raise exception 'Unknown account status';
  end;

  select license_verified into v_verified
  from public.drivers
  where driver_id = p_driver_id;
  if not found then
    raise exception 'Driver not found';
  end if;

  if v_status = 'active' and not coalesce(v_verified, false) then
    raise exception 'License must be visually verified before activation. This is a manual check only — PASAKAY does not validate against a government database.';
  end if;
  if v_status in ('suspended', 'deactivated') and nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required to suspend or deactivate a driver';
  end if;

  update public.drivers
  set
    status = v_status,
    is_active = (v_status = 'active'),
    status_reason = case
      when v_status = 'active' then null
      else nullif(trim(coalesce(p_reason, '')), '')
    end,
    updated_at = now()
  where driver_id = p_driver_id;

  -- Deactivated blocks login; suspended may log in (cannot accept — is_active false).
  perform public.set_auth_login_allowed(
    p_driver_id,
    v_status in ('active', 'suspended')
  );
end;
$$;

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
begin
  perform public.reconcile_ride_workflow();

  v_on_shift := coalesce(public.is_driver_on_shift(p_driver_id), false);

  if v_commuter_id is null then
    return jsonb_build_object(
      'on_shift', v_on_shift,
      'can_request', false,
      'reason', 'Not signed in',
      'call_sms_enabled', false,
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

  -- Active booking only (not completed/cancelled).
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
    'server_now', now()
  );
end;
$$;

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

  -- Never allow a second request while an active booking exists.
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

  insert into public.ride_requests (commuter_id, driver_id, status, expires_at)
  values (v_commuter_id, p_driver_id, 'PENDING', now() + make_interval(mins => v_expire))
  returning * into v_row;

  perform public.log_booking_event('REQUEST_CREATED', v_row.request_id, null, v_commuter_id, '{}'::jsonb);

  select full_name into v_name from public.commuters where commuter_id = v_commuter_id;
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
