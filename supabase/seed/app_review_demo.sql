-- Idempotent App Review seed. Do not run this against the hosted project until
-- the owner has applied the migrations and created the hospital auth user.
-- =============================================================================
-- MD Shift: App Review demo accounts (doctor + hospital).
-- Project: yrnndfpvovuvjlzgivgu.
--
-- What it does (all in one transaction, safe to re-run: every row has a fixed id
-- or natural key, and a re-run puts the demo back to this starting state):
--   * Finishes the doctor demo account jdunn@eporthospine.com
--     (d10290cb-1dd6-4e65-8a9d-7efb4ea83419): name, demo NPI, license, verified,
--     and doctor_profiles.is_demo.
--   * Onboards the hospital demo account review-hospital@mdshift.net
--     (the auth user must exist first; see the steps below) and flags it is_demo.
--   * Adds 5 placeholder doctors that cannot sign in, flags each is_demo, and
--     adds a 6-doctor roster (1 pending),
--     240 shifts for 1 Oct to 30 Nov 2026 (124 filled, 116 open), 13 token requests
--     (4 pending), 3 pending trades, 2 penalties, and 12 savings events.
--
-- -----------------------------------------------------------------------------
-- ROLLOUT (this order, hosted project only, by the owner):
--   1. Apply supabase/migrations, including 20260930150000_app_review_access.sql
--      and 20260930180000_demo_doctor_scope.sql.
--   2. Create the hospital auth user with the email confirmed. Leave the password
--      unset here. Dashboard > Authentication > Users > Add user >
--      email review-hospital@mdshift.net, Auto Confirm User. Or the Admin API
--      (keep the service role key out of git and chat):
--        curl -X POST "https://yrnndfpvovuvjlzgivgu.supabase.co/auth/v1/admin/users" \
--          -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
--          -H "Content-Type: application/json" \
--          -d '{"email":"review-hospital@mdshift.net","email_confirm":true,
--               "user_metadata":{"role":"hospital"},
--               "app_metadata":{"mdshift_demo":true}}'
--   3. Run this file as the database owner (SQL editor). Never with a user JWT.
--   4. Set the reviewer's hospital password. Dashboard > Authentication > Users >
--      review-hospital@mdshift.net > Reset password. Or:
--        curl -X PUT "https://yrnndfpvovuvjlzgivgu.supabase.co/auth/v1/admin/users/<USER_ID>" \
--          -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
--          -H "Content-Type: application/json" \
--          -d '{"password":"<OWNER_CHOOSES>"}'
--   The doctor login already exists (jdunn@eporthospine.com). Do NOT enroll MFA
--   on either demo account.
--   Why the auth user is not created in SQL: a password login needs auth.users
--   plus a matching auth.identities row, a bcrypt hash, and '' (not NULL) in the
--   token columns, or GoTrue fails at sign-in. The Auth API does that correctly.
--
-- HOW THE SAFETY TRIGGERS ARE HANDLED
--   The SQL editor runs as `postgres` with no JWT, so auth.uid() and auth.role()
--   are NULL. private.db_admin_bypass() is true in that case, and so is the same
--   check inside guard_profile_privileges and guard_verification_review. Nothing
--   is disabled. Trigger by trigger:
--   - profiles_guard_privileges: owner bypass. We do not set is_admin or Plus.
--   - doctor_profiles_guard_review / hospital_profiles_guard_review: owner bypass,
--     so verification_status = 'verified' is kept (a user write drops it to pending).
--   - doctor_profiles_guard_demo_flag: owner bypass, so is_demo = true is kept.
--     A signed-in client cannot set or clear that flag.
--   - hospital_profiles_guard_work_email: the personal-domain check runs even for
--     the owner. mdshift.net passes. The verified-code check is skipped by the bypass.
--   - hospital_doctors_guard_membership: owner bypass. On INSERT it sets
--     approved_at = now() when NULL, so the one pending link is inserted and then
--     set back to NULL with an UPDATE (UPDATE keeps what we write).
--   - token_requests_guard_status: owner bypass, so approved/denied/auto_approved stay.
--   - assignments_guard_shift: owner bypass (no token needed).
--   - trade_requests_guard_parties: NOT bypassed, even for the owner. Each trade's
--     from_doctor must hold a non-canceled assignment on that shift, and from != to.
--     This file writes assignments before trades so the check passes. Both doctors
--     are demo doctors and the shift is at the demo hospital, so the demo-scope
--     check passes too.
--   - token, roster, and assignment demo-scope triggers are not bypassed. Every
--     demo doctor in this file is attached only to the demo hospital.
--   RLS does not apply to the table owner here, so no policy is involved.
--
-- The demo NPIs (1999999992, 1999999919, 1999999935, 1999999950, 1999999976,
-- 1999999984, org 2990000004) are 10 digits and pass the NPI Luhn check
-- (prefix 80840). On 2026-09-30 the public NPPES registry had no provider with any
-- of these numbers. They are not real people. The apps check only "10 digits" plus
-- a live NPPES lookup during onboarding, and the database has no NPI check.
-- The profiles are marked verified directly, so no lookup happens.
-- The doctor row now holds 1679576722, which NPPES lists as a real provider
-- (DAVID WIEBE). This file replaces it.
-- =============================================================================

begin;

do $$
declare
  c_doctor   constant uuid := 'd10290cb-1dd6-4e65-8a9d-7efb4ea83419';
  c_hosp     constant uuid := 'de000000-0000-4000-8000-000000000001';  -- hospital_profiles.id
  c_hosp_name constant text := 'MD Shift Demo Medical Center';
  c_hosp_email constant text := 'review-hospital@mdshift.net';
  c_admin    constant uuid := 'b9f7ecaa-e7b0-4bba-8753-d25efaaf6e25';  -- info@erdanimates.shop (is_admin), when that profile exists
  f_patel    constant uuid := 'de000000-0000-4000-9000-000000000011';
  f_brooks   constant uuid := 'de000000-0000-4000-9000-000000000012';
  f_liu      constant uuid := 'de000000-0000-4000-9000-000000000013';
  f_haddad   constant uuid := 'de000000-0000-4000-9000-000000000014';
  f_ramirez  constant uuid := 'de000000-0000-4000-9000-000000000015';
  v_hosp_user uuid;
  v_reviewer uuid := null;
  v_count int;
begin
  -- ---------------------------------------------------------------- preconditions
  if not private.db_admin_bypass() then
    raise exception 'Run as the database owner (SQL editor), not as a signed-in user.';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'hospital_profiles' and column_name = 'is_demo'
  ) then
    raise exception 'Apply migration 20260930150000_app_review_access.sql before this seed.';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'trade_requests' and column_name = 'from_doctor_name'
  ) then
    raise exception 'Apply migration 20260930150000_app_review_access.sql before this seed.';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'doctor_profiles' and column_name = 'is_demo'
  ) then
    raise exception 'Apply migration 20260930180000_demo_doctor_scope.sql before this seed.';
  end if;
  if not exists (select 1 from auth.users where id = c_doctor) then
    raise exception 'Doctor demo auth user % not found.', c_doctor;
  end if;
  select id into v_hosp_user from auth.users where lower(email) = c_hosp_email;
  if v_hosp_user is null then
    raise exception 'Create % in Supabase Auth first (STEP 1), then re-run.', c_hosp_email;
  end if;
  if exists (select 1 from auth.users where id = v_hosp_user and email_confirmed_at is null) then
    raise exception '% exists but its email is not confirmed. Tick Auto Confirm / email_confirm.', c_hosp_email;
  end if;
  if exists (select 1 from auth.mfa_factors where user_id in (c_doctor, v_hosp_user) and status = 'verified') then
    raise exception 'A demo account has a verified MFA factor. Remove it so App Review can sign in with email + password only.';
  end if;
  if exists (select 1 from public.hospital_profiles where profile_id = v_hosp_user and id <> c_hosp) then
    raise exception 'The hospital demo user already owns another hospital_profiles row; the apps load exactly one.';
  end if;
  if exists (select 1 from public.profiles where id = c_admin) then
    v_reviewer := c_admin;
  end if;

  -- ---------------------------------------------------------------- 1. doctor demo account
  -- Change: J -> Jordan, and a demo NPI replaces the real NPI.
  update public.doctor_profiles set
    first_name = 'Jordan',
    last_name = 'Dunn',
    credential = 'MD',
    npi = '1999999992',
    specialties = array['Orthopedics'],
    license_number = 'DEMO-48219',
    license_state = 'CO',
    dea_number = '',
    email = 'jdunn@eporthospine.com',
    verification_status = 'verified',
    verification_flags = '{}',
    npi_registry_name = null,
    npi_taxonomy = 'Orthopaedic Surgery',
    reviewed_by = v_reviewer,
    reviewed_at = now(),
    review_note = 'App Review demo account. NPI 1999999992 is a Luhn-valid placeholder, not a real provider.',
    is_demo = true
  where profile_id = c_doctor;
  get diagnostics v_count = row_count;
  if v_count <> 1 then raise exception 'doctor_profiles row for the demo doctor is missing'; end if;

  update public.profiles set role = 'doctor' where id = c_doctor and role <> 'doctor';

  -- ---------------------------------------------------------------- 2. hospital demo account
  insert into public.profiles (id, email, role)
  values (v_hosp_user, c_hosp_email, 'hospital')
  on conflict (id) do update set email = excluded.email, role = 'hospital';

  insert into public.hospital_profiles
    (id, profile_id, name, npi, email, verification_status, verification_flags,
     npi_registry_name, reviewed_by, reviewed_at, review_note, is_demo)
  values
    (c_hosp, v_hosp_user, c_hosp_name, '2990000004', c_hosp_email, 'verified', '{}',
     'MD SHIFT DEMO MEDICAL CENTER', v_reviewer, now(),
     'App Review demo hospital. Organization NPI 2990000004 is a placeholder.', true)
  on conflict (id) do update set
    profile_id = excluded.profile_id, name = excluded.name, npi = excluded.npi,
    email = excluded.email, verification_status = 'verified', verification_flags = '{}',
    npi_registry_name = excluded.npi_registry_name, reviewed_by = excluded.reviewed_by,
    reviewed_at = excluded.reviewed_at, review_note = excluded.review_note,
    is_demo = true;

  -- Records that this address was confirmed. Unchanged profile saves no longer
  -- consult this row (see guard_hospital_work_email). A change to a different
  -- address still needs a code verified within 24 hours. Re-running the seed
  -- refreshes this one address only.
  insert into public.email_verification_challenges (user_id, email, attempts, verified_at)
  values (v_hosp_user, c_hosp_email, 0, now())
  on conflict (user_id, email) do update
    set verified_at = excluded.verified_at, code_hash = null, expires_at = null, attempts = 0;

  insert into public.scheduling_policies (hospital_id, policy) values (c_hosp, jsonb_build_object(
    'granularity', 'day',
    'administratorApproveShifts', true,
    'useAlgorithmPricingByDefault', true,
    'defaultDailyTokens', 3,
    'doctorTokenLimits', '{}'::jsonb,
    'doctorBaseRates', '{}'::jsonb,
    'specialtyBaseRates', jsonb_build_object('Orthopedics', 1500, 'Emergency Medicine', 1400,
                                             'Internal Medicine', 1100, 'Anesthesiology', 1450),
    'specialtyUsesAlgorithm', '{}'::jsonb,
    'disabledPricingVariables', '[]'::jsonb,
    'cancelWindowHours', 6,
    'basePenaltyAmount', 425,
    -- The cancellation scale is a multiplier the apps clamp to 1.0 to 5.0 (app default: 2.0 inside 24 h).
    'cancellationPenaltyScale', '[{"penaltyPercent":2.0,"hoursBeforeStart":24}]'::jsonb,
    'tradePenaltiesEnabled', true,
    'tradePenaltyAmount', 75,
    'tradeWindowHours', 12,
    'tradePenaltyHoursBeforeStart', 72,
    'tradePenaltyScale', '[{"penaltyPercent":0.25,"hoursBeforeStart":24},{"penaltyPercent":0.1,"hoursBeforeStart":72},{"penaltyPercent":0,"hoursBeforeStart":99999}]'::jsonb,
    'caseVolumeRewardEnabled', true,
    'caseVolumeRewardAuto', true,
    'caseVolumeRewardScale', 40))
  on conflict (hospital_id) do update set policy = excluded.policy;

  insert into public.unavailable_days (hospital_id, date)
  values (c_hosp, date '2026-11-26')
  on conflict do nothing;

  -- ---------------------------------------------------------------- 3. placeholder doctors
  -- doctor_profiles -> profiles -> auth.users are foreign keys, so each needs an auth
  -- user. These cannot sign in: no password, no identity, banned until 2999. They use
  -- the same shape as the existing seeded users (c0000000-/d0000000-).
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      email_change_token_current, reauthentication_token, phone_change, phone_change_token,
      banned_until, is_sso_user, is_anonymous)
  select '00000000-0000-0000-0000-000000000000'::uuid, d.id, 'authenticated', 'authenticated', d.email, '',
      now(), '{"provider":"email","providers":["email"],"mdshift_demo":true}'::jsonb,
      '{"role":"doctor","mdshift_demo":true}'::jsonb, now(), now(),
      '', '', '', '', '', '', '', '', timestamptz '2999-12-31 00:00:00+00', false, false
  from (values
      (f_patel,   'maya.patel@demo.mdshift.net'),
      (f_brooks,  'daniel.brooks@demo.mdshift.net'),
      (f_liu,     'grace.liu@demo.mdshift.net'),
      (f_haddad,  'omar.haddad@demo.mdshift.net'),
      (f_ramirez, 'sofia.ramirez@demo.mdshift.net')) as d(id, email)
  on conflict (id) do nothing;

  insert into public.profiles (id, email, role)
  select id, email, 'doctor' from auth.users where id in (f_patel, f_brooks, f_liu, f_haddad, f_ramirez)
  on conflict (id) do update set role = 'doctor';

  insert into public.doctor_profiles (profile_id, first_name, last_name, credential, npi, specialties,
      verification_status, license_number, license_state, email, verification_flags,
      reviewed_by, reviewed_at, review_note, is_demo)
  select d.id, d.fn, d.ln, d.cred, d.npi, d.spec, 'verified', d.lic, d.st, d.email, '{}',
      v_reviewer, now(), 'App Review placeholder doctor. Not a real provider.', true
  from (values
      (f_patel,   'Maya',   'Patel',   'MD', '1999999919', array['Orthopedics'],        'DEMO-51102', 'CO', 'maya.patel@demo.mdshift.net'),
      (f_brooks,  'Daniel', 'Brooks',  'DO', '1999999935', array['Orthopedics'],        'DEMO-51103', 'CO', 'daniel.brooks@demo.mdshift.net'),
      (f_liu,     'Grace',  'Liu',     'MD', '1999999950', array['Emergency Medicine'], 'DEMO-51104', 'CO', 'grace.liu@demo.mdshift.net'),
      (f_haddad,  'Omar',   'Haddad',  'MD', '1999999976', array['Internal Medicine'],  'DEMO-51105', 'CO', 'omar.haddad@demo.mdshift.net'),
      (f_ramirez, 'Sofia',  'Ramirez', 'MD', '1999999984', array['Anesthesiology'],     'DEMO-51106', 'CO', 'sofia.ramirez@demo.mdshift.net'))
    as d(id, fn, ln, cred, npi, spec, lic, st, email)
  on conflict (profile_id) do update set
    first_name = excluded.first_name, last_name = excluded.last_name, credential = excluded.credential,
    npi = excluded.npi, specialties = excluded.specialties, verification_status = 'verified',
    license_number = excluded.license_number, license_state = excluded.license_state,
    email = excluded.email, verification_flags = '{}', reviewed_by = excluded.reviewed_by,
    reviewed_at = excluded.reviewed_at, review_note = excluded.review_note,
    is_demo = true;

  -- ---------------------------------------------------------------- 4. roster (hospital_doctors)
  insert into public.hospital_doctors (hospital_id, doctor_id, auto_approve, approved_at)
  values
    (c_hosp, c_doctor, true,  timestamptz '2026-09-15 16:00:00+00'),  -- reviewer's doctor: approved + auto-approve
    (c_hosp, f_patel,  true,  timestamptz '2026-09-01 16:00:00+00'),
    (c_hosp, f_brooks, false, timestamptz '2026-09-03 16:00:00+00'),
    (c_hosp, f_liu,    false, timestamptz '2026-09-05 16:00:00+00'),
    (c_hosp, f_haddad, false, timestamptz '2026-09-08 16:00:00+00'),
    (c_hosp, f_ramirez, false, null)                                   -- pending roster request
  on conflict (hospital_id, doctor_id) do update
    set auto_approve = excluded.auto_approve, approved_at = excluded.approved_at;
  -- The membership trigger fills approved_at on INSERT; set the pending row back to NULL.
  update public.hospital_doctors set approved_at = null, auto_approve = false
  where hospital_id = c_hosp and doctor_id = f_ramirez;

  -- ---------------------------------------------------------------- 5. shifts: 1 Oct to 30 Nov 2026
  -- 4 specialties x 60 days (26 Nov is blocked) = 240 day shifts. Each is stored at
  -- 12:00 UTC, so it lands on the same calendar day in every US time zone. The apps
  -- take the local start of day, and token shift_date uses the UTC date.
  -- (The existing rows at 06:00 UTC show one day early on a Pacific-time device.)
  insert into public.shifts (id, hospital_id, hospital_name, specialty, date, rate_floor, rate_unit, duration_hours, escalation)
  select md5('mdshift-review-demo|shift|' || d::date || '|' || sp.name)::uuid,
         c_hosp, c_hosp_name, sp.name,
         (d::date + time '12:00') at time zone 'UTC',
         sp.base + case when extract(isodow from d) in (6, 7) then 150 else 0 end,
         'per_day', 24, '{"type":"automatic","usesAlgorithmPricing":true}'::jsonb
  from generate_series(date '2026-10-01', date '2026-11-30', interval '1 day') as d
  cross join (values ('Orthopedics', 1500), ('Emergency Medicine', 1400),
                     ('Internal Medicine', 1100), ('Anesthesiology', 1450)) as sp(name, base)
  where d::date <> date '2026-11-26'
  on conflict (id) do update set
    hospital_id = excluded.hospital_id, hospital_name = excluded.hospital_name,
    specialty = excluded.specialty, date = excluded.date, rate_floor = excluded.rate_floor,
    rate_unit = excluded.rate_unit, duration_hours = excluded.duration_hours,
    escalation = excluded.escalation;

  -- ---------------------------------------------------------------- 6. assignments (fill rate about 50%)
  -- n = days since 1 Oct.
  --   Orthopedics: jdunn on 6, 14, 22 Oct and 3, 12, 20 Nov. Open when n % 3 = 2.
  --     Otherwise Patel on even n, Brooks on odd n.
  --   Emergency Medicine: Liu unless n % 4 = 3.  Internal Medicine: Haddad when n % 5 < 3.
  --   Anesthesiology: all open (the hard-to-fill specialty).
  with s as (
    select id, specialty, (date at time zone 'UTC')::date as day,
           ((date at time zone 'UTC')::date - date '2026-10-01') as n
    from public.shifts where hospital_id = c_hosp
  ), pick as (
    select s.id as shift_id,
      case
        when s.specialty = 'Orthopedics' and s.day in (date '2026-10-06', date '2026-10-14', date '2026-10-22',
                                                       date '2026-11-03', date '2026-11-12', date '2026-11-20') then c_doctor
        when s.specialty = 'Orthopedics' and s.n % 3 = 2 then null
        when s.specialty = 'Orthopedics' and s.n % 2 = 0 then f_patel
        when s.specialty = 'Orthopedics' then f_brooks
        when s.specialty = 'Emergency Medicine' and s.n % 4 <> 3 then f_liu
        when s.specialty = 'Internal Medicine' and s.n % 5 < 3 then f_haddad
        else null
      end as doctor_id,
      s.day
    from s
  )
  insert into public.assignments (id, shift_id, doctor_id, status, assigned_at)
  select md5('mdshift-review-demo|assignment|' || shift_id)::uuid, shift_id, doctor_id, 'scheduled',
         timestamptz '2026-09-10 15:00:00+00' + ((day - date '2026-10-01') % 19) * interval '1 day'
  from pick where doctor_id is not null
  on conflict (shift_id) do update
    set doctor_id = excluded.doctor_id, status = 'scheduled', assigned_at = excluded.assigned_at
    -- Only reset rows that already belong to a demo doctor. Never touch anyone else's row.
    where public.assignments.doctor_id in (c_doctor, f_patel, f_brooks, f_liu, f_haddad, f_ramirez);

  -- ---------------------------------------------------------------- 7. token requests
  insert into public.token_requests (id, doctor_id, hospital_id, shift_date, status, specialty, requested_at)
  select md5('mdshift-review-demo|token|' || t.tag)::uuid, t.doc, c_hosp, t.day, t.st::token_status, t.sp, t.ts
  from (values
    -- Pending: these appear in the hospital's approvals queue.
    ('p1', f_patel,  date '2026-10-09', 'pending', 'Orthopedics',        timestamptz '2026-09-29 14:05:00+00'),
    ('p2', f_liu,    date '2026-10-04', 'pending', 'Emergency Medicine', timestamptz '2026-09-29 18:40:00+00'),
    ('p3', f_haddad, date '2026-10-10', 'pending', 'Internal Medicine',  timestamptz '2026-09-30 01:15:00+00'),
    ('p4', f_brooks, date '2026-10-27', 'pending', 'Orthopedics',        timestamptz '2026-09-30 03:30:00+00'),
    -- History.
    ('h1', f_brooks, date '2026-10-02', 'approved', 'Orthopedics',        timestamptz '2026-09-12 15:00:00+00'),
    ('h2', f_liu,    date '2026-10-01', 'approved', 'Emergency Medicine', timestamptz '2026-09-12 16:00:00+00'),
    ('h3', f_brooks, date '2026-10-03', 'denied',   'Orthopedics',        timestamptz '2026-09-14 16:00:00+00'),
    -- The demo doctor's six shifts (auto-approved roster member).
    ('j1', c_doctor, date '2026-10-06', 'auto_approved', 'Orthopedics', timestamptz '2026-09-16 15:00:00+00'),
    ('j2', c_doctor, date '2026-10-14', 'auto_approved', 'Orthopedics', timestamptz '2026-09-16 15:01:00+00'),
    ('j3', c_doctor, date '2026-10-22', 'auto_approved', 'Orthopedics', timestamptz '2026-09-16 15:02:00+00'),
    ('j4', c_doctor, date '2026-11-03', 'auto_approved', 'Orthopedics', timestamptz '2026-09-18 15:00:00+00'),
    ('j5', c_doctor, date '2026-11-12', 'auto_approved', 'Orthopedics', timestamptz '2026-09-18 15:01:00+00'),
    ('j6', c_doctor, date '2026-11-20', 'auto_approved', 'Orthopedics', timestamptz '2026-09-18 15:02:00+00')
  ) as t(tag, doc, day, st, sp, ts)
  on conflict (id) do update set
    doctor_id = excluded.doctor_id, hospital_id = excluded.hospital_id, shift_date = excluded.shift_date,
    status = excluded.status, specialty = excluded.specialty, requested_at = excluded.requested_at;

  -- ---------------------------------------------------------------- 8. trades (all pending)
  -- guard_trade_parties: from_doctor must hold the shift (see section 6), and from <> to.
  insert into public.trade_requests (id, shift_id, from_doctor_id, to_doctor_id, state, compensation_amount,
      requested_shift_id, from_doctor_name, to_doctor_name, offered_date, requested_date, specialty, created_at, updated_at)
  select md5('mdshift-review-demo|trade|' || t.tag)::uuid,
         md5('mdshift-review-demo|shift|' || t.offered || '|Orthopedics')::uuid,
         t.from_doc, t.to_doc, 'pending', t.comp,
         case when t.req is null then null else md5('mdshift-review-demo|shift|' || t.req || '|Orthopedics')::uuid end,
         t.from_name, t.to_name,
         (t.offered + time '12:00') at time zone 'UTC',
         case when t.req is null then null else (t.req + time '12:00') at time zone 'UTC' end,
         'Orthopedics', t.ts, t.ts
  from (values
    -- Incoming 1: Patel offers her 17 Oct shift in exchange for jdunn's 22 Oct shift.
    ('in1',  f_patel,  c_doctor, date '2026-10-17', date '2026-10-22', 0::numeric,
             'Maya Patel, MD', 'Jordan Dunn, MD', timestamptz '2026-09-28 17:20:00+00'),
    -- Incoming 2: Brooks gives away his 7 Nov shift and adds $250.
    ('in2',  f_brooks, c_doctor, date '2026-11-07', null::date, 250::numeric,
             'Daniel Brooks, DO', 'Jordan Dunn, MD', timestamptz '2026-09-29 20:05:00+00'),
    -- Outgoing: jdunn offers his 20 Nov shift to Patel with $150.
    ('out1', c_doctor, f_patel, date '2026-11-20', null::date, 150::numeric,
             'Jordan Dunn, MD', 'Maya Patel, MD', timestamptz '2026-09-30 02:10:00+00')
  ) as t(tag, from_doc, to_doc, offered, req, comp, from_name, to_name, ts)
  on conflict (id) do update set
    state = 'pending', compensation_amount = excluded.compensation_amount,
    requested_shift_id = excluded.requested_shift_id, from_doctor_name = excluded.from_doctor_name,
    to_doctor_name = excluded.to_doctor_name, offered_date = excluded.offered_date,
    requested_date = excluded.requested_date, specialty = excluded.specialty, updated_at = now();

  -- ---------------------------------------------------------------- 9. penalties and savings
  insert into public.penalty_ledger (id, doctor_id, hospital_id, shift_id, type, amount, created_at)
  values
    (md5('mdshift-review-demo|penalty|1')::uuid, f_brooks, c_hosp,
     md5('mdshift-review-demo|shift|2026-10-11|Orthopedics')::uuid, 'cancel', 425, timestamptz '2026-09-24 15:00:00+00'),
    (md5('mdshift-review-demo|penalty|2')::uuid, f_liu, c_hosp,
     md5('mdshift-review-demo|shift|2026-10-15|Emergency Medicine')::uuid, 'trade', 75, timestamptz '2026-09-26 15:00:00+00')
  on conflict (id) do update set
    doctor_id = excluded.doctor_id,
    hospital_id = excluded.hospital_id,
    shift_id = excluded.shift_id,
    type = excluded.type,
    amount = excluded.amount,
    created_at = excluded.created_at;

  insert into public.hospital_savings_events (event_key, hospital_id, hospital_name, shift_id, specialty, kind, amount,
      occurred_at, source, metadata, created_by)
  select 'review-demo:' || e.k, c_hosp, c_hosp_name,
         md5('mdshift-review-demo|shift|' || e.day || '|' || e.sp)::uuid, e.sp, e.kind, e.amt, e.ts, 'seed',
         jsonb_build_object('demo', true), null
  from (values
    ('rate:1',  date '2026-10-01', 'Emergency Medicine', 'rate_savings',   310, timestamptz '2026-09-02 15:00:00+00'),
    ('rate:2',  date '2026-10-02', 'Orthopedics',        'rate_savings',   280, timestamptz '2026-09-04 15:00:00+00'),
    ('rate:3',  date '2026-10-06', 'Internal Medicine',  'rate_savings',   190, timestamptz '2026-09-07 15:00:00+00'),
    ('rate:4',  date '2026-10-06', 'Orthopedics',        'rate_savings',   340, timestamptz '2026-09-16 15:00:00+00'),
    ('rate:5',  date '2026-10-08', 'Orthopedics',        'rate_savings',   260, timestamptz '2026-09-10 15:00:00+00'),
    ('rate:6',  date '2026-10-13', 'Emergency Medicine', 'rate_savings',   220, timestamptz '2026-09-13 15:00:00+00'),
    ('rate:7',  date '2026-10-14', 'Orthopedics',        'rate_savings',   300, timestamptz '2026-09-16 15:01:00+00'),
    ('rate:8',  date '2026-10-16', 'Internal Medicine',  'rate_savings',   150, timestamptz '2026-09-18 15:00:00+00'),
    ('rate:9',  date '2026-10-22', 'Orthopedics',        'rate_savings',   275, timestamptz '2026-09-16 15:02:00+00'),
    ('rate:10', date '2026-11-03', 'Orthopedics',        'rate_savings',   230, timestamptz '2026-09-18 15:00:00+00'),
    ('pen:1',   date '2026-10-11', 'Orthopedics',        'penalty_cancel', 425, timestamptz '2026-09-24 15:00:00+00'),
    ('pen:2',   date '2026-10-15', 'Emergency Medicine', 'penalty_trade',   75, timestamptz '2026-09-26 15:00:00+00')
  ) as e(k, day, sp, kind, amt, ts)
  on conflict (event_key) do update set
    hospital_id = excluded.hospital_id, amount = excluded.amount, occurred_at = excluded.occurred_at,
    shift_id = excluded.shift_id, specialty = excluded.specialty, kind = excluded.kind;

  raise notice 'Demo seed done. Hospital user %, hospital %.', v_hosp_user, c_hosp;
end $$;

-- Quick check (read-only):
-- select (select count(*) from shifts where hospital_id='de000000-0000-4000-8000-000000000001') shifts,
--        (select count(*) from assignments a join shifts s on s.id=a.shift_id where s.hospital_id='de000000-0000-4000-8000-000000000001') filled,
--        (select count(*) from token_requests where hospital_id='de000000-0000-4000-8000-000000000001' and status='pending') pending_tokens,
--        (select count(*) from trade_requests where from_doctor_id='d10290cb-1dd6-4e65-8a9d-7efb4ea83419' or to_doctor_id='d10290cb-1dd6-4e65-8a9d-7efb4ea83419') trades;

commit;

-- =============================================================================
-- APPENDIX A: remove the demo data after approval. Commented out. Review before use.
-- Assignments and trades go first because their foreign keys do not cascade.
-- =============================================================================
-- begin;
-- delete from trade_requests  where id in (select md5('mdshift-review-demo|trade|'||t)::uuid from unnest(array['in1','in2','out1']) t)
--    or shift_id in (select id from shifts where hospital_id='de000000-0000-4000-8000-000000000001');
-- delete from penalty_ledger  where hospital_id='de000000-0000-4000-8000-000000000001';
-- delete from token_requests  where hospital_id='de000000-0000-4000-8000-000000000001';
-- delete from assignments     where shift_id in (select id from shifts where hospital_id='de000000-0000-4000-8000-000000000001');
-- delete from hospital_profiles where id='de000000-0000-4000-8000-000000000001';  -- cascades shifts, roster, policy, savings, unavailable_days
-- delete from email_verification_challenges where email='review-hospital@mdshift.net';
-- delete from auth.users where id in ('de000000-0000-4000-9000-000000000011','de000000-0000-4000-9000-000000000012',
--   'de000000-0000-4000-9000-000000000013','de000000-0000-4000-9000-000000000014','de000000-0000-4000-9000-000000000015');
--   -- cascades profiles and doctor_profiles
-- -- Delete the hospital login in Dashboard > Authentication. The doctor account's
-- -- old values (J Dunn, NPI 1679576722) are not restored on purpose.
-- commit;

-- Demo hospital isolation lives in migration 20260930150000_app_review_access.sql.
-- Demo doctor isolation lives in migration 20260930180000_demo_doctor_scope.sql.
-- This seed sets hospital_profiles.is_demo and doctor_profiles.is_demo.
