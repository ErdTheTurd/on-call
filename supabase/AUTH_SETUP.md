# Auth setup — email OTP + Google / Apple + Resend SMTP

Password signups use a **6-digit email code** (no “click this link”).
Auth mail is sent through **Resend SMTP** (not Supabase’s built-in mailer).
Google and Apple OAuth are available on web and iOS once providers are enabled.

## 0. Resend SMTP (required for reliable OTP delivery)

Supabase’s default mailer is not for production. Wire Resend:

### 0a. Resend account + domain DNS

1. Sign up at https://resend.com
2. **Domains** → **Add Domain** → `mdshift.net` (or `mail.mdshift.net`)
3. Add the DNS records Resend shows (SPF, DKIM; DMARC if prompted)

**Important for mdshift.net today:** public TXT is currently `v=spf1 -all`, which
blocks all senders. Replace that SPF with Resend’s (typically includes
`include:amazonses.com` / Resend’s published SPF). DNS appears to be on
Squarespace (`squarespacedns.com`) — edit DNS there until Resend shows **Verified**.

Sender to use: `noreply@mdshift.net` (must match the verified domain).

Until the domain verifies, Resend only allows limited test sends (e.g. to your
own account email with their onboarding sender). Finish DNS before real signups.

### 0b. API key

1. Resend → **API Keys** → create key with **Sending access**
2. Copy `re_...` once

### 0c. Paste into Supabase (dashboard or script)

**Dashboard:** Authentication → Email → SMTP Settings  
https://supabase.com/dashboard/project/yrnndfpvovuvjlzgivgu/auth/smtp

| Field | Value |
|--------|--------|
| Enable custom SMTP | ON |
| Sender email | `noreply@mdshift.net` |
| Sender name | `MD Shift` |
| Host | `smtp.resend.com` |
| Port | `465` |
| Username | `resend` |
| Password | your Resend API key |

**Or script** (needs a Supabase personal access token from
https://supabase.com/dashboard/account/tokens):

```bash
export RESEND_API_KEY=re_...
export SUPABASE_ACCESS_TOKEN=sbp_...
export RESEND_FROM_EMAIL=noreply@mdshift.net
./scripts/configure-resend-smtp.sh
./scripts/configure-otp-email-template.sh
```

Smoke-test Resend alone:

```bash
export RESEND_API_KEY=re_...
export RESEND_TEST_TO=you@example.com
export RESEND_FROM_EMAIL=noreply@mdshift.net
./scripts/test-resend-send.sh
```

### 0d. Rate limits

After custom SMTP is on: Auth → Rate Limits — raise email send rate above the
built-in default.  
https://supabase.com/dashboard/project/yrnndfpvovuvjlzgivgu/auth/rate-limits

Local CLI config already points SMTP at Resend via `env(RESEND_API_KEY)` in
`supabase/config.toml`.

---

## 1. Confirm email (OTP)

Already on for this project (`mailer_autoconfirm = false`).

Update the hosted **Confirm signup** template so the body shows the token only
(or run `./scripts/configure-otp-email-template.sh`):

1. Auth → Email Templates → Confirm signup  
   https://supabase.com/dashboard/project/yrnndfpvovuvjlzgivgu/auth/templates
2. Subject: `Your MD Shift verification code`
3. Body (no confirmation URL):

```html
<h2>MD Shift verification</h2>
<p>Enter this 6-digit code in the MD Shift app or website:</p>
<p style="font-size:28px;letter-spacing:6px;font-weight:700;">{{ .Token }}</p>
<p>This code expires in about an hour.</p>
```

Local CLI already points at `supabase/templates/confirmation.html`.

---

## 2. Redirect URLs

Auth → URL Configuration:

- Site URL: `https://mdshift.net`
- Redirect URLs:
  - `https://mdshift.net/**`
  - `https://mdshift.net/callback.html`
  - `oncallwizard://auth-callback` (iOS OAuth)

## 3. Google (required for “Continue with Google”)

Google is still **off** until Client ID + Secret are pasted into Supabase.

### 3a. Google Cloud Console

1. Open https://console.cloud.google.com/apis/credentials
2. Create / select a project
3. Configure **OAuth consent screen** (External is fine while testing)
4. **Create credentials** → **OAuth client ID** → type **Web application**
5. Authorized JavaScript origins:
   - `https://mdshift.net`
   - `http://127.0.0.1:3000` (local)
6. Authorized redirect URIs — **exact**:
   - `https://yrnndfpvovuvjlzgivgu.supabase.co/auth/v1/callback`
7. Copy **Client ID** and **Client Secret**

### 3b. Supabase

1. Auth → Providers → Google  
   https://supabase.com/dashboard/project/yrnndfpvovuvjlzgivgu/auth/providers
2. Enable Google
3. Paste Client ID + Client Secret → Save

Or with a PAT:

```bash
export SUPABASE_ACCESS_TOKEN=sbp_...
export GOOGLE_CLIENT_ID=....apps.googleusercontent.com
export GOOGLE_CLIENT_SECRET=...
./scripts/configure-oauth-providers.sh
```

### 3c. Redirect URLs (Auth → URL Configuration)

Must include:

- `https://mdshift.net/callback.html`
- `https://mdshift.net/**`
- `oncallwizard://auth-callback` (iOS)

## 4. Apple (required for “Continue with Apple”)

### 4a. Apple Developer

Bundle ID: `callsystems.on-call-wizard`

1. Identifiers → App ID → enable **Sign In with Apple**
2. Create a **Services ID** (for web/OAuth), e.g. `callsystems.on-call-wizard.web`
   - Domains: `yrnndfpvovuvjlzgivgu.supabase.co`
   - Return URL: `https://yrnndfpvovuvjlzgivgu.supabase.co/auth/v1/callback`
3. Keys → create a key with Sign In with Apple → download `.p8` once
4. Note Team ID, Key ID, Services ID
5. Generate the client secret JWT (Supabase docs / dashboard helper)

### 4b. Supabase

Auth → Providers → Apple → enable  
https://supabase.com/dashboard/project/yrnndfpvovuvjlzgivgu/auth/providers

- **Client IDs** (comma-separated so web + iOS both work):  
  `callsystems.on-call-wizard,callsystems.on-call-wizard.web`  
  (Bundle ID first, then your Services ID — adjust the Services ID to whatever you created)
- **Secret Key**: the JWT generated from your `.p8` (Team ID + Key ID + Services ID/Bundle ID per Apple docs)
- Save

Or: `APPLE_CLIENT_ID` / `APPLE_SECRET` with `./scripts/configure-oauth-providers.sh`

### 4c. Xcode

Sign in with Apple capability is already in `Config/OnCallWizard.entitlements`.
URL scheme `oncallwizard` is in `Config/AppInfo.plist` for Google OAuth return.

## 5. Authenticator 2FA (TOTP)

After email OTP (or OAuth), web and iOS prompt to enroll Google Authenticator / Authy.
If enrolled, later sign-ins require the 6-digit authenticator code before entering the app.

## 6. App behavior

- Web/iOS: after email signup, user enters the 6-digit email code (`verifyOtp` / `/auth/v1/verify`).
- Then optional authenticator enroll (same UX on both platforms).
- Web: Google/Apple → `callback.html` → session (+ MFA if enrolled).
- iOS: Google via `ASWebAuthenticationSession` (`oncallwizard://auth-callback`); Apple via native Sign in with Apple + `id_token` grant.

**Parity rule:** any auth/security change ships on web and iOS together (see `.cursor/rules/web-ios-auth-parity.mdc`).
