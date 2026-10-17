# 3 · Database Design

The authoritative source for this chapter is the **live Supabase PostgreSQL**
database (read on 2026-10-17 through standard catalog views — read-only
queries only). The checked-in migrations (`apps/admin/supabase/migrations/`,
34 files) describe how each object got there. Nothing was applied to the
database while documenting it.

## How the database is organized

One project database, three relevant layers:

1. **`public` schema (ours)** — 26 tables, 4 enums, 94 functions, 9 triggers,
   43 RLS policies, and 2 scheduled jobs. This is every table described below.
2. **`auth` schema (Supabase)** — the login identity table `auth.users`. We
   never modify it; one trigger on it (`on_auth_user_created_pasakay` →
   `handle_pasakay_auth_user()`) creates the matching profile row and stamps
   the `role` metadata when a signup is confirmed.
3. **no views** — all list/report queries are functions returning JSON.

## The tables (26), grouped by purpose

### Core roster (who's who)

| Table | Purpose (one line) | Key columns | Primary key | Foreign keys (enforced) |
|---|---|---|---|---|
| `terminals` | the 5 physical tricycle terminals | `terminal_name` (unique) | `terminal_id` | — |
| `shifts` | the 3 operating shifts | `shift_start_time`, `shift_end_time`, `label`, unique pair of times | `shift_id` | — |
| `drivers` | one row per registered driver | `full_name`, `contact_number`, `plate_number` (NOT NULL), `toda_number`, `terminal_id`, `shift_id`, `current_terminal_id`, `username` (unique), `status` enum, `is_active`, `average_rating`, `review_count`, `license_verified` (legacy) | `driver_id` | → `terminals` (2 links), → `shifts`, → `auth.users` |
| `commuters` | one row per registered commuter | `full_name`, `contact_number`, `email_address`, `username` (unique), `status` enum, `status_reason` | `commuter_id` | → `auth.users` |
| `admins` | system admin accounts | `email` (unique), `username` (unique), `is_active` | `admin_id` | → `auth.users` |

The `auth.users` links are **identity bindings**: signup provisions both the
auth record and the profile row, and they stay in sync through the
`handle_pasakay_auth_user()` trigger. Deleting a profile row requires admin
action (the apps call admin-managed deletion, not direct deletes).

### Ride workflow (the central chain)

| Table | Purpose | Constraints that matter |
|---|---|---|
| `ride_requests` | commuter → driver request, one of `PENDING` / `ACCEPTED` / `REJECTED` / `EXPIRED` / `CANCELLED` | check on status; `expires_at` NOT NULL; partial unique index: **only one `PENDING` per (commuter, driver)** |
| `bookings` | created when a request is accepted; `BOOKED` → `COMPLETED` / `FLAGGED` / `CANCELLED` | `request_id` unique (1:1 with `ride_requests`); check on status; `review_eligible_at` NOT NULL (review window start) |
| `booking_events` | append-only journal of every workflow step (`REQUEST_CREATED`, `BOOKING_ACCEPTED`, `TRIP_COMPLETED`, …) with `details` JSONB | FKs to bookings/ride_requests are `ON DELETE SET NULL` so history survives record deletion |
| `reviews` | commuter's rating of a completed trip | rating `CHECK (rating BETWEEN 1 AND 5)`; partial unique index `reviews_one_per_booking` gives **one review per completed booking** |
| `review_reports` | a driver disputing/consumer flagging a review | status `OPEN/RESOLVED/DISMISSED`; partial unique index: one OPEN report per (review, driver) |

### Contact/notification

| Table | Purpose |
|---|---|
| `device_tokens` / `commuter_device_tokens` | FCM tokens per driver/commuter device (token unique per platform table) |
| `notifications` | in-app rows per `recipient_id` (+`recipient_type`: driver/commuter), with optional `dedupe_key` (unique where not null) to stop duplicate reminders |
| `notification_event_log` | server-side record of which notification events were sent (no client access) |
| `app_notification_settings` | global switches (e.g. push endpoint on/off) |
| `driver_notification_preferences` / `commuter_notification_preferences` | per-user category toggles (schedule reminders, followed-driver availability …) |
| `commuter_followed_drivers` | commuter ↔ driver "follows" (composite PK of both IDs) |

### Research/ops support

| Table | Purpose |
|---|---|
| `driver_shift_requests` | driver asks for a different shift; admin approves/rejects (status `pending/approved/rejected`, `admin_note`) |
| `driver_activity_sessions` / `driver_activity_heartbeats` | foreground usage: one row per app open, heartbeats every ~30 s |
| `commuter_activity_sessions` / `commuter_activity_heartbeats` | same mechanism for the passenger app |
| `user_audit_logs` | "which screens and actions were used": `user_id`, `user_role` (check: driver/commuter), `action` (check: ≤64 chars), `detail` JSONB, `occurred_at` — deliberately **no FK**, because it must keep logging users that are later deactivated |
| `device_logs` | technical device info report (optional crash logs) |
| `privacy_requests` | research-team Data-Privacy-Act workflow: subject, request type enum, status enum, retention decisions |

## Relationships, with a practical example

**Enforced foreign keys (36 total).** Example chain for a single trip:

```
commuters (Ana)  ←─  ride_requests  ─→  drivers (Juno)
                            │ 1:1 (unique FK)
                            ▼
                       bookings ──╮ 0:1 (nullable FK)
                                  ▼
                             reviews        (+ review_reports)
```

When Ana taps "Request ride", `create_ride_request(Ana, Juno)` validates that
they don't already have a pending pair (`ride_requests_one_pending_per_pair`)
and inserts a row whose `commuter_id` must exist in `commuters` and whose
`driver_id` must exist in `drivers` — the FKs guarantee no ghost rider.
When Juno accepts, `accept_ride_request` updates the same request and inserts
the matching `bookings` row (the unique FK makes it impossible to have two
bookings for one request). When the trip completes and Ana reviews, the
review row's `booking_id` points at that booking, and the
`refresh_driver_rating` trigger updates Juno's `average_rating` and
`review_count` in `drivers` — so the rating commuters see is always computed
from real rows, never hand-edited.

**Constraints the panel may ask about**

- `drivers_active_requires_license`: a driver cannot be set `active` without
  the verification flag — the admin really must verify.
- Deleting a terminal: enforced in the `admin_delete_terminal` function
  (it fails while drivers still reference it) — a delete-guarantee in code
  rather than a database `ON DELETE` rule.
- `commuter_followed_drivers` has a **composite primary key**
  (`commuter_id, driver_id`), which is how "follow" is prevented from being
  duplicated.

**Relationships that are *not* enforced** (documented, not drawn as FKs — the
`user_audit_logs`, `device_logs`, `notifications`, and
`notification_event_log` tables all have `user_id`-style columns but no foreign
keys, because they must survive account deletion and they key off a role
column, like `user_role`, which the apps supply):

## How the code reads/writes this database

- **Mobile apps** mostly use RPC functions for anything with rules (ride
  actions, registration) and direct **RLS-guarded table** queries for plain
  lists (drivers roster, their own bookings/history/notifications).
- **Admin app** is almost entirely RPC-based (28 `admin_*` functions), plus a
  handful of direct selects guarded by the `is_system_admin()` policy.
- **Never in the client:** passwords (only during the initial sign-in call),
  service-role keys, or admin-only tables.

## Operations summary

| Operation | Where implemented |
|---|---|
| Reads browsing data | `list_terminal_shift_drivers`, direct RLS-guarded selects |
| Ride lifecycle writes | `create_ride_request`, `accept_ride_request`, `reject_ride_request`, `complete_booking`, `flag_booking`, `report_driver_booking` |
| Review writes | `submit_booking_review` (+ trigger updates), `report_review` |
| Account writes | `register_driver`, `register_commuter`, admin status functions |
| Hourly-ish housekeeping | `reconcile_ride_workflow` (cron, every minute) |
| Push dispatch | `trg_notifications_dispatch_push` → `dispatch_notification_push` → Edge Functions |

## ERD

The complete ERD, in DBML format validated against `dbdiagram.io`, is in
[`database-erd.dbml`](database-erd.dbml). Paste the whole file into
[dbdiagram.io](https://dbdiagram.io/d/new). It contains every column, PK, FK,
unique constraint, and index of the verified live schema.

Full details of every function, trigger and policy are in
[`../system-analysis/database/database-implementation.md`](../system-analysis/database/database-implementation.md).
