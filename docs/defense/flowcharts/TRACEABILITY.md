# FCM Implementation Flowchart — Traceability

Evidence for every significant step in
`supabase-firebase-fcm-implementation.mmd` and
`supabase-firebase-fcm-runtime.mmd`. Line anchors valid for commit `2dd47b5`.

Statuses: **Verified** — inspected in source/config/catalog or directly
probed; **Inferred** — indirect evidence; **Unverified** — cannot be
established from available evidence. **No credential values, tokens, or
service-account material appear anywhere in these documents.**

| # | Step / claim | Source | Anchor | Status |
|---|---|---|---|---|
| 1 | Firebase deps in both apps | `apps/{driver,customer}/pubspec.yaml` | `firebase_core ^4.0.0`, `firebase_messaging ^16.0.0`, `flutter_local_notifications ^19.0.0` | Verified |
| 2 | google-services Gradle plugin applied | `apps/driver/android/app/build.gradle.kts` L7 (customer equivalent) | `id("com.google.gms.google-services")` with comment "requires android/app/google-services.json" | Verified |
| 3 | minSdk 23 enforced for FCM | same file L24-25 | `minSdk = maxOf(23, flutter.minSdkVersion)` + comment | Verified |
| 4 | Permissions declared | `apps/{driver,customer}/android/app/src/main/AndroidManifest.xml` L2-3 | `INTERNET`, `POST_NOTIFICATIONS` | Verified |
| 5 | Default channel + icon meta-data | `AndroidManifest.xml` L30-35 | `com.google.firebase.messaging.default_notification_channel_id`, `default_notification_icon`, values `pasakay_*_alerts`, `ic_stat_pasakay` | Verified |
| 6 | Channel icon drawable exists | `apps/{driver,customer}/android/app/src/main/res/drawable/ic_stat_pasakay.xml` | file present | Verified |
| 7 | Two separate Firebase projects | `apps/{driver,customer}/android/app/google-services.json` | driver `project_id: pasakay-9c97c` package `com.pasakay.pasakay_driver`; customer `project_id: pasakay-passenger` package `com.pasakay.pasakay_customer` (ids read from config; no key values documented) | Verified |
| 8 | Package names match applicationId | `build.gradle.kts` vs `google-services.json` | identical strings per app | Verified |
| 9 | Firebase console was used to create projects/configs | consequences of `google-services.json` existing | — | Inferred |
| 10 | Token tables with cascade FK, RLS, platform check | `20260915010000_driver_device_tokens.sql` L2-40; `20260915020000_commuter_device_tokens.sql` L1-14+ | `device_tokens` / `commuter_device_tokens`, `*_select_own/insert_own/delete_own` policies | Verified |
| 11 | Token uniqueness + claim flow | `20260915270000_driver_device_token_claim.sql` L2-14; `20260915280000…` L5 | `device_tokens_token_uidx` unique on `token`; update policy `using (true) with check (driver_id = auth.uid())` | Verified |
| 12 | Registration RPCs are SECURITY DEFINER from auth.uid() + eligibility | `20260915270000…` L17-55 | `register_driver_device_token` raises 'Not authenticated' / 'Driver session is not eligible for push tokens'; upsert `on conflict (token)`; commuter mirror L15-54 | Verified |
| 13 | Client persists token via RPC with direct-upsert fallback then log-only | `apps/driver/lib/services/push_notification_service.dart` L281-306; `apps/driver/lib/services/driver_repository.dart` L319-347 | `registerDeviceToken` rpc; `upsertDeviceToken` direct table write; catch chain | Verified |
| 14 | Notification sources all through `notifications` INSERT | `20260915100000_schedule_notifications_part1.sql` L209 (`emit_notification`), `20260915010000…` L42-78 (`notify_driver`) | insert-only push contract | Verified |
| 15 | Per-user preference gates and dedupe | `emit_notification` body; `driver/commuter_notification_preferences` tables | live catalog (earlier session) | Verified |
| 16 | Vault secret bootstrap + skip-if-missing | `20260915120000_notification_push_pg_net_trigger.sql` L1-36 | `vault.decrypted_secrets` read; `raise warning … push skipped` | Verified |
| 17 | pg_net dispatch trigger | same file L8, L38-61, L71-75 | `create extension pg_net`, `net.http_post` 5000 ms, `trg_notifications_dispatch_push AFTER INSERT FOR EACH ROW` | Verified |
| 18 | Function URL chosen by recipient_type | same file L38-42 | driver → `…/functions/v1/send-driver-push`, else passenger | Verified |
| 19 | Trigger failure never blocks the insert | same file L64-68 | `exception when others` → warning → `return new` | Verified |
| 20 | Edge Function auth: service-role OR shared secret; else 401 | `send-driver-push/index.ts` L49-57; mirror L42-50 | Bearer comparisons; 401/405/400/500 branches L45-87 | Verified |
| 21 | Service-account JSON required, else 500 | `send-driver-push/index.ts` L62-75 | `FIREBASE_SERVICE_ACCOUNT_JSON` / `FIREBASE_PASSENGER_SERVICE_ACCOUNT_JSON` reads L62, L55 | Verified |
| 22 | Payload normalization + optional row lookup | same L82-128 | webhook `record.*` shape; `notifications` read via service-role client L108-128 | Verified |
| 23 | Recipient-type cross-filter | driver L104-106; passenger L96-98 | `{ok: true, skipped: "not a driver/passenger notification"}` | Verified |
| 24 | No tokens → ok, sent 0 | driver L140-142; passenger L132-134 | `reason: "no device tokens"` | Verified |
| 25 | FCM HTTP v1 + OAuth JWT (no legacy server key, no Admin SDK) | driver L193-232, L242-279; passenger L184-275 | RS256 JWT → `oauth2.googleapis.com/token` (scope `firebase.messaging`); POST `fcm.googleapis.com/v1/projects/{id}/messages:send` with `notification`, `data`, android priority HIGH, `channel_id`, APNs block | Verified |
| 26 | Stale-token self-cleanup | driver L165-175 | UNREGISTERED / INVALID_ARGUMENT → token row deleted | Verified |
| 27 | Functions deployed and auth-enforced | live probe 2026-10-17 | both function URLs answer HTTP 401 with no Authorization header | Verified |
| 28 | Deployment method (CLI vs dashboard) | absence of `config.toml`, CLI scripts, deploy docs | — | Unverified |
| 29 | Dashboard secrets actually set | `apps/driver/README.md` L73-84 instructs; runtime would 500 if absent | — | Unverified |
| 30 | Firebase init at app start, optional at boot | `apps/driver/lib/main.dart` L21-24; customer mirror L19-22; `push_notification_service.dart` L51-74 (init + background handler L56-59; warning-tolerant fallback L63-73) | comment "Firebase is optional at boot — push registers after an active driver session" | Verified |
| 31 | Background handler registered early | `push_notification_service.dart` L13-16, L56-59 | `@pragma('vm:entry-point')`, `FirebaseMessaging.onBackgroundMessage`, re-init only | Verified |
| 32 | Session hookup | `apps/driver/lib/core/providers/session_provider.dart` L23, L224 (`startForDriver`); customer L20, L189 (`startForCommuter`); re-register from profile screen L274 / L180 | provider wiring | Verified |
| 33 | Permission request (runtime + FCM) | `push_notification_service.dart` L106-134 | Android 13 `requestNotificationsPermission` + FCM `requestPermission`; denied → continue path L155-157 | Verified |
| 34 | Foreground display strategy | same L149-153 + L203-221 (`onMessage` → local heads-up), L318-403 (`_showHeadsUp`: debounce L326-333, channel import max L380-390) | push payload includes notification block; app raises local notification in foreground | Verified |
| 35 | Dual display source: Realtime INSERT also raises heads-up | same L259-279 (`subscribeNotifications`) | insert event → `_showHeadsUp` | Verified |
| 36 | Token refresh re-persist | same L202 (`onTokenRefresh` → `_persistToken`) | — | Verified |
| 37 | Logout cleanup: unsubscribe + delete token | same L167-184 | `stop()`, `deleteDeviceToken` | Verified |
| 38 | Tap routes (push + local + initial) | same L163-164 (`getInitialMessage`), L221 (`onMessageOpenedApp`), L346-351 (local tap payload), L308-316 (`_handleOpen` → `NotificationEventType.routeFor` → `onOpenRoute`); router wiring `main.dart` L50-52 | deep-link routing | Verified |
| 39 | Route mapping unit-tested | `apps/driver/test/notification_event_type_test.dart` (5 tests), `apps/customer/…/notification_event_type_test.dart` (2) | schedule/request/review route tests — all passing | Verified |
| 40 | Build evidence: Firebase packages compiled | session `flutter build apk` outputs; iOS SourcePackages contain `firebase_messaging-16.7.0` | analyzer 0 errors both apps | Verified |
| 41 | Test suite totals | 2026-10-17 run | driver 10/10, customer 9/9, admin 8/8; no push-delivery tests exist anywhere | Verified |
| 42 | Prior live-DB verification of trigger/RPC existence | earlier session introspection (read-only catalog) | `trg_notifications_dispatch_push`, `register_*_device_token`, pg_net, cron jobs | Verified (prior session) |
| 43 | Fresh live re-check this session | attempted read-only introspection 2026-10-17 | connection refused: password authentication failed (DB password rotated by team — recommended act) | Blocked |
| 44 | End-to-end device delivery (banner seen) | repository contains procedure only: `apps/driver/README.md` L87-105 (`notify_driver` SQL + curl) | no recorded execution result anywhere in repo | Unverified |
| 45 | iOS support | absent `GoogleService-Info.plist`; README L107-108 "Not configured yet (needs Apple Developer APNs key…)" | — | Verified (not implemented) |
| 46 | Stale doc: "Customer app: Not wired yet" | `apps/driver/README.md` L110-111 vs customer push service + passenger tokens + Edge Function + own Firebase project | code contradicts the doc | Verified (documentation discrepancy) |
| 47 | No retry/queue for failed pushes | both `index.ts`: fire-and-forget list of results; `notes` in `fcm-implementation-methodology.md` §F.6 | in-app row + Realtime remain the source of truth | Verified (as limitation) |
| 48 | `process_schedule_notifications` cron exists | `20260915110000_schedule_notifications_processor.sql` + live cron catalog (2 jobs every minute) | schedule-driven notifications path | Verified |
| 49 | Flowcharts render | mermaid-cli headless run 2026-10-17 | both `.mmd` files → SVG, 0 errors; same syntax class renders in mermaid.live | Verified |

## Definitions recap

- *Verified* = provable by reading the cited file, by a catalog query in a
  previous session, or by a direct non-destructive probe (HTTP status of the
  public function URL).
- *Inferred* = the only plausible way the artifact could exist (e.g. the
  Firebase console created the config files).
- *Unverified* = genuinely open; listed in the methodology's §F so that no
  defense claim overreaches.
