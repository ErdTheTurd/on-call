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
  if [[ "$(psql "$db_url" -tAc "select to_regprocedure('auth.uid()') is not null")" != "t" ]]; then
    echo "Bootstrapping a local auth schema (not the hosted project)."
    psql "$db_url" -v ON_ERROR_STOP=1 -f supabase/tests/bootstrap_local_auth.sql
  fi
  applied="$(psql "$db_url" -tAc "select to_regprocedure('private.owns_hospital(uuid)') is not null")"
  if [[ "$applied" != "t" ]]; then
    for f in supabase/migrations/*.sql; do
      echo "Applying $f"
      psql "$db_url" -v ON_ERROR_STOP=1 -f "$f"
    done
  else
    echo "Lockdown helpers are already installed; skipping files that are already present."
    if [[ "$(psql "$db_url" -tAc "select to_regclass('public.email_verification_challenges') is not null")" != "t" ]]; then
      echo "Applying supabase/migrations/20260929035000_email_verification_challenges.sql"
      psql "$db_url" -v ON_ERROR_STOP=1 -f supabase/migrations/20260929035000_email_verification_challenges.sql
    fi
    if [[ "$(psql "$db_url" -tAc "select to_regprocedure('public.reserve_verification_send(uuid,text,text,integer,integer,integer,integer,integer)') is not null")" != "t" ]]; then
      echo "Applying supabase/migrations/20260929160000_review_findings.sql"
      psql "$db_url" -v ON_ERROR_STOP=1 -f supabase/migrations/20260929160000_review_findings.sql
    fi
  fi
fi

echo "Running RLS checks against local Postgres"
psql "$db_url" -v ON_ERROR_STOP=1 -f supabase/tests/rls_lockdown_test.sql

echo "Running parallel attempt and send-limit checks"
race_user="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
psql "$db_url" -v ON_ERROR_STOP=1 <<SQL
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token, email_change
) values (
  '00000000-0000-0000-0000-000000000000', '${race_user}', 'authenticated', 'authenticated',
  'race@example.com', '', now(), '{}', '{}', now(), now(), '', '', '', ''
) on conflict (id) do nothing;
delete from public.email_verification_challenges
  where user_id = '${race_user}' and email = 'race-attempt@example.com';
insert into public.email_verification_challenges (user_id, email, code_hash, expires_at, attempts)
values ('${race_user}', 'race-attempt@example.com', 'race-hash', now() + interval '10 minutes', 0);
delete from public.email_verification_email_windows where email = 'race-send@example.com';
delete from public.email_verification_user_windows where user_id = '${race_user}';
delete from public.email_verification_ip_windows where ip_hash = 'race-ip';
SQL

for i in $(seq 1 10); do
  psql "$db_url" -v ON_ERROR_STOP=1 -c \
    "select code_hash from public.consume_email_attempt('${race_user}', 'race-attempt@example.com', 5)" \
    >/tmp/consume_"$i".out &
done
wait

attempts="$(psql "$db_url" -tAc "select attempts from public.email_verification_challenges where user_id = '${race_user}' and email = 'race-attempt@example.com'")"
if [[ "$attempts" != "5" ]]; then
  echo "Parallel guesses did not all count (attempts=${attempts})" >&2
  exit 1
fi

for i in $(seq 1 8); do
  psql "$db_url" -v ON_ERROR_STOP=1 -c \
    "select public.reserve_verification_send('${race_user}'::uuid, 'race-send@example.com', 'race-ip', 3, 20, 20, 3600, 0)" \
    >/tmp/reserve_"$i".out &
done
wait

sends="$(psql "$db_url" -tAc "select send_count from public.email_verification_email_windows where email = 'race-send@example.com'")"
if [[ "$sends" != "3" ]]; then
  echo "Parallel sends exceeded the per-email limit (send_count=${sends})" >&2
  exit 1
fi

psql "$db_url" -v ON_ERROR_STOP=1 -c \
  "delete from public.email_verification_challenges where user_id = '${race_user}';
   delete from auth.users where id = '${race_user}';
   delete from public.email_verification_email_windows where email in ('race-send@example.com');
   delete from public.email_verification_user_windows where user_id = '${race_user}';
   delete from public.email_verification_ip_windows where ip_hash = 'race-ip';"

echo "RLS lockdown checks passed."
