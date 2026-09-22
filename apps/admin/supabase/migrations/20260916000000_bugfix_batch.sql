-- Bug fix batch:
--  1. Auto-finish / dispute timer default 20 -> 60 minutes.
--  2. Terminal lists must use the driver's EFFECTIVE terminal
--     (coalesce(current_terminal_id, terminal_id)) so a driver's "where I am
--     today" pick is visible to passengers.
--  3. 'suspended' == 'deactivated': migrate rows, stop accepting/labeling
--     suspended as a separate status.
--  4. Plate (ABC-1234) and driver's license (D00-00-000000) format
--     enforcement at registration and admin create.
--  5. get_login_status RPC so apps can show "waiting for admin approval"
--     instead of a raw auth error for banned/pending accounts.
--  6. Driver operating-hours (shift) change requests with admin approval.
--  7. Reactivating a driver clears current_terminal_id so the first screen
--     after approval is "Where are you today?" (terminal picker).

-- ============================================================================
-- 1. Booking / dispute timer = 60 minutes
-- ============================================================================

insert into public.app_notification_settings (key, value, updated_at)
values ('dispute_window_minutes', '60', now())
on conflict (key) do update
  set value = '60', updated_at = now();

create or replace function public.get_booking_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'dispute_window_minutes', public.booking_setting_int('dispute_window_minutes', 60),
    'request_expire_minutes', public.booking_setting_int('request_expire_minutes', 30),
    'request_cooldown_minutes', public.booking_setting_int('request_cooldown_minutes', 30),
    'review_eligible_minutes', public.booking_setting_int('review_eligible_minutes', 0)
  );
end;
$$;

revoke all on function public.get_booking_settings() from public;
grant execute on function public.get_booking_settings() to authenticated;

-- ============================================================================
-- 2. Terminal driver lists use the driver's effective (current) terminal
-- ============================================================================

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
        -- Effective terminal: where the driver is today, else the assigned one.
        coalesce(d.current_terminal_id, d.terminal_id) as terminal_id,
        d.terminal_id as assigned_terminal_id,
        d.current_terminal_id,
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
      left join public.terminals t
        on t.terminal_id = coalesce(d.current_terminal_id, d.terminal_id)
      left join public.shifts s on s.shift_id = d.shift_id
      where coalesce(d.current_terminal_id, d.terminal_id) = p_terminal_id
        and d.is_active = true
        and d.status = 'active'
        and (p_shift_id is null or d.shift_id = p_shift_id)
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.list_terminal_shift_drivers(uuid, uuid) from public;
grant execute on function public.list_terminal_shift_drivers(uuid, uuid) to authenticated;

-- ============================================================================
-- 3. 'suspended' -> 'deactivated'
-- ============================================================================

do $$
declare
  r record;
begin
  for r in select driver_id from public.drivers where status = 'suspended' loop
    update public.drivers
       set status = 'deactivated',
           is_active = false,
           status_reason = coalesce(nullif(status_reason, ''), 'Converted from suspended to deactivated.'),
           updated_at = now()
     where driver_id = r.driver_id;
    -- Suspended may log in; deactivated may not.
    perform public.set_auth_login_allowed(r.driver_id, false);
  end loop;

  for r in select commuter_id from public.commuters where status = 'suspended' loop
    update public.commuters
       set status = 'deactivated',
           status_reason = coalesce(nullif(status_reason, ''), 'Converted from suspended to deactivated.')
     where commuter_id = r.commuter_id;
    perform public.set_auth_login_allowed(r.commuter_id, false);
  end loop;
end $$;

-- Admin overview: the "suspended" metric now means deactivated accounts too.
create or replace function public.admin_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_system_admin();
  return jsonb_build_object(
    'drivers_total', (select count(*)::int from public.drivers),
    'drivers_pending', (select count(*)::int from public.drivers where status = 'pending_verification'),
    'drivers_active', (select count(*)::int from public.drivers where status = 'active'),
    'drivers_suspended', (select count(*)::int from public.drivers where status in ('suspended', 'deactivated')),
    'commuters_total', (select count(*)::int from public.commuters),
    'commuters_suspended', (select count(*)::int from public.commuters where status in ('suspended', 'deactivated')),
    'terminals', (select count(*)::int from public.terminals),
    'shifts', (select count(*)::int from public.shifts),
    'reviews_visible', (select count(*)::int from public.reviews where is_hidden = false),
    'reviews_hidden', (select count(*)::int from public.reviews where is_hidden = true),
    'requests_pending', (select count(*)::int from public.ride_requests where status = 'PENDING'),
    'requests_total', (select count(*)::int from public.ride_requests),
    'bookings_booked', (select count(*)::int from public.bookings where status = 'BOOKED'),
    'bookings_completed', (select count(*)::int from public.bookings where status = 'COMPLETED'),
    'bookings_flagged', (select count(*)::int from public.bookings where status = 'FLAGGED'),
    'bookings_cancelled', (select count(*)::int from public.bookings where status = 'CANCELLED'),
    'bookings_total', (select count(*)::int from public.bookings),
    'review_reports_open', (select count(*)::int from public.review_reports where status = 'OPEN'),
    'crash_logs', (select count(*)::int from public.device_logs where crash_error_log is not null and crash_error_log <> ''),
    'device_logs', (select count(*)::int from public.device_logs),
    'privacy_open', (select count(*)::int from public.privacy_requests where status in ('received', 'in_progress')),
    'generated_at', now()
  );
end;
$$;

revoke all on function public.admin_overview() from public;
grant execute on function public.admin_overview() to authenticated;

-- Suspended is no longer settable; deactivated is the single blocked status.
-- Reactivation (active) also clears current_terminal_id so the driver picks
-- "Where are you today?" again on first login after approval.
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

  if v_status = 'suspended' then
    raise exception 'Suspended has been replaced by Deactivated. Choose Deactivated instead.';
  end if;

  select license_verified into v_verified
  from public.drivers
  where driver_id = p_driver_id;
  if not found then
    raise exception 'Driver not found';
  end if;

  if v_status = 'active' and not coalesce(v_verified, false) then
    raise exception 'License must be visually verified before activation. This is a manual check only — PASAKAY does not validate against a government database.';
  end if;
  if v_status = 'deactivated' and nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required to deactivate a driver';
  end if;

  update public.drivers
  set
    status = v_status,
    is_active = (v_status = 'active'),
    -- First login after (re)approval must show the terminal picker.
    current_terminal_id = case
      when v_status = 'active' then null
      else current_terminal_id
    end,
    status_reason = case
      when v_status = 'active' then null
      else nullif(trim(coalesce(p_reason, '')), '')
    end,
    updated_at = now()
  where driver_id = p_driver_id;

  perform public.set_auth_login_allowed(p_driver_id, v_status = 'active');
end;
$$;

revoke all on function public.admin_set_driver_status(uuid, text, text) from public;
grant execute on function public.admin_set_driver_status(uuid, text, text) to authenticated;

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

  if v_status = 'suspended' then
    raise exception 'Suspended has been replaced by Deactivated. Choose Deactivated instead.';
  end if;
  if v_status = 'pending_verification' then
    raise exception 'Use Active to approve a passenger account';
  end if;
  if not exists (select 1 from public.commuters where commuter_id = p_commuter_id) then
    raise exception 'Commuter not found';
  end if;
  if v_status = 'deactivated' and nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required to deactivate a commuter';
  end if;

  update public.commuters
  set
    status = v_status,
    status_reason = case
      when v_status = 'active' then null
      else nullif(trim(coalesce(p_reason, '')), '')
    end
  where commuter_id = p_commuter_id;

  perform public.set_auth_login_allowed(p_commuter_id, v_status = 'active');
end;
$$;

revoke all on function public.admin_set_commuter_status(uuid, text, text) from public;
grant execute on function public.admin_set_commuter_status(uuid, text, text) to authenticated;

-- ============================================================================
-- 4. Plate / driver's license formats (registration + admin create only;
--    legacy rows such as '123ABC' stay untouched and admin_update_driver is
--    intentionally not strict so old records remain editable)
-- ============================================================================

create or replace function public.normalize_plate(p_value text)
returns text
language sql
immutable
as $$
  select upper(regexp_replace(coalesce(p_value, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

create or replace function public.normalize_driver_license(p_value text)
returns text
language sql
immutable
as $$
  select upper(regexp_replace(coalesce(p_value, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

-- Canonical display forms: ABC-1234 and D00-00-000000.
create or replace function public.format_plate(p_norm text)
returns text
language sql
immutable
as $$
  select case
    when p_norm ~ '^[A-Z]{3}[0-9]{4}$'
      then substr(p_norm, 1, 3) || '-' || substr(p_norm, 4, 4)
    else p_norm
  end;
$$;

create or replace function public.format_driver_license(p_norm text)
returns text
language sql
immutable
as $$
  select case
    when p_norm ~ '^[A-Z][0-9]{10}$'
      then substr(p_norm, 1, 1) || '-' || substr(p_norm, 2, 2) || '-'
           || substr(p_norm, 4, 2) || '-' || substr(p_norm, 6, 6)
    else p_norm
  end;
$$;

create or replace function public.check_registration_availability(
  p_role text,
  p_mobile text,
  p_email text default null,
  p_license text default null,
  p_plate text default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
declare
  v_mobile text := public.normalize_ph_mobile(p_mobile);
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_license text := nullif(trim(coalesce(p_license, '')), '');
  v_plate text := nullif(upper(trim(coalesce(p_plate, ''))), '');
  v_license_norm text;
  v_plate_norm text;
  v_auth_email text;
begin
  if p_role not in ('driver', 'commuter') then
    raise exception 'Invalid registration role';
  end if;
  if v_mobile is null or v_mobile !~ '^09[0-9]{9}$' then
    raise exception 'Enter a valid PH mobile (09XXXXXXXXX)';
  end if;
  if v_email is not null and position('@' in v_email) = 0 then
    raise exception 'Enter a valid email address';
  end if;

  if p_role = 'driver' then
    v_plate_norm := public.normalize_plate(v_plate);
    v_license_norm := public.normalize_driver_license(v_license);

    if v_plate is null or v_plate_norm !~ '^[A-Z]{3}[0-9]{4}$' then
      raise exception 'Plate number must be in the format ABC-1234.';
    end if;
    if v_license is null or v_license_norm !~ '^[A-Z][0-9]{10}$' then
      raise exception 'Driver''s license must be in the format D00-00-000000.';
    end if;

    v_auth_email := coalesce(v_email, v_mobile || '@pasakay.driver');
    if v_email is not null and exists (select 1 from auth.users where lower(email) = v_email) then
      raise exception 'An account with this email address already exists. Try logging in.';
    end if;
    if exists (select 1 from auth.users where lower(email) = lower(v_auth_email)) then
      raise exception 'An account with this mobile number already exists. Try logging in.';
    end if;
    if exists (select 1 from public.drivers where contact_number = v_mobile) then
      raise exception 'An account with this mobile number already exists. Try logging in.';
    end if;
    if exists (
      select 1 from public.drivers d
      where public.normalize_driver_license(d.driver_license_number) = v_license_norm
    ) then
      raise exception 'This license number is already registered.';
    end if;
    if exists (
      select 1 from public.drivers d
      where public.normalize_plate(d.plate_number) = v_plate_norm
    ) then
      raise exception 'This plate number is already registered.';
    end if;
  else
    v_auth_email := coalesce(v_email, v_mobile || '@pasakay.commuter');
    if v_email is not null and exists (select 1 from auth.users where lower(email) = v_email) then
      raise exception 'An account with this email address already exists. Try logging in.';
    end if;
    if exists (select 1 from auth.users where lower(email) = lower(v_auth_email)) then
      raise exception 'An account with this mobile number already exists. Try logging in.';
    end if;
    if exists (select 1 from public.commuters where contact_number = v_mobile) then
      raise exception 'An account with this mobile number already exists. Try logging in.';
    end if;
    if v_email is not null and exists (
      select 1 from public.commuters c where lower(c.email_address) = v_email
    ) then
      raise exception 'An account with this email address already exists. Try logging in.';
    end if;
  end if;
end;
$function$;

revoke all on function public.check_registration_availability(text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.check_registration_availability(text, text, text, text, text) to anon, authenticated;

-- register_driver: store the canonical ABC-1234 / D00-00-000000 forms.
create or replace function public.register_driver(
  p_full_name text,
  p_mobile text,
  p_email text,
  p_password text,
  p_license text,
  p_plate text,
  p_terminal_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'auth', 'extensions'
as $function$
declare
  v_mobile text := public.normalize_ph_mobile(p_mobile);
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_auth_email text;
  v_name text := nullif(trim(coalesce(p_full_name, '')), '');
  v_license text := nullif(trim(coalesce(p_license, '')), '');
  v_plate text := nullif(upper(trim(coalesce(p_plate, ''))), '');
  v_user_id uuid := gen_random_uuid();
  v_shift_id uuid;
begin
  if v_name is null or length(v_name) < 2 then
    raise exception 'Full name is required';
  end if;
  if v_mobile is null or v_mobile !~ '^09[0-9]{9}$' then
    raise exception 'Enter a valid PH mobile (09XXXXXXXXX)';
  end if;
  if v_email is not null and position('@' in v_email) = 0 then
    raise exception 'Enter a valid email address';
  end if;
  if p_password is null or length(p_password) < 8 then
    raise exception 'Password must be at least 8 characters';
  end if;
  if v_license is null then
    raise exception 'License number is required';
  end if;
  if v_plate is null then
    raise exception 'Plate number is required';
  end if;
  if p_terminal_id is null or not exists (select 1 from public.terminals where terminal_id = p_terminal_id) then
    raise exception 'Please select a valid terminal';
  end if;

  v_auth_email := coalesce(v_email, v_mobile || '@pasakay.driver');

  -- Validates the plate/license formats (raises on bad format or duplicates).
  perform public.check_registration_availability('driver', v_mobile, v_email, v_license, v_plate);
  v_plate := public.format_plate(public.normalize_plate(v_plate));
  v_license := public.format_driver_license(public.normalize_driver_license(v_license));

  select shift_id into v_shift_id from public.shifts order by shift_start_time limit 1;
  if v_shift_id is null then
    raise exception 'No shifts are configured yet. Contact an administrator.';
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new,
    email_change_token_current, is_sso_user, is_anonymous
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated',
    'authenticated',
    v_auth_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'full_name', v_name,
      'contact_number', v_mobile,
      'email', v_email,
      'email_address', v_email,
      'license_number', v_license,
      'driver_license_number', v_license,
      'plate_number', v_plate,
      'username', v_mobile,
      'assigned_terminal_id', p_terminal_id::text,
      'role', 'driver'
    ),
    now(), now(), '', '', '', '', '', false, false
  );

  insert into auth.identities (
    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_auth_email, 'email_verified', true),
    'email',
    v_user_id::text,
    now(), now(), now()
  )
  on conflict do nothing;

  insert into public.drivers (
    driver_id, full_name, contact_number, driver_license_number, plate_number,
    username, terminal_id, shift_id, is_active, license_verified, status, status_reason
  ) values (
    v_user_id, v_name, v_mobile, v_license, v_plate,
    v_mobile, p_terminal_id, v_shift_id, false, false, 'pending_verification',
    'Waiting for administrator license verification.'
  )
  on conflict (driver_id) do update
    set status = 'pending_verification',
        is_active = false,
        license_verified = false,
        status_reason = coalesce(public.drivers.status_reason, 'Waiting for administrator license verification.');

  perform public.set_auth_login_allowed(v_user_id, false);

  return v_user_id;
end;
$function$;

revoke all on function public.register_driver(text, text, text, text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.register_driver(text, text, text, text, text, text, uuid) to anon, authenticated;

-- admin_create_driver: same format checks + canonical storage.
create or replace function public.admin_create_driver(
  p_full_name text,
  p_contact_number text,
  p_license_number text,
  p_plate_number text,
  p_toda_number text,
  p_username text,
  p_password text,
  p_terminal_id uuid,
  p_shift_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_mobile text := public.normalize_ph_mobile(p_contact_number);
  v_username text := nullif(trim(coalesce(p_username, '')), '');
  v_license_norm text;
  v_plate_norm text;
  v_license text;
  v_plate text;
begin
  perform public.assert_system_admin();

  if nullif(trim(coalesce(p_full_name, '')), '') is null then
    raise exception 'Full name is required';
  end if;
  if v_mobile = '' or length(v_mobile) < 10 then
    raise exception 'A valid contact number is required';
  end if;

  v_license_norm := public.normalize_driver_license(p_license_number);
  v_plate_norm := public.normalize_plate(p_plate_number);
  if v_license_norm is null or v_license_norm = '' or v_license_norm !~ '^[A-Z][0-9]{10}$' then
    raise exception 'Driver''s license must be in the format D00-00-000000.';
  end if;
  if v_plate_norm is null or v_plate_norm = '' or v_plate_norm !~ '^[A-Z]{3}[0-9]{4}$' then
    raise exception 'Plate number must be in the format ABC-1234.';
  end if;
  v_license := public.format_driver_license(v_license_norm);
  v_plate := public.format_plate(v_plate_norm);

  if not exists (select 1 from public.terminals where terminal_id = p_terminal_id) then
    raise exception 'Select a terminal';
  end if;
  if not exists (select 1 from public.shifts where shift_id = p_shift_id) then
    raise exception 'Select one of the 3 shifts';
  end if;

  v_username := coalesce(v_username, v_mobile);
  if exists (select 1 from public.drivers where username = v_username) then
    raise exception 'Username is already taken';
  end if;
  if exists (
    select 1 from public.drivers d
    where public.normalize_plate(d.plate_number) = v_plate_norm
  ) then
    raise exception 'This plate number is already registered.';
  end if;
  if exists (
    select 1 from public.drivers d
    where public.normalize_driver_license(d.driver_license_number) = v_license_norm
  ) then
    raise exception 'This license number is already registered.';
  end if;

  -- Login email matches the driver app ({mobile}@pasakay.driver).
  -- Account stays pending until an admin visually verifies the license.
  perform public.provision_auth_user(
    v_id,
    v_mobile || '@pasakay.driver',
    p_password,
    trim(p_full_name)
  );
  perform public.set_auth_login_allowed(v_id, false);

  insert into public.drivers (
    driver_id,
    full_name,
    contact_number,
    driver_license_number,
    plate_number,
    toda_number,
    username,
    terminal_id,
    shift_id,
    is_active,
    license_verified,
    status
  ) values (
    v_id,
    trim(p_full_name),
    v_mobile,
    v_license,
    v_plate,
    nullif(trim(coalesce(p_toda_number, '')), ''),
    v_username,
    p_terminal_id,
    p_shift_id,
    false,
    false,
    'pending_verification'
  );

  return v_id;
end;
$$;

revoke all on function public.admin_create_driver(text, text, text, text, text, text, text, uuid, uuid) from public;
grant execute on function public.admin_create_driver(text, text, text, text, text, text, text, uuid, uuid) to authenticated;

-- ============================================================================
-- 5. Pre-login status check so apps can show "waiting for admin approval"
--    instead of a raw auth error (pending/deactivated accounts are banned in
--    auth.users via set_auth_login_allowed).
-- ============================================================================

create or replace function public.get_login_status(p_role text, p_login text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'auth'
as $$
declare
  v_login text := lower(trim(coalesce(p_login, '')));
  v_mobile text;
  v_status public.account_status;
begin
  if p_role not in ('driver', 'commuter') then
    return jsonb_build_object('exists', false, 'status', null, 'allowed', true, 'message', null);
  end if;
  if v_login = '' or position('@' in v_login) > 0 then
    -- Not a plain mobile login; let the normal sign-in flow handle it.
    return jsonb_build_object('exists', false, 'status', null, 'allowed', true, 'message', null);
  end if;

  v_mobile := public.normalize_ph_mobile(v_login);
  if v_mobile is null or v_mobile !~ '^09[0-9]{9}$' then
    return jsonb_build_object('exists', false, 'status', null, 'allowed', true, 'message', null);
  end if;

  if p_role = 'driver' then
    select d.status into v_status
      from public.drivers d
     where d.contact_number = v_mobile
     limit 1;
  else
    select c.status into v_status
      from public.commuters c
     where c.contact_number = v_mobile
     limit 1;
  end if;

  if v_status is null then
    -- Unknown account: keep the regular invalid-credentials error.
    return jsonb_build_object('exists', false, 'status', null, 'allowed', true, 'message', null);
  end if;

  if v_status = 'pending_verification' then
    return jsonb_build_object(
      'exists', true, 'status', 'pending_verification', 'allowed', false,
      'message', 'Your account is waiting for admin approval. You will be able to sign in once an administrator approves it.'
    );
  end if;

  if v_status in ('deactivated', 'suspended') then
    return jsonb_build_object(
      'exists', true, 'status', 'deactivated', 'allowed', false,
      'message', 'Your account has been deactivated. Please contact the administrator.'
    );
  end if;

  return jsonb_build_object('exists', true, 'status', v_status, 'allowed', true, 'message', null);
end;
$$;

revoke all on function public.get_login_status(text, text) from public;
grant execute on function public.get_login_status(text, text) to anon, authenticated;

-- ============================================================================
-- 6. Driver operating-hours (shift) change requests with admin approval
-- ============================================================================

create table if not exists public.driver_shift_requests (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers (driver_id) on delete cascade,
  current_shift_id uuid references public.shifts (shift_id) on delete set null,
  requested_shift_id uuid not null references public.shifts (shift_id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  admin_id uuid references public.admins (admin_id) on delete set null,
  admin_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create index if not exists driver_shift_requests_status_idx
  on public.driver_shift_requests (status, created_at desc);

alter table public.driver_shift_requests enable row level security;

drop policy if exists "driver_shift_requests_own" on public.driver_shift_requests;
create policy "driver_shift_requests_own"
  on public.driver_shift_requests for select
  to authenticated
  using (driver_id = auth.uid());

drop policy if exists "driver_shift_requests_admin" on public.driver_shift_requests;
create policy "driver_shift_requests_admin"
  on public.driver_shift_requests for select
  to authenticated
  using (public.is_system_admin());

grant select on public.driver_shift_requests to authenticated;

-- Driver: request a different shift block (pending admin approval).
create or replace function public.request_driver_shift_change(p_shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_driver public.drivers%rowtype;
  v_shift public.shifts%rowtype;
begin
  if v_driver_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_driver from public.drivers where driver_id = v_driver_id;
  if not found then
    raise exception 'Driver not found';
  end if;
  if not v_driver.is_active or v_driver.status is distinct from 'active' then
    raise exception 'Only active drivers can request a shift change';
  end if;

  select * into v_shift from public.shifts where shift_id = p_shift_id;
  if not found then
    raise exception 'Shift not found';
  end if;
  if v_driver.shift_id = p_shift_id then
    raise exception 'You are already assigned to that shift';
  end if;

  -- One pending request at a time; a new request replaces the old one.
  delete from public.driver_shift_requests
   where driver_id = v_driver_id and status = 'pending';

  insert into public.driver_shift_requests (driver_id, current_shift_id, requested_shift_id)
  values (v_driver_id, v_driver.shift_id, p_shift_id);

  return public.get_my_shift_change_request();
end;
$$;

revoke all on function public.request_driver_shift_change(uuid) from public;
grant execute on function public.request_driver_shift_change(uuid) to authenticated;

-- Driver: view own pending request.
create or replace function public.get_my_shift_change_request()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_shift_id uuid;
  v_created timestamptz;
  v_label text;
  v_start time;
  v_end time;
begin
  select r.id, r.requested_shift_id, r.created_at, s.label, s.shift_start_time, s.shift_end_time
    into v_id, v_shift_id, v_created, v_label, v_start, v_end
  from public.driver_shift_requests r
  left join public.shifts s on s.shift_id = r.requested_shift_id
  where r.driver_id = auth.uid()
    and r.status = 'pending'
  order by r.created_at desc
  limit 1;

  if v_id is null then
    return jsonb_build_object('hasPendingRequest', false);
  end if;

  return jsonb_build_object(
    'hasPendingRequest', true,
    'id', v_id,
    'requestedShiftId', v_shift_id,
    'requestedShiftLabel', v_label,
    'requestedShiftStart', v_start,
    'requestedShiftEnd', v_end,
    'createdAt', v_created
  );
end;
$$;

revoke all on function public.get_my_shift_change_request() from public;
grant execute on function public.get_my_shift_change_request() to authenticated;

-- Admin: pending shift change requests.
create or replace function public.admin_list_shift_change_requests()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_system_admin();

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', r.id,
             'driverId', r.driver_id,
             'driverName', d.full_name,
             'plateNumber', d.plate_number,
             'currentShiftId', r.current_shift_id,
             'currentShiftLabel', cs.label,
             'requestedShiftId', r.requested_shift_id,
             'requestedShiftLabel', ts.label,
             'requestedShiftStart', ts.shift_start_time,
             'requestedShiftEnd', ts.shift_end_time,
             'createdAt', r.created_at
           ) order by r.created_at)
    from public.driver_shift_requests r
    join public.drivers d on d.driver_id = r.driver_id
    left join public.shifts cs on cs.shift_id = r.current_shift_id
    left join public.shifts ts on ts.shift_id = r.requested_shift_id
    where r.status = 'pending'
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_list_shift_change_requests() from public;
grant execute on function public.admin_list_shift_change_requests() to authenticated;

-- Admin: approve / reject. Approval moves the driver to the requested shift.
create or replace function public.admin_review_shift_change_request(
  p_request_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.driver_shift_requests%rowtype;
  v_shift public.shifts%rowtype;
begin
  perform public.assert_system_admin();

  select * into v_request
    from public.driver_shift_requests
   where id = p_request_id
     and status = 'pending'
   for update;

  if not found then
    raise exception 'Shift change request not found';
  end if;

  update public.driver_shift_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         admin_id = auth.uid(),
         admin_note = nullif(trim(coalesce(p_note, '')), ''),
         reviewed_at = now()
   where id = p_request_id;

  if p_approve then
    select * into v_shift from public.shifts where shift_id = v_request.requested_shift_id;
    if not found then
      raise exception 'Shift not found';
    end if;

    update public.drivers
       set shift_id = v_request.requested_shift_id,
           updated_at = now()
     where driver_id = v_request.driver_id;

    -- Keep day-by-day operating windows (used for on-shift checks) in sync.
    begin
      update public.driver_schedules ds
         set start_time = v_shift.shift_start_time,
             end_time = v_shift.shift_end_time
       where ds.driver_id = v_request.driver_id;
    exception when undefined_table then
      null;
    end;
  end if;

  return public.admin_list_shift_change_requests();
end;
$$;

revoke all on function public.admin_review_shift_change_request(uuid, boolean, text) from public;
grant execute on function public.admin_review_shift_change_request(uuid, boolean, text) to authenticated;
