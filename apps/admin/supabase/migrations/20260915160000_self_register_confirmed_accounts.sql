-- Self-signup for phone-based accounts without confirmation email.
-- Synthetic @pasakay.* emails cannot receive mail; auth.signUp fails when confirm-email is on.

create or replace function public.register_commuter(
  p_full_name text,
  p_mobile text,
  p_email text,
  p_password text
) returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_mobile text := public.normalize_ph_mobile(p_mobile);
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_name text := nullif(trim(coalesce(p_full_name, '')), '');
  v_auth_email text;
  v_user_id uuid := gen_random_uuid();
begin
  if v_name is null or length(v_name) < 2 then
    raise exception 'Full name is required';
  end if;
  if v_mobile is null or v_mobile !~ '^09[0-9]{9}$' then
    raise exception 'Enter a valid PH mobile (09XXXXXXXXX)';
  end if;
  if v_email is null or position('@' in v_email) = 0 then
    raise exception 'Enter a valid email address';
  end if;
  if p_password is null or length(p_password) < 8 then
    raise exception 'Password must be at least 8 characters';
  end if;

  perform public.check_registration_availability('commuter', v_mobile, v_email, null, null);

  v_auth_email := v_mobile || '@pasakay.commuter';

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
  );

  insert into public.commuters (
    commuter_id, full_name, contact_number, email_address, username, status
  ) values (
    v_user_id, v_name, v_mobile, v_email, v_mobile, 'active'
  );

  return v_user_id;
end;
$$;

create or replace function public.register_driver(
  p_full_name text,
  p_mobile text,
  p_email text,
  p_password text,
  p_license text,
  p_plate text,
  p_terminal_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_mobile text := public.normalize_ph_mobile(p_mobile);
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_name text := nullif(trim(coalesce(p_full_name, '')), '');
  v_license text := nullif(trim(coalesce(p_license, '')), '');
  v_plate text := nullif(upper(trim(coalesce(p_plate, ''))), '');
  v_auth_email text;
  v_user_id uuid := gen_random_uuid();
  v_shift_id uuid;
begin
  if v_name is null or length(v_name) < 2 then
    raise exception 'Full name is required';
  end if;
  if v_mobile is null or v_mobile !~ '^09[0-9]{9}$' then
    raise exception 'Enter a valid PH mobile (09XXXXXXXXX)';
  end if;
  if v_email is null or position('@' in v_email) = 0 then
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

  perform public.check_registration_availability('driver', v_mobile, v_email, v_license, v_plate);

  select shift_id into v_shift_id
  from public.shifts
  order by shift_start_time
  limit 1;
  if v_shift_id is null then
    raise exception 'No shifts are configured yet. Contact an administrator.';
  end if;

  v_auth_email := v_mobile || '@pasakay.driver';

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
      'license_number', v_license,
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
  );

  insert into public.drivers (
    driver_id, full_name, contact_number, driver_license_number, plate_number,
    username, terminal_id, shift_id, is_active, license_verified, status
  ) values (
    v_user_id, v_name, v_mobile, v_license, v_plate,
    v_mobile, p_terminal_id, v_shift_id, false, false, 'pending_verification'
  );

  return v_user_id;
end;
$$;

revoke all on function public.register_commuter(text, text, text, text) from public;
grant execute on function public.register_commuter(text, text, text, text) to anon, authenticated;

revoke all on function public.register_driver(text, text, text, text, text, text, uuid) from public;
grant execute on function public.register_driver(text, text, text, text, text, text, uuid) to anon, authenticated;

drop policy if exists "shifts_read_all" on public.shifts;
create policy "shifts_read_all"
  on public.shifts for select
  to anon, authenticated
  using (true);
