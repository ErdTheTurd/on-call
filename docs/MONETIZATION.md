# Monetization

## Stack (deferred ~1 year)

Monetization is **off by default** until launch maturity:

- Web: `docs/assets/js/config.js` → `monetizationLive: false`
- iOS: `PlusMembershipStore.isMonetizationLive = false`

While off: Plus upgrade CTAs are hidden and the app stays ad-free.

### 1. MD Shift+ — $9.99/mo (when you flip monetization on)

Personal / account upgrade on **web and iOS**:

- Ad-free workspace
- Priority badge + faster support lane
- Doctors: **+2 daily tokens**
- Hospitals: priority posting / control-room perks

**Checkout:** Stripe on the **web** (Payment Link or Checkout Session via `create-plus-checkout`). iOS opens the same web checkout — one Supabase account unlocks Plus on both platforms.

**Entitlement:** `profiles.plus_active`, `plus_until`, `stripe_customer_id`, `stripe_subscription_id` (see `supabase/migrations/004_md_shift_plus.sql`).

**Wire-up checklist**

1. Run migration `004_md_shift_plus.sql` in Supabase SQL editor (or CLI).
2. Stripe Dashboard → Product **MD Shift+** at **$9.99/month** → copy Price ID.
3. Create a Payment Link *or* set secrets:
   - `STRIPE_SECRET_KEY`
   - `STRIPE_PLUS_PRICE_ID`
   - `STRIPE_PLUS_PAYMENT_LINK` (optional shortcut)
   - `STRIPE_WEBHOOK_SECRET` → point webhook to `…/functions/v1/stripe-webhook`
4. Deploy edge functions `create-plus-checkout` and `stripe-webhook`.
5. Optional client config: `stripePlusPaymentLink` in `docs/assets/js/config.js`.

Entry points: **Dashboard → Get MD Shift+** (doctor + hospital, web + iOS).

### 2. Real ads (non-Plus)

- **iOS and Android:** a short Google Mobile Ads banner at the bottom of the doctor home, hospital home, and doctors list. Sign-in, onboarding, and shift-trade / confirm screens do not carry a banner. The checked-in IDs are Google’s test app and banner units. Replace them with the AdMob app and banner unit for publisher `ca-app-pub-8874506793712009` before a store build (see the TODO next to `GADApplicationIdentifier` and in `android/app/build.gradle.kts`).
- **iOS** asks for App Tracking Transparency before the first ad request, and `Config/PrivacyInfo.xcprivacy` declares advertising data.
- **Web:** no visible ad slots yet. `docs/ads.txt` authorizes `pub-8874506793712009`. The in-app sponsor / AdSense markup stays in the website code and stays hidden while `monetizationLive` is false.
- Banners hide for an active MD Shift+ membership once `isMonetizationLive` is turned on. Until then, native banners still show.

### 3. Hospital department SaaS (primary ARR)

- **$99/mo** or **$990/yr** per hospital / specialty department  
- Math: **10 hospitals × $990 ≈ $9,900/yr**
- Gate after a short trial; keep demo accounts free for sales
- Charge on **web** with Stripe (avoid App Store cut for B2B)

## Later / stackable

| Idea | Rough $10k math |
|------|-----------------|
| Annual “Coverage OS” at $2,000–$2,500 | 4–5 hospitals |
| Take-rate on filled shifts (1–3%) | Needs Stripe Connect |
| Verification / credentialing add-on | $50–100/mo per hospital |
| Setup fee ($500) + lower monthly | Early cash |

Avoid App Store IAP as the **hospital** billing channel. Doctor Plus may need StoreKit later if App Review requires it for in-app digital goods; v1 uses web Stripe + synced entitlement.
