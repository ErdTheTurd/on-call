# Auth setup — email OTP + Google / Apple

Password signups use a **6-digit email code** (no “click this link”).
Google and Apple OAuth are available on web and iOS once providers are enabled.

## 1. Confirm email (OTP)

Already on for this project (`mailer_autoconfirm = false`).

Update the hosted **Confirm signup** template so the body shows the token only:

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
