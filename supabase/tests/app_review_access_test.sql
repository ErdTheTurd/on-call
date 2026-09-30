-- Proves the App Review seed and the access rules around it.
-- Assumes migrations and supabase/seed/app_review_demo.sql have been applied.
-- Rolls back its own fixture so the seed stays in place.

\set ON_ERROR_STOP on

begin;

-- ---------------------------------------------------------------------------
-- Seed shape, read as the owner.
-- ---------------------------------------------------------------------------

do $$
declare
  v_hosp uuid := 'de000000-0000-4000-8000-000000000001';
  v_doctor uuid := 'd10290cb-1dd6-4e65-8a9d-7efb4ea83419';
  v_shifts int;
  v_filled int;
  v_open int;
  v_pending int;
  v_trades int;
begin
  if (select npi from public.doctor_profiles where profile_id = v_doctor) is distinct from '1999999992' then
    raise exception 'demo doctor NPI was not replaced';
  end if;
  if (select npi from public.doctor_profiles where profile_id = v_doctor) = '1679576722' then
    raise exception 'demo doctor still has the real NPI';
  end if;
  if (select verification_status::text from public.doctor_profiles where profile_id = v_doctor) is distinct from 'verified' then
    raise exception 'demo doctor is not verified';
  end if;
  if (select first_name || ' ' || last_name from public.doctor_profiles where profile_id = v_doctor) is distinct from 'Jordan Dunn' then
    raise exception 'demo doctor name was not finished';
  end if;
  if not exists (
    select 1 from public.hospital_profiles
    where id = v_hosp and is_demo and email = 'review-hospital@mdshift.net' and verification_status = 'verified'
  ) then
    raise exception 'demo hospital is missing or not flagged is_demo';
  end if;
  select count(*) into v_shifts from public.shifts where hospital_id = v_hosp;
  select count(*) into v_filled
  from public.assignments a
  join public.shifts s on s.id = a.shift_id
  where s.hospital_id = v_hosp and a.status = 'scheduled';
  v_open := v_shifts - v_filled;
  if v_shifts <> 240 or v_filled <> 124 or v_open <> 116 then
    raise exception 'expected 240 shifts, 124 filled, 116 open; got % / % / %', v_shifts, v_filled, v_open;
  end if;
  select count(*) into v_pending from public.token_requests
  where hospital_id = v_hosp and status = 'pending';
  if v_pending <> 4 then
    raise exception 'expected 4 pending token requests, got %', v_pending;
  end if;
  select count(*) into v_trades from public.trade_requests
  where from_doctor_id = v_doctor or to_doctor_id = v_doctor;
  if v_trades <> 3 then
    raise exception 'expected 3 trades for the demo doctor, got %', v_trades;
  end if;
  if (select count(*) from public.hospital_doctors where hospital_id = v_hosp and approved_at is null) <> 1 then
    raise exception 'expected one pending roster request';
  end if;
  if (select count(*) from public.penalty_ledger where hospital_id = v_hosp) <> 2 then
    raise exception 'expected 2 penalties';
  end if;
  if (select count(*) from public.hospital_savings_events where hospital_id = v_hosp) <> 12 then
    raise exception 'expected 12 savings events';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'token_request_queue'
      and column_name in ('npi', 'email', 'dea_number', 'license_number')
  ) then
    raise exception 'token_request_queue exposes a credential column it should not';
  end if;
end $$;

-- A real, non-demo hospital so we can prove ordinary doctors still see ordinary shifts.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token, email_change
) values (
  '00000000-0000-0000-0000-000000000000',
  'aa000000-0000-4000-8000-0000000000aa',
  'authenticated', 'authenticated', 'unrelated.doctor@example.com', '', now(),
  '{}', '{}', now(), now(), '', '', '', ''
), (
  '00000000-0000-0000-0000-000000000000',
  'aa000000-0000-4000-8000-0000000000bb',
  'authenticated', 'authenticated', 'real.hospital@example.com', '', now(),
  '{}', '{}', now(), now(), '', '', '', ''
) on conflict (id) do nothing;

insert into public.profiles (id, email, role) values
  ('aa000000-0000-4000-8000-0000000000aa', 'unrelated.doctor@example.com', 'doctor'),
  ('aa000000-0000-4000-8000-0000000000bb', 'real.hospital@example.com', 'hospital')
on conflict (id) do nothing;

insert into public.doctor_profiles (
  profile_id, first_name, last_name, credential, npi, specialties, verification_status, email
) values (
  'aa000000-0000-4000-8000-0000000000aa', 'Una', 'Related', 'MD', '1234567893',
  '{Cardiology}', 'verified', 'unrelated.doctor@example.com'
) on conflict (profile_id) do nothing;

insert into public.hospital_profiles (id, profile_id, name, npi, email, verification_status, is_demo)
values (
  'aa000000-0000-4000-8000-0000000000cc',
  'aa000000-0000-4000-8000-0000000000bb',
  'Real Community Hospital', '1234567893', 'real.hospital@example.com', 'verified', false
);

insert into public.shifts (id, hospital_id, hospital_name, specialty, date, rate_floor)
values (
  'aa000000-0000-4000-8000-0000000000dd',
  'aa000000-0000-4000-8000-0000000000cc',
  'Real Community Hospital', 'Cardiology', timestamptz '2026-10-08 12:00:00+00', 1200
);

-- ---------------------------------------------------------------------------
-- Unrelated doctor: no demo shifts, no demo requests, no demo roster join.
-- The real hospital's shift is still visible.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'aa000000-0000-4000-8000-0000000000aa', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"aa000000-0000-4000-8000-0000000000aa","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.shifts where hospital_id = 'de000000-0000-4000-8000-000000000001') <> 0 then
    raise exception 'unrelated doctor can see demo shifts';
  end if;
  if (select count(*) from public.shifts where hospital_id = 'aa000000-0000-4000-8000-0000000000cc') <> 1 then
    raise exception 'unrelated doctor cannot see a real hospital shift';
  end if;
  if (select count(*) from public.shift_coverage where hospital_id = 'de000000-0000-4000-8000-000000000001') <> 0 then
    raise exception 'unrelated doctor can see demo coverage';
  end if;
  if (select count(*) from public.token_request_queue where hospital_id = 'de000000-0000-4000-8000-000000000001') <> 0 then
    raise exception 'unrelated doctor can see demo approval names';
  end if;
  begin
    insert into public.token_requests (doctor_id, hospital_id, shift_date, specialty)
    values (auth.uid(), 'de000000-0000-4000-8000-000000000001', date '2026-10-09', 'Orthopedics');
    raise exception 'unrelated doctor requested a demo shift';
  exception when others then
    if sqlerrm like '%unrelated doctor requested a demo shift%' then raise; end if;
    if sqlerrm not like '%row-level security%' then raise; end if;
  end;
  begin
    insert into public.hospital_doctors (hospital_id, doctor_id, auto_approve, approved_at)
    values ('de000000-0000-4000-8000-000000000001', auth.uid(), false, null);
    raise exception 'unrelated doctor joined the demo roster';
  exception when others then
    if sqlerrm like '%unrelated doctor joined the demo roster%' then raise; end if;
    if sqlerrm not like '%row-level security%' then raise; end if;
  end;
  if exists (
    select 1 from public.doctor_profiles
    where profile_id <> auth.uid()
  ) then
    raise exception 'unrelated doctor can read another doctor profile';
  end if;
end $$;

reset role;

-- ---------------------------------------------------------------------------
-- Demo doctor sees the board, their shifts, trades, and peer names.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'd10290cb-1dd6-4e65-8a9d-7efb4ea83419', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"d10290cb-1dd6-4e65-8a9d-7efb4ea83419","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.shifts where hospital_id = 'de000000-0000-4000-8000-000000000001') <> 240 then
    raise exception 'demo doctor cannot see the demo board';
  end if;
  if (select count(*) from public.shifts where hospital_id = 'aa000000-0000-4000-8000-0000000000cc') <> 1 then
    raise exception 'demo doctor lost visibility of a real hospital';
  end if;
  if (select count(*) from public.assignments where doctor_id = auth.uid()) <> 6 then
    raise exception 'demo doctor cannot see their six assignments';
  end if;
  if (select count(*) from public.trade_requests
      where state = 'pending' and (from_doctor_id = auth.uid() or to_doctor_id = auth.uid())) <> 3 then
    raise exception 'demo doctor cannot see their three trades';
  end if;
  if (select count(*) from public.hospital_roster
      where hospital_id = 'de000000-0000-4000-8000-000000000001'
        and approved_at is not null) < 5 then
    raise exception 'demo doctor cannot see approved roster peers';
  end if;
  if exists (
    select 1 from public.doctor_profiles
    where profile_id <> auth.uid() and npi is not null
  ) then
    raise exception 'demo doctor can read another doctor''s credential row';
  end if;
end $$;

reset role;

-- ---------------------------------------------------------------------------
-- Demo hospital: names on approvals, full roster, unchanged save after 24h,
-- email change still needs a code, is_demo cannot be cleared by the client.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'de000000-0000-4000-8000-0000000000aa', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"de000000-0000-4000-8000-0000000000aa","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.shifts where hospital_id = 'de000000-0000-4000-8000-000000000001') <> 240 then
    raise exception 'demo hospital cannot see its shifts';
  end if;
  if (select count(*) from public.assignments a
      join public.shifts s on s.id = a.shift_id
      where s.hospital_id = 'de000000-0000-4000-8000-000000000001') <> 124 then
    raise exception 'demo hospital cannot see its assignments';
  end if;
  if (select count(*) from public.token_request_queue
      where hospital_id = 'de000000-0000-4000-8000-000000000001' and status = 'pending'
        and doctor_name in ('Maya Patel', 'Grace Liu', 'Omar Haddad', 'Daniel Brooks')) <> 4 then
    raise exception 'demo hospital cannot see pending doctors by name';
  end if;
  if exists (
    select 1 from public.token_request_queue
    where hospital_id = 'de000000-0000-4000-8000-000000000001'
      and (doctor_name is null or btrim(doctor_name) = '' or doctor_name = 'Doctor')
  ) then
    raise exception 'a demo approval is missing its doctor name';
  end if;
  if (select count(*) from public.hospital_roster where hospital_id = 'de000000-0000-4000-8000-000000000001') <> 6 then
    raise exception 'demo hospital cannot see the full roster, including the pending doctor';
  end if;
  if exists (select 1 from public.doctor_profiles where npi = '1999999919') then
    raise exception 'demo hospital can read a doctor NPI from doctor_profiles';
  end if;
end $$;

reset role;

-- Age the verified code, then save unchanged data as the hospital.
update public.email_verification_challenges
  set verified_at = now() - interval '25 hours'
  where email = 'review-hospital@mdshift.net';

select set_config('request.jwt.claim.sub', 'de000000-0000-4000-8000-0000000000aa', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

update public.hospital_profiles
  set name = 'MD Shift Demo Medical Center'
  where id = 'de000000-0000-4000-8000-000000000001';

insert into public.hospital_profiles (id, profile_id, name, npi, email, verification_status)
values (
  'de000000-0000-4000-8000-000000000001',
  'de000000-0000-4000-8000-0000000000aa',
  'MD Shift Demo Medical Center',
  '2990000004',
  'review-hospital@mdshift.net',
  'verified'
)
on conflict (id) do update
  set name = excluded.name, npi = excluded.npi, email = excluded.email;

do $$
begin
  begin
    update public.hospital_profiles
      set email = 'changed@mdshift.net'
      where id = 'de000000-0000-4000-8000-000000000001';
    raise exception 'hospital changed its email without a fresh code';
  exception when others then
    if sqlerrm like '%hospital changed its email without a fresh code%' then raise; end if;
    if sqlerrm not like '%not verified%' then raise; end if;
  end;
  update public.hospital_profiles
    set is_demo = false
    where id = 'de000000-0000-4000-8000-000000000001';
  if (select is_demo from public.hospital_profiles where id = 'de000000-0000-4000-8000-000000000001') is distinct from true then
    raise exception 'hospital client cleared is_demo';
  end if;
  if (select email from public.hospital_profiles where id = 'de000000-0000-4000-8000-000000000001')
     is distinct from 'review-hospital@mdshift.net' then
    raise exception 'hospital email changed despite the guard';
  end if;
end $$;

reset role;

rollback;
