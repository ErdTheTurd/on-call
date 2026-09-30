-- App Review access. Not applied to the hosted project by this file.
-- The owner applies it before creating the review hospital login and before
-- running supabase/seed/app_review_demo.sql.
--
-- Rules this file changes:
-- 1. A verified work-email code is required only when a hospital profile is
--    created or its email actually changes. Saving the same address again,
--    including an upsert that arrives as INSERT ... ON CONFLICT, does not
--    need a new code. Personal-domain addresses are still rejected when the
--    email is new or changed.
-- 2. hospital_profiles.is_demo marks a hospital as demo data. Only the
--    database owner or service role can set that flag. A doctor who is not
--    already linked to that hospital (approved roster row, or an assignment
--    there) cannot see its shifts, request one, or ask to join its roster.
--    Every other hospital stays visible to doctors, the same as before.
-- 3. The hospital that owns a token request can read that doctor's display
--    name and credential, and nobody else can, except the doctor on the
--    request and an admin. NPI, license, DEA, and email stay off this view.
-- 4. A doctor can see whether a shift they are already allowed to see is
--    filled. That view does not include who holds it.
-- 5. trade_requests stores the display fields the apps already send (names,
--    dates, specialty, compensation, the other shift).

-- ---------------------------------------------------------------------------
-- Demo hospitals
-- ---------------------------------------------------------------------------

alter table public.hospital_profiles
  add column if not exists is_demo boolean not null default false;

comment on column public.hospital_profiles.is_demo is
  'Demo hospitals are hidden from doctors who are not already linked to them.';

create or replace function private.guard_hospital_demo_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if private.db_admin_bypass() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.is_demo := false;
  else
    new.is_demo := old.is_demo;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_hospital_demo_flag() from public, anon;
grant execute on function private.guard_hospital_demo_flag() to authenticated;

drop trigger if exists hospital_profiles_guard_demo_flag on public.hospital_profiles;
create trigger hospital_profiles_guard_demo_flag
  before insert or update on public.hospital_profiles
  for each row execute function private.guard_hospital_demo_flag();

-- True when this doctor may see a hospital's open board.
-- A non-demo hospital is visible to every doctor. A demo hospital is visible
-- only when doctor_linked_to_hospital is already true (approved roster or an
-- assignment). The check goes through this helper so it is not hidden by the
-- doctor's own hospital_profiles RLS.
create or replace function private.hospital_visible_to_doctor(target uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1
    from public.hospital_profiles hp
    where hp.id = target
      and hp.is_demo
  )
  or private.doctor_linked_to_hospital(target);
$$;

revoke all on function private.hospital_visible_to_doctor(uuid) from public, anon;
grant execute on function private.hospital_visible_to_doctor(uuid) to authenticated;

drop policy if exists "shifts_select" on public.shifts;
create policy "shifts_select" on public.shifts
  for select using (
    private.is_admin()
    or private.owns_hospital(hospital_id)
    or (private.is_doctor() and private.hospital_visible_to_doctor(hospital_id))
  );

drop policy if exists "token_requests_insert" on public.token_requests;
create policy "token_requests_insert" on public.token_requests
  for insert with check (
    private.is_admin()
    or private.owns_hospital(hospital_id)
    or (
      doctor_id = auth.uid()
      and private.hospital_visible_to_doctor(hospital_id)
    )
  );

drop policy if exists "hospital_doctors_insert" on public.hospital_doctors;
create policy "hospital_doctors_insert" on public.hospital_doctors
  for insert with check (
    private.is_admin()
    or private.owns_hospital(hospital_id)
    or (
      doctor_id = auth.uid()
      and auto_approve = false
      and approved_at is null
      and private.hospital_visible_to_doctor(hospital_id)
    )
  );

-- ---------------------------------------------------------------------------
-- Work email: create, or a real email change, not every save.
-- ---------------------------------------------------------------------------

create or replace function private.guard_hospital_work_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(new.email, '')));
  v_previous text;
begin
  -- A normal UPDATE whose address did not change.
  if tg_op = 'UPDATE'
     and v_email is not distinct from lower(btrim(coalesce(old.email, ''))) then
    new.email := lower(btrim(coalesce(old.email, '')));
    return new;
  end if;

  -- PostgREST upsert is INSERT ... ON CONFLICT, so a save of an existing row
  -- arrives here as INSERT. If that row already has this address, this is not
  -- a create and not an email change.
  if tg_op = 'INSERT' then
    select lower(btrim(coalesce(hp.email, '')))
      into v_previous
    from public.hospital_profiles hp
    where hp.id = new.id;
    if found and v_previous = v_email then
      new.email := v_email;
      return new;
    end if;
  end if;

  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'hospital work email is required';
  end if;
  if private.is_personal_email_domain(v_email) then
    raise exception 'personal email domains are not allowed for hospitals';
  end if;

  new.email := v_email;

  if private.db_admin_bypass() then
    return new;
  end if;

  if not private.hospital_email_is_verified(auth.uid(), v_email) then
    raise exception 'hospital work email is not verified';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_hospital_work_email() from public, anon;
grant execute on function private.guard_hospital_work_email() to authenticated;

-- ---------------------------------------------------------------------------
-- Names on the approval queue. Display name and credential only.
-- ---------------------------------------------------------------------------

create or replace view public.token_request_queue
with (security_barrier = true, security_invoker = false) as
select
  tr.id,
  tr.doctor_id,
  tr.hospital_id,
  tr.shift_date,
  tr.status,
  tr.specialty,
  tr.requested_at,
  btrim(concat_ws(
    ' ',
    nullif(btrim(d.first_name), ''),
    nullif(btrim(d.last_name), '')
  )) as doctor_name,
  d.credential,
  hp.name as hospital_name
from public.token_requests tr
join public.doctor_profiles d on d.profile_id = tr.doctor_id
join public.hospital_profiles hp on hp.id = tr.hospital_id
where private.is_admin()
   or tr.doctor_id = auth.uid()
   or private.owns_hospital(tr.hospital_id);

comment on view public.token_request_queue is
  'Token requests plus the doctor display name and credential. The hospital that owns the request can read that name. NPI, license, DEA, and email are not in this view.';

grant select on public.token_request_queue to authenticated, service_role;
revoke all on public.token_request_queue from anon, public;

-- Filled or not, for shifts the caller can already see. No doctor identity.
create or replace view public.shift_coverage
with (security_barrier = true, security_invoker = false) as
select
  s.id as shift_id,
  s.hospital_id,
  exists (
    select 1
    from public.assignments a
    where a.shift_id = s.id
      and a.status::text <> 'canceled'
  ) as is_filled
from public.shifts s
where private.is_admin()
   or private.owns_hospital(s.hospital_id)
   or (private.is_doctor() and private.hospital_visible_to_doctor(s.hospital_id));

comment on view public.shift_coverage is
  'Whether a visible shift is filled. Does not name the doctor who holds it.';

grant select on public.shift_coverage to authenticated, service_role;
revoke all on public.shift_coverage from anon, public;

-- ---------------------------------------------------------------------------
-- Trade display fields the apps already send.
-- ---------------------------------------------------------------------------

alter table public.trade_requests
  add column if not exists compensation_amount numeric not null default 0,
  add column if not exists requested_shift_id uuid references public.shifts(id),
  add column if not exists counter_of_trade_id uuid references public.trade_requests(id),
  add column if not exists from_doctor_name text,
  add column if not exists to_doctor_name text,
  add column if not exists offered_date timestamptz,
  add column if not exists requested_date timestamptz,
  add column if not exists specialty text,
  add column if not exists updated_at timestamptz default now();
