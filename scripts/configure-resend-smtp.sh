#!/usr/bin/env bash
# Configure hosted Supabase Auth to send mail via Resend SMTP.
#
# Prerequisites:
#   1. Resend API key (re_...) from https://resend.com/api-keys
#   2. Verified domain in Resend (production) — or onboarding@resend.dev for self-tests
#   3. Supabase PAT from https://supabase.com/dashboard/account/tokens
#
# Usage:
#   export RESEND_API_KEY=re_...
#   export SUPABASE_ACCESS_TOKEN=sbp_...
#   optional: export RESEND_FROM_EMAIL=noreply@mdshift.net
#   optional: export RESEND_FROM_NAME="MD Shift"
#   ./scripts/configure-resend-smtp.sh
set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-yrnndfpvovuvjlzgivgu}"

if [[ -z "${RESEND_API_KEY:-}" ]]; then
  echo "Missing RESEND_API_KEY (https://resend.com/api-keys)" >&2
  exit 1
fi
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "Missing SUPABASE_ACCESS_TOKEN (https://supabase.com/dashboard/account/tokens)" >&2
  exit 1
fi

export PROJECT_REF
python3 <<'PY'
import json, os, urllib.request

payload = {
    "external_email_enabled": True,
    "mailer_autoconfirm": False,
    "mailer_secure_email_change_enabled": True,
    "smtp_admin_email": os.environ.get("RESEND_FROM_EMAIL", "noreply@mdshift.net"),
    "smtp_host": "smtp.resend.com",
    "smtp_port": "465",
    "smtp_user": "resend",
    "smtp_pass": os.environ["RESEND_API_KEY"],
    "smtp_sender_name": os.environ.get("RESEND_FROM_NAME", "MD Shift"),
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

print("smtp_host:", d.get("smtp_host"))
print("smtp_port:", d.get("smtp_port"))
print("smtp_user:", d.get("smtp_user"))
print("smtp_admin_email:", d.get("smtp_admin_email"))
print("smtp_sender_name:", d.get("smtp_sender_name"))
print("mailer_autoconfirm:", d.get("mailer_autoconfirm"))
print("OK — custom SMTP configured (password not printed).")
PY
