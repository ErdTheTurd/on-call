# On Call Wizard

iOS app for on-call scheduling with a Supabase backend (Postgres, Auth, Edge Functions).

## Prerequisites

| Tool | Version tested | Purpose |
|------|----------------|---------|
| **Xcode** | 26.6+ | Build and run the iOS app |
| **Docker Desktop** | Latest | Local Supabase stack (`supabase start`) |
| **Supabase CLI** | 2.111+ | Migrations, local dev, edge functions |

## Quick start

### 1. Configure secrets

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Edit `Config/Secrets.xcconfig`:

- **Local Supabase** (after step 2): use `http:/$()/127.0.0.1:54321` and the default local anon key (see example in `Secrets.xcconfig`).
- **Remote Supabase**: paste your project URL and anon key from the [Supabase dashboard](https://supabase.com/dashboard).

`Secrets.xcconfig` is gitignored and wired into the Xcode project via `INFOPLIST_KEY_*` entries.

### 2. Start the backend (optional)

Requires Docker Desktop running.

```bash
./scripts/bin/supabase start    # first run pulls containers (~2–5 min)
./scripts/bin/supabase status   # API URL, anon key, Studio URL
```

Migrations in `supabase/migrations/` are applied automatically on start.

- **API**: http://127.0.0.1:54321  
- **Studio**: http://127.0.0.1:54323  
- **DB**: postgresql://postgres:postgres@127.0.0.1:54322/postgres  

Stop the stack:

```bash
./scripts/bin/supabase stop
```

### 3. Build and run the iOS app

**Xcode:** open `on-call wizard.xcodeproj`, select an iPhone simulator, press Run (⌘R).

**CLI:**

```bash
xcodebuild -scheme "on-call wizard" \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -configuration Debug build

# Install & launch (replace SIM_ID with your simulator UUID from `xcrun simctl list`)
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/on-call_wizard-*/Build/Products/Debug-iphonesimulator/on-call\ wizard.app
xcrun simctl launch booted callsystems.on-call-wizard
```

The app runs without Supabase for UI development (local auth/onboarding). Supabase is required for cloud sync, edge functions, and production auth.

## Website companion (GitHub Pages)

The `docs/` folder is a web companion that shares the same Supabase project as the iOS app.

### 1. Configure the website

```bash
cp docs/assets/js/config.example.js docs/assets/js/config.js
```

Set `supabaseUrl` and `supabaseAnonKey` to the **same values** as `Config/Secrets.xcconfig`.

### 2. Enable GitHub Pages

In GitHub → **Settings → Pages**, set **Source** to **Deploy from branch**, branch **main**, folder **/docs**.

The site will be available at:

**https://erdtheturd.github.io/on-call/**

### 3. Configure Supabase Auth redirects

In your Supabase project dashboard → **Authentication → URL Configuration**, set:

- **Site URL**: `https://erdtheturd.github.io/on-call`
- **Redirect URLs**: `https://erdtheturd.github.io/on-call/callback.html`

These match `supabase/config.toml` for local development.

### 4. Universal Links (optional)

Replace `TEAMID` in `docs/.well-known/apple-app-site-association` with your Apple Team ID, then rebuild the iOS app. The app also supports the custom URL scheme `oncallwizard://`.

## Project layout

```
docs/                    GitHub Pages website (landing, auth, dashboard)
on-call wizard/          SwiftUI iOS app
supabase/
  migrations/            Database schema
  functions/             Edge functions (accept-shift, cancel-shift, trades, notifications)
Config/
  Secrets.example.xcconfig
  Secrets.xcconfig       Local secrets (gitignored)
  OnCallWizard.entitlements
scripts/bin/supabase     Bundled Supabase CLI (macOS arm64)
```

## Edge functions

Deploy to a linked remote project:

```bash
./scripts/bin/supabase link --project-ref YOUR_PROJECT_REF
./scripts/bin/supabase functions deploy
```

## Troubleshooting

- **Simulator not found**: list devices with `xcrun simctl list devices available` and pick one from the output (e.g. `iPhone 17`).
- **`supabase start` fails**: install [Docker Desktop](https://www.docker.com/products/docker-desktop/) and ensure it is running.
- **Supabase not configured in app**: confirm `Config/Secrets.xcconfig` exists and rebuild; check `SupabaseConfig.isConfigured` reads non-empty `SUPABASE_URL` / `SUPABASE_ANON_KEY` in the built Info.plist.
