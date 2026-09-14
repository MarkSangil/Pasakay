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
