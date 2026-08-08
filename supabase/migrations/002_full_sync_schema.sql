-- Expand schema for full web ↔ iOS sync
-- Safe to run on top of 001_initial_schema.sql

-- Extra doctor profile fields used by the iOS app
alter table doctor_profiles
  add column if not exists dea_number text default '',
  add column if not exists license_number text default '',
  add column if not exists license_state text default '',
  add column if not exists email text,
  add column if not exists verification_flags text[] default '{}',
  add column if not exists npi_registry_name text,
  add column if not exists npi_taxonomy text;

alter table hospital_profiles
  add column if not exists email text,
  add column if not exists verification_flags text[] default '{}',
  add column if not exists npi_registry_name text;

-- Points / local gamification optional cloud backup
create table if not exists doctor_points (
  doctor_id uuid primary key references doctor_profiles(profile_id) on delete cascade,
  total_points int not null default 0,
  current_streak int not null default 0,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now()
);

create table if not exists doctor_tokens (
  doctor_id uuid primary key references doctor_profiles(profile_id) on delete cascade,
  tokens_remaining int not null default 3,
  daily_limit int not null default 3,
  last_reset_date date not null default current_date,
  updated_at timestamptz default now()
);

-- Preferential filters (optional sync)
create table if not exists doctor_preferences (
  doctor_id uuid primary key references doctor_profiles(profile_id) on delete cascade,
  prefs jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now()
);

-- Proposed rate overrides
create table if not exists proposed_rates (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references hospital_profiles(id) on delete cascade,
  specialty text not null,
  date date not null,
  rate numeric not null,
  unique (hospital_id, specialty, date)
);

alter table doctor_points enable row level security;
alter table doctor_tokens enable row level security;
alter table doctor_preferences enable row level security;
alter table proposed_rates enable row level security;
alter table doctor_profiles enable row level security;
alter table hospital_profiles enable row level security;
alter table hospital_doctors enable row level security;
alter table penalty_ledger enable row level security;

-- Broad authenticated policies for MVP shared sync
-- (tighten before production)

drop policy if exists "profiles_own" on profiles;
create policy "profiles_own" on profiles for all
  using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "doctor_profiles_all" on doctor_profiles;
create policy "doctor_profiles_all" on doctor_profiles for all
  using (true) with check (auth.uid() = profile_id or exists (
    select 1 from profiles p where p.id = auth.uid() and p.role = 'hospital'
  ));

drop policy if exists "hospital_profiles_all" on hospital_profiles;
create policy "hospital_profiles_all" on hospital_profiles for all
  using (true) with check (auth.uid() = profile_id or exists (
    select 1 from profiles p where p.id = auth.uid()
  ));

drop policy if exists "shifts_read" on shifts;
drop policy if exists "shifts_all" on shifts;
create policy "shifts_all" on shifts for all using (true) with check (true);

drop policy if exists "assignments_own" on assignments;
drop policy if exists "assignments_all" on assignments;
create policy "assignments_all" on assignments for all using (true) with check (true);

drop policy if exists "token_requests_all" on token_requests;
create policy "token_requests_all" on token_requests for all using (true) with check (true);

drop policy if exists "trade_requests_all" on trade_requests;
create policy "trade_requests_all" on trade_requests for all using (true) with check (true);

drop policy if exists "unavailable_days_all" on unavailable_days;
create policy "unavailable_days_all" on unavailable_days for all using (true) with check (true);

drop policy if exists "scheduling_policies_all" on scheduling_policies;
create policy "scheduling_policies_all" on scheduling_policies for all using (true) with check (true);

drop policy if exists "hospital_doctors_all" on hospital_doctors;
create policy "hospital_doctors_all" on hospital_doctors for all using (true) with check (true);

drop policy if exists "penalty_ledger_all" on penalty_ledger;
create policy "penalty_ledger_all" on penalty_ledger for all using (true) with check (true);

drop policy if exists "doctor_points_own" on doctor_points;
create policy "doctor_points_own" on doctor_points for all using (true) with check (true);

drop policy if exists "doctor_tokens_own" on doctor_tokens;
create policy "doctor_tokens_own" on doctor_tokens for all using (true) with check (true);

drop policy if exists "doctor_preferences_own" on doctor_preferences;
create policy "doctor_preferences_own" on doctor_preferences for all using (true) with check (true);

drop policy if exists "proposed_rates_all" on proposed_rates;
create policy "proposed_rates_all" on proposed_rates for all using (true) with check (true);
