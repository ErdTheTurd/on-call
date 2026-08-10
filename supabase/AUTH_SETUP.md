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

## 3. Google

1. Create OAuth credentials in Google Cloud Console (Web + iOS if needed).
2. Auth → Providers → Google → enable  
   https://supabase.com/dashboard/project/yrnndfpvovuvjlzgivgu/auth/providers
3. Paste Client ID + Client Secret.
4. Authorized redirect URI from Supabase (shown in the provider panel), typically:  
   `https://yrnndfpvovuvjlzgivgu.supabase.co/auth/v1/callback`

## 4. Apple

1. Apple Developer → Identifiers → enable Sign in with Apple for the App ID.
2. Create a Services ID for web if needed; configure return URL to the Supabase callback above.
3. Auth → Providers → Apple → enable; paste Services ID, Secret Key (JWT), Team ID, Key ID.
4. Xcode: Sign in with Apple capability is in `Config/OnCallWizard.entitlements`.

## 5. App behavior

- Web/iOS: after email signup, user enters the 6-digit code (`verifyOtp` / `/auth/v1/verify`).
- Web: Google/Apple → `callback.html` → session.
- iOS: Google via `ASWebAuthenticationSession` (`oncallwizard://auth-callback`); Apple via native Sign in with Apple + `id_token` grant.
