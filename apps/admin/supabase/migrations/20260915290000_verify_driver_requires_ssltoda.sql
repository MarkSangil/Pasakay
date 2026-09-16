-- Require SSLTODA number when an admin visually verifies a driver license.

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
      raise exception 'SSLTODA number is required to verify a driver';
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
      status_reason = 'License verification cleared. Visual check required before activation.',
      updated_at = now()
    where driver_id = p_driver_id;
    perform public.set_auth_login_allowed(p_driver_id, false);
  end if;
end;
$function$;
