# MD Shift Demo — App Store review kit

Paste these into App Store Connect. Screenshots live in `../AppStoreScreenshots/` (`*-1284x2778.png`).

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
We replaced the App Store screenshots. The previous set had a mock status bar (text signal / battery). The new set has no status bar chrome and shows the in-app UI only. Please use the updated iPhone 6.5" assets (and View All Sizes in Media Manager if needed).

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
1. Upload all `AppStoreScreenshots/*-1284x2778.png` to App Store Connect → Previews and Screenshots.
2. Also open **View All Sizes in Media Manager** and replace any leftover sizes that still show a mock status bar.

### Sign in with Apple (2.1a) — Supabase dashboard (required)
Native Apple tokens use the **Bundle ID** as audience. In Supabase:

1. Authentication → Providers → **Apple** → Enabled
2. **Client IDs** must include BOTH (Services ID first):
   `com.eporthospine.mdshift.web,com.eporthospine.mdshift`
3. Secret JWT must be valid if web Apple is enabled (regenerate if older than ~6 months)
4. Apple Developer → Identifiers → App ID `com.eporthospine.mdshift` → Sign In with Apple ON
5. Rebuild / upload build **3**, then test Continue with Apple on an iPad simulator or device before resubmitting

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

Upload from `AppStoreScreenshots/`:

1. `01-doctor-home-1284x2778.png`
2. `02-open-shifts-1284x2778.png`
3. `03-hospital-dashboard-1284x2778.png`
4. `04-alter-rates-1284x2778.png`
5. `05-approvals-1284x2778.png`
6. `06-analytics-1284x2778.png`

Use the **iPhone 6.5"** slot (1284×2778). Do not upload Simulator captures from iPhone 17 Pro Max.

Regenerate:

```bash
python3 scripts/generate-app-store-screenshots.py --also-1242
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
