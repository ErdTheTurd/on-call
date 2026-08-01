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
