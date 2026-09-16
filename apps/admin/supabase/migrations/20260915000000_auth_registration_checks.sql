-- Pre-signup uniqueness checks (callable before an auth session exists).
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
set search_path = public, auth
as $$
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
  if v_mobile is null or v_mobile = '' or length(v_mobile) < 10 then
    raise exception 'A valid mobile number is required';
  end if;

  if p_role = 'driver' then
    v_auth_email := v_mobile || '@pasakay.driver';
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
    v_auth_email := v_mobile || '@pasakay.commuter';
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
$$;

revoke all on function public.check_registration_availability(text, text, text, text, text) from public;
grant execute on function public.check_registration_availability(text, text, text, text, text) to anon, authenticated;

-- Admin-assisted password reset for passengers (synthetic emails cannot receive mail).
create or replace function public.admin_reset_commuter_password(
  p_commuter_id uuid,
  p_password text
)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
begin
  perform public.assert_system_admin();
  if p_password is null or length(p_password) < 8 then
    raise exception 'Password must be at least 8 characters';
  end if;
  if not exists (select 1 from public.commuters where commuter_id = p_commuter_id) then
    raise exception 'Commuter not found';
  end if;

  update auth.users
  set
    encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
    updated_at = now()
  where id = p_commuter_id;
end;
$$;

revoke all on function public.admin_reset_commuter_password(uuid, text) from public;
grant execute on function public.admin_reset_commuter_password(uuid, text) to authenticated;
