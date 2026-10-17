# PASAKAY System Analysis

Source-backed documentation describing the **implemented** PASAKAY system —
two Flutter Android apps (Driver, Customer/commuter), one Flutter web admin
dashboard hosted on GitHub Pages, and a Supabase backend (PostgreSQL + Auth +
Realtime + Edge Functions + pg_cron). Nothing here is proposed design; every
diagram and schema element is anchored to inspected sources in
[`TRACEABILITY.md`](TRACEABILITY.md).

## What was inspected

| Area | Sources |
|---|---|
| Mobile apps | `apps/driver/lib/**`, `apps/customer/lib/**` (routers, providers, services, repositories, screens) |
| Admin web app | `apps/admin/lib/**` (RPC-driven repository, screens) |
| Database | live Supabase PostgreSQL (read-only introspection: `pg_catalog`, `information_schema`, `pg_policies`, cron catalog) + `apps/admin/supabase/migrations/*.sql` (34 migrations) |
| Edge functions | `apps/admin/supabase/functions/send-driver-push/`, `send-passenger-push/` (Deno) |

## Files

| Path | Purpose |
|---|---|
| `flowcharts/system-context.mmd` | Applications, users, external services (Supabase, FCM, device dialer/SMS), how they connect |
| `flowcharts/application-startup.mmd` | `main()` init order, provider wiring, splash-based routing, admin session check |
| `flowcharts/authentication.mmd` | Login (pre-login gate → auth → role/profile checks), self-registration with admin approval, admin sign-in |
| `flowcharts/core-workflows.mmd` | The ride lifecycle: request → accept/reject → booking → complete/dispute → review/report, with server-side validation and expiry paths |
| `flowcharts/database-interactions.mmd` | How each app reaches data: direct RLS-guarded reads, RPCs, Realtime, triggers, push chain |
| `flowcharts/activity-audit.mmd` | Foreground-activity session chain (heartbeats, timeout) and the client audit-log RPC, plus the admin 5-minute sweep |
| `database/schema.dbml` | Complete ERD of the live public schema (26 tables) + `auth.users` reference, in dbdiagram.io-compatible DBML |
| `database/database-implementation.md` | Inventory of everything the ERD cannot show: 94 functions, triggers, policies, checks, partial/ordered indexes, pg_cron jobs |
| `TRACEABILITY.md` | Evidence map: sources, line anchors, verified/inferred/unverified grades, discovered inconsistencies |

## How to view the diagrams

1. Open <https://mermaid.live/edit>.
2. Open any `.mmd` file from `flowcharts/` in a text editor.
3. Paste the entire file content into the left pane — the rendered diagram
   appears on the right.

All six diagrams were rendered headlessly with `mmdc` in SVG (no errors).

## How to view the ERD

1. Open <https://dbdiagram.io/d/new>.
2. Paste the entire content of `database/schema.dbml` into the code panel.

The file parses with `@dbml/core` (dbmlv2). Note: DBML cannot express sort
directions or partial-index predicates, so `DESC` and `WHERE ...` clauses on
indexes are documented in `database/database-implementation.md` §3 instead.

## Schema sources used

- **Primary (authoritative):** live-database introspection — read-only
  `psycopg2` queries against pg catalog views. This captures what is actually
  deployed, including later hotfixes not reordering migrations.
- **Supporting:** `apps/admin/supabase/migrations/*.sql` (34 files) for the
  evolution of each object and comments/documented intent.
- **Identity layer:** `auth.users` is Supabase-managed; only its `id` column is
  shown in the ERD, as the parent of the three profile tables.

## Known limitations

- 5 flows could not be traced to completion (client-side audit retries, Edge
  Function secrets, dashboard auth settings, notification scheduling edge
  cases, admin offline UX). Grades and reasons are in
  [`TRACEABILITY.md` §4](TRACEABILITY.md).
- Discovered code↔database inconsistencies (e.g. `driver_shifts` dead-code
  access, deprecated license fields) are documented only — no source or schema
  change was made, per the task's restrictions.
