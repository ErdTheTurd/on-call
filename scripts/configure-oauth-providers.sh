#!/usr/bin/env bash
# Enable Google and/or Apple on the hosted Supabase project.
#
# You must create the OAuth apps first (see supabase/AUTH_SETUP.md), then:
#
#   export SUPABASE_ACCESS_TOKEN=sbp_...
#   export GOOGLE_CLIENT_ID=....apps.googleusercontent.com
#   export GOOGLE_CLIENT_SECRET=...
#   export APPLE_CLIENT_ID=...          # Services ID
#   export APPLE_SECRET=...             # generated JWT secret
#   ./scripts/configure-oauth-providers.sh
set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-yrnndfpvovuvjlzgivgu}"

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "Missing SUPABASE_ACCESS_TOKEN" >&2
  exit 1
fi

python3 <<'PY'
import json, os, urllib.request

payload = {}
if os.environ.get("GOOGLE_CLIENT_ID") and os.environ.get("GOOGLE_CLIENT_SECRET"):
    payload.update({
        "external_google_enabled": True,
        "external_google_client_id": os.environ["GOOGLE_CLIENT_ID"],
        "external_google_secret": os.environ["GOOGLE_CLIENT_SECRET"],
    })
if os.environ.get("APPLE_CLIENT_ID") and os.environ.get("APPLE_SECRET"):
    payload.update({
        "external_apple_enabled": True,
        "external_apple_client_id": os.environ["APPLE_CLIENT_ID"],
        "external_apple_secret": os.environ["APPLE_SECRET"],
    })

if not payload:
    raise SystemExit("Set GOOGLE_CLIENT_ID/SECRET and/or APPLE_CLIENT_ID/SECRET")

ref = os.environ.get("SUPABASE_PROJECT_REF", "yrnndfpvovuvjlzgivgu")
# Write body for curl (urllib often blocked with 403 on this API)
path = "/tmp/mdshift-oauth.json"
open(path, "w").write(json.dumps(payload))
print(path)
print("fields:", ", ".join(sorted(payload)))
PY

BODY_FILE=/tmp/mdshift-oauth.json
curl -sS -o /tmp/mdshift-oauth-out.json -w "HTTP:%{http_code}\n" -X PATCH \
  "https://api.supabase.com/v1/projects/${PROJECT_REF}/config/auth" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary @"$BODY_FILE"

python3 - <<'PY'
import json
from pathlib import Path
d = json.loads(Path("/tmp/mdshift-oauth-out.json").read_text())
print("google_enabled:", d.get("external_google_enabled"))
print("apple_enabled:", d.get("external_apple_enabled"))
if d.get("message"):
    print("message:", d.get("message"))
PY
rm -f /tmp/mdshift-oauth.json
