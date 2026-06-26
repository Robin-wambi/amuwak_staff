# Staff invites & email + password auth

The app uses **invite-only** onboarding with **email + password** sign-in. There
is no public sign-up: a manager invites a teammate, who clicks an emailed link to
set their own password (which also verifies their email). Returning users stay
signed in — the persisted Supabase session lands them straight on the dashboard.

## How it fits together

- **Login** — `signInWithEmailPassword` (real email + password). "Forgot
  password?" sends a reset link. See [auth_service.dart](../lib/src/auth/auth_service.dart).
- **AuthGate** — root widget that routes Login / Set-password / Dashboard from the
  auth state. See [auth_gate.dart](../lib/src/auth/auth_gate.dart).
- **Invite (manager only)** — Account tab → "Invite staff" opens a form that calls
  the `invite-staff` Edge Function via [invite_staff_service.dart](../lib/src/staff/invite_staff_service.dart).
- **Edge Function** — [supabase/functions/invite-staff/index.ts](../supabase/functions/invite-staff/index.ts)
  authenticates the caller as a manager, then uses the service-role key to invite
  the user and insert their `staff` row (`id == auth.users.id`, role defaults to
  `driver`). The UI gating is convenience only — this function is the real
  boundary. New roles must be one of `driver | in_shop | manager` (migration 0002).

## One-time setup (Supabase dashboard / CLI)

These cannot be done from app code — an operator must run them:

1. **Deploy the function** (the service-role secret is injected automatically as
   `SUPABASE_SERVICE_ROLE_KEY`; never put it in the app):

   ```sh
   supabase functions deploy invite-staff
   ```

   Optionally set where invite/reset links land (defaults to the project Site
   URL): `supabase secrets set INVITE_REDIRECT_URL=https://<your-web-app>`

2. **Auth settings** (Authentication → Providers / URL config):
   - Enable email confirmations.
   - Set **Site URL** and add the web app origin to **Redirect URLs**.
   - Review the **Invite user** and **Reset password** email templates.

3. **Bootstrap a manager.** Only managers can invite, so seed the first one:
   create an auth user (Authentication → Users → Add user, set a password), then
   insert a matching `staff` row with the same `id` and `role = 'manager'`.

## End-to-end check

1. Sign in as the seeded manager → Account → **Invite staff** → invite a test
   email as `driver`. Confirm the email arrives and a `staff` row exists
   (`active = true`, `role = driver`).
2. Open the invite link → **Set password** → submit → land on the dashboard with
   driver-scoped data and `user_role = driver` in the JWT.
3. Sign out → **Forgot password?** → complete the reset → sign in again.
4. Negative: a non-manager calling the function is rejected (403); a duplicate
   username/email returns a clear error.
