#!/usr/bin/env bash
# Send a one-off test email through Resend to verify the API key + domain.
#
# Usage:
#   export RESEND_API_KEY=re_...
#   export RESEND_TEST_TO=you@example.com
#   optional: export RESEND_FROM_EMAIL=noreply@mdshift.net
#   ./scripts/test-resend-send.sh
set -euo pipefail

FROM_EMAIL="${RESEND_FROM_EMAIL:-noreply@mdshift.net}"

if [[ -z "${RESEND_API_KEY:-}" ]]; then
  echo "Missing RESEND_API_KEY" >&2
  exit 1
fi
if [[ -z "${RESEND_TEST_TO:-}" ]]; then
  echo "Missing RESEND_TEST_TO (inbox that should receive the test)" >&2
  exit 1
fi

export FROM_EMAIL
python3 <<'PY'
import json, os, urllib.request

payload = {
    "from": f"MD Shift <{os.environ['FROM_EMAIL']}>",
    "to": [os.environ["RESEND_TEST_TO"]],
    "subject": "MD Shift Resend SMTP test",
    "html": "<p>If you received this, Resend can deliver MD Shift auth email.</p><p>Sample code: <strong>482193</strong></p>",
}
req = urllib.request.Request(
    "https://api.resend.com/emails",
    data=json.dumps(payload).encode(),
    headers={
        "Authorization": f"Bearer {os.environ['RESEND_API_KEY']}",
        "Content-Type": "application/json",
    },
    method="POST",
)
try:
    with urllib.request.urlopen(req) as resp:
        d = json.load(resp)
    print("sent id:", d.get("id"))
    print("OK — check", os.environ["RESEND_TEST_TO"])
except urllib.error.HTTPError as e:
    print(e.read().decode())
    raise
PY
