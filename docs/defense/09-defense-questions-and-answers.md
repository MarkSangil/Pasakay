# 9 · Defense Questions and Answers

Answers are grounded in this repository as of commit `0df2a87`. Where the
honest answer is "we don't have evidence for that", the answer says so —
saying so is expected in a defense.

## A. Project purpose and scope

**Q1. Why build another "hailing" app if there are already ridesharing apps?**
A: This is not a ridesharing product. It digitizes an *association's own*
driver roster at barangay-terminal level for contact-first communication.
There is no fare engine, no dispatch, no payment — the in-app Terms exclude
them. Panels often probe for scope creep; the answer demonstrates the Terms
and the code agree (no `location` permission in either app manifest).

**Q2. Who exactly is a "user" of the admin console, and why is it a web app?**
A: One research-team administrator. It's web (Flutter web on GitHub Pages)
because the admin manages from a laptop with better searching/editing than a
phone form — and the same Supabase project is reused, so no extra backend.

**Q3. What does "SSLTODA" mean and why does verification matter here?**
A: Special Local Tricycle Operators and Drivers' Association. TODA plate
verification is the manual act of checking a driver's plate/registration
against the association's roster. It's a research-prototype control: the
"No LTFRB/government lookup" limitation is documented in the first migration
file itself.

## B. System architecture

**Q4. Where does the "server logic" live — is there a backend server?**
A: There is no self-managed server. Business logic in SECURITY DEFINER
PostgreSQL functions (94 of them) inside Supabase; the two scheduled jobs run
under `pg_cron`; push is dispatched from a database trigger through `pg_net`
to two Deno Edge Functions. All verifiable in
`apps/admin/supabase/migrations/`.

**Q5. Why is the state of a trip not computed inside Flutter?**
A: Because the state machine must be authoritative and race-safe. Both apps
are installed on consumer devices; if any screen computed acceptance
locally, two simultaneous "accept" clicks could corrupt state. The database
function `accept_ride_request` re-checks status inside the transaction, so
exactly one of two racing accepters wins; the other gets a clear error.

**Q6. What if a passenger loses internet while waiting for a request?**
A: The request stays server-side (row in `ride_requests` with `expires_at`).
If the driver accepts, the push may be missed — but on reconnect the waiting
screen's realtime subscription re-syncs, and the History list (which calls
`reconcile_ride_workflow`) reflects the truth. Push delivery is best-effort
(limitation documented in `08-limitations-and-scope.md`).

## C. Database design and relationships

**Q7. Why no foreign key on `user_audit_logs.user_id`?**
A: Deliberate. Audit rows must survive account deletion, and `user_id` may
point into *either* `drivers` or `commuters` (polymorphic via `user_role`
column). Enforcing one FK target would break the mirror design; the check
constraint restricts the role text and the client never writes the ids
(server resolves them from `auth.uid()`).

**Q8. Why does `bookings.request_id` have a UNIQUE constraint (1:1)?**
A: The booking is the *materialized acceptance* of one request. One request
can only produce one trip, so the FK is unique — it makes double-booking
impossible at schema level, not just in code.

**Q9. Explain composite keys in this project.**
A: `commuter_followed_drivers` uses `(commuter_id, driver_id)` as the PK — a
follow is the pair. This prevents duplicate follows and gives a natural
index for "all followers of driver X".

**Q10. What stops one commuter from spam-creating requests?**
A: Three layers: (1) `ride_requests_one_pending_per_pair` partial unique
index (only one PENDING request to a given driver at a time); (2) the
cooldown key from `admin_set_booking_settings`
(`p_request_cooldown_minutes`) enforced inside `create_ride_request`;
(3) RLS keeps only your own rows visible.

## D. Authentication and security

**Q11. Users log in with a mobile number — how is that stored in an
email-based auth system?**
A: Supabase Auth signs in with an email+password pair. The registration
function provisions the auth user with a deterministic identity
(`normalized-phone@<role-domain>`) and stores `role` metadata. At login the
app resolves the phone to that email via `resolve_auth_email` before calling
`signInWithPassword`. Files: `auth_service.dart` (both apps),
`apps/customer/test/widget_test.dart` ("phone maps to commuter auth email").

**Q12. How is unauthorized access prevented?**
A: Per row, at the database: 43 RLS policies (owner-only for almost all
tables; admin checks via `is_system_admin()`; peer checks on bookings and
requests). Admin functions call `assert_system_admin()` internally. The
admin web key is the same anon key as the apps, so a public console cannot
read anything without a signed-in admin.

**Q13. Passwords — where are they stored?**
A: Only inside Supabase Auth, hashed by the platform. Our tests only pass
plaintext at the sign-in call; profile tables contain no credential columns
(you can confirm in `database-erd.dbml`: `drivers` and `commuters` have no
password field). Admin password reset uses dedicated functions
(`admin_reset_*_password`).

**Q14. What about the audit log — isn't that surveillance?**
A: It's disclosed in the in-app Privacy Policy ("Records of in-app actions…
"), covers screens + a fixed set of key actions only, stores ids and labels
(never message bodies or location), and is scoped to the research
evaluation, with a documented retention/withdrawal path
(`privacy_requests`). Opt-out is not offered (limitation honestly
documented).

## E. Workflows and business logic

**Q15. Walk me through what happens after a driver taps Accept.**
A: The app calls `accept_ride_request(p_request_id)`; the function (SECURITY
DEFINER) re-authenticates the driver, checks the request is still PENDING
and unexpired, updates the request to ACCEPTED, inserts the `bookings` row
(BOOKED) with `review_eligible_at`, and journals a booking event. Failures:
"Request is no longer pending", "This request has expired", or a permission
error — all surfaced to the UI (`driver_repository.dart` L140-147).

**Q16. What happens if the driver never responds?**
A: The cron job `pasakay-reconcile-ride-workflow` (every minute) expires it:
`reconcile_ride_workflow()` sets `EXPIRED` on pending requests whose
`expires_at` passed. The commuter's waiting screen also shows the countdown,
and calling `reconcile_ride_workflow` on read keeps stale rows out of view.

**Q17. How does a booking age into a review?**
A: The same reconciliation: `review_eligible_at` = confirmed time + settings
delay. A COMPLETED booking exposes a review row only after that timestamp
(`submit_booking_review` raises otherwise); the daily auto-complete path
marks overdue COMPLETED-not-reviewed bookings through that same clock — see
the `bookings_review_due_idx` partial index used for that "review due" query.

**Q18. If the commuter reports "not delivered but marked COMPLETED", what
happens?**
A: `report_driver_booking` (available within the passenger-report window)
records the passenger name + details; a driver dispute uses `flag_booking`
within the admin-configured window and flips the booking to FLAGGED; the
admin sees it in `/disputed-bookings` with the event journal and resolves
with `admin_resolve_disputed_booking` (complete or cancel).

## F. Technology choices

**Q19. Why Flutter and why three separate apps instead of one?**
A: Flutter gives one codebase for both Android apps plus the admin web build.
They are separate apps because their users, navigation and permissions
differ (driver sees bookings; commuter sees terminals; admin is a console).
The repo shows this folder split (`apps/{driver,customer,admin}`) and the
`environment` blocks are identical (Dart ^3.13.2).

**Q20. Why store business rules in the database rather than Dart?**
A: Because the rules must hold regardless of which client talks to the
database: the same tables are updated by two mobile apps, a web console and
server-side cron. Centralizing in SQL functions means there is exactly one
place a rule can be violated and one place the error text lives.

**Q21. Why is Firebase in the project if everything else is Supabase?**
A: Firebase is used only for Cloud Messaging (device push), the standard
user-facing Android push path. The two roles deliberately live on separate
Firebase projects (`pasakay-passenger` documented in
`apps/customer/README.md`) to keep token scope isolated.

## G. Testing and validation

**Q22. What evidence shows the app actually works?**
A: Three layers we can honestly cite: (1) 27 automated tests across the three
apps, all passing in the last documented run (see
`07-testing-and-validation.md`); (2) the schema's own constraints acting as
guards for race conditions; (3) manual smoke testing on real devices and the
live database during development. We do not have an automated end-to-end
suite or CI jobs for tests — that is a stated gap.

**Q23. What is NOT tested automatically that you wish were?**
A: The ride-state machine's database functions and the RLS policies (the
most security-critical parts). The trade-off we took was schema-level
constraints (unique partial indexes, checks) as runtime guards; a
next-step improvement is `pgTAP`-style database tests.

## H. Limitations and future improvements

**Q24. What are the system's main limitations?**
A: Summarized in `08-limitations-and-scope.md`: no offline mode; commuter
cannot cancel a pending request; the admin Privacy and Diagnostics screens
exist as files but aren't routed; push delivery depends on FCM; the audit
log can be skipped by a hostile client (it is evidence, not a security wall);
registration requires admin internet access for every new account.

**Q25. How would the system handle more users?**
A: Traffic today is research-scale. Scaling levers already present:
Postgres indexes for list queries (38 non-constraint indexes, reviewed),
read-time staleness instead of background sweeps for activity, and
reconciliation batch functions. Honest unknowns: Edge Function cold starts
per push and Postgres connection limits under many Realtime channels —
neither has been load-tested (documented as unverified).

**Q26. What would you add next (and why didn't you)?**
A: (1) Route the admin Privacy and Diagnostics screens (code exists);
(2) commuter "cancel pending request" before accepting; (3) automated
database tests. Each was deferred to keep the approved scope freeze and
avoid behavior changes during research deployment.

**Q27. What happens if Supabase is down?**
A: Sign-in fails with a friendly error; already-signed-in users see empty
or stale data with the previous or an error snapshot (repos wrap failures;
`SessionController` never silently fakes a session). Nothing critical writes
to the device except recent contacts and FCM tokens (customer app keeps
recent contacts in shared preferences locally).

**Q28. A reviewer sees two processes accepting the same request — who
wins?**
A: Exactly one wins; the loser gets "Request is no longer pending" because
`accept_ride_request` re-validates inside the transaction (row-locked
update). Both sides' UIs then re-sync through Realtime. This is a
transactional guarantee, not luck.
