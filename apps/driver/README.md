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

## Schedule push notifications

Backend cron runs every minute: `process_schedule_notifications()` (Asia/Manila).

| Setting | Table/key | Default |
|---------|-----------|---------|
| Reminder lead time | `app_notification_settings.shift_reminder_lead_minutes` | `30` |
| Timezone | `app_notification_settings.timezone` | `Asia/Manila` |

Event types: `DRIVER_SHIFT_APPROACHING`, `DRIVER_SHIFT_STARTED`, `DRIVER_SHIFT_ENDED`, `DRIVER_SCHEDULE_UPDATED`, `DRIVER_SCHEDULE_CANCELLED`, `DRIVER_TERMINAL_UPDATED`, `DRIVER_AVAILABILITY_UPDATED`, `FOLLOWED_DRIVER_AVAILABLE`, `FOLLOWED_DRIVER_UNAVAILABLE`.

Push delivery uses a DB `pg_net` trigger on `notifications` INSERT → `send-driver-push` / `send-passenger-push`, plus Firebase + `NOTIFICATION_PUSH_SECRET` edge secrets.

### Already in the app
- `google-services.json` for package `com.pasakay.pasakay_driver`
- Google Services Gradle plugin
- `firebase_core` + `firebase_messaging` + local notifications
- Token saved to `device_tokens` after an **active** driver signs in

### What you still must do once

1. **Firebase service account** (Project settings → Service accounts → Generate new private key)
2. In Supabase Dashboard → **Edge Functions → Secrets**, add:
   - Name: `FIREBASE_SERVICE_ACCOUNT_JSON`
   - Value: the full JSON file contents (one line is fine)
   - Name: `NOTIFICATION_PUSH_SECRET`
   - Value: same value as vault secret `notification_push_webhook_secret` (ask team / agent store)
3. Rebuild/run the driver app on a **real Android device** or emulator with Google Play
4. Sign in as an active driver and allow notifications
5. Confirm a row appears in `device_tokens`

`notifications` INSERT already dispatches via `trg_notifications_dispatch_push` (pg_net). No Dashboard Database Webhook needed.

### Test send (SQL)

```sql
-- Replace with a real active driver_id that has a device_tokens row
select public.notify_driver(
  'a0000000-0000-4000-8000-000000000001'::uuid,
  'Smoke test: driver push notification'
);
```

If `NOTIFICATION_PUSH_SECRET` is set on the edge functions, FCM should fire from the insert. Manual call with the service role key:

```bash
curl -X POST \
  'https://musogdwaxdyiatmnitkg.supabase.co/functions/v1/send-driver-push' \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"driver_id":"<uuid>","title":"Pasakay","body":"Hello driver"}'
```

### iOS
Not configured yet (needs Apple Developer APNs key + `GoogleService-Info.plist`).

### Customer app
Not wired yet (needs its own Firebase Android app + token table for commuters).


## Brand assets

- `assets/images/pasakay_logo.jpg`
- `assets/images/pasakay_background.jpg`
- Design references under `assets/design/`
