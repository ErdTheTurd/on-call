# MD Shift — App Store review kit

Paste these into App Store Connect. Screenshots live in `../AppStoreScreenshots/`: iPhone `*-1284x2778.png` and iPad `*-2064x2752.png` (plus `*-2048x2732.png`). None include status-bar chrome.

## Identity

| Field | Value |
| --- | --- |
| Name | MD Shift |
| Bundle ID | `com.eporthospine.mdshift` |
| SKU | `mdshift-ios` (or your ASC SKU) |
| Primary category | Medical |
| Secondary | Business (optional) |
| Version | 1.0 |
| Build | 7 |
| Copyright | 2026 Edward Dunn / MD Shift |

## URLs

| Field | URL |
| --- | --- |
| Support | https://mdshift.net/support/ |
| Privacy Policy | https://mdshift.net/privacypolicy/ |
| Marketing (optional) | https://mdshift.net/ |

## Subtitle (30 characters max)

```
Hospital on-call, filled.
```

## Promotional text (170 characters, editable anytime)

```
Fill open call faster. Doctors claim shifts at locked rates; hospitals set Smart Algo or proprietary rates and approve coverage with a clear audit trail.
```

## Description

```
MD Shift helps hospitals fill on-call coverage and helps doctors find shifts without the usual email chaos.

Hospitals
• See fill rate, open nights, and pending approvals in one place
• Set locked proprietary rates or Smart Algo escalation with a clear floor
• Approve doctors and hospitals before they cover
• Track savings you can audit

Doctors
• Claim open shifts with rates you can trust
• Manage assigned call, trades, and availability
• Keep credentials and NPI verification in one profile

Explore as a doctor or Explore as a hospital loads sample data so you can walk the product before creating a live roster. MD Shift is a scheduling tool — not emergency dispatch. Use your hospital’s normal channels for clinical emergencies.

Support: https://mdshift.net/support/
Privacy: https://mdshift.net/privacypolicy/
```

## Keywords (100 characters, comma-separated, no spaces after commas if you want max room)

```
on-call,hospital,physician,shift,coverage,scheduling,locum,NPI,medical staffing,doctor
```

## What’s New (1.0)

```
Hospital on-call coverage, doctor shift claims, trades, and verification. Sign in with Apple uses the name and email Apple already provided.
```

## App Review Information — Notes (paste as-is)

```
Hi App Review team,

Thanks for the follow-up on MD Shift 1.0 (6). This build is 7.

SIGN IN WITH APPLE (Guideline 4)
The app requests fullName and email from Authentication Services. When Apple provides givenName, familyName, and/or email, we persist them (keyed by Apple user id), bind them to the Supabase session user, and do not ask the user to type those values again.

• Doctor onboarding: if both given and family name are present, name fields are skipped. If Apple email is present, the work-email field and the email-verification step are skipped. Remaining steps are credential/NPI and specialties.
• Hospital onboarding: Apple’s personal name is not the facility name, so we still ask for hospital name and NPI. If Apple email is present, the admin-email field is skipped and that address is used.
• Later Sign in with Apple attempts often omit fullName/email (Apple only sends them on the first authorization). Empty later values never overwrite a name or email we already stored.
• If Apple hid name and email and nothing is stored, we collect what we still need.

SCREENSHOTS (2.3.10)
We replaced the App Store screenshots for iPhone and iPad. The previous set had a mock status bar (text signal / battery). The new set has no status bar chrome and shows the in-app UI only. Please replace both iPhone 6.5" (1284×2778) and iPad 13" (2064×2752) slots — open Media Manager → View All Sizes so leftover 12.9" / 2048×2732 assets are replaced too.

SIGN IN WITH APPLE (2.1a)
Sign in with Apple is supported on iPhone and iPad. Choose Doctor or Hospital on the sign-in screen, then Continue with Apple.

If you only need to exercise scheduling features without creating an Apple account:
1. Tap Explore as a doctor or Explore as a hospital (no password). Sample data loads immediately.
2. Or create / sign in with a real Apple, Google, or email account — normal auth (OTP / MFA when required).

Support: https://mdshift.net/support/
Privacy: https://mdshift.net/privacypolicy/
Contact: erdunn706@gmail.com
```

## Fix checklist after Sept 2026 rejection

### Screenshots (2.3.10)
1. In App Store Connect → your version → **Previews and Screenshots**, open **View All Sizes in Media Manager**.
2. Replace **iPhone** slots with `AppStoreScreenshots/*-1284x2778.png` (6.5"). Also replace 1242×2688 if that size is still listed.
3. Replace **iPad** slots with `AppStoreScreenshots/*-2064x2752.png` (13"). If Media Manager still shows a 12.9" / 2048×2732 row, upload `*-2048x2732.png` there too.
4. Confirm every remaining size has **no** mock status bar (no “9:41”, signal bars, or battery). ASC often keeps old iPad assets after only the iPhone set is updated.

### Sign in with Apple (2.1a) — Supabase dashboard (required)
Native Apple tokens use the **Bundle ID** as audience. In Supabase:

1. Authentication → Providers → **Apple** → Enabled
2. **Client IDs** must include BOTH (Services ID first):
   `com.eporthospine.mdshift.web,com.eporthospine.mdshift`
3. Secret JWT must be valid if web Apple is enabled (regenerate if older than ~6 months)
4. Apple Developer → Identifiers → App ID `com.eporthospine.mdshift` → Sign In with Apple ON
5. Rebuild / upload build **7**, then test Continue with Apple on an iPad simulator or device before resubmitting

Native SIWA is already wired (`com.apple.developer.applesignin` = Default; `SignInWithAppleButton` sends a hashed nonce to `signInWithAppleIDToken`). After Sign in with Apple, if Apple shares the name and/or email, the app uses them and does not ask the user to re-enter them (Guideline 4). The usual iPad review failure is missing **Bundle ID** in the Supabase Apple Client IDs list above — not a presentation-anchor bug. Do not ship iOS-only Client IDs.

### Sign in with Apple name and email (Guideline 4)
Apple only sends `fullName` and `email` on the **first** authorization. Build 7 persists given name, family name, **and email** (UserDefaults, keyed by Apple user id), binds that Apple user to the session after Supabase sign-in, and prefills / skips onboarding fields. Empty later values never overwrite stored non-empty values. Hospital onboarding still asks for **hospital** name (that is the facility, not the signed-in person’s Apple name).

### Demo / showcase framing (Guideline 2.2)
The shipping product name is **MD Shift** (not “MD Shift Demo”). App Review can use **Explore as a doctor** / **Explore as a hospital** for sample data. There is no admin/marketing shortcut in the shipping sign-in UI.

## Demo account (App Review form)

| Field | Value |
| --- | --- |
| Sign-in required? | Prefer Explore (no password). Email / Apple / Google also work for real accounts. |
| User | (optional) any registered email |
| Password | (optional) that account’s password |

Mention **Explore as a doctor / Explore as a hospital** in Notes so reviewers are never blocked.

## Export compliance

- Uses only standard HTTPS / OS crypto → **ITSAppUsesNonExemptEncryption = NO** (set in the app).
- In ASC: answer that the app only uses exempt encryption / standard encryption.

## Privacy nutrition labels (declare)

Collect / linked to identity (typical for this app):

- Email address (account)
- Name (doctor / hospital profile)
- Other user content (NPI, license, specialties, shift notes) as needed for scheduling
- Product interaction / diagnostics only if you enable analytics (currently none required)

Do **not** claim tracking unless you add ATT / ad SDKs.

## Age rating

- Medical / information — no unrestricted web, no gambling, etc.
- Typically 4+ or 12+ depending on questionnaire; answer honestly for medical content.

## Screenshots

Upload from `AppStoreScreenshots/` — **iPhone 6.5"** (1284×2778):

1. `01-doctor-home-1284x2778.png`
2. `02-open-shifts-1284x2778.png`
3. `03-hospital-dashboard-1284x2778.png`
4. `04-alter-rates-1284x2778.png`
5. `05-approvals-1284x2778.png`
6. `06-analytics-1284x2778.png`

Then **iPad 13"** (2064×2752) — required because the app runs on iPad. Open **Media Manager → View All Sizes** and replace these slots (do not leave the old mock-status-bar iPad assets):

1. `01-doctor-home-2064x2752.png`
2. `02-open-shifts-2064x2752.png`
3. `03-hospital-dashboard-2064x2752.png`
4. `04-alter-rates-2064x2752.png`
5. `05-approvals-2064x2752.png`
6. `06-analytics-2064x2752.png`

If Media Manager still lists **iPad 12.9"** (2048×2732), upload the matching `*-2048x2732.png` files from the same folder.

Do not upload Simulator captures from iPhone 17 Pro Max.

The marketing-site copies in `docs/app-store-screenshots/` are the same clean 1284×2778 set (no status bar).

Regenerate (writes iPhone 1284 + 1242, iPad 2064 + 2048, and syncs docs):

```bash
python3 scripts/generate-app-store-screenshots.py
```

## Build & upload (no physical iPhone required)

You do **not** need a phone to submit. Release builds use **Manual** signing with the **Md Shift Demo** profile (App Store profiles are not device-bound; the profile name is unchanged). Automatic Debug signing still needs a device UDID if you want to run on hardware.

### One-time profile setup

Follow **[CREATE_PROFILE.md](CREATE_PROFILE.md)** — create/install an App Store provisioning profile named exactly `Md Shift Demo`.

Also ensure an **Apple Distribution** cert exists: Xcode → Settings → Accounts → team **8LVD2L956K** → Manage Certificates → **+** → Apple Distribution.

### Archive & upload

1. Open `on-call wizard.xcodeproj`
2. Destination: **Any iOS Device (arm64)** (not a Simulator)
3. **Product → Archive**
4. Organizer → **Distribute App** → App Store Connect → Upload  
   (or export with `AppStore/ExportOptions.plist`)
5. App Store Connect → select build → paste listing from this file → Submit for Review

```bash
xcodebuild -scheme "on-call wizard" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/MDShift.xcarchive \
  archive

xcodebuild -exportArchive \
  -archivePath build/MDShift.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist AppStore/ExportOptions.plist
```
