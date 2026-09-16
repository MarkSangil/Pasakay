-- Signup uses the real registered email so Supabase can send confirmation mail.
-- Phone login resolves to that auth email (with legacy @pasakay.* fallback).

create or replace function public.resolve_auth_email(
  p_role text,
  p_login text
) returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_login text := lower(trim(coalesce(p_login, '')));
  v_mobile text;
  v_email text;
begin
  if p_role not in ('driver', 'commuter') then
    raise exception 'Invalid role';
  end if;
  if v_login = '' then
    raise exception 'Login is required';
  end if;

  if position('@' in v_login) > 0 then
    return v_login;
  end if;

  v_mobile := public.normalize_ph_mobile(v_login);

  if p_role = 'driver' then
    select u.email into v_email
    from public.drivers d
    join auth.users u on u.id = d.driver_id
    where d.contact_number = v_mobile
    limit 1;
    if v_email is not null then return lower(v_email); end if;
    return v_mobile || '@pasakay.driver';
  else
    select u.email into v_email
    from public.commuters c
    join auth.users u on u.id = c.commuter_id
    where c.contact_number = v_mobile
    limit 1;
    if v_email is not null then return lower(v_email); end if;
    return v_mobile || '@pasakay.commuter';
  end if;
end;
$$;

revoke all on function public.resolve_auth_email(text, text) from public;
grant execute on function public.resolve_auth_email(text, text) to anon, authenticated;

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
    v_auth_email := v_mobile || '@pasakay.commuter';
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
$$;

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
  v_license text := nullif(trim(coalesce(
    new.raw_user_meta_data->>'driver_license_number',
    new.raw_user_meta_data->>'license_number',
    ''
  )), '');
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
    if v_license is null or v_plate is null or v_terminal is null then
      raise exception 'Driver signup requires license, plate, and terminal';
    end if;
    select shift_id into v_shift_id from public.shifts order by shift_start_time limit 1;
    if v_shift_id is null then
      raise exception 'No shifts are configured yet. Contact an administrator.';
    end if;
    insert into public.drivers (
      driver_id, full_name, contact_number, driver_license_number, plate_number,
      username, terminal_id, shift_id, is_active, license_verified, status
    ) values (
      new.id,
      coalesce(v_name, 'Driver'),
      v_mobile,
      v_license,
      v_plate,
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

drop trigger if exists on_auth_user_created_pasakay on auth.users;
create trigger on_auth_user_created_pasakay
  after insert on auth.users
  for each row
  execute function public.handle_pasakay_auth_user();
