-- =============================================================================
-- ON CALL — paste this entire file into Supabase → SQL Editor → Run
-- Project: xapkoawwyfhyzusnzhzk
-- =============================================================================

-- On-Call Wizard Supabase schema
-- Run in Supabase SQL editor

create type user_role as enum ('doctor', 'hospital');
create type verification_status as enum ('unverified', 'pending', 'verified', 'flagged', 'rejected');
create type token_status as enum ('pending', 'approved', 'denied', 'auto_approved');
create type assignment_status as enum ('scheduled', 'canceled', 'traded_pending', 'traded_complete');
create type trade_state as enum ('pending', 'accepted', 'rejected', 'canceled');
create type penalty_type as enum ('cancel', 'trade');

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  role user_role not null,
  created_at timestamptz default now()
);

create table doctor_profiles (
  profile_id uuid primary key references profiles(id) on delete cascade,
  first_name text not null,
  last_name text not null,
  credential text not null,
  npi text not null,
  specialties text[] not null default '{}',
  verification_status verification_status not null default 'pending'
);

create table hospital_profiles (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  npi text not null,
  verification_status verification_status not null default 'pending'
);

create table hospital_doctors (
  hospital_id uuid references hospital_profiles(id) on delete cascade,
  doctor_id uuid references doctor_profiles(profile_id) on delete cascade,
  auto_approve boolean not null default false,
  primary key (hospital_id, doctor_id)
);

create table shifts (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references hospital_profiles(id) on delete cascade,
  hospital_name text not null,
  specialty text not null,
  date timestamptz not null,
  rate_floor numeric not null,
  rate_unit text not null default 'per_day',
  duration_hours numeric not null default 24,
  escalation jsonb default '{}'::jsonb
);

create table assignments (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null references shifts(id) on delete cascade,
  doctor_id uuid not null references doctor_profiles(profile_id),
  status assignment_status not null default 'scheduled',
  assigned_at timestamptz default now(),
  unique (shift_id)
);

create table unavailable_days (
  hospital_id uuid references hospital_profiles(id) on delete cascade,
  date date not null,
  primary key (hospital_id, date)
);

create table scheduling_policies (
  hospital_id uuid primary key references hospital_profiles(id) on delete cascade,
  policy jsonb not null default '{}'::jsonb
);

create table token_requests (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references doctor_profiles(profile_id),
  hospital_id uuid not null references hospital_profiles(id),
  shift_date date not null,
  status token_status not null default 'pending',
  specialty text not null,
  requested_at timestamptz default now()
);

create table trade_requests (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null references shifts(id),
  from_doctor_id uuid not null references doctor_profiles(profile_id),
  to_doctor_id uuid not null references doctor_profiles(profile_id),
  state trade_state not null default 'pending',
  penalty_amount numeric default 0,
  created_at timestamptz default now()
);

create table penalty_ledger (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references doctor_profiles(profile_id),
  hospital_id uuid not null references hospital_profiles(id),
  shift_id uuid references shifts(id),
  type penalty_type not null,
  amount numeric not null,
  created_at timestamptz default now()
);

alter table profiles enable row level security;
alter table shifts enable row level security;
alter table assignments enable row level security;
alter table token_requests enable row level security;
alter table trade_requests enable row level security;
alter table unavailable_days enable row level security;
alter table scheduling_policies enable row level security;

create policy "profiles_own" on profiles for all using (auth.uid() = id);
create policy "shifts_read" on shifts for select using (true);
create policy "assignments_own" on assignments for all using (auth.uid() = doctor_id);

-- Expand schema for full web ↔ iOS sync

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

create table if not exists doctor_preferences (
  doctor_id uuid primary key references doctor_profiles(profile_id) on delete cascade,
  prefs jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now()
);

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
