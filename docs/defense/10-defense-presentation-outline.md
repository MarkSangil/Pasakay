# 10 · Defense Presentation Outline

Suggested flow for a 15–20-minute defense: about 16 slides. Slide bodies stay
short; the "speaker notes" carry the substance. Diagrams noted below already
exist in this repo and render in Mermaid Live Editor or dbdiagram.io.

| # | Slide title | Main points | Visual | Speaker notes | Source |
|---|---|---|---|---|---|
| 1 | Title | PASAKAY — SSLTODA driver directory + ride contact, La Salle College Antipolo, Grade 12 STEM | System logo + apps side-by-side | One sentence: "We turned a paper tricycle roster into a working directory with contact actions and evaluation data." | `docs/defense/01` |
| 2 | The problem | New drivers shift across 5 terminals; commuters can't reach the right driver; research needs usage data | before/after sketch | Explain barangay context; state the two goals: communication aid + research data | `01-project-overview.md`, `admin/supabase/migrations/20260911000000` comment header |
| 3 | Scope and boundaries | What it IS: directory, contact, ride request, reviews. What it is NOT: no GPS, no payment, no booking engine | three red "X" chips + three green chips | Repeat the Terms line; this is a plan we kept, verified in code (no location permission) | `lib/core/utils/legal_content.dart` (terms), `docs/system-analysis/database/schema.dbml` |
| 4 | Three applications, one backend | Driver APK, Customer APK, Admin web on GitHub Pages | `02` diagram | Emphasize one Supabase project; no custom server | `docs/defense/02-system-architecture.md` |
| 5 | Architecture in one diagram | UI → repositories → Supabase DB (RLS + functions); cron; Edge Functions; FCM | the mermaid `02` diagram verbatim | Walk one arrow slowly (commuter tap → DB write → trigger → FCM push) | `02-system-architecture.md` |
| 6 | Where the rules live | 26 tables, 94 functions, 43 RLS policies, 2 cron jobs | counts Mosaic | "The database refuses what the app shouldn't do"; examples: pending-pair index, accept race, admin gate | `03-database-design.md`, `../system-analysis/database/database-implementation.md` |
| 7 | Data model tour | roster (terminals/shifts/profiles) → ride chain (requests→bookings→events→reviews) → support (tokens/notifications/audit) | `docs/defense/database-erd.dbml` screenshot | Show the 1:1 bookings↔requests link (unique FK), follow-table composite PK | `03-database-design.md` |
| 8 | Workflow: getting contact info | terminal tap → driver list → profile → Call/SMS taps passthrough | end-to-end excerpt or phone screenshot | Point out audit logging ("call_driver") happens without capturing conversations | `04-application-workflows.md` §4, `contact_launcher.dart` |
| 9 | Workflow: ride request lifecycle | create → accept/reject/expiry → booking → complete/flag → review | `core-workflows.mmd` excerpt | Mention the every-minute reconciliation cron — "the system polices itself" | `20260915130000_ride_request_booking_flow.sql`, `docs/system-analysis/flowcharts/core-workflows.mmd` |
| 10 | Failure paths the panel will ask about | expired request, cooldown, race accept, offline | one-node "errors we show" | Quote actual error strings ("Driver is outside their scheduled operating period") | `04-application-workflows.md`, Q15-Q16, Q28 |
| 11 | Keeping accounts safe | registration validation, admin approval, password hashing by Supabase, RLS per row, admin re-checks | auth flow excerpt of `authentication.mmd` | Do a live claim: pending account cannot log in (get_login_status gate + DB status) | `04` §4.2, `20260915210000` migration |
| 12 | Notifications both ways | in-app rows + FCM pushes + preference settings + dedupe | push screenshot | Two Firebase projects (driver/passenger); retries are best-effort (honest) | `04` §4.5, `apps/customer/README.md` |
| 13 | Research instrumentation | activity sessions/heartbeats + action audit log + admin activity columns | `activity-audit.mmd` | Describe read-time staleness (no sweeper) and 5-minute admin sweep | `driver_activity_tracker.dart`, `user_audit_trail.dart` |
| 14 | Testing evidence | 27 automated tests (list of the 6 files), all passing; analyzer 0 errors; manual DB smoke tests | counts table | Honest gaps: no e2e/CI test jobs, no DB test suite — stated, not hidden | `07-testing-and-validation.md` |
| 15 | Limitations we own | unrouted admin Privacy/Diagnostics screens; no commuter cancel; FCM dependency; offline = error states | limitation table truncated to 5 rows | Frame as "documented, not hidden", cite the status table | `08-limitations-and-scope.md` |
| 16 | Conclusion + roadmap | research goals met within scope; next: route admin privacy screens, commuter cancel, DB tests | one line each | Invite questions; key backup slides: SLIDE 5 diagram, ERD, error-string deck | `01`, `08`, Q24–Q26 |

## Backup-slides worth having on hand

- Full architecture diagram (`02-system-architecture.md`).
- DBML ERD open in dbdiagram.io (`docs/defense/database-erd.dbml`).
- Error-string list from the migration files (concrete proof the rules live
  server-side).
- The `08-limitations-and-scope.md` table (in full).

## Head-off THESE questions with prepared evidence

| Likely question | Where the answer lives |
|---|---|
| "Show me where the cancel rule is." | `ride_requests_status_check` check constraint; absence of a client cancel RPC; Q8/Q24 |
| "What if two drivers/two users race?" | Q28, `accept_ride_request` re-check in transaction |
| "Where are passwords stored?" | Q13, ERD has no password columns |
| "How do you know the app hasn't been modified maliciously?" | Q12, Q14 + RLS + admin gate — be candid that audit is evidence, not a wall |
| "What research data did you collect?" | Be specific and honest: audit rows + activity sessions only; no effectiveness studies have been performed — do NOT claim outcomes |
