#!/usr/bin/env bash
# Push the 6-digit OTP Confirm signup template to hosted Supabase Auth.
#
# Usage:
#   export SUPABASE_ACCESS_TOKEN=sbp_...
#   ./scripts/configure-otp-email-template.sh
set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-yrnndfpvovuvjlzgivgu}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PROJECT_REF
export TEMPLATE_FILE="${ROOT}/supabase/templates/confirmation.html"

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "Missing SUPABASE_ACCESS_TOKEN" >&2
  exit 1
fi
if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Missing template: $TEMPLATE_FILE" >&2
  exit 1
fi

python3 <<'PY'
import json, os, urllib.request
from pathlib import Path

content = Path(os.environ["TEMPLATE_FILE"]).read_text()
payload = {
    "mailer_subjects_confirmation": "Your MD Shift verification code",
    "mailer_templates_confirmation": content,
}
ref = os.environ["PROJECT_REF"]
req = urllib.request.Request(
    f"https://api.supabase.com/v1/projects/{ref}/config/auth",
    data=json.dumps(payload).encode(),
    headers={
        "Authorization": f"Bearer {os.environ['SUPABASE_ACCESS_TOKEN']}",
        "Content-Type": "application/json",
    },
    method="PATCH",
)
with urllib.request.urlopen(req) as resp:
    d = json.load(resp)

subj = d.get("mailer_subjects_confirmation")
body = d.get("mailer_templates_confirmation") or ""
print("confirmation subject:", subj)
print("template contains {{ .Token }}:", "{{ .Token }}" in body)
print("OK — confirm signup template updated.")
PY
