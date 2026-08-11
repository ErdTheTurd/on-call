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

Auth → URL Configuration  
https://supabase.com/dashboard/project/yrnndfpvovuvjlzgivgu/auth/url-configuration

- **Site URL:** `https://mdshift.net/docs/` (must NOT be `http://localhost…` — that causes “localhost refused to connect” after Google)
- **Redirect URLs** (one per line):
  - `https://mdshift.net/docs/callback.html`
  - `https://mdshift.net/callback.html`
  - `https://mdshift.net/**`
  - `oncallwizard://auth-callback`
  - `http://127.0.0.1:5500/**` (optional local)
  - `http://localhost:5500/**` (optional local)

## 3. Google (required for “Continue with Google”)

Google stays **off** in Supabase until a **Web** Client ID + Secret are pasted.
The iOS client ID alone cannot enable the provider (iOS clients have no secret).

### 3a. Show “MD Shift” on the Google screen

1. Open [Google Auth Platform → Branding](https://console.cloud.google.com/auth/branding) (or APIs & Services → OAuth consent screen)
2. **App name:** `MD Shift`
3. Support email: your address → Save

Google will still say “continue to `….supabase.co`” on the account picker — that is the Auth callback host, not your product name. Changing that string requires a [Supabase custom domain](https://supabase.com/docs/guides/platform/custom-domains). The **App name** above is what users recognize as MD Shift.

### 3b. iOS client (already set in the app)

Client ID (in `Config/AppInfo.plist`):

`260587604070-m7jj35o7risf6ql8ctldqiet9k3f3cd3.apps.googleusercontent.com`

In Google Cloud, that iOS client’s Bundle ID must match Xcode:

`com.eporthospine.mdshift`

### 3c. Web client (required for Supabase)

1. Open https://console.cloud.google.com/apis/credentials  
2. **Create credentials** → **OAuth client ID** → type **Web application**  
3. Authorized JavaScript origins:
   - `https://mdshift.net`
   - `http://127.0.0.1:5500` (local, if you use Live Server)
4. Authorized redirect URIs — **exact**:
   - `https://yrnndfpvovuvjlzgivgu.supabase.co/auth/v1/callback`
5. Copy **Client ID** and **Client Secret**

### 3d. Supabase

1. Auth → Providers → Google  
   https://supabase.com/dashboard/project/yrnndfpvovuvjlzgivgu/auth/providers
2. Enable Google
3. Paste the **Web** Client ID + Client Secret → Save

Or:

```bash
export SUPABASE_ACCESS_TOKEN=sbp_...
export GOOGLE_CLIENT_ID=....apps.googleusercontent.com   # Web client
export GOOGLE_CLIENT_SECRET=...
./scripts/configure-oauth-providers.sh
```

### 3e. If Google ends on “localhost refused to connect”

1. Supabase → URL Configuration → Site URL must be `https://mdshift.net/docs/` (not localhost)
2. Redirect allow-list must include `https://mdshift.net/docs/callback.html`
3. Sign in from **https://mdshift.net/docs/** (or a local server that is actually running)
4. Soft-refresh / hard-refresh so the fixed `oauthRedirectTo()` code is loaded

The web app returns to `/docs/callback.html` after Google (not `/callback.html`, which 404s on the live site).

## 4. Apple (App ID + Services ID)

Your Xcode bundle ID is **`com.eporthospine.mdshift`**. That string *is* the App ID you register (or edit) in Apple Developer — you do not invent a second “product” ID.

### 4a. App ID (Identifiers → App IDs)

1. Open https://developer.apple.com/account/resources/identifiers/list  
2. Click **+** → **App IDs** → Continue  
3. Type: **App** → Continue  
4. Description: `MD Shift`  
5. Bundle ID: **Explicit** → `com.eporthospine.mdshift`  
   - If this App ID already exists, open it instead of creating a duplicate  
6. Capabilities — enable only what the app uses today (see checklist below) → Save / Register

Xcode already mirrors these in `Config/OnCallWizard.entitlements`. After the App ID is saved, refresh signing in Xcode (Signing & Capabilities).

#### App ID capability checklist

**Enable now**

| Capability | Why |
|---|---|
| **Sign In with Apple** | Native Apple auth + Supabase `id_token` grant |
| **Associated Domains** | Universal Links for `mdshift.net` (and legacy `erdtheturd.github.io`) |

**Leave off until you ship the feature**

- **Push Notifications** — local alerts only today; no APNs entitlement yet  
- **In-App Purchase** — only if doctor subscriptions are sold through the App Store  
- **App Groups / iCloud / HealthKit / Background Modes** — unused  
- **Apple Pay** — only if PassKit payments ship in-app (hospital Stripe can stay on web)

**Outside the Capabilities checkboxes (still required for auth)**

- Google Cloud iOS OAuth client Bundle ID = `com.eporthospine.mdshift`  
- Apple **Services ID** (next section) for web OAuth + Supabase callback  
- Apple **Key** (`.p8`) for the Supabase Apple secret JWT

### 4b. Services ID (for web / Supabase OAuth)

1. Identifiers → **+** → **Services IDs** → Continue  
2. Description: `MD Shift Web`  
3. Identifier: e.g. `com.eporthospine.mdshift.web` (must be unique)  
4. Enable **Sign In with Apple** → Configure:
   - Domains: `yrnndfpvovuvjlzgivgu.supabase.co`
   - Return URLs: `https://yrnndfpvovuvjlzgivgu.supabase.co/auth/v1/callback`
5. Save

### 4c. Key (.p8)

1. Keys → **+** → name `MD Shift Apple Auth`  
2. Enable **Sign In with Apple** → Configure → choose your App ID  
3. Register → **download the `.p8` once** (you cannot download again)  
4. Note **Key ID** and your **Team ID** (top-right of the developer account)

### 4d. Supabase → Apple provider

Auth → Providers → Apple → enable  
https://supabase.com/dashboard/project/yrnndfpvovuvjlzgivgu/auth/providers

- **Client IDs** (comma-separated):  
  `com.eporthospine.mdshift,com.eporthospine.mdshift.web`  
  (Bundle ID + Services ID — adjust if your Services ID string differs)
- **Secret Key**: JWT from the `.p8` (Supabase’s Apple panel / docs walk through Team ID + Key ID)
- Save

Or: `APPLE_CLIENT_ID` / `APPLE_SECRET` with `./scripts/configure-oauth-providers.sh`

### 4f. End-to-end checklist (app + site)

**iOS app**

1. App ID `com.eporthospine.mdshift` has Sign In with Apple (+ Associated Domains)  
2. Xcode Signing & Capabilities shows Sign in with Apple  
3. Supabase Apple provider enabled with Client IDs including `com.eporthospine.mdshift`  
4. Tap **Continue with Apple** in the app → native sheet → lands in MD Shift  

**Website**

1. Same Supabase Apple provider also lists Services ID `com.eporthospine.mdshift.web`  
2. Site URL / redirects include `https://mdshift.net/docs/callback.html`  
3. On https://mdshift.net/docs/ tap **Continue with Apple** → Apple → back to `/docs/callback.html` → app  

**Secret JWT tip:** Supabase’s Apple provider panel can generate the client secret from Team ID + Key ID + `.p8`. If the panel asks for a secret string, use that generated JWT (it expires ~6 months — rotate before then).

## 5. Authenticator 2FA (TOTP)

After email OTP (or OAuth), web and iOS prompt to enroll Google Authenticator / Authy.
If enrolled, later sign-ins require the 6-digit authenticator code before entering the app.

## 6. App behavior

- Web/iOS: after email signup, user enters the 6-digit email code (`verifyOtp` / `/auth/v1/verify`).
- Then optional authenticator enroll (same UX on both platforms).
- Web: Google/Apple → `callback.html` → session (+ MFA if enrolled).
- iOS: Google via `ASWebAuthenticationSession` (`oncallwizard://auth-callback`); Apple via native Sign in with Apple + `id_token` grant.

**Parity rule:** any auth/security change ships on web and iOS together (see `.cursor/rules/web-ios-auth-parity.mdc`).
