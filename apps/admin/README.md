# PASAKAY System Admin

Web console at `apps/admin` for the seven scoped admin features. It talks to the same Supabase project as the driver and customer apps.

## Seed account

| | |
|---|---|
| Email | `admin@pasakay.app` |
| Username | `sysadmin` |
| Password | `PasakayAdmin#2026` |

Change the password from the sidebar after first sign-in. Driver and commuter accounts cannot open this console.

## Deploy (GitHub Pages)

The admin console deploys from `main` to a dedicated `gh-pages` branch (Flutter web build of `apps/admin` only).

1. In the GitHub repo, add Actions secrets:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
2. Enable Pages: **Settings → Pages → Deploy from a branch → `gh-pages` / `/ (root)`**.
3. Push to `main` (or run **Deploy admin to GitHub Pages**). Site URL: `https://marksangil.github.io/Pasakay/`.

## Run

```bash
cd apps/admin
cp .env.example .env
flutter pub get
flutter run -d chrome
```

## What this console does — and does not

1. **Drivers** — list, open a detail page to view/edit profile and shift availability, verify license, activate/suspend/deactivate. Activation is blocked until that manual check. No LTFRB lookup, no bulk import/export, no change log.
2. **Terminals** — plain-text list. No map. Delete is blocked while drivers are still assigned; reassign them first.
3. **Shifts** — edit the 3 existing blocks and reassign drivers. Cannot add or delete a shift. This is assignment, not clock-in. Overlapping windows warn but a driver can only sit on one shift.
4. **Commuters** — view, suspend, or deactivate. No abuse-report queue, no blacklist, and no call/SMS content.
5. **Reviews** — a review is a 1–5 rating plus optional text. Hide or remove it by hand. No report queue and no automated filter.
6. **Diagnostics** — read-only device and crash logs. Not analytics, and you cannot push a fix from here.
7. **Privacy** — log an access, correction, or deletion request that arrived outside the app. Deletion anonymizes the account. If research retention applies, records stay and the request is marked retained. Full erasure is not guaranteed during the study.
