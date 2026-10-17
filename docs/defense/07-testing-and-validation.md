# 7 · Testing and Validation

This chapter reports exactly what test code exists in the repository, which
tests were actually executed by the developer, and what that does (and does
not) establish. **No test results were invented.** Where no evidence exists,
that is stated.

## 7.1 What exists in the repository

Seven test source files, all runnable with plain `flutter test` (no extra
plugins declared):

| App | File | Count | What it verifies |
|---|---|---|---|
| driver | `apps/driver/test/widget_test.dart` | 5 | PH-mobile normalization, dialable `tel:`/`sms:` URI construction (`ContactLauncher`), TODA plate validator (empty rejected, freeform accepted, whitespace-collapsed) |
| driver | `apps/driver/test/notification_event_type_test.dart` | 5 | deterministic per-day/shift dedupe keys, notification routing (deep-link target per event), explicit-route override, new-request and review deep links |
| customer | `apps/customer/test/widget_test.dart` | 2 | phone → commuter auth-email mapping; plain-email login identity |
| customer | `apps/customer/test/history_screen_test.dart` | 5 | widget tests: bookings render after load, cancel-during-load safety (dispose mid-load), error state on failure, empty state, auto-open review for completed booking |
| customer | `apps/customer/test/notification_event_type_test.dart` | 2 | followed-driver availability routing, dedupe-key composition |
| admin | `apps/admin/test/widget_test.dart` | 8 | driver form validation (name/TODA + plate required, PH contact format, password length on create, terminal + shift must be chosen), payload parsing for nested shift/terminal, status-label mapping stays within the allowed actions, audit log parsing (accepts both role id keys, label coverage for known actions) |

**27 test cases total** (5 + 5 + 2 + 5 + 2 + 8).

No integration test suite, no end-to-end suite and no screenshot/golden
tests exist in the repository. There are no CI jobs that run tests — the
GitHub Action only builds and deploys the admin web app.

## 7.2 What was actually executed (developer-run, session of 2026-10-17)

Executed locally with the Flutter toolchain (stable, matching the
`environment.sdk` constraint) during the documentation/editing session:

| Command (per app) | Result |
|---|---|
| `cd apps/customer && flutter analyze` | 0 errors |
| `cd apps/customer && flutter test` | 9 / 9 passed |
| `cd apps/driver && flutter analyze` | 0 errors |
| `cd apps/driver && flutter test` | 10 / 10 passed |
| `cd apps/admin && flutter analyze` | 0 errors |
| `cd apps/admin && flutter test` | 8 / 8 passed |

These executions are documented in the development transcript; they were not
run through CI, so a fresh `flutter test` run reproduces them only if the
environment matches. There is no report artifact committed to the repo.

Manual verification performed and documented during the same session (not
automated anywhere):

- Fresh debug APKs built from a clean `main` tree for both mobile apps
  (build outputs are not committed).
- Live-database smoke checks (read-only) confirming the audit/commuter-activity
  RPCs exist and reject unauthenticated calls.
- GitHub Pages deployment observed green (admin console renders).

## 7.3 What the tests do and do not establish

**Established by the tests above:** input normalization (mobile, TODA plate,
dial URIs), notification routing/dedupe-key invariants, driver-form
validation rules, history-screen behaviors including failure and empty
states, audit-log row parsing. These are exactly the fiddly pure-logic pieces
of the client.

**Not established by these tests:**

- Server-side workflows (`create_ride_request`, `accept_ride_request`,
  `reconcile_ride_workflow`, RLS policies) are **not covered by any test
  script** in the repository.
- Push delivery end-to-end is untested in repo code (originates outside the
  repo: FCM projects + Edge Function secrets).
- The admin server functions' authorization behavior (`assert_system_admin`)
  has no automated test.
- Concurrency/soak behavior (many simultaneous requests to one driver) is
  unsubstantiated — the DB constraints *guarantee* single pending pair and
  ONE accept wins (accept_ride_request re-checks status inside the
  transaction), but there is no load test.

## 7.4 Manual verification already documented vs not performed

| Evidence level | Scope |
|---|---|
| Documented manual checks (this repo's development session) | clean APK builds, DB RPC existence/permission smoke test, Pages deploy, endpoints' read-only liveness |
| Documented but **not** exhaustive | ride flows exist live and RPC smoke checks ran, but individual real-device journey scenarios were ad hoc |
| Not performed (no evidence) | load/soak tests of the cron reconciliation against backlog data; behaviour of `process_schedule_notifications` with zero followers; comprehensive offline-device UX |

## 7.5 Validation rules that double as tests (non-executable)

The material layer that enforces most business rules is the **database schema
itself** (despite no test suite exercising it):

- unique partial indexes controlling one pending request per pair and one
  review per booking;
- CHECK constraints enumerating every status/domain value;
- RCS ownership policies;
- delete-guards implemented server-side.

These are constraints that would make the risky scenarios fail closed, but
adherence is a property of the schema rather than a verifiable test — a
"what if two taps race" answer must cite the constraints and their
transaction semantics, not a test result.
