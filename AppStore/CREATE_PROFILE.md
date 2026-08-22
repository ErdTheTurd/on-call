# Create App Store profile (no iPhone)

Archive fails with Automatic signing when the team has **no registered devices**, because Xcode tries to build a *Development* profile. An **App Store** profile does **not** need a device.

## Do this once (≈3 minutes)

1. Open: https://developer.apple.com/account/resources/profiles/add  
   (Sign in with the same Apple ID as Xcode team **8LVD2L956K**.)

2. Select **App Store Connect** → Continue.

3. App ID: **com.eporthospine.mdshift**  
   - If missing: create it under Identifiers first (App → bundle id `com.eporthospine.mdshift`).  
   - Enable **Sign In with Apple** and **Associated Domains** to match the app entitlements.

4. Certificate: **Apple Distribution: Edward Dunn (8LVD2L956K)** → Continue.  
   If you have no Distribution cert yet: Xcode → Settings → Accounts → Manage Certificates → **+** → Apple Distribution.

5. Profile name (must match exactly):

   ```
   MD Shift App Store
   ```

6. Generate → **Download** → double-click the `.mobileprovision` file (installs into Xcode).

7. In Xcode: destination **Any iOS Device (arm64)** → **Product → Archive**.

Release builds in this project already use Manual signing with that profile name.
