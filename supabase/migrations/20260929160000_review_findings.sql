-- Review findings from PR #69. Not applied to the hosted project by this file.
-- The owner applies it in the SQL editor or CLI after reading the rules below.
--
-- Rules this file adds:
-- 1. Email codes are stored per signed-in user and email. A code request from
--    someone else cannot clear another user's verified address.
-- 2. Guessing a code and sending a code each take one locked database update,
--    so parallel requests all count toward the limits.
-- 3. A hospital profile can be created, and its email can be changed, only when
--    that same user has a verified, unexpired code for that address.
-- 4. Hospital emails on personal domains (Gmail, Yahoo, Outlook, iCloud,
--    Apple Hide My Email, and the same list the apps already use) are rejected.
-- 5. A doctor who adds themselves to a hospital stays pending. They cannot see
--    that hospital's roster or peer directory cards until the hospital approves.
--    Opening a trade does not reveal an unrelated doctor's card.
-- 6. A doctor cannot approve their own token request or move an assignment
--    onto a different shift. A doctor can create an assignment only for
--    themselves, and only on a shift covered by their approved or
--    auto-approved token for that hospital and UTC date. Hospitals, admins,
--    and the service role can still create any assignment. A hospital's
--    auto-approve setting can still mark a request auto-approved.
-- 7. Doctors can write savings and penalty rows only for a hospital that has
--    approved them or that they already have an assignment at. Those rows
--    cannot be moved to a different hospital.
-- 8. Only the doctor who was asked, the hospital that owns the shift, or an
--    admin may update a trade. The doctor who sent it cannot accept it.
-- 9. public.is_admin() moves to the private schema so it is not a public API,
--    and policies keep working. public.rls_auto_enable() is not callable by
--    the website key if that helper exists.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

alter function public.is_admin() set schema private;

revoke all on function private.is_admin() from public, anon;
grant execute on function private.is_admin() to authenticated;

-- The review trigger stores public.is_admin() as source text, so it must be
-- recreated after the move. Policies keep the same function by id.
create or replace function private.guard_verification_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  reviewer boolean;
begin
  reviewer := private.is_admin()
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

do $$
declare
  sig regprocedure;
begin
  for sig in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rls_auto_enable'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', sig);
  end loop;
end $$;

create or replace function private.is_personal_email_domain(p_email text)
returns boolean
language sql
immutable
as $$
  select exists (
    select 1
    from unnest(array[
      'gmail.com', 'googlemail.com', 'yahoo.com', 'ymail.com',
      'hotmail.com', 'outlook.com', 'live.com', 'msn.com',
      'icloud.com', 'me.com', 'mac.com', 'aol.com',
      'protonmail.com', 'proton.me', 'tutanota.com',
      'privaterelay.appleid.com'
    ]) as blocked(domain)
    where lower(split_part(coalesce(p_email, ''), '@', 2)) = blocked.domain
       or lower(split_part(coalesce(p_email, ''), '@', 2)) like '%.' || blocked.domain
  );
$$;

revoke all on function private.is_personal_email_domain(text) from public, anon, authenticated;

create or replace function private.db_admin_bypass()
returns boolean
language sql
stable
as $$
  select private.is_admin()
    or auth.role() = 'service_role'
    or (
      auth.uid() is null
      and coalesce(auth.role(), '') not in ('anon', 'authenticated')
    );
$$;

revoke all on function private.db_admin_bypass() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Email challenges: one row per user and address.
-- Old rows were keyed only by email, so they are not kept.
-- ---------------------------------------------------------------------------

alter table public.email_verification_challenges
  add column if not exists user_id uuid;

delete from public.email_verification_challenges where user_id is null;

alter table public.email_verification_challenges
  drop constraint if exists email_verification_challenges_pkey;

alter table public.email_verification_challenges
  alter column user_id set not null;

alter table public.email_verification_challenges
  add primary key (user_id, email);

alter table public.email_verification_challenges
  drop constraint if exists email_verification_challenges_user_id_fkey;

alter table public.email_verification_challenges
  add constraint email_verification_challenges_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

create table if not exists public.email_verification_email_windows (
  email text primary key,
  window_started_at timestamptz not null default now(),
  send_count int not null default 0
);

create table if not exists public.email_verification_user_windows (
  user_id uuid primary key,
  window_started_at timestamptz not null default now(),
  send_count int not null default 0
);

alter table public.email_verification_email_windows enable row level security;
alter table public.email_verification_user_windows enable row level security;

revoke all on public.email_verification_email_windows from public, anon, authenticated;
revoke all on public.email_verification_user_windows from public, anon, authenticated;
grant all on public.email_verification_email_windows to service_role;
grant all on public.email_verification_user_windows to service_role;

create or replace function private.hospital_email_is_verified(p_user uuid, p_email text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.email_verification_challenges c
    where c.user_id = p_user
      and lower(c.email) = lower(btrim(coalesce(p_email, '')))
      and c.verified_at is not null
      and c.verified_at > now() - interval '24 hours'
  );
$$;

revoke all on function private.hospital_email_is_verified(uuid, text) from public, anon, authenticated;

-- Reserves one send under row locks. Does not replace the stored code, so a
-- failed delivery leaves the previous code and verified_at alone.
create or replace function public.reserve_verification_send(
  p_user_id uuid,
  p_email text,
  p_ip_hash text,
  p_max_per_email integer,
  p_max_per_ip integer,
  p_max_per_user integer,
  p_window_seconds integer,
  p_min_resend_seconds integer
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_window interval := make_interval(secs => greatest(p_window_seconds, 1));
  v_resend interval := make_interval(secs => greatest(p_min_resend_seconds, 0));
  v_count integer;
  v_started timestamptz;
  v_last timestamptz;
begin
  if p_user_id is null or v_email = '' or position('@' in v_email) = 0 or coalesce(p_ip_hash, '') = '' then
    return 'invalid';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || '|' || v_email, 0));

  perform 1
  from public.email_verification_challenges
  where user_id = p_user_id and email = v_email
  for update;

  select last_sent_at into v_last
  from public.email_verification_challenges
  where user_id = p_user_id and email = v_email;

  if v_last is not null and v_last > now() - v_resend then
    return 'resend';
  end if;

  insert into public.email_verification_email_windows (email, window_started_at, send_count)
  values (v_email, now(), 0)
  on conflict (email) do nothing;

  insert into public.email_verification_ip_windows (ip_hash, window_started_at, send_count)
  values (p_ip_hash, now(), 0)
  on conflict (ip_hash) do nothing;

  insert into public.email_verification_user_windows (user_id, window_started_at, send_count)
  values (p_user_id, now(), 0)
  on conflict (user_id) do nothing;

  perform 1 from public.email_verification_email_windows where email = v_email for update;
  perform 1 from public.email_verification_ip_windows where ip_hash = p_ip_hash for update;
  perform 1 from public.email_verification_user_windows where user_id = p_user_id for update;

  select send_count, window_started_at into v_count, v_started
  from public.email_verification_email_windows where email = v_email;
  if v_started > now() - v_window and v_count >= p_max_per_email then
    return 'email_limit';
  end if;

  select send_count, window_started_at into v_count, v_started
  from public.email_verification_ip_windows where ip_hash = p_ip_hash;
  if v_started > now() - v_window and v_count >= p_max_per_ip then
    return 'ip_limit';
  end if;

  select send_count, window_started_at into v_count, v_started
  from public.email_verification_user_windows where user_id = p_user_id;
  if v_started > now() - v_window and v_count >= p_max_per_user then
    return 'user_limit';
  end if;

  update public.email_verification_email_windows
    set send_count = case when window_started_at <= now() - v_window then 1 else send_count + 1 end,
        window_started_at = case when window_started_at <= now() - v_window then now() else window_started_at end
    where email = v_email;

  update public.email_verification_ip_windows
    set send_count = case when window_started_at <= now() - v_window then 1 else send_count + 1 end,
        window_started_at = case when window_started_at <= now() - v_window then now() else window_started_at end
    where ip_hash = p_ip_hash;

  update public.email_verification_user_windows
    set send_count = case when window_started_at <= now() - v_window then 1 else send_count + 1 end,
        window_started_at = case when window_started_at <= now() - v_window then now() else window_started_at end
    where user_id = p_user_id;

  insert into public.email_verification_challenges (
    user_id, email, attempts, last_sent_at, sends_in_window, window_started_at
  ) values (
    p_user_id, v_email, 0, now(), 1, now()
  )
  on conflict (user_id, email) do update
    set last_sent_at = now(),
        sends_in_window = public.email_verification_challenges.sends_in_window + 1,
        window_started_at = coalesce(public.email_verification_challenges.window_started_at, now());

  return 'ok';
end;
$$;

revoke all on function public.reserve_verification_send(uuid, text, text, integer, integer, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.reserve_verification_send(uuid, text, text, integer, integer, integer, integer, integer)
  to service_role;

create or replace function public.store_verification_code(
  p_user_id uuid,
  p_email text,
  p_code_hash text,
  p_expires_at timestamptz
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.email_verification_challenges
    set code_hash = p_code_hash,
        expires_at = p_expires_at,
        attempts = 0,
        verified_at = null
    where user_id = p_user_id
      and email = lower(btrim(coalesce(p_email, '')));
end;
$$;

revoke all on function public.store_verification_code(uuid, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.store_verification_code(uuid, text, text, timestamptz)
  to service_role;

-- One statement increments attempts only while the code is still guessable.
create or replace function public.consume_email_attempt(
  p_user_id uuid,
  p_email text,
  p_max integer
) returns table (code_hash text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  update public.email_verification_challenges as c
    set attempts = c.attempts + 1
    where c.user_id = p_user_id
      and c.email = lower(btrim(coalesce(p_email, '')))
      and c.attempts < p_max
      and c.expires_at is not null
      and c.expires_at > now()
      and c.code_hash is not null
    returning c.code_hash;
end;
$$;

revoke all on function public.consume_email_attempt(uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.consume_email_attempt(uuid, text, integer)
  to service_role;

create or replace function public.complete_email_verification(
  p_user_id uuid,
  p_email text,
  p_code_hash text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean := false;
begin
  update public.email_verification_challenges
    set verified_at = now(),
        code_hash = null,
        expires_at = null,
        attempts = 0
    where user_id = p_user_id
      and email = lower(btrim(coalesce(p_email, '')))
      and code_hash = p_code_hash
      and expires_at is not null
      and expires_at > now()
    returning true into v_ok;
  return coalesce(v_ok, false);
end;
$$;

revoke all on function public.complete_email_verification(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.complete_email_verification(uuid, text, text)
  to service_role;

create or replace function public.claim_hospital_signup_notice(
  p_user_id uuid,
  p_email text
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_verified timestamptz;
  v_notified timestamptz;
begin
  select verified_at, signup_notified_at
    into v_verified, v_notified
  from public.email_verification_challenges
  where user_id = p_user_id
    and email = lower(btrim(coalesce(p_email, '')))
  for update;

  if v_verified is null or v_verified <= now() - interval '24 hours' then
    return 'unverified';
  end if;
  if v_notified is not null and v_notified > now() - interval '1 hour' then
    return 'already_sent';
  end if;

  update public.email_verification_challenges
    set signup_notified_at = now()
    where user_id = p_user_id
      and email = lower(btrim(coalesce(p_email, '')));
  return 'ok';
end;
$$;

revoke all on function public.claim_hospital_signup_notice(uuid, text)
  from public, anon, authenticated;
grant execute on function public.claim_hospital_signup_notice(uuid, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- Hospital work email is enforced in the database.
-- ---------------------------------------------------------------------------

create or replace function private.guard_hospital_work_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(new.email, '')));
begin
  if tg_op = 'UPDATE' and new.email is not distinct from old.email then
    return new;
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

drop trigger if exists hospital_profiles_guard_work_email on public.hospital_profiles;
create trigger hospital_profiles_guard_work_email
  before insert or update on public.hospital_profiles
  for each row execute function private.guard_hospital_work_email();

-- ---------------------------------------------------------------------------
-- Roster membership is pending until the hospital approves it.
-- ---------------------------------------------------------------------------

alter table public.hospital_doctors
  add column if not exists approved_at timestamptz;

update public.hospital_doctors
  set approved_at = now()
  where approved_at is null;

comment on column public.hospital_doctors.approved_at is
  'Set when the hospital approves the doctor. Null means a self-add is still pending.';

create or replace function private.guard_roster_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_privileged boolean;
begin
  v_privileged := private.db_admin_bypass() or private.owns_hospital(new.hospital_id);

  if v_privileged then
    if tg_op = 'INSERT' and new.approved_at is null then
      new.approved_at := now();
    end if;
    return new;
  end if;

  if new.doctor_id is distinct from auth.uid() then
    raise exception 'cannot add another doctor to a hospital';
  end if;

  if tg_op = 'INSERT' and (new.auto_approve or new.approved_at is not null) then
    raise exception 'doctors cannot approve their own roster link';
  end if;

  new.auto_approve := false;
  if tg_op = 'INSERT' then
    new.approved_at := null;
  else
    new.approved_at := old.approved_at;
    new.auto_approve := old.auto_approve;
    new.hospital_id := old.hospital_id;
    new.doctor_id := old.doctor_id;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_roster_membership() from public, anon;
grant execute on function private.guard_roster_membership() to authenticated;

drop trigger if exists hospital_doctors_guard_membership on public.hospital_doctors;
create trigger hospital_doctors_guard_membership
  before insert or update on public.hospital_doctors
  for each row execute function private.guard_roster_membership();

drop policy if exists "hospital_doctors_insert" on public.hospital_doctors;
create policy "hospital_doctors_insert" on public.hospital_doctors
  for insert with check (
    private.is_admin()
    or private.owns_hospital(hospital_id)
    or (doctor_id = auth.uid() and auto_approve = false and approved_at is null)
  );

-- ---------------------------------------------------------------------------
-- Doctors cannot approve their own tokens or mint assignments.
-- ---------------------------------------------------------------------------

create or replace function private.doctor_may_auto_approve(p_hospital uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.hospital_doctors hd
    where hd.hospital_id = p_hospital
      and hd.doctor_id = auth.uid()
      and hd.auto_approve
      and hd.approved_at is not null
  )
  or exists (
    select 1
    from public.scheduling_policies sp
    join public.doctor_profiles d on d.profile_id = auth.uid()
    where sp.hospital_id = p_hospital
      and coalesce(sp.policy->>'administratorApproveShifts', 'true') = 'false'
      and d.verification_status::text = 'verified'
  );
$$;

revoke all on function private.doctor_may_auto_approve(uuid) from public, anon, authenticated;

create or replace function private.guard_token_request_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if private.db_admin_bypass() or private.owns_hospital(new.hospital_id) then
    return new;
  end if;

  if new.status::text in ('approved', 'denied')
     or (new.status::text = 'auto_approved' and not private.doctor_may_auto_approve(new.hospital_id)) then
    if tg_op = 'INSERT' then
      new.status := 'pending';
    else
      new.status := old.status;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_token_request_status() from public, anon;
grant execute on function private.guard_token_request_status() to authenticated;

drop trigger if exists token_requests_guard_status on public.token_requests;
create trigger token_requests_guard_status
  before insert or update on public.token_requests
  for each row execute function private.guard_token_request_status();

create or replace function private.guard_assignment_shift()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hospital uuid;
begin
  select s.hospital_id into v_hospital
  from public.shifts s
  where s.id = new.shift_id;

  if private.db_admin_bypass() or (v_hospital is not null and private.owns_hospital(v_hospital)) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- Accept Shift on web and iOS inserts this row after a token is approved.
    -- The edge function uses the service role and skips this branch. A direct
    -- insert is allowed only for the signed-in doctor, and only when that
    -- token covers this shift's hospital and UTC calendar date.
    if not exists (
      select 1
      from public.shifts s
      join public.token_requests tr
        on tr.hospital_id = s.hospital_id
       and tr.doctor_id = new.doctor_id
       and tr.shift_date = (s.date at time zone 'utc')::date
       and tr.status::text in ('approved', 'auto_approved')
      where s.id = new.shift_id
        and new.doctor_id = auth.uid()
    ) then
      raise exception 'doctors cannot create assignments';
    end if;
  end if;

  if tg_op = 'UPDATE' and new.shift_id is distinct from old.shift_id then
    raise exception 'cannot change assignment shift';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_assignment_shift() from public, anon;
grant execute on function private.guard_assignment_shift() to authenticated;

drop trigger if exists assignments_guard_shift on public.assignments;
create trigger assignments_guard_shift
  before insert or update on public.assignments
  for each row execute function private.guard_assignment_shift();

-- ---------------------------------------------------------------------------
-- Savings and penalties stay on a hospital the doctor is linked to.
-- ---------------------------------------------------------------------------

create or replace function private.doctor_linked_to_hospital(target uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.hospital_doctors hd
    where hd.hospital_id = target
      and hd.doctor_id = auth.uid()
      and hd.approved_at is not null
  )
  or exists (
    select 1
    from public.assignments a
    join public.shifts s on s.id = a.shift_id
    where a.doctor_id = auth.uid()
      and s.hospital_id = target
  );
$$;

revoke all on function private.doctor_linked_to_hospital(uuid) from public, anon;
grant execute on function private.doctor_linked_to_hospital(uuid) to authenticated;

create or replace function private.guard_hospital_id_immutable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and new.hospital_id is distinct from old.hospital_id then
    if not private.db_admin_bypass() then
      raise exception 'cannot move this row to a different hospital';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_hospital_id_immutable() from public, anon;
grant execute on function private.guard_hospital_id_immutable() to authenticated;

drop trigger if exists hospital_savings_guard_hospital on public.hospital_savings_events;
create trigger hospital_savings_guard_hospital
  before update on public.hospital_savings_events
  for each row execute function private.guard_hospital_id_immutable();

drop trigger if exists penalty_ledger_guard_hospital on public.penalty_ledger;
create trigger penalty_ledger_guard_hospital
  before update on public.penalty_ledger
  for each row execute function private.guard_hospital_id_immutable();

drop policy if exists "hospital_savings_insert" on public.hospital_savings_events;
create policy "hospital_savings_insert" on public.hospital_savings_events
  for insert with check (
    private.is_admin()
    or private.owns_hospital(hospital_id)
    or (
      created_by = auth.uid()
      and private.doctor_linked_to_hospital(hospital_id)
      and (
        shift_id is null
        or exists (
          select 1
          from public.shifts s
          where s.id = shift_id
            and s.hospital_id = hospital_savings_events.hospital_id
        )
      )
    )
  );

drop policy if exists "hospital_savings_update" on public.hospital_savings_events;
create policy "hospital_savings_update" on public.hospital_savings_events
  for update
  using (
    private.is_admin()
    or private.owns_hospital(hospital_id)
    or (created_by = auth.uid() and private.doctor_linked_to_hospital(hospital_id))
  )
  with check (
    private.is_admin()
    or private.owns_hospital(hospital_id)
    or (created_by = auth.uid() and private.doctor_linked_to_hospital(hospital_id))
  );

drop policy if exists "penalty_ledger_insert" on public.penalty_ledger;
create policy "penalty_ledger_insert" on public.penalty_ledger
  for insert with check (
    private.is_admin()
    or private.owns_hospital(hospital_id)
    or (
      doctor_id = auth.uid()
      and private.doctor_linked_to_hospital(hospital_id)
      and (
        shift_id is null
        or exists (
          select 1
          from public.shifts s
          where s.id = shift_id
            and s.hospital_id = penalty_ledger.hospital_id
        )
      )
    )
  );

-- ---------------------------------------------------------------------------
-- Directory and roster peers require an approved membership.
-- A trade alone does not reveal a doctor's card.
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
      )
   or exists (
        select 1
        from public.hospital_doctors mine
        join public.hospital_doctors theirs on theirs.hospital_id = mine.hospital_id
        where mine.doctor_id = auth.uid()
          and mine.approved_at is not null
          and theirs.doctor_id = d.profile_id
          and theirs.approved_at is not null
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
where private.is_admin()
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
      );

comment on view public.doctor_directory is
  'Name, credential, specialty, and verification only. Peer cards require an approved shared hospital. Trades do not unlock cards.';

comment on view public.hospital_roster is
  'Roster cards. A doctor sees peers only after their own membership is approved.';

grant select on public.doctor_directory to authenticated, service_role;
grant select on public.hospital_roster to authenticated, service_role;
revoke all on public.doctor_directory from anon, public;
revoke all on public.hospital_roster from anon, public;

-- Edge functions use the service role. Hosted Supabase already grants it every
-- table; this keeps a local database aligned and does not grant the anon key.
grant all on all tables in schema public to service_role;

-- The sender cannot accept or reject their own trade through the API.
drop policy if exists "trade_requests_update" on public.trade_requests;
create policy "trade_requests_update" on public.trade_requests
  for update
  using (
    private.is_admin()
    or to_doctor_id = auth.uid()
    or private.owns_hospital((select s.hospital_id from public.shifts s where s.id = shift_id))
  )
  with check (
    private.is_admin()
    or to_doctor_id = auth.uid()
    or private.owns_hospital((select s.hospital_id from public.shifts s where s.id = shift_id))
  );
