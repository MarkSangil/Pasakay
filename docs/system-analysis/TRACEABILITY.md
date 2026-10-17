# PASAKAY — Traceability

Evidence map for every flow in the diagrams and every relationship in
[`schema.dbml`](database/schema.dbml). The task specification's evidence grades
are used verbatim:

- **Verified** — explicitly supported by inspected implementation or schema
  definitions.
- **Inferred** — supported by indirect evidence but not explicitly declared.
- **Unverified** — cannot be established from the available sources.

Authoritative schema evidence is the **live database** (read-only
`pg_catalog`/`information_schema` introspection on 2026-10-17) plus the
migrations in `apps/admin/supabase/migrations/` (34 files, all inspected).
Application evidence is the Dart/TypeScript source listed per row.
Line numbers are head anchors valid for commit `6188ff0` and may drift.

## 1. Flowcharts

| Diagram | Flow documented | Primary evidence (verified) |
|---|---|---|
| `flowcharts/system-context.mmd` | clients ↔ Supabase ↔ FCM/device dialer | `apps/*/lib/services/supabase_config.dart` (URL/anon key + `initialize()`); `apps/admin/supabase/migrations/20260915120000_notification_push_pg_net_trigger.sql` L39/L41 (Edge Function URLs, pg_net); device Phone/SMS launched via `apps/{driver,customer}/lib/core/utils/contact_launcher.dart` exposed by `AuthService.openCall/openSms`; cron + job definitions verified live |
| `flowcharts/application-startup.mmd` | `main()` init order, provider wiring, splash routing | `apps/driver/lib/main.dart` L11-52, `apps/customer/lib/main.dart` L11-62, `apps/admin/lib/main.dart` L201-210; routers: `apps/*/lib/core/router/app_router.dart`; splash: `apps/driver/lib/features/splash/splash_screen.dart`, `apps/customer/lib/features/splash/splash_screen.dart` (48 L); session providers `apps/driver/lib/core/providers/session_provider.dart` L30-62, `apps/customer/.../session_provider.dart` L27-40, admin L12-40 |
| `flowcharts/authentication.mmd` | login gate, email resolution, role assertion, registration, admin gate | driver: `apps/driver/lib/services/auth_service.dart` L19-79 (`resolve_auth_email` L25-28, `get_login_status` L44-47, `signInWithPassword` L70, role assert L149-158), customer: `apps/customer/lib/services/auth_service.dart` L18-86, L147-156 + `register_commuter` L97; driver signup `register_driver` L93-104 (TODA plate + terminal); profile fetch L160-199 (drivers + specific FK aliasing) and `apps/customer/lib/services/auth_service.dart` L158-172 (commuters); admin: `apps/admin/lib/core/providers/session_provider.dart` L45-56 + `apps/admin/lib/services/admin_repository.dart` L25-33 (admins row + `is_active`); server gates: migration `20260915200000_signin_requires_confirmed_email.sql`, `20260915210000_signup_admin_approval_no_email_auth.sql`, `20260915290000_verify_driver_requires_ssltoda.sql` |
| `flowcharts/core-workflows.mmd` | ride request → accept/reject → booking → dispute → review | client: `apps/customer/lib/services/customer_repository.dart` L358-437 (`get_driver_request_context` L364, `create_ride_request` L372, `reconcile_ride_workflow` L394, `submit_booking_review` L411, `report_driver_booking` L426), realtime subscriptions L172-246; driver: `apps/driver/lib/services/driver_repository.dart` L140, L148, L172 (`accept_ride_request`, `reject_ride_request`, `complete_booking`, `flag_booking`), bookings screen `apps/driver/lib/features/bookings/bookings_screen.dart`; server: `20260915130000_ride_request_booking_flow.sql` (`create_ride_request` L240+ validation errors L266-299, `accept_ride_request` L341+ incl. expiry L380-395 and booking insert L398-401, `reject_ride_request` L445-479, `flag_booking` L507+ dispute window L538, `submit_booking_review` L575+ eligibility L601-603, `reconcile_ride_workflow` L145+ expire/auto-complete/review-due L166/L184/L210); review triggers: `20260915150000_review_on_booking_completed.sql`, `20260915310000_anonymous_driver_reviews.sql`, `20260915320000_driver_rating_aggregates.sql` |
| `flowcharts/database-interactions.mmd` | PostgREST access pattern, RLS, triggers, push | repositories: `apps/driver/lib/services/driver_repository.dart`, `apps/customer/lib/services/customer_repository.dart`, `apps/admin/lib/services/admin_repository.dart` (34 RPC call sites L40-600); audit RPC: `apps/*/lib/services/user_audit_trail.dart` L17-40; activity RPC: `apps/driver/lib/services/driver_activity_tracker.dart`, `apps/customer/lib/services/commuter_activity_tracker.dart`; realtime channels: `customer_repository.dart` L172-246; triggers/policies/RLS: verified live, source migrations `20260911000000_admin_system.sql`, `20260915120000_notification_push_pg_net_trigger.sql`, `20260915340000_realtime_replica_identity.sql`, `20261015000001_driver_activity_tracking.sql`, `20261017000000_user_audit_and_commuter_activity.sql` |
| `flowcharts/activity-audit.mmd` (extra diagram — justified) | foreground session chain + audit logging + 5-minute admin sweep | `apps/driver/lib/services/driver_activity_tracker.dart` L20-165 (AppLifecycleListener L37, `setDriver` L49, `endForLogout` L64, `_startSession` L102 incl. "don't resurrect" comment L116, heartbeat timer L141-161); `apps/customer/lib/services/commuter_activity_tracker.dart` L21-120, L216; audit services: `apps/{driver,customer}/lib/services/user_audit_trail.dart` L17-60 (`report_user_audit_log` L23, `ScreenAudit` mixin L43); session provider logout wiring: driver `session_provider.dart` L182-192, customer L162-170; admin sweeps: `apps/admin/lib/features/drivers/drivers_screen.dart` (5-min `Timer.periodic`), `apps/admin/lib/features/commuters/commuters_screen.dart` (same pattern); server side: `20261015000001_driver_activity_tracking.sql` + `20261017000000_user_audit_and_commuter_activity.sql` (`*_session_chain_start` functions verified live). **Time-out staleness computed at read time** (verified) |

## 2. Database entities and relations (schema.dbml)

All 26 public tables and all 36 FKs in `schema.dbml` are **Verified** from
`pg_constraint` on the live database and the DDL in the migrations. Selected
notable relationships:

| Relationship | Constraint (live) | Notes |
|---|---|---|
| `profile_table.X_id -> auth.users.id` (`admins`, `commuters`, `drivers`) | `admins_admin_id_fkey`, `commuters_commuter_id_fkey`, `drivers_driver_id_fkey` | one-to-one; profile rows are provisioned by the `auth.users` trigger, not by the apps |
| `bookings.request_id -> ride_requests.request_id` | `bookings_request_id_fkey` + unique `bookings_request_id_key` | DB-enforced 1:1 (unique FK); DBML shows `>` many-to-one because DBML direction syntax is limited — documented here, **Verified** unique |
| `booking_events.booking_id -> bookings`, `booking_events.request_id -> ride_requests` | `ON DELETE SET NULL` | event journal keeps rows after parent deletion |
| `ride_requests.commuter_id/driver_id` -> profiles | no cascade, no identity chain | deletion of profiles is admin-managed; **Verified** |
| `reviews.booking_id -> bookings` | `reviews_booking_id_fkey` + partial index `reviews_one_per_booking` (`WHERE booking_id IS NOT NULL`) | **Verified** |
| `review_reports.review_id -> reviews` | `ON DELETE CASCADE` | **Verified** |
| `drivers.terminal_id` and `drivers.current_terminal_id` -> `terminals` | both `ON DELETE NO ACTION` — `admin_delete_terminal` blocks deletion while drivers attached | **Verified** |
| `user_audit_logs.user_id`, `device_logs.user_id`, `notifications.recipient_id/driver`, `notification_event_log.*` | **no foreign keys** (polymorphic over drivers/commuters by role columns) | database-enforced nothing; relation is logic-only → **Inferred** |
| `drivers.license_verified_by`, `bookings.flagged_by`, `bookings.flagged_at` | `bookings.flagged_by` and `bookings.flagged_at` exist as columns but **no FK** on `flagged_by`; `review_reports.resolved_by -> admins`, `privacy_requests.handled_by -> admins`, `driver_shift_requests.admin_id -> admins` are **Verified** FKs | flagging actor is stored as data only |

Inferred-only relationships to treat with care (documented here, not drawn as
FK in DBML):

1. `user_audit_logs.user_id` → `drivers.driver_id`/`commuters.commuter_id`
   based on `user_audit_logs.user_role` (Verified: `check` constrains role
   values; no FK exists).
2. `device_logs.user_id` + `user_type` → profile rows (same pattern).
3. `notifications.recipient_id` + `recipient_type` → profile rows;
   `related_driver_id` → `drivers` (data-level only).
4. `app_notification_settings.key/value` and `notification_event_log` are
   written exclusively by server functions (Verified by policy absence and
   function source) — no client writes.

## 3. Implementation inconsistencies discovered

These are factual code-vs-database observations only. **No changes were made.**

1. **`driver_shifts` access in the driver app is dead code against this
   database.** `apps/driver/lib/services/driver_repository.dart` L61-78
   (`fetchTodaysShift`) queries `from('driver_shifts')` with columns
   `shift_date`, `start_at`, plus `terminal:terminals(*)` — no table or view
   named `driver_shifts` exists on the live DB (verified). Callers
   (`apps/driver/lib/features/bookings/bookings_screen.dart` L96-100) catch the
   error and render no shift card. Verified as a runtime no-op everywhere.
2. **License field is retained but deprecated.** `drivers.driver_license_number`
   still exists (live DB) while `drivers.plate_number` is NOT NULL and
   `toda_number` is the active verification token
   (`20261015000000_toda_plate_replaces_license.sql`); `format_driver_license`
   RPC shim remains but no client call site uses it (verified by source grep).
3. **Legacy auth fallback columns.** `auth_service.fetchCurrentDriver` and
   `updateCurrentTerminal` keep secondary query paths using `eq('id', ...)` and
   `drivers_assigned_terminal_id_fkey` (L183-190, 225-230) that cannot exist on
   the live schema — they are unreachable fallbacks wrapped in `try/catch`.
4. **`reviews.commuter_id` cascade delete only.** A deleted commuter's reviews
   vanish but the rating trigger treats deletes; consistent with
   `refresh_driver_rating` (verified live).
5. **`driver_notification_preferences` and `commuter_notification_preferences`
   have direct-table upserts from mobile apps (Verified)** but no dedicated
   admin UI (administrative change only via SQL documentation — out of scope).

## 4. Unresolved / unverified items

| Item | Grade | Reason |
|---|---|---|
| Exact retry/offline behavior of client `UserAuditTrail` under network loss | Inferred | code shows silent failure + no queue (`user_audit_trail.dart` L17-40 comment), but no integration test observed |
| Behavior of `process_schedule_notifications()` under no-follow | Verified partially | function definition inspected via live catalog, cron runs every minute, but runtime scheduling edge states not exercised in this analysis |
| Supabase dashboard project settings (auth rate limits, SMTP) | Unverified | configuration is dashboard-side, not in the repo or DB introspection |
| Edge Function secrets (FCM server key wiring) | Unverified | `send-driver-push/index.ts` reads runtime env vars; secrets are platform-managed |
| Admin dashboard offline behavior | Inferred | repositories return raw errors and screens keep previous snapshot; UI-level behavior not exhaustively enumerated |

## 5. Tool availability note

`@mermaid-js/parser` (npm) excluded flowchart from its languages, so
validation used **`@mermaid-js/mermaid-cli` (mmdc) 11.x headless render** per
file — all six `.mmd` files produced SVGs without parse errors.
`schema.dbml` validated with **`@dbml/core` `Parser.parse(..., 'dbmlv2')`**
(27 tables, 2 schemas). Commands recorded in the final report.
