#!/usr/bin/env bash
# Prove the lockdown migration on a local database.
# Does not talk to the hosted project.
#
# Preferred:
#   supabase start
#   supabase/tests/rls_lockdown_test.sh
#
# `supabase db reset --local` reapplies supabase/migrations when the CLI stack
# is already running. If the stack is not up, this script applies those same
# files with psql against DB_URL (default local Postgres on port 54322).
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

db_url="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"

if command -v supabase >/dev/null 2>&1 && supabase status >/dev/null 2>&1; then
  echo "Resetting the local database (migrations only, no hosted project)..."
  supabase db reset --local
else
  echo "Local Supabase CLI stack is not running."
  echo "Applying supabase/migrations with psql. This does not touch the hosted project."
  if ! psql "$db_url" -v ON_ERROR_STOP=1 -c "select 1" >/dev/null; then
    echo "Cannot connect to local Postgres. Start it with \`supabase start\` or the official Postgres image on port 54322." >&2
    exit 1
  fi
  applied="$(psql "$db_url" -tAc "select to_regprocedure('private.owns_hospital(uuid)') is not null")"
  if [[ "$applied" != "t" ]]; then
    for f in supabase/migrations/*.sql; do
      echo "Applying $f"
      psql "$db_url" -v ON_ERROR_STOP=1 -f "$f"
    done
  else
    echo "Lockdown helpers are already installed; skipping the lockdown file."
    if [[ "$(psql "$db_url" -tAc "select to_regclass('public.email_verification_challenges') is not null")" != "t" ]]; then
      echo "Applying supabase/migrations/20260929035000_email_verification_challenges.sql"
      psql "$db_url" -v ON_ERROR_STOP=1 -f supabase/migrations/20260929035000_email_verification_challenges.sql
    fi
  fi
fi

echo "Running RLS checks against local Postgres"
psql "$db_url" -v ON_ERROR_STOP=1 -f supabase/tests/rls_lockdown_test.sql
echo "RLS lockdown checks passed."
