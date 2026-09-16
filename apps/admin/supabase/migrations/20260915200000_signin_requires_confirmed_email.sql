-- Phone sign-in requires the signup email to be confirmed first.
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
  v_confirmed_at timestamptz;
begin
  if p_role not in ('driver', 'commuter') then
    raise exception 'Invalid role';
  end if;
  if v_login = '' then
    raise exception 'Login is required';
  end if;

  if position('@' in v_login) > 0 then
    raise exception 'Sign in with your mobile number. Confirm your email first if you just registered.';
  end if;

  v_mobile := public.normalize_ph_mobile(v_login);
  if v_mobile is null or v_mobile !~ '^09[0-9]{9}$' then
    raise exception 'Enter a valid PH mobile (09XXXXXXXXX)';
  end if;

  if p_role = 'driver' then
    select lower(u.email), u.email_confirmed_at
      into v_email, v_confirmed_at
    from public.drivers d
    join auth.users u on u.id = d.driver_id
    where d.contact_number = v_mobile
    limit 1;
  else
    select lower(u.email), u.email_confirmed_at
      into v_email, v_confirmed_at
    from public.commuters c
    join auth.users u on u.id = c.commuter_id
    where c.contact_number = v_mobile
    limit 1;
  end if;

  if v_email is not null then
    if v_confirmed_at is null then
      raise exception 'Confirm your email before signing in. Check your inbox for the verification link.';
    end if;
    return v_email;
  end if;

  if p_role = 'driver' then
    return v_mobile || '@pasakay.driver';
  end if;
  return v_mobile || '@pasakay.commuter';
end;
$$;
