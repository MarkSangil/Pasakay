# 8 · Limitations and Scope

Statuses used in the table: **Implemented** (verified in code and wired in),
**Partially implemented** (code exists but incomplete/unreachable),
**Not implemented** (planned/excluded, no code), **Unverified** (no
repository evidence either way).

| Item | Current status | Evidence | Explanation |
|---|---|---|---|
| Commuter registration + admin approval gate | Implemented | `register_commuter` (migration `20260915160000`…), `commuters_insert_own` policy, admin commuter functions | accounts are `pending_verification` until the admin sets them active; login blocked until then |
| Driver registration + TODA plate requirement | Implemented | `register_driver`, `20261015000000_toda_plate_replaces_license.sql`, `20260915290000_verify_driver_requires_ssltoda.sql` | plate (freeform TODA number) replaces the old driver's license login; license collection is deprecated, plate stored in `drivers.toda_number` |
| Login (mobile + password) both apps, admin email login | Implemented | `apps/*/lib/services/auth_service.dart`, `apps/admin/lib/core/providers/session_provider.dart` | with pre-login status gate, role assertion, and profile fetch |
| Terminal → shift → driver browsing | Implemented | `list_terminal_shift_drivers`, customer `driver_list` screen | primary commuter journey |
| Call / SMS passthrough | Implemented | `apps/*/lib/core/utils/contact_launcher.dart`, `url_launcher` | opens device apps; no in-app calling |
| Ride request → booking lifecycle | Implemented | `20260915130000_ride_request_booking_flow.sql` + client repos | full state machine incl. reconciliation cron |
| Trip dispute (flag) + admin resolution | Implemented | `flag_booking`, `admin_resolve_disputed_booking`, `/disputed-bookings` screen | only inside the configured window |
| Commuter side explicit "cancel request" | **Partially implemented** | `ride_requests_status_check` allows `CANCELLED`; only admin action writes it | commuter cannot proactively cancel a pending request; it waits for expiry (see `create_ride_request`/`accept_ride_request` — no cancel RPC) |
| Reviews + rating aggregates | Implemented | `submit_booking_review`, `refresh_driver_rating` trigger, `reviews_one_per_booking` | one review per completed booking |
| Review reports + admin resolution | Implemented | `report_review`, `admin_resolve_review_report`, `/review-reports` screen | hides/deletes reviews resolves reports |
| In-app notifications (Realtime) | Implemented | `notifications` table + realtime channels in both apps | recipient-scoped reads |
| Push notifications (FCM via Edge Functions) | Implemented pipeline, delivery **Unverified** | `20260915120000_notification_push_pg_net_trigger.sql`, edge functions, token tables | code path complete; end-to-end delivery depends on FCM + secrets configured in dashboard |
| Schedule-change / reminder notifications | Implemented | `trg_drivers_notify_changes`, `trg_shifts_notify_changes`, `process_schedule_notifications` cron | shift + availability + schedule events |
| Shift-change requests to admin | Implemented | `request_driver_shift_change`, `admin_review_shift_change_request`, `/shifts` screen | fixed to the 3 seeded shifts |
| Booking settings (windows/cooldowns) | Implemented | `admin_set_booking_settings`, `/booking-settings` screen | includes zero-allowed fix (`20260917000000_allow_zero_booking_settings.sql`) |
| Admin driver CRUD + commuter access control | Implemented | `admin_create_driver`, `admin_update_driver`, `admin_set_*_status`, admin screens | suspended accounts can't sign in (get_login_status gate) |
| Terminal delete guard, shift edit guard | Implemented | `admin_delete_terminal`, `admin_update_shift` | delete blocked while drivers exist; only the 3 seeded shifts editable |
| Foreground-usage tracking (driver + commuter) | Implemented | `*_activity_sessions/_heartbeats`, trackers, `get_driver_activity_config` | read-time staleness; heartbeat timeout tunables |
| Action audit log (screens + key actions) | Implemented | `user_audit_logs`, `report_user_audit_log`, `ScreenAudit` mixin, admin viewers | privacy-disclosed; opt-out is not offered in-app |
| Terms & Privacy Policy in-app texts + consent | Implemented | `apps/{driver,customer}/lib/core/utils/legal_content.dart` | compiled into the app; changing text = new APK |
| Privacy-request workflow (DPA) backend | Implemented | `privacy_requests`, `admin_log_privacy_request`, `admin_process_deletion` | admin-side records exist |
| Privacy-request admin **screen** | **Partially implemented** | `apps/admin/lib/features/privacy/privacy_screen.dart` — no route in `app_router.dart` | file exists; not reachable in the UI |
| Diagnostics screen (device logs viewer) | **Partially implemented** | `apps/admin/lib/features/diagnostics/diagnostics_screen.dart`; `device_logs_select_admin` policy | same: DB + policy ready, screen not routed |
| Web/online booking, dispatch, GPS, payments | **Not implemented by design** | in-app `terms` lists them as excluded; no code path anywhere | out of project scope (documented boundary) |
| Offline mode | **Not implemented** | screens show error/empty states | internet required |
| Email verification letters | **Not implemented** | `20260915210000_signup_admin_approval_no_email_auth.sql` header | approval replaces email confirmation |
| Admin dark mode / multi-admin roles | **Not implemented** | single `is_system_admin()` gate | one admin principal assumed |
| Automated CI test run | **Not implemented** | `.github/workflows/deploy-admin.yml` only builds/deploys admin | tests are run manually |
| Automated DB/RPC test suite | **Not implemented** | no files under any `test/` cover database internals | correctness rests on schema constraints |
| Push deep-link routing for *all* event types | **Unverified** | routing unit tests cover known categories (`notification_event_type_test.dart`); no end-to-end push test | routing for every event type not exercised end-to-end |
| Cron auto-complete behaviour under backlog | **Unverified** | `reconcile_ride_workflow` logic inspected; no runtime test | correctness argued from code, not evidence |

## Security limitations supported by the evidence

1. **The anon key ships in the APKs by design.** Security rests on RLS + RPC
   role checks; a determined user can inspect traffic but not bypass policy.
2. **Admin's session persistence** relies on Supabase Auth token storage on
   the device; no step-up re-authentication on the admin console beyond
   initial login.
3. **No rate limiting of our own** beyond Supabase Auth's built-in limits;
   cooldowns exist per ride-request, not per brute-force attempt.
4. **Audit entries are client-initiated** (through an RPC) — a malicious
   client could skip logging; the logs are evidence, not a tamper-proof
   record (server-side session/heartbeat staleness mitigates some of this).

## Known technical limitations

- Devices need internet + SIM for the core "contact driver" action.
- Admin console lives on a public URL but is permissioned by the database.
- Notification dispatch is fire-and-forget: FCM outages lose pushes (in-app
  rows still exist).
- TODA plate data quality (freeform strings, e.g. `SSLTODA No. 00876`) relies
  on admin discipline; uniqueness of plates is not enforced as `UNIQUE`.

## Areas requiring further verification (honest gaps)

1. End-to-end push delivery rates (FCM console metrics vs Supabase logs).
2. `process_schedule_notifications` behaviour with zero followers/no
   follow preferences set.
3. Multi-device simultaneous login behaviour of the activity tracker
   (two foreground devices → two sessions — likely both counted; not tested).
4. The unrouted Privacy/Diagnostics admin screens (dead code today).
