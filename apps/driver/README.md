# Pasakay Driver App

Flutter driver client for Pasakay (tricycle TODA bookings). Lives under `apps/driver` so the repo can grow into a monorepo later.

## Features

- Login / sign-up with assigned credentials (mobile + password)
- Profile: name, TODA number, plate, assigned & current terminal
- Availability from operating schedule (morning / afternoon / evening) — no manual online toggle
- Bookings this shift with Upcoming → Ongoing → Completed flow
- Recents, Reviews, Notifications
- Call / Message via the device Phone & SMS apps
- Supabase auth, Postgres tables, RLS, and Realtime sync

## Setup

### 1. Supabase

1. Open your Supabase project → **SQL Editor**
2. Paste and run `apps/driver/supabase/migrations/20250906000000_init_driver_schema.sql`
3. (Optional) After creating a driver account in the app, use `apps/driver/supabase/seed_demo.sql` for sample bookings/reviews
4. Project Settings → API → copy **Project URL** and **anon public** key

### 2. Env

```bash
cd apps/driver
cp .env.example .env
```

Edit `.env`:

```
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOi...
```

### 3. Run

```bash
cd apps/driver
flutter pub get
flutter run
```

## Auth note

Drivers log in with **mobile number + password**. Under the hood Supabase Auth uses:

`{normalizedMobile}@pasakay.driver`

The real contact email is stored on `drivers.email`.

## Push notifications

`device_tokens` and `notifications` tables are ready. Wire FCM/APNs later and upsert tokens via `DriverRepository.upsertDeviceToken`. Realtime already refreshes the in-app notification list and bookings.

## Brand assets

- `assets/images/pasakay_logo.jpg`
- `assets/images/pasakay_background.jpg`
- Design references under `assets/design/`
