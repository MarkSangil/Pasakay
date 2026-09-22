-- Booking settings: allow 0 for cooldown / review-eligible.
--
-- booking_setting_int() clamped every value with greatest(1, ...), so saving
-- request_cooldown_minutes = 0 or review_eligible_minutes = 0 (both accepted
-- by admin_set_booking_settings and advertised in the admin UI as valid)
-- silently read back as 1 everywhere: get_booking_settings, request expiry /
-- cooldown checks, and review_eligible_at. Cooldown/review of 0 must mean
-- "no wait" / "reviewable immediately".
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
    return greatest(0, coalesce(nullif(trim(v), '')::int, p_default));
  exception when others then
    return p_default;
  end;
end;
$$;
