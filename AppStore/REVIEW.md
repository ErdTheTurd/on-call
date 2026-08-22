# MD Shift — App Store review kit

Paste these into App Store Connect. Screenshots live in `../AppStoreScreenshots/` (`*-1284x2778.png`).

## Identity

| Field | Value |
| --- | --- |
| Name | MD Shift |
| Bundle ID | `com.eporthospine.mdshift` |
| SKU | `mdshift-ios` (or your ASC SKU) |
| Primary category | Medical |
| Secondary | Business (optional) |
| Version | 1.0 |
| Build | 1 |
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

Explore mode includes sample data so you can walk the product before creating a live roster. MD Shift is a scheduling tool — not emergency dispatch. Use your hospital’s normal channels for clinical emergencies.

Support: https://mdshift.net/support/
Privacy: https://mdshift.net/privacypolicy/
```

## Keywords (100 characters, comma-separated, no spaces after commas if you want max room)

```
on-call,hospital,physician,shift,coverage,scheduling,locum,NPI,medical staffing,doctor
```

## What’s New (1.0)

```
First release of MD Shift — hospital on-call coverage, doctor shift claims, trades, and verification.
```

## App Review Information — Notes (paste as-is)

```
MD Shift schedules hospital on-call coverage for doctors and hospitals.

HOW TO REVIEW (recommended)
1. On the sign-in screen, tap “Explore as doctor” or “Explore as hospital”.
2. No password required. Sample data loads so you can browse Dashboard / Alter Rates / Doctors (hospital) or Home / Open Shifts / Trades (doctor).
3. Explore mode is labeled as sample data and is not live hospital volume.

ALTERNATE LOGINS (seeded demos)
• Doctor: jdunn@eporthospine.com / 1234567890
• Hospital: erdunn706@gmail.com / 1234567890
If Supabase auth is reachable these prefer the live account; otherwise they open the same seeded walkthrough.

ADMIN PREVIEW (marketing-style screens, optional)
• info@erdanimates.shop / 1234567890
Opens a curated preview of core screens. Prefer Explore mode for functional review.

Face ID may appear after a real account is created; it can be skipped / cancelled on Simulator.

Support: https://mdshift.net/support/
Privacy: https://mdshift.net/privacypolicy/
Contact: erdunn706@gmail.com
```

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

## Build & upload (Xcode)

Archive failed from CLI until at least one iPhone is registered to team **8LVD2L956K** (Apple: “no devices… provisioning profile”).

**Fix once (pick one):**

1. Plug in an iPhone → unlock → Trust → in Xcode select the phone as run destination → Run once (registers the device), **or**
2. [developer.apple.com](https://developer.apple.com/account/resources/devices/list) → add a device UDID, then create an **App Store** distribution profile for `com.eporthospine.mdshift`.

Then:

1. Open `on-call wizard.xcodeproj`
2. Target **on-call wizard** → Signing & Capabilities → Team selected, Automatic on
3. Scheme **on-call wizard** → destination **Any iOS Device (arm64)**
4. Product → **Archive**
5. Organizer → **Distribute App** → App Store Connect → Upload
6. App Store Connect → select build → paste listing from this file → Submit for Review

CLI after a device is registered:

```bash
xcodebuild -scheme "on-call wizard" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/MDShift.xcarchive \
  -allowProvisioningUpdates archive
```
