# Defense Documentation — Source Traceability

Each significant claim used anywhere in `docs/defense/` maps to its evidence.
Statuses: **Verified** (inspected code/schema/live DB), **Inferred**
(indirect evidence), **Unverified** (no repository evidence). Line anchors
are valid for commit `0df2a87` and may drift afterward.

| # | Claim | Source file / object | Anchor | Status |
|---|---|---|---|---|
| 1 | Three apps share one Supabase project | `apps/*/lib/services/supabase_config.dart`, `apps/*/pubspec.yaml` | `supabase_flutter ^2.17.2` in all three | Verified |
| 2 | Dependency list and versions | `apps/{driver,customer,admin}/pubspec.yaml` | `environment.sdk ^3.13.2` + dep list | Verified |
| 3 | Mobile login is mobile-number based | `apps/{driver,customer}/lib/services/auth_service.dart` | `_resolveLoginEmail` (driver L19-38, customer L18-42), `signInWithPassword` (driver L70, customer L77) | Verified |
| 4 | Pre-login status gate | both `auth_service.dart` | `_assertLoginAllowed` (driver L42-60, customer L46-67), RPC `get_login_status` | Verified |
| 5 | Role assertion on wrong app | `auth_service.dart` | `_assertDriverRole` L149-158, `_assertCommuterRole` L147-156 | Verified |
| 6 | TODA plate replaces driver's license | `20261015000000_toda_plate_replaces_license.sql`; live `drivers.toda_number` | RPC signature `p_toda_number` | Verified |
| 7 | Driver requires verification to be active | `20260911000000_admin_system.sql`; live `drivers_active_requires_license` | constraint definition | Verified |
| 8 | Registration provisions auth user + profile + role | `20260915190000_signup_real_email_auth.sql`; live trigger | `on_auth_user_created_pasakay` on `auth.users` → `handle_pasakay_auth_user` | Verified |
| 9 | Signup validation (mobile, TODA plate) | `apps/{driver,customer}/lib/core/utils/{phone_utils,auth_validators}.dart` | tests in `apps/driver/test/widget_test.dart` | Verified |
| 10 | Ride request validations + error strings | `20260915130000_ride_request_booking_flow.sql` | `create_ride_request` L240, raises L266-299, `accept_ride_request` L341/L380-395/L398-401, `reject_ride_request` L445-479 | Verified |
| 11 | Reconciliation cron every minute | live `cron.job` catalog | `pasakay-reconcile-ride-workflow`, `* * * * *` | Verified |
| 12 | Reconciliation behavior (expire / auto-complete / review due) | `20260915130000...` L145-215 | `reconcile_ride_workflow` body inspected | Verified (logic); no repo test exercises it at runtime |
| 13 | One PENDING request per pair | live index `ride_requests_one_pending_per_pair` | `WHERE status='PENDING'` | Verified |
| 14 | One review per booking | live index `reviews_one_per_booking` | `WHERE booking_id IS NOT NULL` | Verified |
| 15 | Rating aggregation trigger | `20260915320000_driver_rating_aggregates.sql`; live trigger | `reviews_refresh_rating` on `reviews` | Verified |
| 16 | Anonymous-safe review display | `20260915310000_anonymous_driver_reviews.sql` | select policy hides reviewer identity | Verified |
| 17 | Bookings/requests visible to pair + admins | live policies | `bookings_select_own`, `ride_requests_select_own` | Verified |
| 18 | Realtime channels in customer app | `apps/customer/lib/services/customer_repository.dart` | `subscribeNotifications` L172-190, `subscribeRideRequestUpdates` L192-218, `subscribeBookingUpdates` L220-246 | Verified |
| 19 | Driver booking actions are RPCs | `apps/driver/lib/services/driver_repository.dart` | `accept_ride_request` L140, `reject_ride_request` L148, `flag_booking` L160, `complete_booking` L172 | Verified |
| 20 | Commuter ride RPCs | `apps/customer/lib/services/customer_repository.dart` | `create_ride_request` L372, `submit_booking_review` L411, `report_driver_booking` L426, `reconcile_ride_workflow` L394 | Verified |
| 21 | Contact passthrough (tel/sms) | `apps/*/lib/core/utils/contact_launcher.dart` + `url_launcher` | `AuthService.openCall/openSms` | Verified |
| 22 | Follow / unfollow driver | `customer_repository.dart` L248-272 | `commuter_followed_drivers` | Verified |
| 23 | Admin gate in every admin function | live function list; `assert_system_admin` / `is_system_admin` | inspected via live `pg_proc` + migration sources | Verified |
| 24 | Admin driver CRUD / status / verify RPCs | `apps/admin/lib/services/admin_repository.dart` | call sites L225-532 | Verified |
| 25 | Admin activity/audit lists + 5-minute sweep | `admin_repository.dart` L532/L562; `apps/admin/lib/features/{drivers,commuters}` screens | screen-local `Timer.periodic` | Verified |
| 26 | Two admin screens exist but are not routed | `apps/admin/lib/features/privacy/privacy_screen.dart`, `.../diagnostics/diagnostics_screen.dart`, `app_router.dart` | no route or instantiation references | Verified (not wired) |
| 27 | Privacy-request workflow backend | `privacy_requests` table, `admin_log_privacy_request`, `admin_process_deletion` | live schema + `20260911000000` header comment | Verified |
| 28 | Foreground tracker architecture (both apps) | `apps/driver/lib/services/driver_activity_tracker.dart`, `apps/customer/lib/services/commuter_activity_tracker.dart` | `AppLifecycleListener` L37/L38, `_startSession` L102/L103, "don't resurrect" comment L116/L117, heartbeat timer L141-161 | Verified |
| 29 | Audit trail subsystem | `apps/{driver,customer}/lib/services/user_audit_trail.dart` | `report_user_audit_log` L23, `ScreenAudit` mixin L43 | Verified |
| 30 | A hostile client can skip audit logging | design of silent fire-and-forget logging | `user_audit_trail.dart` L17-40 | Inferred |
| 31 | Privacy Policy discloses action logging | `apps/{driver,customer}/lib/core/utils/legal_content.dart` | "Records of in-app actions…" bullet | Verified |
| 32 | Push chain endpoints | `20260915120000_notification_push_pg_net_trigger.sql` | L39/L41 Edge Function URLs | Verified |
| 33 | FCM token registration and storage | `apps/{driver,customer}/lib/services/push_notification_service.dart`; `register_{driver,commuter}_device_token` RPCs | token tables verified live | Verified |
| 34 | Push actually delivered to devices | FCM projects + dashboard edge secrets | configuration outside the repository | Unverified |
| 35 | 27 test cases, all passing on 2026-10-17 | 6 test files; executed locally in the development session | results documented in the session transcript; no artifact in the repo | Verified (execution) |
| 36 | No integration/e2e/database test suites | `find apps/*/test` (7 files, all listed in `07`) | repo inspection | Verified |
| 37 | GitHub Actions only deploys admin web | `.github/workflows/deploy-admin.yml` | single workflow file | Verified |
| 38 | Admin deploy injects env from repo secrets | same workflow | L26-36 `.env` write + `--base-href` build | Verified |
| 39 | No secrets or personal data in the defense docs | `docs/defense/*` | reviewed contents | Verified |
| 40 | Legal texts identical across the two mobile apps | `apps/{driver,customer}/lib/core/utils/legal_content.dart` | byte-identical copies maintained in session | Verified |
| 41 | Commuter cannot cancel a pending request | RPC surface grep shows no client cancel call; `CANCELLED` status written only by admin action | absence-based | Inferred |
| 42 | Recent contacts stay on the device | `customer_repository.dart` L116-136 | `SharedPreferences` only | Verified |
| 43 | `driver_shifts` table access is dead code | `apps/driver/lib/services/driver_repository.dart` L61-78; no such table/view live | complete catalog listing | Verified |
| 44 | No GPS/location usage | Android manifests, pubspec deps, Terms text | no location dependency anywhere | Verified |
| 45 | Performance numbers / effectiveness outcomes | none | no such evidence exists in the repo | Unverified (claimed nowhere) |

## Companion documents

- `../system-analysis/TRACEABILITY.md` — the deeper evidence map (36 refs,
  26 tables, DB drill-down), cited throughout `docs/defense/`.
- `./database-erd.dbml` — identical copy of
  `../system-analysis/database/schema.dbml`, validated with `@dbml/core`
  (dbmlv2): 27 tables, 2 schemas parsed successfully.
- `../system-analysis/flowcharts/*.mmd` — six validated diagrams plus
  `end-to-end-flow.mmd`.
