# MD Shift Demo — App Store review kit

Paste these into App Store Connect. Screenshots live in `../AppStoreScreenshots/`: iPhone `*-1284x2778.png` and iPad `*-2064x2752.png` (plus `*-2048x2732.png`). None include status-bar chrome.

## Identity

| Field | Value |
| --- | --- |
| Name | MD Shift Demo |
| Bundle ID | `com.eporthospine.mdshift` |
| SKU | `mdshift-ios` (or your ASC SKU) |
| Primary category | Medical |
| Secondary | Business (optional) |
| Version | 1.0 |
| Build | 3 |
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
MD Shift Demo helps hospitals fill on-call coverage and helps doctors find shifts without the usual email chaos.

Hospitals
• See fill rate, open nights, and pending approvals in one place
• Set locked proprietary rates or Smart Algo escalation with a clear floor
• Approve doctors and hospitals before they cover
• Track savings you can audit

Doctors
• Claim open shifts with rates you can trust
• Manage assigned call, trades, and availability
• Keep credentials and NPI verification in one profile

Explore mode includes sample data so you can walk the product before creating a live roster. MD Shift Demo is a scheduling tool — not emergency dispatch. Use your hospital’s normal channels for clinical emergencies.

Support: https://mdshift.net/support/
Privacy: https://mdshift.net/privacypolicy/
```

## Keywords (100 characters, comma-separated, no spaces after commas if you want max room)

```
on-call,hospital,physician,shift,coverage,scheduling,locum,NPI,medical staffing,doctor
```

## What’s New (1.0)

```
First release of MD Shift Demo — hospital on-call coverage, doctor shift claims, trades, and verification.
```

## App Review Information — Notes (paste as-is)

```
Hi App Review team,

Thanks for the follow-up on MD Shift Demo 1.0 (3).

SCREENSHOTS (2.3.10)
We replaced the App Store screenshots for iPhone and iPad. The previous set had a mock status bar (text signal / battery). The new set has no status bar chrome and shows the in-app UI only. Please replace both iPhone 6.5" (1284×2778) and iPad 13" (2064×2752) slots — open Media Manager → View All Sizes so leftover 12.9" / 2048×2732 assets are replaced too.

SIGN IN WITH APPLE (2.1a)
Sign in with Apple is supported on iPhone and iPad. Choose Doctor or Hospital on the sign-in screen, then Continue with Apple.

If you only need to exercise scheduling features without creating an Apple account:
1. Tap Explore as a doctor or Explore as a hospital (no password).
2. Or use demo login jdunn@eporthospine.com / 1234567890 (doctor) or erdunn706@gmail.com / 1234567890 (hospital).

Account deletion is not in-app; users email https://mdshift.net/support/

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
5. Rebuild / upload build **3**, then test Continue with Apple on an iPad simulator or device before resubmitting

Native SIWA is already wired (`com.apple.developer.applesignin` = Default; `SignInWithAppleButton` sends a hashed nonce to `signInWithAppleIDToken`). The usual iPad review failure is missing **Bundle ID** in the Supabase Apple Client IDs list above — not a presentation-anchor bug. Do not ship iOS-only Client IDs.

## Demo account (App Review form)

| Field | Value |
| --- | --- |
| Sign-in required? | Yes (or use Explore — note above) |
| User | `jdunn@eporthospine.com` |
| Password | `1234567890` |

Also mention Explore buttons in Notes so reviewers are not blocked if network auth fails.

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

You do **not** need a phone to submit. Release builds use **Manual** signing with the **Md Shift Demo** profile (App Store profiles are not device-bound). Automatic Debug signing still needs a device UDID if you want to run on hardware.

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
