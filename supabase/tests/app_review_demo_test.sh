#!/usr/bin/env bash
# Apply migrations, prove the existing lockdown still holds, then load the
# App Review seed twice and prove the demo access rules.
# Uses a throwaway local database. Does not talk to the hosted project.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

db_name="${DB_NAME:-mdshift_review}"

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is not installed." >&2
  exit 1
fi

echo "Recreating local database ${db_name}"
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '${db_name}' and pid <> pg_backend_pid();" >/dev/null
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "drop database if exists ${db_name};"
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "create database ${db_name};"

psql_db() {
  sudo -u postgres psql -d "$db_name" -v ON_ERROR_STOP=1 "$@"
}

echo "Bootstrapping local auth"
psql_db -f supabase/tests/bootstrap_local_auth.sql

for f in supabase/migrations/*.sql; do
  echo "Applying $f"
  psql_db -f "$f"
done

echo "Running existing lockdown checks"
psql_db -f supabase/tests/rls_lockdown_test.sql

echo "Seeding App Review preconditions"
psql_db -f supabase/tests/app_review_preconditions.sql

echo "Applying App Review seed"
psql_db -f supabase/seed/app_review_demo.sql

echo "Applying App Review seed again"
psql_db -f supabase/seed/app_review_demo.sql

echo "Proving demo access rules"
psql_db -f supabase/tests/app_review_access_test.sql

echo "App Review database checks passed"
