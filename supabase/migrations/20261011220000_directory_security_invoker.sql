-- Security advisor follow-up. Not applied to the hosted project by this file alone.
--
-- doctor_directory and hospital_roster were security-definer views. They had
-- to be: doctor_profiles row security only lets someone read their own
-- credential row, and these views are how a hospital or a peer sees a name
-- card. Turning the views into security invoker without another path would
-- hide those cards.
--
-- The same WHERE clauses now live in private security-definer functions.
-- The views run as the caller (security_invoker) and only return what those
-- functions return. Columns are unchanged. anon still has no select.

create or replace function private.doctor_directory_rows()
returns table (
  profile_id uuid,
  first_name text,
  last_name text,
  credential text,
  specialties text[],
  verification_status public.verification_status
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    d.profile_id,
    d.first_name,
    d.last_name,
    d.credential,
    d.specialties,
    d.verification_status
  from public.doctor_profiles d
  where private.is_admin()
     or d.profile_id = auth.uid()
     or exists (
          select 1
          from public.hospital_doctors hd
          join public.hospital_profiles hp on hp.id = hd.hospital_id
          where hd.doctor_id = d.profile_id
            and hp.profile_id = auth.uid()
            and (not d.is_demo or hp.is_demo)
        )
     or exists (
          select 1
          from public.hospital_doctors mine
          join public.hospital_doctors theirs on theirs.hospital_id = mine.hospital_id
          join public.hospital_profiles hp on hp.id = mine.hospital_id
          where mine.doctor_id = auth.uid()
            and mine.approved_at is not null
            and theirs.doctor_id = d.profile_id
            and theirs.approved_at is not null
            and (
              not private.caller_is_demo_doctor()
              or (hp.is_demo and d.is_demo)
            )
            and (
              private.caller_is_demo_doctor()
              or not d.is_demo
            )
        );
$$;

create or replace function private.hospital_roster_rows()
returns table (
  hospital_id uuid,
  doctor_id uuid,
  auto_approve boolean,
  first_name text,
  last_name text,
  credential text,
  specialties text[],
  verification_status public.verification_status,
  approved_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    hd.hospital_id,
    hd.doctor_id,
    hd.auto_approve,
    d.first_name,
    d.last_name,
    d.credential,
    d.specialties,
    d.verification_status,
    hd.approved_at
  from public.hospital_doctors hd
  join public.doctor_profiles d on d.profile_id = hd.doctor_id
  where (
      private.is_admin()
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
          and mine.approved_at is not null
          and hd.approved_at is not null
      )
    )
    and (
      not d.is_demo
      or private.is_admin()
      or private.caller_is_demo_doctor()
      or exists (
        select 1
        from public.hospital_profiles hp
        where hp.id = hd.hospital_id
          and hp.profile_id = auth.uid()
          and hp.is_demo
      )
    )
    and (
      not private.caller_is_demo_doctor()
      or (
        d.is_demo
        and exists (
          select 1
          from public.hospital_profiles hp
          where hp.id = hd.hospital_id
            and hp.is_demo
        )
      )
    );
$$;

revoke all on function private.doctor_directory_rows() from public, anon, authenticated;
revoke all on function private.hospital_roster_rows() from public, anon, authenticated;
grant execute on function private.doctor_directory_rows() to authenticated, service_role;
grant execute on function private.hospital_roster_rows() to authenticated, service_role;

create or replace view public.doctor_directory
with (security_barrier = true, security_invoker = true) as
select
  profile_id,
  first_name,
  last_name,
  credential,
  specialties,
  verification_status
from private.doctor_directory_rows();

create or replace view public.hospital_roster
with (security_barrier = true, security_invoker = true) as
select
  hospital_id,
  doctor_id,
  auto_approve,
  first_name,
  last_name,
  credential,
  specialties,
  verification_status,
  approved_at
from private.hospital_roster_rows();

alter view public.doctor_directory set (security_barrier = true, security_invoker = true);
alter view public.hospital_roster set (security_barrier = true, security_invoker = true);

comment on view public.doctor_directory is
  'Name, credential, specialty, and verification only. Runs as the caller. Peer cards require an approved shared hospital. Demo doctors are visible only to demo hospitals, demo doctors, and admins.';

comment on view public.hospital_roster is
  'Roster cards. Runs as the caller. A doctor sees peers only after their own membership is approved. Demo doctors are hidden from non-demo hospitals and non-demo doctors.';

grant select on public.doctor_directory to authenticated, service_role;
grant select on public.hospital_roster to authenticated, service_role;
revoke all on public.doctor_directory from anon, public;
revoke all on public.hospital_roster from anon, public;

-- Pin search_path so a caller cannot shadow split_part, auth, or private.
alter function private.is_personal_email_domain(text) set search_path = '';
alter function private.db_admin_bypass() set search_path = '';
