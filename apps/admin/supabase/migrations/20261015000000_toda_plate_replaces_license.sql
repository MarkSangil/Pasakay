-- Replace driver's license number collection with the required TODA Plate
-- Number (public.drivers.toda_number).
--
-- Staged approach (no silent data transfer, no destructive ops):
--  1. public.drivers.driver_license_number is KEPT but relaxed to nullable
--     and marked deprecated. Existing values are preserved untouched; new
--     registrations store NULL. Nothing is ever copied from the license
--     column into toda_number.
--  2. public.drivers.toda_number is the TODA Plate Number. It stays nullable
--     at the column level (legacy rows may not have one) but is REQUIRED by
--     register_driver / admin_create_driver / admin_update_driver, and by
--     admin_verify_driver_license (already required there).
--  3. The license_verified / license_verified_at / license_verified_by
--     columns and the drivers_active_requires_license constraint are KEPT
--     (renaming would churn every dependent function for no behavioral gain).
--     They now record TODA plate verification; comments below say so.
--     User-facing messages were reworded from "license" to "TODA plate".
--  4. p_license / p_license_number RPC parameters are kept (accepted but
--     ignored) so in-flight older clients fail closed with a clear
--     "TODA Plate Number is required" message instead of an RPC
--     signature error.
--  5. A future cleanup migration may drop driver_license_number once no
--     deployed client sends p_license. Do NOT drop it here.

-- ---------------------------------------------------------------------------
-- 1. Relax the deprecated license column; document repurposed columns.
-- ---------------------------------------------------------------------------
alter table public.drivers
  alter column driver_license_number drop not null;

comment on column public.drivers.driver_license_number is
  'DEPRECATED: driver license numbers are no longer collected. Existing values '
  'are preserved for record-keeping only; new registrations store NULL. Do not '
  'copy these values into toda_number.';
comment on column public.drivers.toda_number is
  'TODA Plate Number. Required for new registrations and admin-created drivers.';
comment on column public.drivers.license_verified is
  'Manual visual verification flag. Since the TODA-plate migration this records '
  'verification of the driver''s TODA Plate Number (not a license lookup). '
  'Activation still requires this flag (see drivers_active_requires_license).';

-- ---------------------------------------------------------------------------
-- 2. Availability check: no more license format/duplicate checks.
-- ---------------------------------------------------------------------------
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
  v_plate text := nullif(upper(trim(coalesce(p_plate, ''))), '');
  v_plate_norm text;
  v_auth_email text;
begin
  -- NOTE: p_license is accepted for backward compatibility but ignored.
  -- License numbers are no longer collected or checked.
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

    if v_plate is null or v_plate_norm !~ '^[A-Z]{3}[0-9]{4}$' then
      raise exception 'Plate number must be in the format ABC-1234.';
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

-- ---------------------------------------------------------------------------
-- 3. Self registration: TODA Plate Number required, license no longer taken.
-- ---------------------------------------------------------------------------
-- NOTE: p_toda is appended with a default so the signature change is
-- additive. The previous 7-argument version is dropped so only one
-- register_driver remains.
drop function if exists public.register_driver(text, text, text, text, text, text, uuid);
create or replace function public.register_driver(
  p_full_name text,
  p_mobile text,
  p_email text,
  p_password text,
  p_license text,
  p_plate text,
  p_terminal_id uuid,
  p_toda text default null
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
  v_toda text := nullif(trim(coalesce(p_toda, '')), '');
  v_plate text := nullif(upper(trim(coalesce(p_plate, ''))), '');
  v_user_id uuid := gen_random_uuid();
  v_shift_id uuid;
begin
  -- NOTE: p_license is accepted for backward compatibility but ignored.
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
  if v_toda is null then
    raise exception 'TODA Plate Number is required';
  end if;
  if v_plate is null then
    raise exception 'Plate number is required';
  end if;
  if p_terminal_id is null or not exists (select 1 from public.terminals where terminal_id = p_terminal_id) then
    raise exception 'Please select a valid terminal';
  end if;

  v_auth_email := coalesce(v_email, v_mobile || '@pasakay.driver');

  -- Validates the plate format (raises on bad format or duplicates).
  perform public.check_registration_availability('driver', v_mobile, v_email, null, v_plate);
  v_plate := public.format_plate(public.normalize_plate(v_plate));

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
      'toda_number', v_toda,
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
    toda_number, username, terminal_id, shift_id, is_active, license_verified,
    status, status_reason
  ) values (
    v_user_id, v_name, v_mobile, null, v_plate,
    v_toda, v_mobile, p_terminal_id, v_shift_id, false, false,
    'pending_verification',
    'Waiting for administrator TODA plate verification.'
  )
  on conflict (driver_id) do update
    set status = 'pending_verification',
        is_active = false,
        license_verified = false,
        toda_number = excluded.toda_number,
        status_reason = coalesce(public.drivers.status_reason, 'Waiting for administrator TODA plate verification.');

  perform public.set_auth_login_allowed(v_user_id, false);

  return v_user_id;
end;
$function$;

revoke all on function public.register_driver(text, text, text, text, text, text, uuid, text) from public, anon, authenticated;
grant execute on function public.register_driver(text, text, text, text, text, text, uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Auth-user trigger: build the driver row from TODA metadata.
-- ---------------------------------------------------------------------------
create or replace function public.handle_pasakay_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(new.raw_user_meta_data->>'role', '');
  v_name text := nullif(trim(coalesce(new.raw_user_meta_data->>'full_name', '')), '');
  v_mobile text := public.normalize_ph_mobile(
    coalesce(new.raw_user_meta_data->>'contact_number', new.raw_user_meta_data->>'mobile_number', '')
  );
  v_email text := nullif(lower(trim(coalesce(
    new.raw_user_meta_data->>'email_address',
    new.raw_user_meta_data->>'email',
    new.email,
    ''
  ))), '');
  v_toda text := nullif(trim(coalesce(new.raw_user_meta_data->>'toda_number', '')), '');
  v_plate text := nullif(upper(trim(coalesce(new.raw_user_meta_data->>'plate_number', ''))), '');
  v_terminal uuid := nullif(new.raw_user_meta_data->>'assigned_terminal_id', '')::uuid;
  v_shift_id uuid;
begin
  if v_role = 'commuter' then
    if v_mobile is null or v_mobile = '' then
      raise exception 'Contact number is required for passenger signup';
    end if;
    insert into public.commuters (
      commuter_id, full_name, contact_number, email_address, username, status
    ) values (
      new.id,
      coalesce(v_name, 'Passenger'),
      v_mobile,
      v_email,
      v_mobile,
      'active'
    )
    on conflict (commuter_id) do nothing;
  elsif v_role = 'driver' then
    if v_mobile is null or v_mobile = '' then
      raise exception 'Contact number is required for driver signup';
    end if;
    if v_toda is null or v_plate is null or v_terminal is null then
      raise exception 'Driver signup requires TODA plate number, plate, and terminal';
    end if;
    select shift_id into v_shift_id from public.shifts order by shift_start_time limit 1;
    if v_shift_id is null then
      raise exception 'No shifts are configured yet. Contact an administrator.';
    end if;
    insert into public.drivers (
      driver_id, full_name, contact_number, driver_license_number, plate_number,
      toda_number, username, terminal_id, shift_id, is_active, license_verified, status
    ) values (
      new.id,
      coalesce(v_name, 'Driver'),
      v_mobile,
      null,
      v_plate,
      v_toda,
      v_mobile,
      v_terminal,
      v_shift_id,
      false,
      false,
      'pending_verification'
    )
    on conflict (driver_id) do nothing;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Admin create: TODA required, license ignored.
-- ---------------------------------------------------------------------------
create or replace function public.admin_create_driver(
  p_full_name text,
  p_contact_number text,
  p_license_number text default null,
  p_plate_number text default null,
  p_toda_number text default null,
  p_username text default null,
  p_password text default null,
  p_terminal_id uuid default null,
  p_shift_id uuid default null
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
  v_toda text := nullif(trim(coalesce(p_toda_number, '')), '');
  v_plate_norm text;
  v_plate text;
begin
  -- NOTE: p_license_number is accepted for backward compatibility but ignored.
  perform public.assert_system_admin();

  if nullif(trim(coalesce(p_full_name, '')), '') is null then
    raise exception 'Full name is required';
  end if;
  if v_mobile = '' or length(v_mobile) < 10 then
    raise exception 'A valid contact number is required';
  end if;
  if v_toda is null then
    raise exception 'TODA Plate Number is required';
  end if;

  v_plate_norm := public.normalize_plate(p_plate_number);
  if v_plate_norm is null or v_plate_norm = '' or v_plate_norm !~ '^[A-Z]{3}[0-9]{4}$' then
    raise exception 'Plate number must be in the format ABC-1234.';
  end if;
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

  -- Login email matches the driver app ({mobile}@pasakay.driver).
  -- Account stays pending until an admin verifies the TODA plate.
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
    null,
    v_plate,
    v_toda,
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

-- ---------------------------------------------------------------------------
-- 6. Admin update: TODA required (completes legacy rows on edit); the
--    deprecated license column is left untouched. Changing the TODA plate
--    clears verification, mirroring the old license-change behavior.
-- ---------------------------------------------------------------------------
create or replace function public.admin_update_driver(
  p_driver_id uuid,
  p_full_name text,
  p_contact_number text,
  p_license_number text default null,
  p_plate_number text default null,
  p_toda_number text default null,
  p_username text default null,
  p_terminal_id uuid default null,
  p_shift_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_mobile text := public.normalize_ph_mobile(p_contact_number);
  v_username text := nullif(trim(coalesce(p_username, '')), '');
  v_toda text := nullif(trim(coalesce(p_toda_number, '')), '');
  v_plate text := nullif(upper(trim(coalesce(p_plate_number, ''))), '');
  v_old_toda text;
  v_old_mobile text;
  v_auth_email text;
begin
  -- NOTE: p_license_number is accepted for backward compatibility but ignored;
  -- the deprecated driver_license_number value is preserved as-is.
  perform public.assert_system_admin();

  select toda_number, contact_number
  into v_old_toda, v_old_mobile
  from public.drivers
  where driver_id = p_driver_id;

  if not found then
    raise exception 'Driver not found';
  end if;
  if nullif(trim(coalesce(p_full_name, '')), '') is null then
    raise exception 'Full name is required';
  end if;
  if v_mobile = '' or length(v_mobile) < 10 then
    raise exception 'A valid contact number is required';
  end if;
  if v_toda is null then
    raise exception 'TODA Plate Number is required';
  end if;
  if v_plate is null then
    raise exception 'Plate number is required';
  end if;
  if not exists (select 1 from public.terminals where terminal_id = p_terminal_id) then
    raise exception 'Select a terminal';
  end if;
  if not exists (select 1 from public.shifts where shift_id = p_shift_id) then
    raise exception 'Select one of the 3 shifts';
  end if;

  v_username := coalesce(v_username, v_mobile);
  if exists (
    select 1 from public.drivers
    where username = v_username and driver_id <> p_driver_id
  ) then
    raise exception 'Username is already taken';
  end if;

  v_auth_email := v_mobile || '@pasakay.driver';
  if v_mobile <> v_old_mobile then
    if exists (
      select 1 from auth.users
      where lower(email) = v_auth_email and id <> p_driver_id
    ) then
      raise exception 'That contact number is already used for login';
    end if;
    update auth.users
    set email = v_auth_email, updated_at = now()
    where id = p_driver_id;
    update auth.identities
    set
      identity_data = jsonb_set(
        coalesce(identity_data, '{}'::jsonb),
        '{email}',
        to_jsonb(v_auth_email)
      ),
      updated_at = now()
    where user_id = p_driver_id and provider = 'email';
  end if;

  update public.drivers
  set
    full_name = trim(p_full_name),
    contact_number = v_mobile,
    plate_number = v_plate,
    toda_number = v_toda,
    username = v_username,
    terminal_id = p_terminal_id,
    shift_id = p_shift_id,
    -- A changed TODA plate must be verified again before the account can stay active.
    license_verified = case when v_toda is not distinct from v_old_toda then license_verified else false end,
    license_verified_at = case when v_toda is not distinct from v_old_toda then license_verified_at else null end,
    license_verified_by = case when v_toda is not distinct from v_old_toda then license_verified_by else null end,
    status = case
      when v_toda is not distinct from v_old_toda then status
      else 'pending_verification'::public.account_status
    end,
    is_active = case
      when v_toda is not distinct from v_old_toda then is_active
      else false
    end,
    status_reason = case
      when v_toda is not distinct from v_old_toda then status_reason
      else 'TODA Plate Number changed. Verification required before activation.'
    end,
    updated_at = now()
  where driver_id = p_driver_id;

  if v_toda is distinct from v_old_toda then
    perform public.set_auth_login_allowed(p_driver_id, false);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Verify RPC: same signature; messages reworded to TODA plate.
-- ---------------------------------------------------------------------------
create or replace function public.admin_verify_driver_license(
  p_driver_id uuid,
  p_verified boolean,
  p_toda_number text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_toda text := nullif(trim(coalesce(p_toda_number, '')), '');
begin
  perform public.assert_system_admin();
  if not exists (select 1 from public.drivers where driver_id = p_driver_id) then
    raise exception 'Driver not found';
  end if;

  if p_verified then
    if v_toda is null then
      raise exception 'TODA Plate Number is required to verify a driver';
    end if;
    update public.drivers
    set
      license_verified = true,
      license_verified_at = now(),
      license_verified_by = auth.uid(),
      toda_number = v_toda,
      updated_at = now()
    where driver_id = p_driver_id;
  else
    update public.drivers
    set
      license_verified = false,
      license_verified_at = null,
      license_verified_by = null,
      status = 'pending_verification',
      is_active = false,
      status_reason = 'TODA plate verification cleared. Verification required before activation.',
      updated_at = now()
    where driver_id = p_driver_id;
    perform public.set_auth_login_allowed(p_driver_id, false);
  end if;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 8. Activation gate message reworded to TODA plate (logic unchanged).
-- ---------------------------------------------------------------------------
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
    raise exception 'TODA plate must be verified before activation. This is a manual check only — PASAKAY does not validate against a government database.';
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
