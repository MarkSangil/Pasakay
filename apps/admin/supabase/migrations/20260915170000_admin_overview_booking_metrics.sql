-- Live admin overview counts, including request/booking metrics.
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
    'drivers_suspended', (select count(*)::int from public.drivers where status = 'suspended'),
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
