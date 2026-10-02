# MD Shift for Android

Native Android client for MD Shift. It talks to the same Supabase project as the iOS app and the website (`on-call`, ref `yrnndfpvovuvjlzgivgu`). The anon key in the app is the public publishable key. There is no service-role key in this tree.

The HTTP client is Ktor, aimed at the same GoTrue, PostgREST, and edge-function calls the iOS app makes (email OTP, TOTP, paged reads, `request-trade`, `respond-trade`, `send-notification`). `accept-shift` and `cancel-shift` are called when present and fall back to a direct assignment insert or status update.

## Requirements

- JDK 21
- Android SDK 36 and build-tools 37
- A device or emulator, minSdk 26

```bash
cd android
./gradlew assembleDebug
```

`local.properties` (gitignored) should point at the SDK:

```
sdk.dir=/path/to/Android/sdk
```

## App identity

| | |
|--|--|
| applicationId | `com.eporthospine.mdshift` |
| versionName | 1.0.1 |
| versionCode | 1 |
| minSdk | 26 |
| target / compile | 36 |

## What is in the app

Doctor and hospital roles:

- Email sign-up and sign-in with a 6-digit code (not a magic link)
- Optional authenticator enrollment after sign-up, and a TOTP challenge when a factor is already on the account
- Google sign-in through Credential Manager
- Sign in with Apple through the Supabase OAuth browser flow (`mdshift://auth-callback`)
- Server profile hydration after sign-in, so a finished account skips onboarding on a new device
- Per-user local data cleared on sign-in to a different account and on sign-out
- Doctor NPI check against the public NPPES registry, then specialties
- Hospital work-email code through the `send-notification` function
- Calendars, open shifts, my shifts, trades (incoming, outgoing, counter), coverage requests and approvals with doctor names, roster, scheduling policy, specialty rates, penalties, savings and billing from server rows (empty states when a real account has none)
- Settings, appearance, sign-out, privacy policy (`https://mdshift.net/privacypolicy/`), support
- Account deletion matches iOS: there is no in-app delete. The settings screen points people to support and the privacy policy.

Explore as a doctor or hospital is compiled only when `BuildConfig.DEMO_ENABLED` is true. That is debug builds, and release builds configured with `-Pmdshift.internal=true` or `MDSHIFT_INTERNAL=true` (Play internal testing). A normal release build has no Explore buttons. A real signed-in session never loads the sample board.

Push notifications are not in this build. iOS only schedules local notifications and does not register for remote push.

## Checks

```bash
cd android
./gradlew assembleDebug bundleRelease testDebugUnitTest lint
```

Release uses R8 and resource shrinking. Without signing secrets, `bundleRelease` writes an unsigned AAB.

## Signing

Nothing in git is a keystore. Provide these when you are ready to upload:

| Env or `gradle.properties` | Meaning |
|--|--|
| `MDSHIFT_KEYSTORE_PATH` | Path to the upload `.jks` / `.keystore` |
| `MDSHIFT_KEYSTORE_PASSWORD` | Store password |
| `MDSHIFT_KEY_ALIAS` | Key alias |
| `MDSHIFT_KEY_PASSWORD` | Key password |

Pass the two passwords as environment variables. Do not put them in Gradle `-P` arguments; those are visible in the process list.

```bash
MDSHIFT_KEYSTORE_PASSWORD='…' MDSHIFT_KEY_PASSWORD='…' \
  ./gradlew bundleRelease \
  -PMDSHIFT_KEYSTORE_PATH="$PWD/upload.jks" \
  -PMDSHIFT_KEY_ALIAS=upload
```

The Play Console account, app listing, and upload key are still for the owner to create. Package name: `com.eporthospine.mdshift`.

Internal-testing builds that should keep Explore:

```bash
./gradlew bundleRelease -Pmdshift.internal=true
```

Do not ship that artifact to production.

## Supabase and Google (owner setup)

Do not change the hosted auth templates or provider secrets from the app. Add the Android redirect and OAuth client in the dashboards.

### Supabase redirect URLs

Auth → URL configuration for project `yrnndfpvovuvjlzgivgu`:

- Add `mdshift://auth-callback`

Apple sign-in opens `https://yrnndfpvovuvjlzgivgu.supabase.co/auth/v1/authorize?provider=apple` and returns to that app link. The iOS scheme `oncallwizard://auth-callback` stays as it is.

### Google

Credential Manager needs the **Web** client ID already used by Supabase (the one whose secret is saved on the Google provider). The ID token audience has to be that web client.

1. Google Cloud → Credentials → Create OAuth client ID → **Android**
2. Package name `com.eporthospine.mdshift`
3. SHA-1 of the upload key (and the debug keystore while developing)
4. Pass the **Web** client ID into the app (not the Android client ID):

```bash
./gradlew assembleDebug -PMDSHIFT_GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Or export `MDSHIFT_GOOGLE_WEB_CLIENT_ID`. If it is blank, the Google button explains that the client ID is missing.

Play App Signing adds a second SHA-1 (the app signing certificate). Add that SHA-1 to the Android OAuth client after the first Play upload, or Google sign-in works in local debug and fails for Play installs.

## App Review accounts

These are real Supabase users. Passwords are not in the repo. Ask the owner.

| Role | Email |
|--|--|
| Doctor | `jdunn@eporthospine.com` |
| Hospital | `review-hospital@mdshift.net` |

Sign in with email and password. Do not use Explore on a release build. A finished profile on the server skips onboarding. Demo hospitals and demo doctors stay isolated by `is_demo` on the server; this client never sends that flag.

## Google Play Data safety

Match the iOS privacy label. No analytics or advertising SDK is linked.

| Data | Collected | Shared | Purpose | Linked to user |
|--|--|--|--|--|
| Name | Yes | No | App functionality | Yes |
| Email address | Yes | No | App functionality | Yes |
| User ID | Yes | No | App functionality | Yes |
| Other info: NPI, license, DEA, shifts, rates, trade notes the user enters | Yes | No | App functionality | Yes |

Not collected: location, contacts, photos, financial info beyond rates the user types, health info, crash logs, advertising ID. Data is not used for tracking. Account deletion is requested by email, as on iOS; see https://mdshift.net/privacypolicy/.
