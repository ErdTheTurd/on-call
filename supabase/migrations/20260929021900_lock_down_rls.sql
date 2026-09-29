-- Lock down public data so the anon key cannot read or change patient-adjacent
-- professional records, and signed-in users only see rows they are part of.
--
-- Admins are profiles.is_admin = true, set by hand in the SQL editor
-- (see 003_admin_approvals.sql). public.is_admin() is the check.
-- Nothing in this migration is applied to the hosted project by itself.

-- ---------------------------------------------------------------------------
-- Helpers. Kept out of the Data API schema so they are not RPC endpoints.
-- security definer so policies can read ownership without recursing through RLS.
-- ---------------------------------------------------------------------------

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to postgres, service_role, authenticated;

create or replace function private.owns_hospital(target uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.hospital_profiles hp
    where hp.id = target
      and hp.profile_id = auth.uid()
  );
$$;

create or replace function private.is_doctor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.doctor_profiles d
    where d.profile_id = auth.uid()
  );
$$;

revoke all on function private.owns_hospital(uuid) from public, anon;
revoke all on function private.is_doctor() from public, anon;
grant execute on function private.owns_hospital(uuid) to authenticated;
grant execute on function private.is_doctor() to authenticated;

-- is_admin() already exists. Make sure the public anon key cannot call it.
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- Stop clients from promoting themselves to admin or flipping Plus / Stripe
-- fields. The SQL editor (no JWT) and the service role (webhooks) still can.
-- Plus columns are optional; to_jsonb ignores them until that migration exists.
-- ---------------------------------------------------------------------------

create or replace function private.guard_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  db_admin boolean;
begin
  db_admin := auth.role() = 'service_role'
    or (
      auth.uid() is null
      and coalesce(auth.role(), '') not in ('anon', 'authenticated')
    );

  if db_admin then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if coalesce(new.is_admin, false) then
      raise exception 'not allowed to grant admin status';
    end if;
    if to_jsonb(new) ? 'plus_active'
       and coalesce(to_jsonb(new)->>'plus_active', 'false') not in ('false', '') then
      raise exception 'not allowed to grant billing status';
    end if;
    if to_jsonb(new) ? 'plus_until'
       and nullif(to_jsonb(new)->>'plus_until', '') is not null then
      raise exception 'not allowed to grant billing status';
    end if;
    if to_jsonb(new) ? 'stripe_customer_id'
       and nullif(to_jsonb(new)->>'stripe_customer_id', '') is not null then
      raise exception 'not allowed to set billing identifiers';
    end if;
    if to_jsonb(new) ? 'stripe_subscription_id'
       and nullif(to_jsonb(new)->>'stripe_subscription_id', '') is not null then
      raise exception 'not allowed to set billing identifiers';
    end if;
    return new;
  end if;

  if new.is_admin is distinct from old.is_admin then
    raise exception 'not allowed to change admin status';
  end if;
  if to_jsonb(new) ? 'plus_active'
     and (to_jsonb(new)->'plus_active') is distinct from (to_jsonb(old)->'plus_active') then
    raise exception 'not allowed to change billing status';
  end if;
  if to_jsonb(new) ? 'plus_until'
     and (to_jsonb(new)->'plus_until') is distinct from (to_jsonb(old)->'plus_until') then
    raise exception 'not allowed to change billing status';
  end if;
  if to_jsonb(new) ? 'stripe_customer_id'
     and (to_jsonb(new)->'stripe_customer_id') is distinct from (to_jsonb(old)->'stripe_customer_id') then
    raise exception 'not allowed to set billing identifiers';
  end if;
  if to_jsonb(new) ? 'stripe_subscription_id'
     and (to_jsonb(new)->'stripe_subscription_id') is distinct from (to_jsonb(old)->'stripe_subscription_id') then
    raise exception 'not allowed to set billing identifiers';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_profile_privileges() from public, anon;
grant execute on function private.guard_profile_privileges() to authenticated;

drop trigger if exists profiles_guard_privileges on public.profiles;
create trigger profiles_guard_privileges
  before insert or update on public.profiles
  for each row execute function private.guard_profile_privileges();

-- Owners may edit their own application, but only an admin (or the service
-- role / SQL editor) may mark it verified, waitlisted, or rejected.
create or replace function private.guard_verification_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  reviewer boolean;
begin
  reviewer := public.is_admin()
    or auth.role() = 'service_role'
    or (
      auth.uid() is null
      and coalesce(auth.role(), '') not in ('anon', 'authenticated')
    );

  if reviewer then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.verification_status::text in ('verified', 'waitlisted', 'rejected') then
      new.verification_status := 'pending';
    end if;
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.review_note := null;
    return new;
  end if;

  new.verification_status := old.verification_status;
  new.reviewed_at := old.reviewed_at;
  new.reviewed_by := old.reviewed_by;
  new.review_note := old.review_note;
  return new;
end;
$$;

revoke all on function private.guard_verification_review() from public, anon;
grant execute on function private.guard_verification_review() to authenticated;

drop trigger if exists doctor_profiles_guard_review on public.doctor_profiles;
create trigger doctor_profiles_guard_review
  before insert or update on public.doctor_profiles
  for each row execute function private.guard_verification_review();

drop trigger if exists hospital_profiles_guard_review on public.hospital_profiles;
create trigger hospital_profiles_guard_review
  before insert or update on public.hospital_profiles
  for each row execute function private.guard_verification_review();

-- ---------------------------------------------------------------------------
-- Savings ledger used by the hospital card and the admin dashboard.
-- Created here when missing so a fresh database matches the app. If the live
-- table already exists, this does not rewrite its columns.
-- ---------------------------------------------------------------------------

create table if not exists public.hospital_savings_events (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  hospital_id uuid not null references public.hospital_profiles(id) on delete cascade,
  hospital_name text,
  shift_id uuid,
  specialty text,
  kind text not null,
  amount numeric not null,
  occurred_at timestamptz not null default now(),
  source text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id) on delete set null
);

alter table public.hospital_savings_events enable row level security;

-- ---------------------------------------------------------------------------
-- Drop the open policies from 002 / 003. profiles_admin_read stays.
-- ---------------------------------------------------------------------------

drop policy if exists "profiles_own" on public.profiles;

drop policy if exists "doctor_profiles_all" on public.doctor_profiles;
drop policy if exists "doctor_profiles_admin_review" on public.doctor_profiles;

drop policy if exists "hospital_profiles_all" on public.hospital_profiles;
drop policy if exists "hospital_profiles_admin_review" on public.hospital_profiles;

drop policy if exists "shifts_read" on public.shifts;
drop policy if exists "shifts_all" on public.shifts;

drop policy if exists "assignments_own" on public.assignments;
drop policy if exists "assignments_all" on public.assignments;

drop policy if exists "token_requests_all" on public.token_requests;
drop policy if exists "trade_requests_all" on public.trade_requests;
drop policy if exists "unavailable_days_all" on public.unavailable_days;
drop policy if exists "scheduling_policies_all" on public.scheduling_policies;
drop policy if exists "hospital_doctors_all" on public.hospital_doctors;
drop policy if exists "penalty_ledger_all" on public.penalty_ledger;
drop policy if exists "doctor_points_own" on public.doctor_points;
drop policy if exists "doctor_tokens_own" on public.doctor_tokens;
drop policy if exists "doctor_preferences_own" on public.doctor_preferences;
drop policy if exists "proposed_rates_all" on public.proposed_rates;

do $$
declare
  pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'hospital_savings_events'
  loop
    execute format('drop policy if exists %I on public.hospital_savings_events', pol.policyname);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- profiles: your row, plus admin read of every row (review queue).
-- ---------------------------------------------------------------------------

create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- Full credential rows: the owner and admins only.
-- Hospitals and other doctors use the views below (name, credential, specialty).
-- ---------------------------------------------------------------------------

create policy "doctor_profiles_select" on public.doctor_profiles
  for select using (auth.uid() = profile_id or public.is_admin());

create policy "doctor_profiles_insert" on public.doctor_profiles
  for insert with check (auth.uid() = profile_id or public.is_admin());

create policy "doctor_profiles_update" on public.doctor_profiles
  for update
  using (auth.uid() = profile_id or public.is_admin())
  with check (auth.uid() = profile_id or public.is_admin());

create policy "hospital_profiles_select" on public.hospital_profiles
  for select using (auth.uid() = profile_id or public.is_admin());

create policy "hospital_profiles_insert" on public.hospital_profiles
  for insert with check (auth.uid() = profile_id or public.is_admin());

create policy "hospital_profiles_update" on public.hospital_profiles
  for update
  using (auth.uid() = profile_id or public.is_admin())
  with check (auth.uid() = profile_id or public.is_admin());

-- ---------------------------------------------------------------------------
-- Roster links. A doctor may add themselves with auto-approve off.
-- Only the hospital (or an admin) may turn auto-approve on.
-- ---------------------------------------------------------------------------

create policy "hospital_doctors_select" on public.hospital_doctors
  for select using (
    public.is_admin()
    or doctor_id = auth.uid()
    or private.owns_hospital(hospital_id)
  );

create policy "hospital_doctors_insert" on public.hospital_doctors
  for insert with check (
    public.is_admin()
    or private.owns_hospital(hospital_id)
    or (doctor_id = auth.uid() and auto_approve = false)
  );

create policy "hospital_doctors_update" on public.hospital_doctors
  for update
  using (public.is_admin() or private.owns_hospital(hospital_id))
  with check (public.is_admin() or private.owns_hospital(hospital_id));

create policy "hospital_doctors_delete" on public.hospital_doctors
  for delete using (public.is_admin() or private.owns_hospital(hospital_id));

-- ---------------------------------------------------------------------------
-- Shifts: any signed-in doctor can read the open board. Writes belong to the
-- hospital that owns the row, or an admin.
-- ---------------------------------------------------------------------------

create policy "shifts_select" on public.shifts
  for select using (
    public.is_admin()
    or private.is_doctor()
    or private.owns_hospital(hospital_id)
  );

create policy "shifts_insert" on public.shifts
  for insert with check (public.is_admin() or private.owns_hospital(hospital_id));

create policy "shifts_update" on public.shifts
  for update
  using (public.is_admin() or private.owns_hospital(hospital_id))
  with check (public.is_admin() or private.owns_hospital(hospital_id));

create policy "shifts_delete" on public.shifts
  for delete using (public.is_admin() or private.owns_hospital(hospital_id));

-- ---------------------------------------------------------------------------
-- Assignments, tokens, trades, penalties: the doctor on the row, the hospital
-- that owns the shift / request, and admins.
-- ---------------------------------------------------------------------------

create policy "assignments_select" on public.assignments
  for select using (
    public.is_admin()
    or doctor_id = auth.uid()
    or private.owns_hospital((select s.hospital_id from public.shifts s where s.id = shift_id))
  );

create policy "assignments_insert" on public.assignments
  for insert with check (
    public.is_admin()
    or doctor_id = auth.uid()
    or private.owns_hospital((select s.hospital_id from public.shifts s where s.id = shift_id))
  );

create policy "assignments_update" on public.assignments
  for update
  using (
    public.is_admin()
    or doctor_id = auth.uid()
    or private.owns_hospital((select s.hospital_id from public.shifts s where s.id = shift_id))
  )
  with check (
    public.is_admin()
    or doctor_id = auth.uid()
    or private.owns_hospital((select s.hospital_id from public.shifts s where s.id = shift_id))
  );

create policy "token_requests_select" on public.token_requests
  for select using (
    public.is_admin()
    or doctor_id = auth.uid()
    or private.owns_hospital(hospital_id)
  );

create policy "token_requests_insert" on public.token_requests
  for insert with check (
    public.is_admin()
    or doctor_id = auth.uid()
    or private.owns_hospital(hospital_id)
  );

create policy "token_requests_update" on public.token_requests
  for update
  using (
    public.is_admin()
    or doctor_id = auth.uid()
    or private.owns_hospital(hospital_id)
  )
  with check (
    public.is_admin()
    or doctor_id = auth.uid()
    or private.owns_hospital(hospital_id)
  );

create policy "token_requests_delete" on public.token_requests
  for delete using (
    public.is_admin()
    or doctor_id = auth.uid()
    or private.owns_hospital(hospital_id)
  );

create policy "trade_requests_select" on public.trade_requests
  for select using (
    public.is_admin()
    or from_doctor_id = auth.uid()
    or to_doctor_id = auth.uid()
    or private.owns_hospital((select s.hospital_id from public.shifts s where s.id = shift_id))
  );

create policy "trade_requests_insert" on public.trade_requests
  for insert with check (
    public.is_admin()
    or from_doctor_id = auth.uid()
    or private.owns_hospital((select s.hospital_id from public.shifts s where s.id = shift_id))
  );

create policy "trade_requests_update" on public.trade_requests
  for update
  using (
    public.is_admin()
    or from_doctor_id = auth.uid()
    or to_doctor_id = auth.uid()
    or private.owns_hospital((select s.hospital_id from public.shifts s where s.id = shift_id))
  )
  with check (
    public.is_admin()
    or from_doctor_id = auth.uid()
    or to_doctor_id = auth.uid()
    or private.owns_hospital((select s.hospital_id from public.shifts s where s.id = shift_id))
  );

create policy "penalty_ledger_select" on public.penalty_ledger
  for select using (
    public.is_admin()
    or doctor_id = auth.uid()
    or private.owns_hospital(hospital_id)
  );

create policy "penalty_ledger_insert" on public.penalty_ledger
  for insert with check (
    public.is_admin()
    or private.owns_hospital(hospital_id)
    or doctor_id = auth.uid()
  );

-- Hospital-only scheduling settings.
create policy "unavailable_days_all" on public.unavailable_days
  for all
  using (public.is_admin() or private.owns_hospital(hospital_id))
  with check (public.is_admin() or private.owns_hospital(hospital_id));

create policy "scheduling_policies_all" on public.scheduling_policies
  for all
  using (public.is_admin() or private.owns_hospital(hospital_id))
  with check (public.is_admin() or private.owns_hospital(hospital_id));

create policy "proposed_rates_all" on public.proposed_rates
  for all
  using (public.is_admin() or private.owns_hospital(hospital_id))
  with check (public.is_admin() or private.owns_hospital(hospital_id));

-- Personal doctor backups. Not shared with the hospital.
create policy "doctor_points_own" on public.doctor_points
  for all
  using (public.is_admin() or doctor_id = auth.uid())
  with check (doctor_id = auth.uid() or public.is_admin());

create policy "doctor_tokens_own" on public.doctor_tokens
  for all
  using (public.is_admin() or doctor_id = auth.uid())
  with check (doctor_id = auth.uid() or public.is_admin());

create policy "doctor_preferences_own" on public.doctor_preferences
  for all
  using (public.is_admin() or doctor_id = auth.uid())
  with check (doctor_id = auth.uid() or public.is_admin());

create policy "hospital_savings_select" on public.hospital_savings_events
  for select using (public.is_admin() or private.owns_hospital(hospital_id));

create policy "hospital_savings_insert" on public.hospital_savings_events
  for insert with check (
    public.is_admin()
    or private.owns_hospital(hospital_id)
    or (created_by = auth.uid() and private.is_doctor())
  );

create policy "hospital_savings_update" on public.hospital_savings_events
  for update
  using (
    public.is_admin()
    or private.owns_hospital(hospital_id)
    or created_by = auth.uid()
  )
  with check (
    public.is_admin()
    or private.owns_hospital(hospital_id)
    or (created_by = auth.uid() and private.is_doctor())
  );

-- ---------------------------------------------------------------------------
-- Safe directory. security_barrier view runs as the owner and bypasses RLS on
-- the base tables, so it must not include NPI, license, DEA, or email.
-- ---------------------------------------------------------------------------

create or replace view public.doctor_directory
with (security_barrier = true, security_invoker = false) as
select
  d.profile_id,
  d.first_name,
  d.last_name,
  d.credential,
  d.specialties,
  d.verification_status
from public.doctor_profiles d
where public.is_admin()
   or d.profile_id = auth.uid()
   or exists (
        select 1
        from public.hospital_doctors hd
        join public.hospital_profiles hp on hp.id = hd.hospital_id
        where hd.doctor_id = d.profile_id
          and hp.profile_id = auth.uid()
      )
   or exists (
        select 1
        from public.hospital_doctors mine
        join public.hospital_doctors theirs on theirs.hospital_id = mine.hospital_id
        where mine.doctor_id = auth.uid()
          and theirs.doctor_id = d.profile_id
      )
   or exists (
        select 1
        from public.trade_requests tr
        where (tr.from_doctor_id = auth.uid() and tr.to_doctor_id = d.profile_id)
           or (tr.to_doctor_id = auth.uid() and tr.from_doctor_id = d.profile_id)
      );

create or replace view public.hospital_roster
with (security_barrier = true, security_invoker = false) as
select
  hd.hospital_id,
  hd.doctor_id,
  hd.auto_approve,
  d.first_name,
  d.last_name,
  d.credential,
  d.specialties,
  d.verification_status
from public.hospital_doctors hd
join public.doctor_profiles d on d.profile_id = hd.doctor_id
where public.is_admin()
   or exists (
        select 1
        from public.hospital_profiles hp
        where hp.id = hd.hospital_id
          and hp.profile_id = auth.uid()
      )
   or exists (
        select 1
        from public.hospital_doctors mine
        where mine.hospital_id = hd.hospital_id
          and mine.doctor_id = auth.uid()
      );

comment on view public.doctor_directory is
  'Name, credential, specialty, and verification only. No NPI, license, DEA, or email.';

comment on view public.hospital_roster is
  'Hospital roster cards. Same safe columns as doctor_directory, plus auto-approve.';

-- ---------------------------------------------------------------------------
-- Grants. The anon key is public in the website. It keeps no access to these
-- tables. Signed-in users keep the commands the app uses; RLS filters rows.
-- ---------------------------------------------------------------------------

revoke all on all tables in schema public from anon, public;

grant select, insert, update on public.profiles to authenticated;
grant select, insert, update on public.doctor_profiles to authenticated;
grant select, insert, update on public.hospital_profiles to authenticated;

grant select, insert, update, delete on public.hospital_doctors to authenticated;
grant select, insert, update, delete on public.shifts to authenticated;
grant select, insert, update on public.assignments to authenticated;
grant select, insert, update, delete on public.unavailable_days to authenticated;
grant select, insert, update, delete on public.scheduling_policies to authenticated;
grant select, insert, update, delete on public.token_requests to authenticated;
grant select, insert, update on public.trade_requests to authenticated;
grant select, insert on public.penalty_ledger to authenticated;
grant select, insert, update on public.doctor_points to authenticated;
grant select, insert, update on public.doctor_tokens to authenticated;
grant select, insert, update on public.doctor_preferences to authenticated;
grant select, insert, update, delete on public.proposed_rates to authenticated;
grant select, insert, update on public.hospital_savings_events to authenticated;

grant select on public.doctor_directory to authenticated;
grant select on public.hospital_roster to authenticated;

revoke all on public.doctor_directory from anon, public;
revoke all on public.hospital_roster from anon, public;

grant all on public.hospital_savings_events to service_role;
grant select on public.doctor_directory to service_role;
grant select on public.hospital_roster to service_role;

-- Future tables created by the migration role should not be handed to anon.
alter default privileges in schema public revoke all on tables from anon, public;
