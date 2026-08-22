# Create App Store profile (no iPhone)

Your **Apple Distribution** certificate is already on this Mac. Archive still fails because there is **no provisioning profile** yet. App Store profiles do **not** need a device.

## Do this once (≈3 minutes)

1. Open: https://developer.apple.com/account/resources/profiles/add  
   (Sign in with the same Apple ID as Xcode team **8LVD2L956K**.)

2. Select **App Store Connect** → Continue.

3. App ID: **com.eporthospine.mdshift**  
   - If missing: create it under Identifiers first (App → bundle id `com.eporthospine.mdshift`).  
   - Enable **Sign In with Apple** and **Associated Domains** to match the app entitlements.

4. Certificate: **Apple Distribution: Edward Dunn (8LVD2L956K)** → Continue.

5. Profile name (must match exactly):

   ```
   MD Shift App Store
   ```

6. Generate → **Download** → double-click the `.mobileprovision` file (installs into Xcode).

7. In Xcode: destination **Any iOS Device (arm64)** → **Product → Archive** (not the Play button).

## After the profile is installed

Tell me “profile done” and I’ll run the archive again from here.

## Optional shortcut (still no phone you own)

If you only want Automatic signing for Debug: register any friend’s iPhone UDID under  
https://developer.apple.com/account/resources/devices/list  
That is **not** required for App Store upload once the profile above exists.
