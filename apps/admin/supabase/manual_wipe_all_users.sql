-- ============================================================================
-- DANGER: MANUAL USE ONLY. IRREVERSIBLE.
-- Never place this file in supabase/migrations/ (it must never auto-run).
--
-- Purpose: wipe ALL user accounts (drivers, commuters, admins, auth users)
-- plus all user-linked records, to start fresh. Reference data is KEPT:
-- terminals, shifts, app_notification_settings (booking timers, activity
-- tunables). After wiping, it recreates the seed system admin.
--
-- How to run: Supabase Dashboard > SQL editor > paste > Run.
-- (Dashboard runs as postgres: bypasses RLS. The anon key cannot do this.)
-- Tables are deleted child-first; missing tables are skipped automatically.
-- Everything runs in one transaction: any failure rolls the wipe back.
-- ============================================================================

begin;

do $$
declare
  t text;
begin
  foreach t in array array[
    -- 1. Driver activity tracking.
    'public.driver_activity_heartbeats',
    'public.driver_activity_sessions',
    -- 2. Reports and reviews (review_reports refs drivers WITHOUT cascade).
    'public.review_reports',
    'public.reviews',
    -- 3. Booking flow (bookings/ride_requests have NO cascade to users).
    'public.booking_events',
    'public.bookings',
    'public.ride_requests',
    -- 4. Notifications, tokens, preferences, follows.
    'public.notifications',
    'public.notification_event_log',
    'public.device_tokens',
    'public.commuter_device_tokens',
    'public.driver_notification_preferences',
    'public.commuter_notification_preferences',
    'public.commuter_followed_drivers',
    -- 5. Shift links, requests, logs, privacy, legacy passengers.
    'public.driver_shift_requests',
    'public.driver_schedules',
    'public.driver_shifts',
    'public.device_logs',
    'public.privacy_requests',
    'public.passengers',
    -- 6. User rows (admins last: review_reports/privacy handled_by ref them).
    'public.drivers',
    'public.commuters',
    'public.admins'
  ]
  loop
    if to_regclass(t) is not null then
      execute format('delete from %s', t);
    end if;
  end loop;

  -- Auth last: cascades to auth.identities. All public rows are gone,
  -- so nothing references these ids anymore.
  delete from auth.users;
end $$;

-- ----------------------------------------------------------------------------
-- Recreate the seed system admin (same as admin_system migration).
--   Email:    admin@pasakay.app
--   Username: sysadmin
--   Password: PasakayAdmin#2026
-- Change the password immediately after first login.
-- ----------------------------------------------------------------------------
do $$
declare
  v_id uuid := 'b0000000-0000-4000-8000-000000000001';
begin
  if not exists (select 1 from auth.users where email = 'admin@pasakay.app') then
    perform public.provision_auth_user(
      v_id,
      'admin@pasakay.app',
      'PasakayAdmin#2026',
      'PASAKAY System Admin'
    );
  end if;

  insert into public.admins (admin_id, full_name, email, username)
  select u.id, 'PASAKAY System Admin', 'admin@pasakay.app', 'sysadmin'
  from auth.users u
  where u.email = 'admin@pasakay.app'
  on conflict (admin_id) do update
    set
      full_name = excluded.full_name,
      email = excluded.email,
      username = excluded.username,
      is_active = true;
end $$;

-- Verification: user counts should be 0, admins should be 1.
select 'drivers' as tbl, count(*) from public.drivers
union all select 'commuters', count(*) from public.commuters
union all select 'admins', count(*) from public.admins
union all select 'auth_users', count(*) from auth.users
union all select 'bookings', count(*) from public.bookings
union all select 'ride_requests', count(*) from public.ride_requests
union all select 'reviews', count(*) from public.reviews;

commit;
