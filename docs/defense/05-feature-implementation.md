# 5 · Feature Implementation

One block per major implemented feature, in the standard structure. Evidence
anchors are inline; supporting citations gathered in `SOURCE-TRACEABILITY.md`.

---

## 5.1 Account registration with admin approval

**Purpose:** let residents and SSLTODA drivers self-register while keeping
the association's roster accurate — nobody becomes visible in the app until
the admin verifies them.

**User interaction:** the commuter enters name + mobile (+ optional email)
and password; the driver additionally provides their TODA plate number and
picks their terminal. Both see a success screen telling them an administrator
must approve the account.

**Implementation:**
- Client: `apps/*/lib/features/signup/signup_screen.dart`,
  `apps/*/lib/services/auth_service.dart` (`signUp`),
  `apps/*/lib/core/utils/auth_validators.dart`,
  `apps/*/lib/core/utils/phone_utils.dart`.
- Server: `register_driver` / `register_commuter` functions
  (`20260915160000_self_register_confirmed_accounts.sql`,
  `20260915190000_signup_real_email_auth.sql`,
  `20260915250000_optional_email_required_ph_mobile.sql`,
  `20260915290000_verify_driver_requires_ssltoda.sql`).

**Data handling:** one auth user (Supabase-managed `auth.users`), one profile
row (`drivers`/`commuters`). The pickup information is served from `terminals`
during signup. Live check that usernames/phones/emails are unique through
`check_registration_availability`.

**Validation and access control:** password policy, PH mobile normalize,
unique constraints (`drivers_username_key`, `commuters_username_key`),
driver status forced to `pending_verification`, `drivers_active_requires_license`
check (a driver can't be activated until TODA verification flag is set).
Anonymous users can call registration freely — the rate-limiting and abuse
protection comes from Supabase Auth defaults (unverified beyond the platform).

**Limitations:** email is optional (phone-only accounts get a synthesized
auth email); no email verification letter path. The "verification" is manual
— no external TODA/government database is contacted (stated in the Terms).

---

## 5.2 Login and session state

**Purpose:** the daily "who are you" step, with clear error messages for
pending/suspended accounts.

**User interaction:** mobile number + password. Wrong password, wrong app,
pending, suspended and deactivated accounts all get specific messages.

**Implementation:** `SessionController` (Riverpod async notifier, replaces
state with the profile row or null), `AuthService.login` (gate → resolve
email → sign in → role assert). Admin variant uses admin email + `admins`
row check. Files: `apps/{driver,customer}/lib/core/providers/session_provider.dart`,
`apps/admin/lib/core/providers/session_provider.dart`.

**Data handling:** reads `drivers` or `commuters` row for the signed-in uid,
plus `admins.active check` for the admin path; nothing is written client-side
except the audit row (via `report_user_audit_log`).

**Validation and access control:** `get_login_status` (pre-gate),
`resolve_auth_email` (maps mobile to the provisioned identity),
role assertion (`userMetadata['role']`), RLS on the profile tables
(`*_select_own`).

**Limitations:** if Supabase Auth is unreachable, the app is stuck at splash
with a config error screen (no offline mode). Drivers' remaining shift time
is computed server-side (`is_driver_on_shift`); a stale client copy isn't an
authoritative source.

---

## 5.3 Terminal → driver browsing (commuter)

**Purpose:** let a commuter find who to contact.

**User interaction:** Terminals tab → tap a terminal → see drivers
(primarily filtered by the *current* shift) → tap a driver → profile with
plate, TODA number, rating, current terminal, availability, Follow button
and a large contact card.

**Implementation:** `apps/customer/.../terminals/`, `driver_list/`,
`driver_profile/`; data from `fetchTerminals` (direct select on `terminals`),
`fetchDrivers` → `list_terminal_shift_drivers` (server-computed: driver row +
shift + `is_driver_on_shift` state), `fetchDriver` for the details screen.

**Data handling:** reads only (plus the commuter's own follows table for the
Follow state). Ratings shown come from the trigger-maintained
`drivers.average_rating`/`review_count`.

**Validation and access control:** RLS: `terminals_read_all` and
`drivers_read_all`; the follow insert policies restrict to
`commuter_id = auth.uid()`.

**Limitations:** the list is scoped by the terminal you stood on first —
there is no search-by-name across all terminals in the commuter app
(the admin has global driver search instead). Plate number display includes
legacy "Plate No." formatting from before TODA plate replaced license plates.

---

## 5.4 Direct contact: Call / SMS passthrough

**Purpose:** connect commuter ↔ driver through the phone system without the
app holding the conversation.

**User interaction:** tapping Call opens the device dialer pre-filled with
the driver's number; tapping Message opens the default SMS app with a
pre-written message body. On the driver app, the latter is also how drivers
contact the commuter of an active trip.

**Implementation:** `apps/*/lib/core/utils/contact_launcher.dart` using
`url_launcher` (`tel:` / `sms:` URIs, unit-tested in
`apps/driver/test/widget_test.dart` "builds dialable tel and sms URIs").

**Data handling:** reads only `drivers.contact_number` / commuters. No call
or SMS content is ever transmitted over our backend; an audit row recording
that the action happened (`call_driver` / `sms_driver`) is the only trace.

**Validation and access control:** the phone number comes from the verified
driver profile, not from the commuter. The `report_user_audit_log` action is
fire-and-forget, so a failed log can't block a call.

**Limitations:** does nothing if the device has no SIM/dialer app; the app
cannot confirm the call actually happened. Disclosed in the Privacy Policy
("Phone Permission").

---

## 5.5 Ride-request + booking lifecycle

**Purpose:** actual tricycle-hailing support between the association's
registered drivers and a commuter, with clear states both sides can trust.

**User interaction:** detailed in §4.3 — commuter requests, driver sees a
card in Bookings tab with Accept/Reject, then the trip lands in "My Trip",
whose card flips around COMPLETE when the driver taps Done, FLAGGED when
either party marks an issue, or auto-COMPLETES when the cron decides.

**Implementation:** server functions in
`20260915130000_ride_request_booking_flow.sql` (list in §3),
client repos `apps/customer/lib/services/customer_repository.dart` and
`apps/driver/lib/services/driver_repository.dart`, driver UI
`apps/driver/lib/features/bookings/bookings_screen.dart`,
`apps/driver/lib/features/booking_details/booking_details_screen.dart`,
commuter realtime in `apps/customer/lib/core/providers/` ride providers.

**Data handling:** `ride_requests` (one PENDING per pair), `bookings`
(unique per request), `booking_events` journal every transition
(with `details` JSONB including actor + reason), `reconcile_ride_workflow`
for babysitting (expiry, auto-complete, review-eligibility).

**Validation and access control:** all state transitions are server-authored,
never written directly by the app: only the target driver can accept their
own request, only their commuter can report it, only within a set window
(`dispute_window_minutes`); pending requests are visible only to the pair
involved (`ride_requests_select_own`), and commuters can see only their own
bookings (`bookings_select_own`).

**Limitations:** commuter *cannot* cancel a pending request proactively
(no `cancel_ride_request` — the cancel status exists but is only reachable
through admin action; so a wrong tap means waiting for expiry). The
completed-only window for flagging (the full dispute window may be
about longer than documented; see `admin_set_booking_settings` defaults) is
server-tuned rather than fixed in code.

---

## 5.6 Reviews, ratings and review reports

**Purpose:** let commuters give feedback and the association spot problems.

**User interaction:** after a trip completes, History-entry shows a "Review"
button; the commuter submits 1–5 stars + optional text. Drivers view reviews
in their Reviews tab; either side can report a review, which the admin
resolves.

**Implementation:** `submit_booking_review`, `report_review`,
`admin_delete_review`, `admin_set_review_hidden`; triggers
`refresh_driver_rating` (updates `drivers.average_rating`/`review_count`)
and `reviews_one_per_booking` partial unique index. Client screens:
`apps/customer/.../review/`, `apps/driver/.../reviews/`,
`apps/admin/.../reviews/reviews_screen.dart`.

**Data handling:** one row per completed booking; anonymous display —
the review list for other commuters shows the driver name but never the
reviewer's identity (20260915310000_anonymous_driver_reviews.sql).

**Validation and access control:** RPC-side checks (owner/completed/window/
rating 1–5/unique); RLS `reviews_insert_own`; the admin-delete path hides
rather than hard-deletes (consistent with the research data-retention rules).

**Limitations:** no commuter-side "edit my review" (delete only in admin;
resubmission grace covered by one-per-booking rule); hidden reviews remain in
the DB (data-retention policy).

---

## 5.7 Notifications (in-app + push)

**Purpose:** keep both sides aware without both sitting in the app.

**User interaction:** bell icon + system push. Tapping a push routes to the
relevant screen (`onOpenRoute`): schedule → driver profile, request → driver
bookings, review/reply → commuter review. The Notification screen lists rows,
moves messages to read state (`markNotificationsRead`).

**Implementation:** `emit_notification` + `notifications` table +
`subscribeNotifications` realtime channels +
`PushNotificationService` (FCM token registration through
`register_driver_device_token` / `register_commuter_device_token`),
db triggers `trg_drivers_notify_changes` / `trg_shifts_notify_changes` /
schedule processor (`process_schedule_notifications` cron) making the actual
calls at scheduled times; Edge Functions (`send-driver-push`,
`send-passenger-push`) forward to FCM with the correct recipient tokens.

**Data handling:** `notifications` rows (recipient-scoped, read state), FCM
token tables, `app_notification_settings` keys (global toggles that the
notification functions consult).

**Validation and access control:** recipient-only read/update policies
(`notifications_own`, `notifications_update_own`), per-user preference
gates (`driver/commuter_pref_enabled`), dedupe via `notifications_dedupe_key_uidx`.

**Limitations:** two separate Firebase projects (driver + passenger);
edge-function secrets must be set manually in the Supabase dashboard
(documented in `apps/customer/README.md`). No offline queue — push dispatch is
best-effort; a missed push is still an unread in-app notification.

---

## 5.8 Admin console

**Purpose:** the research team's control panel for roster management and
research monitoring.

**User interaction:** list screens with pull-to-refresh and search:
Overview (usage + booking metrics), Drivers (+ per-driver detail sheet),
Commuters, Terminals, Shifts (incl. incoming shift-change requests),
Booking settings, Reviews, Disputed bookings, Review reports, plus
sidebar-audit access and password change.

**Implementation:** `apps/admin/lib/features/*`, one repository
(`drivers` select + 34 RPC call sites in
`apps/admin/lib/services/admin_repository.dart`), models parsing JSON
returned by the `admin_*` functions.

**Data handling:** reads via `admin_overview`, `admin_list_reviews`,
`admin_driver_activity_list`, `admin_commuter_activity_list`,
`admin_user_audit_logs`, etc.; writes via `admin_create_driver`,
`admin_update_driver`, `admin_set_driver_status`,
`admin_verify_driver_license` (stores `toda_number`), `admin_create_terminal`,
`admin_update_shift`, `admin_review_shift_change_request`,
`admin_resolve_disputed_booking`, `admin_resolve_review_report`,
`admin_set_booking_settings`, `admin_log_privacy_request` and friends.

**Validation and access control:** admin login gating (must have an
`admins` row with `is_active`), then `assert_system_admin()` inside each
function; deletion guards (terminal-with-drivers is blocked server-side);
The privacy-request workflow stores
"deletion may be retained for the study" in the migration header comment of
`20260911000000_admin_system.sql`.

**Limitations:** **two screens exist but are not routed** —
`PrivacyScreen` and `DiagnosticsScreen`
(`apps/admin/lib/features/privacy/privacy_screen.dart`,
`.../diagnostics/diagnostics_screen.dart`) — privacy and device-log content
behind them cannot be reached from the admin UI. No dark mode. The drivers
list soft-live-activity column polls every 5 minutes (screen-local timer).

---

## 5.9 Foreground-usage tracking + audit log (research instrumentation)

**Purpose:** let the researchers evaluate *how* the app was used, without
tracking GPS or message content.

**User interaction:** invisible.

**Implementation:**
`apps/{driver,customer}/lib/services/{driver,commuter}_activity_tracker.dart`
(Riverpod singleton, `AppLifecycleListener`, UUID session ids,
`report_driver_activity`/`report_commuter_activity`,
`get_driver_activity_config` for server-tunable heartbeat/timeout),
`apps/{driver,customer}/lib/services/user_audit_trail.dart`
(`UserAuditTrail.log`, fire-and-forget `ScreenAudit` widget mixin).
Admin surface: live activity columns and per-user Activity dialogs
(`/commuters`, `/drivers/:id`) plus the report viewer
(`admin_user_audit_logs`).

**Data handling:** `driver_activity_sessions`, `commuter_activity_sessions`
(open-ended with `end_reason` `logout|background`),
`*_heartbeats` (30-second spaced), `user_audit_logs`. Sessions self-report
`last_heartbeat_at`; the admin "state" is computed at read time (active now /
inactive if the last beat is older than the timeout or the session is closed).

**Validation and access control:** all writes go through SECURITY DEFINER
functions that resolve the user role from `auth.uid()`; unauthenticated calls
are rejected; row policies keep each user's own rows visible.

**Limitations:** tracking is **opt-in** only in the sense that it's part of
the consent text (Privacy Policy records "Records of in-app actions…");
logging failures are silently dropped; a device clock skew or no-network
period can leave a session open for longer than reality (the timeout rule
closes it at read time).

---

## 5.10 Legal texts + consent

**Purpose:** Data Privacy Act compliance — show what data is collected,
why, and get explicit consent before signup.

**User interaction:** Terms & Privacy Policy screens accessible from both
mobile apps (and referenced before signup); the text is compiled into the app
(storage: `lib/core/utils/legal_content.dart` per app). It includes the
research-team contact emails and the moderator's DPO email.

**Implementation:** shared `legal_content.dart` file, identical between the
customer app and driver app (checked-in file, no fetch-from-server step).

**Data handling:** only `report_user_audit_log` inserts documented data;
crash/device info uploads through `device_logs` (optional, insert-own).

**Validation and access control:** the signup flow displays the link to the
Privacy Policy and Terms; the consent text is listed verbatim at the bottom
of the Privacy Policy. RLS restricts no legal tables because they aren't
stored in the DB at all (static in-app text).

**Limitations:** the legal text lives in the compiled APK, so changing it
means shipping a new APK; privacy-request handling (what a user does to
invoke their DPA rights) depends on the admin console (the corresponding
admin screen is in the codebase but not routed — see 5.8).
