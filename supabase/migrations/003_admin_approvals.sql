-- Admin review queue for doctor and hospital applications
-- Safe to run on top of 002_full_sync_schema.sql, and safe to re-run.

-- Waitlisted sits between approved and rejected: the applicant is credible but
-- we are not onboarding them yet, so they keep read-only access.
alter type verification_status add value if not exists 'waitlisted';

-- Admin is granted by hand in the SQL editor. Nothing in the app can set it,
-- so a compromised client cannot promote itself.
alter table profiles
  add column if not exists is_admin boolean not null default false;

-- Who decided, when, and why. reviewed_by is a second foreign key from these
-- tables to profiles, so PostgREST needs an explicit constraint name to embed
-- the applicant: profiles!doctor_profiles_profile_id_fkey.
alter table doctor_profiles
  add column if not exists submitted_at timestamptz default now(),
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid references profiles(id) on delete set null,
  add column if not exists review_note text;

alter table hospital_profiles
  add column if not exists submitted_at timestamptz default now(),
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid references profiles(id) on delete set null,
  add column if not exists review_note text;

update doctor_profiles set submitted_at = now() where submitted_at is null;
update hospital_profiles set submitted_at = now() where submitted_at is null;

-- Security definer so a policy on profiles can call this without recursing
-- back into that same policy.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select p.is_admin from profiles p where p.id = auth.uid()), false);
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- profiles_own only exposes your own row. Admins need every row to show who
-- each application belongs to. Permissive policies are OR'd together.
drop policy if exists "profiles_admin_read" on profiles;
create policy "profiles_admin_read" on profiles for select
  using (public.is_admin());

-- Only admins may set a verification outcome. Applicants can still edit their
-- own details through the existing policies.
drop policy if exists "doctor_profiles_admin_review" on doctor_profiles;
create policy "doctor_profiles_admin_review" on doctor_profiles for update
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "hospital_profiles_admin_review" on hospital_profiles;
create policy "hospital_profiles_admin_review" on hospital_profiles for update
  using (public.is_admin()) with check (public.is_admin());

-- Grant an admin, once, after the account has signed up:
--   update profiles set is_admin = true where email = 'you@example.com';
