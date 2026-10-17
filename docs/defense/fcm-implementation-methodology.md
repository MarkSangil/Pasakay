# Supabase + Firebase FCM Implementation Methodology

This document explains the flowchart
[`flowcharts/supabase-firebase-fcm-implementation.mmd`](flowcharts/supabase-firebase-fcm-implementation.mmd)
in plain English. It describes the **development process** (how the push
integration was built) and separates it from the **runtime delivery process**
(how a notification actually travels), which has its own diagram
[`flowcharts/supabase-firebase-fcm-runtime.mmd`](flowcharts/supabase-firebase-fcm-runtime.mmd).

Everything here is based on inspected code, migrations and configuration in
this repository (commit `2dd47b5`), with evidence anchors in
[`flowcharts/TRACEABILITY.md`](flowcharts/TRACEABILITY.md). Where the
repository cannot prove something, that is stated — nothing is filled in
with assumptions.

## A. Where to Start

The integration does not start in the mobile code — it starts with the
backend contract the apps will use. The verified starting points and
prerequisites, and why each one is needed:

| # | Starting point / prerequisite | Why it is needed | Evidence |
|---|---|---|---|
| 1 | Two Flutter app projects working against one Supabase project (`apps/driver`, `apps/customer`) | Push is a per-role feature; both apps need their own device registration and their own Firebase project because a driver's devices and a commuter's devices are separate audiences | `pubspec.yaml` files, `supabase_config.dart` |
| 2 | A notifications data model already defined (`notifications` table with `recipient_id`, `recipient_type`, `event_type`, `data`) | Push delivery is a *side effect* of a notification row being written; without the row there is no dispatch and no in-app record | `20260910…` `notifications` migration; prior chapters of this doc set |
| 3 | Flutter SDK with the Firebase packages pinned (`firebase_core ^4`, `firebase_messaging ^16`, `flutter_local_notifications ^19`) | Device registration, token lifecycle and foreground display all go through these plugins | `apps/*/pubspec.yaml` |
| 4 | Android `minSdk 23` and the `POST_NOTIFICATIONS` permission | `firebase_messaging` requires API 23+; Android 13 requires the runtime permission for any banner to appear | `android/app/build.gradle.kts`, `AndroidManifest.xml` |
| 5 | A Firebase project per Android application ID (driver: `pasakay-9c97c`, customer: `pasakay-passenger`) | FCM routing is project-scoped; the google-services plugin refuses to build if the package name in the config file does not match `applicationId` | `google-services.json` in each `android/app/` |
| 6 | A Supabase Vault secret + matching Edge Function secret | The database trigger needs a shared secret to call the Edge Function, and the function needs a Firebase service-account JSON to call Google | `20260915120000…sql` header, both `index.ts` files, `apps/driver/README.md` |

## B. Applications and Tools Used

Only tools with repository or session evidence are listed as verified. "How
it is used" describes this project specifically.

| Application or tool | Purpose | How it is used in this project | Evidence |
|---|---|---|---|
| Flutter SDK + Dart | Application framework and language for both Android apps | The entire mobile layer (`lib/` of both apps) is Flutter; `flutter pub get`, `flutter analyze`, `flutter test` and `flutter build apk` were executed in the development sessions | `pubspec.yaml` (SDK ^3.13.2); session build/test results | 
| Gradle (Kotlin DSL) | Android build configuration | Applies the google-services plugin, sets `minSdk 23`, `applicationId`, desugaring | `android/app/build.gradle.kts` |
| Firebase Console | Creating Firebase projects, registering Android apps, generating the service-account key | The two `google-services.json` files and the service-account JSON referenced by the Edge Function secrets are produced here. The config files exist and are committed; actually clicking through the console is **inferred** (necessary to produce those files) but not filmed anywhere | `apps/*/android/app/google-services.json`; `apps/driver/README.md` console instructions |
| Supabase Dashboard | Project, Edge Function secrets, Vault secret, cron schedules | The project is live (API base `musogdwaxdyiatmnitkg.supabase.co`); the Vault secret name and both dashboard secrets are part of the documented one-time setup. Secret *values* are by design never in the repository, so this stage is **inferred/documented**, not code-verifiable | `20260915120000…sql` header; both `index.ts` `Deno.env.get` reads; driver README |
| Supabase CLI | Deploying Edge Functions / migrations | **Not evidenced.** There is no `config.toml`, no CLI scripts, no deployment scripts in the repo. Deployment method (dashboard import vs CLI) is **unverified** — but deployment itself is proven: both function URLs answer HTTP 401 without auth | repo tree (no CLI config); 401 curl check 2026-10-17 |
| Terminal (`curl`, SQL editor equivalents) | Manual test sends | The README documents a `notify_driver` SQL smoke test and a curl call with the service-role key as the acceptance procedure | `apps/driver/README.md` §Push delivery |
| Android device or emulator | Receiving tokens and banners | The README explicitly requires a device/emulator **with Google Play** for FCM to function. Whether the team ran the end-to-end manual test on a device is **unverified** from the repository | `apps/driver/README.md` step 3 |
| Android Studio / VS Code | IDE used for editing | **Unverified** — no workspace metadata is committed, and the choice of IDE has no effect on the implementation. Android Studio is *not* claimed as the place code was written | no `.idea`/`.vscode` files tracked |
| Mermaid Live Editor | Rendering the flowcharts | The `.mmd` files in `docs/` were validated headlessly with mermaid-cli (0 errors) during the documentation sessions; the same sources render in mermaid.live | this docs set; validation logs |

## C. Implementation Methodology (chronological)

The numbers below match the numbered nodes in
`supabase-firebase-fcm-implementation.mmd`. All push-related code entered the
repository in one commit (`6b12d1e`, 2026-09-16: "Add booking, push, and
admin web deploy"), so the *chronology described here is the internal
design order of that change rather than separate commits*.

### Stage A — Development environment (steps 1–3)

**What was done:** the two existing Flutter apps were extended with the
Firebase plugin family, and the Android build was prepared: the
`com.google.gms.google-services` Gradle plugin applied, `minSdk` raised to 23
with a comment explaining why ("Firebase Messaging requires minSdk 23+"),
the `INTERNET` and `POST_NOTIFICATIONS` permissions declared, and the default
notification channel id (`pasakay_driver_alerts` / `pasakay_passenger_alerts`)
and status-bar icon (`ic_stat_pasakay`) registered in each manifest.

**Tool:** Flutter toolchain + Gradle. **Files:** `pubspec.yaml`,
`android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`,
`res/drawable/ic_stat_pasakay.xml`.

**Why necessary:** the google-services plugin processes `google-services.json`
at build time and fails without it; a banner on Android 13+ cannot appear
without the declared and runtime-granted permission; the Edge Function later
sends `channel_id` values that only work if the app created channels with the
same ids at startup (which it does, `PushNotificationService._ensureLocalNotifications`).

**Expected result / evidence:** running `flutter pub get` and a build
compiles the Firebase packages — confirmed in the session APK builds with
Firebase packages resolved (both iOS SourcePackages and Android Gradle
dependency graphs contain `firebase_messaging-16.7.0`).

### Stage B — Firebase configuration (steps 4–6)

**What was done:** two Firebase projects exist: `pasakay-9c97c` for
`com.pasakay.pasakay_driver` and `pasakay-passenger` for
`com.pasakay.pasakay_customer` (verified by reading the committed
config files — package names and project ids only; no secret material is
reproduced in documentation). Each app received its own `google-services.json`
under `android/app/`. iOS is **not** configured: there is no
`GoogleService-Info.plist` anywhere, matching the README note "Not configured
yet".

**Tool:** Firebase Console (inferred as the only way these files are
produced). **Why separated into two projects:** token scope isolation — the
driver service account keys can only send to driver devices, so a compromised
driver backend credential cannot target commuters, and vice versa.

**Decision point in the diagram:** if the package name does not match
`applicationId`, the Gradle google-services task fails — that is the first
place a reviewer sees a wrong configuration.

### Stage C — Supabase configuration (steps 7–11)

**What was done, in order:**

1. **Token tables** — `device_tokens` and `commuter_device_tokens`: uuid PK,
   FK to `drivers`/`commuters` with `ON DELETE CASCADE`, `platform` CHECK
   (`ios`/`android`/`web`), `created_at`/`updated_at`, `updated_at`
   maintenance trigger, RLS enabled with owner-only select/insert/delete
   policies. A later migration (`…token_claim`) made `token` itself unique
   (`device_tokens_token_uidx`) and relaxed the update policy so the
   security-definer RPC can *claim* an existing token row when account
   switches happen on the same phone.
2. **Registration RPCs** — `register_driver_device_token` /
   `register_commuter_device_token` are `SECURITY DEFINER`: they resolve the
   current principal from `auth.uid()`, refuse unauthenticated calls, validate
   the platform, check the driver is `active`/`suspended` ("Driver session is
   not eligible for push tokens" otherwise), and upsert on token conflict so
   a token always ends up owned by the currently signed-in user.
3. **Notification sources** — `emit_notification` (respects per-user
   preference toggles and dedupe keys), `notify_driver` (simple helper used
   by the README smoke test), the minute-cron schedule processor, and the
   ride/review workflow functions — all of them ultimately insert into
   `notifications`. **No push is sent by any of these functions directly.**
4. **Shared secret in Vault** — `notification_push_webhook_secret`; the
   trigger aborts dispatch with only a warning if it is missing (documented
   failure path, not an app crash).
5. **Dispatch trigger** — `trg_notifications_dispatch_push`, `AFTER INSERT
   FOR EACH ROW` on `notifications`, SECURITY DEFINER, uses the `pg_net`
   extension: builds a payload shaped like `{ type, table, schema, record }`
   and fires `net.http_post` (5-second timeout) to one of two Edge Function
   URLs chosen by `recipient_type`. Any exception is logged as a warning and
   swallowed — **the insert never fails because of push problems**, which is
   why in-app notifications stay reliable even when push is broken.

**Why this design:** centralizing dispatch in a row-level trigger means every
notification-producing path (workflow functions, cron, admin tooling) gets
push automatically without any additional code.

### Stage D — Edge Functions (steps 12–14)

**Location:** `apps/admin/supabase/functions/send-driver-push/index.ts`
(306 lines) and `…/send-passenger-push/index.ts` (295 lines). They are
deliberately mirrored: the driver one reads `device_tokens` by `driver_id`,
the passenger one `commuter_device_tokens` by `commuter_id`.

**What the function does at run time:**

1. **Auth check** — accepts either `Bearer SUPABASE_SERVICE_ROLE_KEY`
   (platform-managed) or `Bearer NOTIFICATION_PUSH_SECRET` (the shared secret
   from the Vault); anything else → `401`. Non-POST → `405`. Missing secrets
   → `500` with a descriptive message.
2. **Payload normalization** — accepts a manual test body
   (`{driver_id…}`/`{commuter_id…}`) **or** the webhook-style body the
   trigger sends (`record.recipient_id`, `message_content`, `event_type`,
   `data`). If only a `notification_id` is provided, the row is loaded from
   the `notifications` table via a service-role Supabase client. Wrong
   recipient type → `{ok: true, skipped}` (the driver function ignores
   commuter rows, and vice versa).
3. **No tokens → success with `sent: 0`** — a recipient without registered
   devices is not an error.
4. **Google authorization** — the function builds a signed JWT (RS256) from
   the stored Firebase service-account JSON, exchanges it at
   `https://oauth2.googleapis.com/token` with the
   `firebase.messaging` OAuth scope, and receives a 1-hour access token.
   This is implemented by hand with `crypto.subtle` (no Firebase Admin SDK on
   the server, no legacy FCM server key).
5. **FCM send** — for each token: `POST
   https://fcm.googleapis.com/v1/projects/{projectId}/messages:send` with
   `notification` (title/body), `data` (event routing), Android priority
   `HIGH`, the matching `channel_id`, icon and APNs block.
6. **Response handling** — per-token `ok/detail` results; two failures are
   self-healing: an `UNREGISTERED` or `INVALID_ARGUMENT` FCM result deletes
   that token row immediately, so stale device tokens never accumulate.
   The function answers `{ok, sent, failed, results}`.
7. **Deployment** — proven live: `POST /functions/v1/send-driver-push` and
   `…/send-passenger-push` both answer **401** without an Authorization
   header (checked 2026-10-17). *Which deployment mechanism was used is not
   recorded in the repo — secrets and deployment live in the Supabase
   Dashboard, outside version control.*

### Stage E — The Supabase ↔ Firebase connection (clarification)

There is **no automatic Supabase–Firebase integration**. The connection is
three explicit HTTP hops, each authenticated differently:

1. Postgres → Edge Function: `net.http_post` with the Vault-derived shared
   secret (asynchronous, does not block the inserting transaction).
2. Edge Function → Google OAuth2: a service-account JWT (RS256) exchanged for
   an access token.
3. Edge Function → FCM HTTP v1: bearer-token message send per device token.

Roles are therefore cleanly separated: **Supabase** owns storage, workflows,
the trigger and server-side execution; **Firebase Cloud Messaging** is purely
the delivery service to Android devices; **the mobile app** is the receiver
and the owner of token registration against Supabase.

### Stage F — In-app integration (steps 15–19)

All paths below are in `apps/{driver,customer}/lib/services/push_notification_service.dart`:

- **Initialization** — `main()` calls
  `PushNotificationService.initializeFirebase()` immediately after Supabase
  init, and deliberately treats Firebase as optional at boot ("push registers
  after an active driver session"): a missing Supabase config still wins the
  config-error screen. A top-level background handler
  (`firebaseMessagingBackgroundHandler`) is registered with
  `@pragma('vm:entry-point')` so background data messages boot Firebase
  before the handler runs.
- **Session hookup** — when a session appears, `session_provider` creates the
  service (Riverpod provider) and calls `startForDriver(id)` /
  `startForCommuter(id)`; the profile screen re-runs the same call.
- **Permission** — permission is requested from inside the service: Android
  13+ runtime `POST_NOTIFICATIONS` through the local-notifications plugin and
  FCM's own `requestPermission` (alert/badge/sound). If permission is denied,
  the app continues — the token is still persisted, the user simply gets no
  banners.
- **Token acquisition & persistence** — `getToken()` → RPC
  `register_*_device_token`; on RPC failure a second attempt writes directly
  to the token table (RLS-guarded, add-only-own-row); if that also fails the
  error is logged and dropped (token persistence is never allowed to break
  login). `onTokenRefresh` re-runs the same persistence path automatically.
  On logout, `stop()` deletes the token row (owner-only RLS) and unsubscribes
  realtime channels.
- **Foreground reception** — because the Edge Function always includes a
  `notification` block, Android suppresses the system banner while the app is
  foregrounded; the app compensates through `onMessage`, which builds a local
  heads-up notification on the `pasakay_*_alerts` channel (importance max,
  sound, vibration, 4-second duplicate debounce). There is a **second,
  independent display source**: the app also subscribes via Supabase
  Realtime to `notifications` inserts and raises the same local heads-up —
  so a push that FCM drops still surfaces while the app is open.
- **Tap → deep link** — `onMessageOpenedApp`, `getInitialMessage` (app fully
  closed) and the local-notification payload all funnel through
  `NotificationEventType.routeFor(eventType, data, isDriverApp)` and then
  `onOpenRoute` → `go_router` navigation to the relevant screen (unit tests
  cover the route mapping).

**Deliberately missing steps (honest gaps):** no iOS support (no APNs key,
no `GoogleService-Info.plist`), and the background message handler
re-initializes Firebase but does **not** persist tokens from the background
isolate — app kills/reinstalls are eventually covered by `getToken` refresh,
not instantly.

## D. Runtime Notification Flow

This is the second diagram (`…-runtime.mmd`), i.e. what happens when the
system is already built and a user does something that produces a
notification. One full pass:

1. A workflow event (ride request created, booking accepted/completed, new
   review, schedule day starting via cron) calls a server function that
   inserts a row into `notifications` — but only after consulting the
   recipient's category preferences and the dedupe key, which prevents
   repeated reminder spam.
2. The row insert fires `trg_notifications_dispatch_push`, which reads the
   shared secret from Vault (skip + warning if missing) and fires an
   async pg_net POST at the right Edge Function URL.
3. The Edge Function authenticates the call, normalizes the payload, loads
   the row if needed, and looks up the recipient's live device tokens.
4. For each token it obtains a fresh Google access token by exchanging the
   service-account JWT, then calls FCM HTTP v1. An FCM 200 is reused as a
   per-token success; failed tokens are reported, and stale tokens
   (`UNREGISTERED`/`INVALID_ARGUMENT`) are deleted.
5. The device receives the message. In the background Android shows the
   banner from the `notification` block directly; in the foreground the app
   converts the message (or an equivalent Realtime row insert) into a local
   heads-up notification, debounced.
6. Tapping any banner routes the user to the relevant screen via the
   event-type mapping table, in both apps.

**Key distinction for the defense:** the repository fully proves steps 1–4 by
code, and proves the functions are deployed (401 behavior). Steps 5–6 depend
on FCM and Google Play services and can be observed only on a physical
device — the repository contains the *procedure* for that test
(`notify_driver` SQL smoke test and the curl call), but no recorded result.
"Therefore the pipeline is implemented and wired; device-level delivery is
the documented, repeatable manual test."

## E. Testing and Verification

| What | Method | Observed result | Status |
|---|---|---|---|
| Client routing + dedupe logic | Unit tests (`notification_event_type_test.dart` driver 5, customer 2) | all passing in the last runs (driver 10/10, customer 9/9, admin 8/8, 2026-10-17) | Verified |
| Firebase packages compile into the app | `flutter build apk` debug builds (both apps) | builds succeed from a clean tree, Firebase packages resolved | Verified |
| Functions deployed + auth enforced | `curl` POST without Authorization header (today) | both functions answered **401** | Verified |
| Token RPC access control | earlier live-DB smoke session (RPC exists, rejects unauthenticated) | document in repo session notes | Verified (prior session) |
| Fresh live-catalog re-check (pg_net, trigger, Vault secret, RPCs) | read-only introspection | **could not be re-run this session — the DB password has since been rotated** (expected user action); relies on the earlier introspection snapshot | Blocked |
| Vault secret presence by name / dashboard secrets | documentation-based | cannot be observed (values and even existence are outside the repo) | Unverified |
| FCM sends accepted (`sent ≥ 1`) | README manual test send (`notify_driver` SQL / curl) | procedure documented; **no recorded execution result in the repo** | Unverified |
| Banner actually displayed on device | physical-device test | repository cannot prove this; the FCM responses logging even at `sent:1` is server-level proof only (see §F note) | Unverified |
| Background/terminated banner tap routing | physical-device test | code path exists + unit tests for mapping; end-to-end not exercised in repo | Unverified |

## F. Limitations and Missing Evidence

1. **Device-level delivery is the main untested claim.** `sent: 1` means
   *FCM accepted the message*, not that the user saw it. The distinction is
   maintained everywhere in this document set.
2. **Secrets and deployment method are unrecorded by design.** Service
   accounts, the shared secret, the deployment mechanism and notification
   settings for push live outside version control. There is no CLI config
   (`config.toml`) — deployment could have been dashboard or CLI; nothing in
   the repo settles it.
3. **Live-recheck blocked by password rotation.** Earlier sessions verified
   the schema, trigger, RPCs and cron jobs against the live database; the
   database password has since been changed (as the team was advised), so
   this session could not repeat the introspection. The claims above rest on
   the earlier verified snapshot plus migration files.
4. **iOS is not implemented** (documented in the README and by absence of
   `GoogleService-Info.plist`); the `apns: {}` block in the FCM payload has
   no working target today.
5. **Documentation-vs-code discrepancy:** the driver README still says
   "Customer app: Not wired yet". The code shows the passenger path is fully
   implemented (own Firebase project `pasakay-passenger`, dedicated token
   table + RPC + dedicated Edge Function). Treat the code as authoritative.
6. **No retry mechanism.** If FCM is down or the Edge Function 500s
   (e.g. missing service-account secret at that moment), the push is lost;
   the in-app notification row and Realtime channel remain the sources of
   truth. Edge Function failures are not retried or queued anywhere in the
   repo.
7. **No test-coverage of the token RPCs' authorization behavior** or of the
   trigger: correctness is argued from code (SECURITY DEFINER +
   `auth.uid()` + status check) rather than exercised by automated tests.
8. **Background isolate minimalism:** the background handler only
   bootstraps Firebase; it does not refresh tokens while the process is
   dead — acceptable for this scope but worth stating if asked "what
   happened on device kill?".

Nothing in the app source or database migrations was modified while
producing this document set.
