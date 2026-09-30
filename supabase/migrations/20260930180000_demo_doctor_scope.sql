-- Demo doctors. Not applied to the hosted project by this file.
-- The owner applies it before re-running supabase/seed/app_review_demo.sql.
--
-- Rules this file changes:
-- 1. doctor_profiles.is_demo marks a doctor as demo data. The guard matches
--    hospital_profiles.is_demo: on a client insert the flag is forced off, and
--    on a client update it stays at the old value. The database owner, the
--    service role, and an admin profile can set or clear it. Every other
--    signed-in user cannot.
-- 2. A demo doctor can see shifts, coverage, their assignments, roster rows,
--    trades, and doctor directory cards only when those rows belong to a demo
--    hospital. A demo hospital's board is visible to that doctor. Every other
--    hospital's board is not, even if the doctor is already linked there.
-- 3. A demo doctor can create a token request, a roster join, or an assignment
--    only at a demo hospital. A trade is allowed only when both doctors are
--    demo doctors and every shift on the trade belongs to a demo hospital.
--    The other direction is the same: a non-demo doctor cannot open a trade
--    with a demo doctor.
-- 4. A non-demo hospital, and a doctor who is not a demo doctor, cannot see a
--    demo doctor in the directory, on a roster, or on a trade. A non-demo
--    hospital also cannot see that doctor's assignments or token requests.
--    A demo hospital still can. An admin still can.
-- 5. The write rules are triggers. They apply to signed-in users and to the
--    service role, so an edge function cannot bypass them. Turning is_demo
--    off is the owner's way to repair an old row. Non-demo doctors and
--    non-demo hospitals keep the previous behavior, including linked doctors
--    still being able to see a demo hospital's board.

-- ---------------------------------------------------------------------------
-- Flag
-- ---------------------------------------------------------------------------

alter table public.doctor_profiles
  add column if not exists is_demo boolean not null default false;

comment on column public.doctor_profiles.is_demo is
  'Demo doctors only see demo hospitals, and non-demo hospitals cannot see them.';

create or replace function private.guard_doctor_demo_flag()
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

revoke all on function private.guard_doctor_demo_flag() from public, anon;
grant execute on function private.guard_doctor_demo_flag() to authenticated, service_role;

drop trigger if exists doctor_profiles_guard_demo_flag on public.doctor_profiles;
create trigger doctor_profiles_guard_demo_flag
  before insert or update on public.doctor_profiles
  for each row execute function private.guard_doctor_demo_flag();

-- ---------------------------------------------------------------------------
-- Helpers. security definer so policies can read the flag without recursing
-- through RLS. private is not exposed as an API schema.
-- ---------------------------------------------------------------------------

create or replace function private.doctor_is_demo(target uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select d.is_demo from public.doctor_profiles d where d.profile_id = target),
    false
  );
$$;

create or replace function private.hospital_is_demo(target uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select hp.is_demo from public.hospital_profiles hp where hp.id = target),
    false
  );
$$;

create or replace function private.caller_is_demo_doctor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select private.doctor_is_demo(auth.uid());
$$;

create or replace function private.shift_hospital_id(target uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select s.hospital_id from public.shifts s where s.id = target;
$$;

-- True unless this doctor is demo and this hospital is not.
create or replace function private.demo_doctor_may_use_hospital(doctor uuid, hospital uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not private.doctor_is_demo(doctor)
    or private.hospital_is_demo(hospital);
$$;

-- Both doctors must be demo, and every shift must sit on a demo hospital,
-- when either doctor is demo. Two non-demo doctors are unchanged.
create or replace function private.demo_trade_allowed(
  p_shift uuid,
  p_from uuid,
  p_to uuid,
  p_requested uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when private.doctor_is_demo(p_from) or private.doctor_is_demo(p_to) then
      private.doctor_is_demo(p_from)
      and private.doctor_is_demo(p_to)
      and private.demo_doctor_may_use_hospital(p_from, private.shift_hospital_id(p_shift))
      and (
        p_requested is null
        or private.demo_doctor_may_use_hospital(p_from, private.shift_hospital_id(p_requested))
      )
    else true
  end;
$$;

create or replace function private.trade_visible_to_caller(
  p_shift uuid,
  p_from uuid,
  p_to uuid,
  p_requested uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when private.is_admin() then true
    when private.caller_is_demo_doctor() then
      private.demo_trade_allowed(p_shift, p_from, p_to, p_requested)
    when private.doctor_is_demo(p_from) or private.doctor_is_demo(p_to) then
      private.owns_hospital(private.shift_hospital_id(p_shift))
      and private.hospital_is_demo(private.shift_hospital_id(p_shift))
    else true
  end;
$$;

revoke all on function private.doctor_is_demo(uuid) from public, anon;
revoke all on function private.hospital_is_demo(uuid) from public, anon;
revoke all on function private.caller_is_demo_doctor() from public, anon;
revoke all on function private.shift_hospital_id(uuid) from public, anon;
revoke all on function private.demo_doctor_may_use_hospital(uuid, uuid) from public, anon;
revoke all on function private.demo_trade_allowed(uuid, uuid, uuid, uuid) from public, anon;
revoke all on function private.trade_visible_to_caller(uuid, uuid, uuid, uuid) from public, anon;

grant execute on function private.doctor_is_demo(uuid) to authenticated, service_role;
grant execute on function private.hospital_is_demo(uuid) to authenticated, service_role;
grant execute on function private.caller_is_demo_doctor() to authenticated, service_role;
grant execute on function private.shift_hospital_id(uuid) to authenticated, service_role;
grant execute on function private.demo_doctor_may_use_hospital(uuid, uuid) to authenticated, service_role;
grant execute on function private.demo_trade_allowed(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function private.trade_visible_to_caller(uuid, uuid, uuid, uuid) to authenticated, service_role;

-- A demo doctor only sees demo hospitals. Everyone else keeps the previous
-- rule: a non-demo hospital is visible, and a demo hospital is visible only
-- when the doctor is already linked.
create or replace function private.hospital_visible_to_doctor(target uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when private.caller_is_demo_doctor() then private.hospital_is_demo(target)
    else
      not private.hospital_is_demo(target)
      or private.doctor_linked_to_hospital(target)
  end;
$$;

revoke all on function private.hospital_visible_to_doctor(uuid) from public, anon;
grant execute on function private.hospital_visible_to_doctor(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Writes. The service role bypasses RLS, so these triggers are the backstop
-- for the edge functions. No role is exempt.
-- ---------------------------------------------------------------------------

create or replace function private.guard_demo_doctor_hospital()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doctor uuid;
  v_hospital uuid;
begin
  if tg_table_name = 'assignments' then
    v_doctor := new.doctor_id;
    v_hospital := private.shift_hospital_id(new.shift_id);
  else
    v_doctor := new.doctor_id;
    v_hospital := new.hospital_id;
  end if;

  if not private.demo_doctor_may_use_hospital(v_doctor, v_hospital) then
    raise exception 'demo doctors can only work with demo hospitals';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_demo_doctor_hospital() from public, anon;
grant execute on function private.guard_demo_doctor_hospital() to authenticated, service_role;

drop trigger if exists token_requests_guard_demo_scope on public.token_requests;
create trigger token_requests_guard_demo_scope
  before insert or update on public.token_requests
  for each row execute function private.guard_demo_doctor_hospital();

drop trigger if exists hospital_doctors_guard_demo_scope on public.hospital_doctors;
create trigger hospital_doctors_guard_demo_scope
  before insert or update on public.hospital_doctors
  for each row execute function private.guard_demo_doctor_hospital();

drop trigger if exists assignments_guard_demo_scope on public.assignments;
create trigger assignments_guard_demo_scope
  before insert or update on public.assignments
  for each row execute function private.guard_demo_doctor_hospital();

create or replace function private.guard_trade_parties()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.from_doctor_id = new.to_doctor_id then
    raise exception 'cannot trade a shift to yourself';
  end if;

  if tg_op = 'INSERT' and not exists (
    select 1
    from public.assignments a
    where a.shift_id = new.shift_id
      and a.doctor_id = new.from_doctor_id
      and a.status::text <> 'canceled'
  ) then
    raise exception 'only the assigned doctor can request a trade';
  end if;

  if tg_op = 'UPDATE' and (
    new.shift_id is distinct from old.shift_id
    or new.from_doctor_id is distinct from old.from_doctor_id
    or new.to_doctor_id is distinct from old.to_doctor_id
  ) then
    raise exception 'cannot retarget a trade request';
  end if;

  if not private.demo_trade_allowed(
    new.shift_id,
    new.from_doctor_id,
    new.to_doctor_id,
    new.requested_shift_id
  ) then
    raise exception 'demo doctors can only trade with demo doctors at demo hospitals';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_trade_parties() from public, anon;
grant execute on function private.guard_trade_parties() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Reads and client writes. Non-demo rows stay on the previous predicates.
-- ---------------------------------------------------------------------------

drop policy if exists "assignments_select" on public.assignments;
create policy "assignments_select" on public.assignments
  for select using (
    private.is_admin()
    or (
      doctor_id = auth.uid()
      and private.demo_doctor_may_use_hospital(doctor_id, private.shift_hospital_id(shift_id))
    )
    or (
      private.owns_hospital(private.shift_hospital_id(shift_id))
      and private.demo_doctor_may_use_hospital(doctor_id, private.shift_hospital_id(shift_id))
    )
  );

drop policy if exists "assignments_insert" on public.assignments;
create policy "assignments_insert" on public.assignments
  for insert with check (
    private.is_admin()
    or (
      doctor_id = auth.uid()
      and private.demo_doctor_may_use_hospital(doctor_id, private.shift_hospital_id(shift_id))
    )
    or (
      private.owns_hospital(private.shift_hospital_id(shift_id))
      and private.demo_doctor_may_use_hospital(doctor_id, private.shift_hospital_id(shift_id))
    )
  );

drop policy if exists "assignments_update" on public.assignments;
create policy "assignments_update" on public.assignments
  for update
  using (
    private.is_admin()
    or (
      doctor_id = auth.uid()
      and private.demo_doctor_may_use_hospital(doctor_id, private.shift_hospital_id(shift_id))
    )
    or (
      private.owns_hospital(private.shift_hospital_id(shift_id))
      and private.demo_doctor_may_use_hospital(doctor_id, private.shift_hospital_id(shift_id))
    )
  )
  with check (
    private.is_admin()
    or (
      doctor_id = auth.uid()
      and private.demo_doctor_may_use_hospital(doctor_id, private.shift_hospital_id(shift_id))
    )
    or (
      private.owns_hospital(private.shift_hospital_id(shift_id))
      and private.demo_doctor_may_use_hospital(doctor_id, private.shift_hospital_id(shift_id))
    )
  );

drop policy if exists "token_requests_select" on public.token_requests;
create policy "token_requests_select" on public.token_requests
  for select using (
    private.is_admin()
    or (
      doctor_id = auth.uid()
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
    or (
      private.owns_hospital(hospital_id)
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
  );

drop policy if exists "token_requests_insert" on public.token_requests;
create policy "token_requests_insert" on public.token_requests
  for insert with check (
    private.is_admin()
    or (
      private.owns_hospital(hospital_id)
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
    or (
      doctor_id = auth.uid()
      and private.hospital_visible_to_doctor(hospital_id)
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
  );

drop policy if exists "token_requests_update" on public.token_requests;
create policy "token_requests_update" on public.token_requests
  for update
  using (
    private.is_admin()
    or (
      doctor_id = auth.uid()
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
    or (
      private.owns_hospital(hospital_id)
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
  )
  with check (
    private.is_admin()
    or (
      doctor_id = auth.uid()
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
    or (
      private.owns_hospital(hospital_id)
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
  );

drop policy if exists "token_requests_delete" on public.token_requests;
create policy "token_requests_delete" on public.token_requests
  for delete using (
    private.is_admin()
    or (
      doctor_id = auth.uid()
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
    or (
      private.owns_hospital(hospital_id)
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
  );

drop policy if exists "hospital_doctors_select" on public.hospital_doctors;
create policy "hospital_doctors_select" on public.hospital_doctors
  for select using (
    private.is_admin()
    or (
      doctor_id = auth.uid()
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
    or (
      private.owns_hospital(hospital_id)
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
  );

drop policy if exists "hospital_doctors_insert" on public.hospital_doctors;
create policy "hospital_doctors_insert" on public.hospital_doctors
  for insert with check (
    private.is_admin()
    or (
      private.owns_hospital(hospital_id)
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
    or (
      doctor_id = auth.uid()
      and auto_approve = false
      and approved_at is null
      and private.hospital_visible_to_doctor(hospital_id)
      and private.demo_doctor_may_use_hospital(doctor_id, hospital_id)
    )
  );

drop policy if exists "trade_requests_select" on public.trade_requests;
create policy "trade_requests_select" on public.trade_requests
  for select using (
    (
      private.is_admin()
      or from_doctor_id = auth.uid()
      or to_doctor_id = auth.uid()
      or private.owns_hospital(private.shift_hospital_id(shift_id))
    )
    and private.trade_visible_to_caller(shift_id, from_doctor_id, to_doctor_id, requested_shift_id)
  );

drop policy if exists "trade_requests_insert" on public.trade_requests;
create policy "trade_requests_insert" on public.trade_requests
  for insert with check (
    (
      private.is_admin()
      or from_doctor_id = auth.uid()
      or private.owns_hospital(private.shift_hospital_id(shift_id))
    )
    and (
      private.is_admin()
      or private.demo_trade_allowed(shift_id, from_doctor_id, to_doctor_id, requested_shift_id)
    )
  );

-- The doctor who sent a trade still cannot accept it. Demo scope is added
-- on top of that rule.
drop policy if exists "trade_requests_update" on public.trade_requests;
create policy "trade_requests_update" on public.trade_requests
  for update
  using (
    (
      private.is_admin()
      or to_doctor_id = auth.uid()
      or private.owns_hospital(private.shift_hospital_id(shift_id))
    )
    and private.trade_visible_to_caller(shift_id, from_doctor_id, to_doctor_id, requested_shift_id)
  )
  with check (
    (
      private.is_admin()
      or to_doctor_id = auth.uid()
      or private.owns_hospital(private.shift_hospital_id(shift_id))
    )
    and (
      private.is_admin()
      or private.demo_trade_allowed(shift_id, from_doctor_id, to_doctor_id, requested_shift_id)
    )
  );

-- Names on the approval queue stay name and credential only. A non-demo
-- hospital does not receive a demo doctor's card.
create or replace function private.token_request_doctor_card(doctor uuid, hospital uuid)
returns table (doctor_name text, credential text)
language sql
stable
security definer
set search_path = public
as $$
  select
    btrim(concat_ws(
      ' ',
      nullif(btrim(d.first_name), ''),
      nullif(btrim(d.last_name), '')
    )),
    d.credential
  from public.doctor_profiles d
  where d.profile_id = doctor
    and (
      private.is_admin()
      or doctor = auth.uid()
      or private.owns_hospital(hospital)
    )
    and (
      private.is_admin()
      or private.demo_doctor_may_use_hospital(doctor, hospital)
    )
    and exists (
      select 1
      from public.token_requests tr
      where tr.doctor_id = doctor
        and tr.hospital_id = hospital
    );
$$;

revoke all on function private.token_request_doctor_card(uuid, uuid) from public, anon;
grant execute on function private.token_request_doctor_card(uuid, uuid) to authenticated, service_role;

create or replace function private.token_request_hospital_name(hospital uuid, doctor uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select hp.name
  from public.hospital_profiles hp
  where hp.id = hospital
    and (
      private.is_admin()
      or private.owns_hospital(hospital)
      or doctor = auth.uid()
    )
    and (
      not private.caller_is_demo_doctor()
      or private.hospital_is_demo(hospital)
    )
    and exists (
      select 1
      from public.token_requests tr
      where tr.hospital_id = hospital
        and tr.doctor_id = doctor
    );
$$;

revoke all on function private.token_request_hospital_name(uuid, uuid) from public, anon;
grant execute on function private.token_request_hospital_name(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Directory and roster. security_barrier, owner rights, same columns.
-- A demo doctor only sees demo doctors at demo hospitals. A non-demo hospital
-- or non-demo doctor does not see a demo doctor. Peer cards still require an
-- approved membership. A trade still does not reveal a card.
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

comment on view public.doctor_directory is
  'Name, credential, specialty, and verification only. Peer cards require an approved shared hospital. Demo doctors are visible only to demo hospitals, demo doctors, and admins.';

comment on view public.hospital_roster is
  'Roster cards. A doctor sees peers only after their own membership is approved. Demo doctors are hidden from non-demo hospitals and non-demo doctors.';

grant select on public.doctor_directory to authenticated, service_role;
grant select on public.hospital_roster to authenticated, service_role;
revoke all on public.doctor_directory from anon, public;
revoke all on public.hospital_roster from anon, public;
