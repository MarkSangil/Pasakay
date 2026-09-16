# Pasakay Customer

Flutter customer app for browsing SSLTODA terminals, viewing drivers by shift, Call/SMS, recent contacts, and reviews.

Uses the **same Supabase project** as `apps/driver`.

## Run

```bash
cd apps/customer
flutter pub get
flutter run
```

`.env` must contain the same `SUPABASE_URL` and `SUPABASE_ANON_KEY` as the driver app.

## Demo login

| Field | Value |
|---|---|
| Phone | `09181234567` |
| Password | `Password123!` |

(Auth email is `09181234567@pasakay.commuter`.)

## Screens

- Splash / Login / Sign up — **no bottom navigation**
- Terminals → Drivers by schedule → Driver profile (Call / Message)
- Recent, Review, Profile tabs

Call and SMS open the device dialer / Messages app (not in-app calling).

## Push notifications

Passenger Android FCM uses a **separate** Firebase project: `pasakay-passenger`.

### Already wired
- `android/app/google-services.json` for `com.pasakay.pasakay_customer`
- Google Services Gradle plugin
- `firebase_core` + `firebase_messaging` + local notifications
- Tokens saved to `commuter_device_tokens` after an **active** passenger signs in
- Edge Function: `send-passenger-push`

### What you still must do once

1. In Firebase project **Pasakay Passenger** → Project settings → Service accounts → **Generate new private key**
2. Supabase → Edge Functions → Secrets → add:
   - Name: `FIREBASE_PASSENGER_SERVICE_ACCOUNT_JSON`
   - Value: full JSON from step 1  
     *(Different from the driver secret — different Firebase project.)*
   - Name: `NOTIFICATION_PUSH_SECRET`
   - Value: same as vault `notification_push_webhook_secret` (shared with driver push)
3. Run the customer app, sign in, allow notifications
4. Confirm a row in `commuter_device_tokens`

`notifications` INSERT already dispatches via `trg_notifications_dispatch_push` (pg_net). No Dashboard Database Webhook needed.

### Test

```sql
select public.notify_commuter('<commuter_uuid>'::uuid, 'Smoke test: passenger push');
```
