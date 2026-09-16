-- Make registration email optional; keep PH mobile (09XXXXXXXXX) required.
-- Auth.users always gets a stable login identity:
--   provided email when present, otherwise {mobile}@pasakay.{role}.

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
    if v_license is not null and exists (
      select 1 from public.drivers where driver_license_number = v_license
    ) then
      raise exception 'This license number is already registered.';
    end if;
    if v_plate is not null and exists (
      select 1 from public.drivers where plate_number = v_plate
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
      select 1 from public.commuters where lower(email_address) = v_email
    ) then
      raise exception 'An account with this email address already exists. Try logging in.';
    end if;
  end if;
end;
$function$;

create or replace function public.register_commuter(
  p_full_name text,
  p_mobile text,
  p_email text,
  p_password text
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
  v_user_id uuid := gen_random_uuid();
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

  v_auth_email := coalesce(v_email, v_mobile || '@pasakay.commuter');

  perform public.check_registration_availability('commuter', v_mobile, v_email, null, null);

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
      'email_address', v_email,
      'username', v_mobile,
      'role', 'commuter'
    ),
    now(), now(), '', '', '', '', '', false, false
  );

  insert into auth.identities (
    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at, email
  ) values (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_auth_email, 'email_verified', true),
    'email',
    v_user_id::text,
    now(), now(), now(),
    v_auth_email
  )
  on conflict do nothing;

  insert into public.commuters (
    commuter_id, full_name, contact_number, email_address, username, status,
    status_reason
  ) values (
    v_user_id, v_name, v_mobile, v_email, v_mobile, 'pending_verification',
    'Waiting for administrator approval.'
  )
  on conflict (commuter_id) do update
    set status = 'pending_verification',
        status_reason = coalesce(public.commuters.status_reason, 'Waiting for administrator approval.');

  perform public.set_auth_login_allowed(v_user_id, false);

  return v_user_id;
end;
$function$;

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

  perform public.check_registration_availability('driver', v_mobile, v_email, v_license, v_plate);

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
    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at, email
  ) values (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_auth_email, 'email_verified', true),
    'email',
    v_user_id::text,
    now(), now(), now(),
    v_auth_email
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
