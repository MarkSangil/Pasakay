# 6 · Technology Stack

Every entry below is verified in `pubspec.yaml` / migration files / workflow
configuration — the "where" column names the actual usage in this repo. Where
no design rationale exists in the repository or project documentation, the
entry states its *technical purpose* without inventing a selection story.

## 6.1 Applications

| Technology | Version (constraint) | Used in | Technical purpose | Depends on it |
|---|---|---|---|---|
| Flutter framework + Dart | SDK ^3.13.2 | all three apps | one shared framework for both Android targets and the admin web build | everything client-side |
| `flutter_riverpod` | ^3.4.3 | all three | app state (session, trackers, repositories are injected providers) | every screen and service |
| `go_router` | ^18.0.1 | all three | declarative navigation plus deep-link routes from notifications | router providers (`app_router.dart`) |
| `supabase_flutter` | ^2.17.2 | all three | Supabase client: auth, PostgREST, realtime channels | the entire backend contract |
| `flutter_dotenv` | ^6.0.1 | all three | loads `.env` (URL/anon key) at startup | `SupabaseConfig.initialize` |
| `google_fonts` | ^8.2.1 | all three | app typography | UI theme |
| `intl` / `timeago` | ^0.20.3 / ^3.7.1 | mobiles | dates, relative times | booking cards, activity lists |
| `url_launcher` | ^6.3.2 | mobiles | opens dialer/SMS apps | contact feature |
| `shared_preferences` | ^2.5.5 | customers | the on-device recent-contact list (privacy choice: stays on the device) | customer `loadRecent` |
| `firebase_core` ^4 / `firebase_messaging` ^16 / `flutter_local_notifications` ^19 | | mobiles | FCM token registration + foreground push + local notifications | push notifications |
| `cupertino_icons` | | all | iconography | UI |

## 6.2 Backend services (Supabase project)

| Capability | Object(s) that use it | Notes |
|---|---|---|
| Supabase Auth | sign-in/signup, `handle_pasakay_auth_user` trigger | password provider only |
| PostgreSQL + Row Level Security | 26 public tables, 43 policies | access control can't be bypassed by the client |
| Database functions (SECURITY DEFINER) | 94 functions — registration, ride workflow, admin operations, activity/audit | the "server code" of this project |
| Triggers | 9 public + 1 auth-table | updated-at stamps, notification fan-out, rating aggregation |
| `pg_cron` | `pasakay-process-schedule-notifications`, `pasakay-reconcile-ride-workflow` (both `* * * * *`) | scheduled server-side work without any app running |
| `pg_net` | push dispatch | async HTTP from inside the database |
| Edge Functions (Deno) | `send-driver-push`, `send-passenger-push` | forwards FCM messages using service-account secrets set in the dashboard |
| Realtime (Postgres changes) | notifications, ride requests, bookings channels in both mobile apps | live updates without polling |

## 6.3 CI/CD and hosting

| Technology | Where | Purpose |
|---|---|---|
| GitHub Actions (`.github/workflows/deploy-admin.yml`) | admin app only | builds the Flutter web release on every push to `main` that touches `apps/admin/**`, injecting Supabase URL/anon key from repo secrets |
| GitHub Pages (`gh-pages` branch) | admin app | public hosting of the admin console at `https://marksangil.github.io/Pasakay/` |
| Debug APK (built locally with Flutter/Gradle) | mobiles | the driver and customer test builds; no store build pipeline exists |

## 6.4 Development tools (verified in repo)

- **Flutter SDK 3.13+ toolchain** (`flutter build apk --debug`, `flutter test`,
  `flutter analyze` — used during development; results in `07-testing-and-validation.md`).
- **flutter_lints ^6** — lint rules in every `analysis_options.yaml`.
- **Git monorepo layout** — `apps/{driver,customer,admin}` + `.github/` +
  `docs/`.

## 6.5 Not used (and therefore not claimed)

The system does **not** use: GPS/location libraries, external REST APIs
besides Supabase and FCM/Google-style endpoints, custom web servers, JWT
manual verification (Supabase Auth issues and refreshes tokens itself), or
any message routing engine — the Terms exclude GPS/booking dispatch, and the
`pubspec.yaml` files confirm no such dependency exists.
