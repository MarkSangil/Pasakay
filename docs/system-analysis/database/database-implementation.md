# PASAKAY — Database Implementation Inventory

Scope: every public-schema database object that is *not* fully represented in
[`schema.dbml`](schema.dbml), plus supporting objects that live outside `public`.
All entries were extracted by **read-only** introspection of the live Supabase
PostgreSQL instance on 2026-10-17 (`pg_catalog` + `information_schema`), then
cross-checked against the migration files in
`apps/admin/supabase/migrations/`.

**Counts (verified live):** 26 public tables · 4 enums · 36 foreign keys
(3 of them to `auth.users`) · 43 row-level-security policies · 9 public triggers
(+ 1 trigger on `auth.users`) · 94 functions/procedures · 38 non-constraint
indexes · 13 check constraints · 2 pg_cron jobs.

---

## 1. Enums (public schema)

| Enum | Values (order matters) |
|---|---|
| `account_status` | `pending_verification`, `active`, `suspended`, `deactivated` |
| `privacy_request_type` | `access`, `correction`, `deletion` |
| `privacy_request_status` | `received`, `in_progress`, `completed`, `denied`, `retained` |
| `user_role` | `commuter`, `driver` |

Created idempotently in `20260911000000_admin_system.sql` (`do $$ ... exception
when duplicate_object`). Free-text statuses (`bookings.status`,
`ride_requests.status`, `review_reports.status`, `driver_shift_requests.status`,
`*_activity_sessions.end_reason`) are guarded by the check constraints in §5,
not by enums.

## 2. Table-level check constraints (13)

| Table · constraint | Definition |
|---|---|
| `bookings.bookings_status_check` | `status` ∈ `BOOKED, FLAGGED, COMPLETED, CANCELLED` |
| `commuter_activity_sessions ... end_reason_check` | `logout`, `background` |
| `driver_activity_sessions ... end_reason_check` | `logout`, `background` |
| `commuter_device_tokens ... platform_check` | `ios`, `android`, `web` |
| `device_tokens ... platform_check` | `ios`, `android`, `web` |
| `driver_shift_requests ... status_check` | `pending`, `approved`, `rejected` |
| `drivers_active_requires_license` | `status <> 'active' OR license_verified` |
| `drivers_is_active_matches_status` | `is_active = (status = 'active')` |
| `review_reports_status_check` | `OPEN`, `RESOLVED`, `DISMISSED` |
| `reviews_rating_check` | `1 <= rating <= 5` |
| `ride_requests_status_check` | `PENDING, ACCEPTED, REJECTED, EXPIRED, CANCELLED` |
| `user_audit_logs_action_check` | `1 <= length(trim(action)) <= 64` |
| `user_audit_logs_user_role_check` | `user_role ∈ driver, commuter` |

## 3. Indexes (of which DBML cannot capture the full definition)

`schema.dbml` carries each index's columns and uniqueness, but the DBML grammar
does not support ordering or partial-predicate parameters. The live definitions:

| Table · index | Full definition |
|---|---|
| `bookings_auto_complete_idx` | `(status, confirmed_at) WHERE status = 'BOOKED'` |
| `bookings_review_due_idx` | `(status, review_eligible_at) WHERE status='COMPLETED' AND reviewed_at IS NULL` |
| `bookings_passenger_reported_idx` | `(passenger_reported_at DESC) WHERE passenger_reported_at IS NOT NULL` |
| `bookings_commuter_status_idx` | `(commuter_id, status, confirmed_at DESC)` |
| `bookings_driver_status_idx` | `(driver_id, status, confirmed_at DESC)` |
| `booking_events_created_idx` | `(created_at DESC)` |
| `commuter_activity_heartbeats_commuter_idx` | `(commuter_id, beat_at DESC)` |
| `commuter_activity_heartbeats_session_idx` | `(session_id, beat_at)` |
| `commuter_activity_sessions_commuter_idx` | `(commuter_id, started_at DESC)` |
| `commuter_device_tokens_token_uidx` | UNIQUE `(token)` |
| `commuter_device_tokens_commuter_id_idx` | `(commuter_id)` |
| `commuter_followed_drivers_driver_idx` | `(driver_id)` |
| `commuters_status_idx` | `(status)` |
| `device_logs_access_idx` | `(access_datetime DESC)` |
| `device_logs_user_idx` | `(user_type, user_id, access_datetime DESC)` |
| `device_tokens_token_uidx` | UNIQUE `(token)` |
| `device_tokens_driver_id_idx` | `(driver_id)` |
| `driver_activity_heartbeats_driver_idx` | `(driver_id, beat_at DESC)` |
| `driver_activity_heartbeats_session_idx` | `(session_id, beat_at)` |
| `driver_activity_sessions_driver_idx` | `(driver_id, started_at DESC)` |
| `driver_shift_requests_status_idx` | `(status, created_at DESC)` |
| `drivers_shift_idx`, `drivers_status_idx`, `drivers_terminal_idx` | single-column `(shift_id)`, `(status)`, `(terminal_id)` |
| `notifications_recipient_date_idx` | `(recipient_id, date_sent DESC)` |
| `notifications_recipient_idx` | `(recipient_type, recipient_id, date_sent DESC)` |
| `notifications_dedupe_key_uidx` | UNIQUE `(dedupe_key) WHERE dedupe_key IS NOT NULL` |
| `privacy_requests_status_idx` | `(status, received_at DESC)` |
| `review_reports_one_open_per_pair` | UNIQUE `(review_id, driver_id) WHERE status = 'OPEN'` |
| `reviews_commuter_idx` | `(commuter_id)` |
| `reviews_driver_idx` | `(driver_id, date_created DESC)` |
| `reviews_hidden_idx` | `(is_hidden, date_created DESC)` |
| `reviews_one_per_booking` | UNIQUE `(booking_id) WHERE booking_id IS NOT NULL` |
| `ride_requests_commuter_status_idx` | `(commuter_id, status, created_at DESC)` |
| `ride_requests_driver_status_idx` | `(driver_id, status, created_at DESC)` |
| `ride_requests_one_pending_per_pair` | UNIQUE `(commuter_id, driver_id) WHERE status = 'PENDING'` |
| `user_audit_logs_action_idx` | `(action, occurred_at DESC)` |
| `user_audit_logs_user_idx` | `(user_id, occurred_at DESC)` |

Unique *constraint* indexes (`drivers_username_key`, `commuters_username_key`,
`admins_email_key`, `admins_username_key`, `shifts_shift_start_time_shift_end_time_key`,
`terminals_terminal_name_key`, `bookings_request_id_key`) are represented in the
DBML as column/index `unique` attributes.

## 4. Row-level security

RLS is enabled on 24 of 26 tables (exceptions: `app_notification_settings`,
`notification_event_log` — both are internal system tables).

Policy patterns (43 policies total):

- **Own-row ownership** (`auth.uid()` matches the profile/scope column):
  `admins`, `commuters` (select/update/insert-own, plus select for a driver with
  an active `BOOKED` booking with that commuter), `device_logs`,
  `device_tokens`, `commuter_device_tokens`, notifications
  (`recipient_id = uid`, select + update-is-read), notification & privacy
  preferences, follow tables, activity session/heartbeat tables, audit logs
  (select own only — inserts go through `report_user_audit_log`).
- **Broader read**: `drivers_read_all`, `shifts_read_all`,
  `terminals_read_all` (includes `anon` — these power pre-login screens).
- **Admin** via `is_system_admin()`: `booking_events` select,
  `privacy_requests` all, plus private clauses inside `commuters`,
  `device_logs`, `driver_shift_requests`, `review_reports`.
- **Peer visibility**: `bookings` and `ride_requests` are visible to their
  commuter, their driver, or a system admin; `review_reports` to the flagged
  driver or admin; `reviews` to owners, admins, or when not hidden.

## 5. Functions and procedures (94, SECURITY DEFINER unless noted)

By group (verified live via `pg_proc`):

**Identity / registration**
`handle_pasakay_auth_user()` (trigger fn), `provision_auth_user()`,
`register_driver()`, `register_commuter()`, `check_registration_availability()`,
`normalize_ph_mobile()`, `resolve_auth_email()`, `get_login_status()`,
`set_auth_login_allowed()`, `admin_change_password()`,
`admin_reset_driver_password()`, `admin_reset_commuter_password()`.

**Formatting / normalization helpers**
`normalize_driver_license()`, `format_driver_license()` (deprecated license
support retained), `normalize_plate()`, `format_plate()`, `manila_now()`,
`manila_today()`, `shift_display_name()`, `shift_windows_overlap()`.

**Terminals**
`admin_create_terminal()`, `admin_update_terminal()`,
`admin_delete_terminal()` (blocked while drivers are attached).

**Shifts**
`admin_update_shift()`, `request_driver_shift_change()`,
`admin_review_shift_change_request()`, `get_my_shift_change_request()`,
`admin_list_shift_change_requests()`, `invalidate_driver_shift_events()`,
`is_driver_on_shift()`, `notify_commuter()`, `notify_driver()`,
`notify_followers_of_driver()`, `emit_notification()`, `notif_setting()`,
`driver_pref_enabled()`, `commuter_pref_enabled()`,
`process_schedule_notifications()` (pg_cron every minute).

**Drivers (admin CRUD)**
`admin_create_driver()`, `admin_update_driver()`, `admin_delete_driver()`,
`admin_set_driver_status()`, `admin_verify_driver_license()` (2 overloads —
the 3-arg version also stores `toda_number`), `admin_set_commuter_status()`.

**Ride workflow**
`create_ride_request()`, `accept_ride_request()`, `reject_ride_request()`,
`complete_booking()`, `flag_booking()`, `report_driver_booking()`,
`submit_booking_review()`, `report_review()`, `reconcile_ride_workflow()`
(pg_cron every minute), `booking_setting_int()`, `get_booking_settings()`,
`admin_set_booking_settings()`, `log_booking_event()`,
`get_driver_request_context()`, `list_terminal_shift_drivers()`,
`peer_contact_for_active_booking()`, `admin_resolve_disputed_booking()`,
`admin_resolve_review_report()`.

**Reviews / ratings**
`refresh_driver_rating()` (trigger fn), `admin_list_reviews()`,
`admin_delete_review()`, `admin_set_review_hidden()`.

**Notifications**
`dispatch_notification_push()` (trigger fn, uses `pg_net` to POST the
`send-driver-push` / `send-passenger-push` Edge Functions),
`trg_drivers_notify_changes()`, `trg_shifts_notify_changes()` (trigger fns).

**Admin overview / privacy**
`admin_overview()`, `assert_system_admin()`, `is_system_admin()`,
`admin_log_privacy_request()`, `admin_set_privacy_status()`,
`admin_subject_snapshot()`, `admin_apply_correction()`,
`admin_process_deletion()`.

**Usage activity tracking**
`report_driver_activity()`, `report_commuter_activity()`,
`get_driver_activity_config()`, `driver_session_chain_start()`,
`commuter_session_chain_start()`, `admin_driver_activity_list()`,
`admin_commuter_activity_list()`, `admin_driver_usage_summary()`,
`admin_commuter_usage_summary()`.

**Audit logs**
`report_user_audit_log()` (role resolved server-side from `auth.uid()`;
unauthenticated calls are rejected), `admin_user_audit_logs()`.

**Device tokens**
`register_driver_device_token()`, `register_commuter_device_token()`,
`touch_device_token_updated_at()`, `touch_commuter_device_token_updated_at()`
(trigger fns), `set_updated_at()` (generic trigger fn).

## 6. Triggers

On `public` (9):

| Trigger | Table | Function | Fires |
|---|---|---|---|
| `admins_set_updated_at` | `admins` | `set_updated_at()` | BEFORE UPDATE |
| `commuters_set_updated_at` | `commuters` | `set_updated_at()` | BEFORE UPDATE |
| `privacy_requests_set_updated_at` | `privacy_requests` | `set_updated_at()` | BEFORE UPDATE |
| `device_tokens_set_updated_at` | `device_tokens` | `touch_device_token_updated_at()` | BEFORE UPDATE |
| `commuter_device_tokens_set_updated_at` | `commuter_device_tokens` | `touch_commuter_device_token_updated_at()` | BEFORE UPDATE |
| `drivers_notify_changes` | `drivers` | `trg_drivers_notify_changes()` | AFTER UPDATE OF `shift_id, terminal_id, is_active, status` |
| `shifts_notify_changes` | `shifts` | `trg_shifts_notify_changes()` | AFTER UPDATE OF `shift_start_time, shift_end_time, label` |
| `trg_notifications_dispatch_push` | `notifications` | `dispatch_notification_push()` | AFTER INSERT (pg_net push) |
| `reviews_refresh_rating` | `reviews` | `refresh_driver_rating()` | AFTER INSERT/UPDATE/DELETE |

Outside `public` (verified live):

| Trigger | Table | Function |
|---|---|---|
| `on_auth_user_created_pasakay` | `auth.users` | `public.handle_pasakay_auth_user()` |

The `auth.users` trigger provisions the mirrored profile row and the role
metadata that the mobile apps read back (migration
`20260915190000_signup_real_email_auth.sql`).

## 7. Scheduled jobs (pg_cron)

| Job name | Schedule | Command |
|---|---|---|
| `pasakay-process-schedule-notifications` | `* * * * *` | `select public.process_schedule_notifications()` |
| `pasakay-reconcile-ride-workflow` | `* * * * *` | `select public.reconcile_ride_workflow()` |

## 8. Extensions installed

`pgcrypto` (uuid generation), `pg_net` (HTTP push), `pg_cron` (scheduling).
Additional third-party extensions (`pgjwt`, etc.) may exist from the Supabase
base image but are not used by project code.

## 9. Supabase-managed objects outside project scope

`auth.users`, `auth.sessions`, `storage.buckets`, and related schema ownership
belong to the Supabase platform. PASAKAY depends on `auth.users.id` (FK target)
and password sign-in, but does not alter those schemas beyond the single
`on_auth_user_created_pasakay` trigger documented above.

## 10. Views

There are **no views or materialized views** in the `public` schema — all list
queries are SECURITY DEFINER functions returning `jsonb`.
