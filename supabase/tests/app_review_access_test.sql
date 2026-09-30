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
  if (select is_demo from public.doctor_profiles where profile_id = v_doctor) is distinct from true then
    raise exception 'demo doctor is not flagged is_demo';
  end if;
  if (
    select count(*)
    from public.doctor_profiles
    where is_demo
      and profile_id in (
        'de000000-0000-4000-9000-000000000011',
        'de000000-0000-4000-9000-000000000012',
        'de000000-0000-4000-9000-000000000013',
        'de000000-0000-4000-9000-000000000014',
        'de000000-0000-4000-9000-000000000015'
      )
  ) <> 5 then
    raise exception 'placeholder doctors are not flagged is_demo';
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
  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'token_request_queue'
      and c.reloptions @> array['security_invoker=true']
  ) or not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'shift_coverage'
      and c.reloptions @> array['security_invoker=true']
  ) then
    raise exception 'approval or coverage view is not security_invoker';
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
  update public.doctor_profiles set is_demo = true where profile_id = auth.uid();
  if (select is_demo from public.doctor_profiles where profile_id = auth.uid()) is distinct from false then
    raise exception 'doctor client set is_demo';
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
  if (select count(*) from public.shifts where hospital_id = 'aa000000-0000-4000-8000-0000000000cc') <> 0 then
    raise exception 'demo doctor can see a non-demo hospital shift';
  end if;
  if (select count(*) from public.shift_coverage where hospital_id = 'aa000000-0000-4000-8000-0000000000cc') <> 0 then
    raise exception 'demo doctor can see non-demo coverage';
  end if;
  if (select count(*) from public.assignments a
      join public.shifts s on s.id = a.shift_id
      where s.hospital_id = 'aa000000-0000-4000-8000-0000000000cc') <> 0 then
    raise exception 'demo doctor can see a non-demo assignment';
  end if;
  if (select count(*) from public.assignments where doctor_id = auth.uid()) <> 6 then
    raise exception 'demo doctor cannot see their six assignments';
  end if;
  if (select count(*) from public.shift_coverage
      where hospital_id = 'de000000-0000-4000-8000-000000000001' and is_filled) <> 124 then
    raise exception 'demo doctor cannot see which demo shifts are filled';
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
  if (select count(*) from public.doctor_directory
      where profile_id = 'de000000-0000-4000-9000-000000000011') <> 1 then
    raise exception 'demo doctor cannot see a demo-hospital peer';
  end if;
  if exists (
    select 1 from public.doctor_directory
    where profile_id = 'aa000000-0000-4000-8000-0000000000aa'
  ) then
    raise exception 'demo doctor can see a non-demo doctor in the directory';
  end if;
  update public.doctor_profiles set is_demo = false where profile_id = auth.uid();
  if (select is_demo from public.doctor_profiles where profile_id = auth.uid()) is distinct from true then
    raise exception 'demo doctor cleared is_demo';
  end if;
  begin
    insert into public.token_requests (doctor_id, hospital_id, shift_date, specialty)
    values (auth.uid(), 'aa000000-0000-4000-8000-0000000000cc', date '2026-10-08', 'Cardiology');
    raise exception 'demo doctor requested a non-demo shift';
  exception when others then
    if sqlerrm like '%demo doctor requested a non-demo shift%' then raise; end if;
    if sqlerrm not like '%demo doctors%' then raise; end if;
  end;
  begin
    insert into public.hospital_doctors (hospital_id, doctor_id, auto_approve, approved_at)
    values ('aa000000-0000-4000-8000-0000000000cc', auth.uid(), false, null);
    raise exception 'demo doctor joined a non-demo roster';
  exception when others then
    if sqlerrm like '%demo doctor joined a non-demo roster%' then raise; end if;
    if sqlerrm not like '%demo doctors%' then raise; end if;
  end;
  begin
    insert into public.assignments (shift_id, doctor_id, status)
    values ('aa000000-0000-4000-8000-0000000000dd', auth.uid(), 'scheduled');
    raise exception 'demo doctor accepted a non-demo shift';
  exception when others then
    if sqlerrm like '%demo doctor accepted a non-demo shift%' then raise; end if;
    if sqlerrm not like '%demo doctors%' then raise; end if;
  end;
  begin
    insert into public.trade_requests (shift_id, from_doctor_id, to_doctor_id, state)
    select a.shift_id, auth.uid(), 'aa000000-0000-4000-8000-0000000000aa', 'pending'
    from public.assignments a
    where a.doctor_id = auth.uid()
      and a.status <> 'canceled'
    limit 1;
    raise exception 'demo doctor traded with a non-demo doctor';
  exception when others then
    if sqlerrm like '%demo doctor traded with a non-demo doctor%' then raise; end if;
    if sqlerrm not like '%demo doctors%' then raise; end if;
  end;
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
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claims', '{}', true);

-- ---------------------------------------------------------------------------
-- A normal doctor who can see the demo board still cannot see the demo doctor.
-- Link them only after the unlinked checks above. Also flag a doctor who
-- already has a real-hospital roster row, which is the row a non-demo
-- hospital would otherwise show.
-- ---------------------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token, email_change
) values (
  '00000000-0000-0000-0000-000000000000',
  'ee000000-0000-4000-8000-0000000000ee',
  'authenticated', 'authenticated', 'soon.demo@example.com', '', now(),
  '{}', '{}', now(), now(), '', '', '', ''
) on conflict (id) do nothing;

insert into public.profiles (id, email, role) values
  ('ee000000-0000-4000-8000-0000000000ee', 'soon.demo@example.com', 'doctor')
on conflict (id) do nothing;

insert into public.doctor_profiles (
  profile_id, first_name, last_name, credential, npi, specialties, verification_status, email, is_demo
) values (
  'ee000000-0000-4000-8000-0000000000ee', 'Erin', 'Edge', 'MD', '1234567893',
  '{Cardiology}', 'verified', 'soon.demo@example.com', false
) on conflict (profile_id) do update set is_demo = false;

insert into public.shifts (id, hospital_id, hospital_name, specialty, date, rate_floor)
values (
  'ee000000-0000-4000-8000-0000000000e1',
  'aa000000-0000-4000-8000-0000000000cc',
  'Real Community Hospital', 'Cardiology', timestamptz '2026-10-09 12:00:00+00', 1200
);

insert into public.assignments (shift_id, doctor_id, status) values
  ('aa000000-0000-4000-8000-0000000000dd', 'aa000000-0000-4000-8000-0000000000aa', 'scheduled'),
  ('ee000000-0000-4000-8000-0000000000e1', 'ee000000-0000-4000-8000-0000000000ee', 'scheduled');

insert into public.hospital_doctors (hospital_id, doctor_id, auto_approve, approved_at) values
  ('aa000000-0000-4000-8000-0000000000cc', 'aa000000-0000-4000-8000-0000000000aa', false, now()),
  ('aa000000-0000-4000-8000-0000000000cc', 'ee000000-0000-4000-8000-0000000000ee', false, now()),
  ('de000000-0000-4000-8000-000000000001', 'aa000000-0000-4000-8000-0000000000aa', false, now());

update public.doctor_profiles
  set is_demo = true
  where profile_id = 'ee000000-0000-4000-8000-0000000000ee';

select set_config('request.jwt.claim.sub', 'aa000000-0000-4000-8000-0000000000aa', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"aa000000-0000-4000-8000-0000000000aa","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.shifts where hospital_id = 'de000000-0000-4000-8000-000000000001') <> 240 then
    raise exception 'linked normal doctor lost the demo board';
  end if;
  if (select count(*) from public.shifts where hospital_id = 'aa000000-0000-4000-8000-0000000000cc') <> 2 then
    raise exception 'linked normal doctor lost the real hospital board';
  end if;
  if exists (
    select 1 from public.doctor_directory
    where profile_id in (
      'd10290cb-1dd6-4e65-8a9d-7efb4ea83419',
      'ee000000-0000-4000-8000-0000000000ee',
      'de000000-0000-4000-9000-000000000011'
    )
  ) then
    raise exception 'normal doctor can see a demo doctor in the directory';
  end if;
  if exists (
    select 1 from public.hospital_roster
    where doctor_id in (
      'd10290cb-1dd6-4e65-8a9d-7efb4ea83419',
      'ee000000-0000-4000-8000-0000000000ee',
      'de000000-0000-4000-9000-000000000011'
    )
  ) then
    raise exception 'normal doctor can see a demo doctor on a roster';
  end if;
  if (select count(*) from public.doctor_directory
      where profile_id = 'aa000000-0000-4000-8000-0000000000aa') <> 1 then
    raise exception 'normal doctor cannot see their own directory card';
  end if;
  begin
    insert into public.trade_requests (shift_id, from_doctor_id, to_doctor_id, state)
    values (
      'aa000000-0000-4000-8000-0000000000dd',
      auth.uid(),
      'd10290cb-1dd6-4e65-8a9d-7efb4ea83419',
      'pending'
    );
    raise exception 'normal doctor traded with the demo doctor';
  exception when others then
    if sqlerrm like '%normal doctor traded with the demo doctor%' then raise; end if;
    if sqlerrm not like '%demo doctors%' then raise; end if;
  end;
  begin
    insert into public.trade_requests (shift_id, from_doctor_id, to_doctor_id, state)
    values (
      'aa000000-0000-4000-8000-0000000000dd',
      auth.uid(),
      'ee000000-0000-4000-8000-0000000000ee',
      'pending'
    );
    raise exception 'normal doctor traded with a demo doctor';
  exception when others then
    if sqlerrm like '%normal doctor traded with a demo doctor%' then raise; end if;
    if sqlerrm not like '%demo doctors%' then raise; end if;
  end;
end $$;

reset role;
select set_config('request.jwt.claim.sub', 'aa000000-0000-4000-8000-0000000000bb', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"aa000000-0000-4000-8000-0000000000bb","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if exists (
    select 1 from public.doctor_directory
    where profile_id = 'ee000000-0000-4000-8000-0000000000ee'
  ) then
    raise exception 'non-demo hospital can see a demo doctor in the directory';
  end if;
  if exists (
    select 1 from public.hospital_roster
    where doctor_id = 'ee000000-0000-4000-8000-0000000000ee'
  ) then
    raise exception 'non-demo hospital can see a demo doctor on the roster';
  end if;
  if (select count(*) from public.doctor_directory
      where profile_id = 'aa000000-0000-4000-8000-0000000000aa') <> 1 then
    raise exception 'non-demo hospital lost a normal roster doctor';
  end if;
  if (select count(*) from public.hospital_roster
      where doctor_id = 'aa000000-0000-4000-8000-0000000000aa') <> 1 then
    raise exception 'non-demo hospital lost a normal roster row';
  end if;
  if exists (
    select 1 from public.assignments
    where doctor_id = 'ee000000-0000-4000-8000-0000000000ee'
  ) then
    raise exception 'non-demo hospital can see a demo doctor assignment';
  end if;
  begin
    insert into public.hospital_doctors (hospital_id, doctor_id, auto_approve, approved_at)
    values (
      'aa000000-0000-4000-8000-0000000000cc',
      'd10290cb-1dd6-4e65-8a9d-7efb4ea83419',
      false,
      now()
    );
    raise exception 'non-demo hospital added the demo doctor';
  exception when others then
    if sqlerrm like '%non-demo hospital added the demo doctor%' then raise; end if;
    if sqlerrm not like '%demo doctors%' then raise; end if;
  end;
end $$;

reset role;
select set_config('request.jwt.claim.sub', 'd10290cb-1dd6-4e65-8a9d-7efb4ea83419', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"d10290cb-1dd6-4e65-8a9d-7efb4ea83419","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if exists (
    select 1 from public.doctor_directory
    where profile_id = 'aa000000-0000-4000-8000-0000000000aa'
  ) then
    raise exception 'demo doctor can see a non-demo peer after they join';
  end if;
  if exists (
    select 1 from public.hospital_roster
    where doctor_id = 'aa000000-0000-4000-8000-0000000000aa'
  ) then
    raise exception 'demo doctor can see a non-demo roster peer';
  end if;
  if (select count(*) from public.hospital_roster
      where hospital_id = 'de000000-0000-4000-8000-000000000001'
        and doctor_id = 'de000000-0000-4000-9000-000000000011') <> 1 then
    raise exception 'demo doctor lost a demo peer on the roster';
  end if;
end $$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

do $$
begin
  begin
    insert into public.token_requests (doctor_id, hospital_id, shift_date, specialty)
    values (
      'd10290cb-1dd6-4e65-8a9d-7efb4ea83419',
      'aa000000-0000-4000-8000-0000000000cc',
      date '2026-10-08',
      'Cardiology'
    );
    raise exception 'service role requested a non-demo shift for the demo doctor';
  exception when others then
    if sqlerrm like '%service role requested a non-demo shift%' then raise; end if;
    if sqlerrm not like '%demo doctors%' then raise; end if;
  end;
  begin
    insert into public.hospital_doctors (hospital_id, doctor_id, auto_approve, approved_at)
    values (
      'aa000000-0000-4000-8000-0000000000cc',
      'd10290cb-1dd6-4e65-8a9d-7efb4ea83419',
      false,
      now()
    );
    raise exception 'service role joined the demo doctor to a non-demo roster';
  exception when others then
    if sqlerrm like '%service role joined the demo doctor%' then raise; end if;
    if sqlerrm not like '%demo doctors%' then raise; end if;
  end;
  begin
    update public.assignments
      set doctor_id = 'd10290cb-1dd6-4e65-8a9d-7efb4ea83419'
      where shift_id = 'aa000000-0000-4000-8000-0000000000dd';
    raise exception 'service role moved the demo doctor onto a non-demo shift';
  exception when others then
    if sqlerrm like '%service role moved the demo doctor%' then raise; end if;
    if sqlerrm not like '%demo doctors%' then raise; end if;
  end;
  begin
    insert into public.trade_requests (shift_id, from_doctor_id, to_doctor_id, state)
    select a.shift_id, 'd10290cb-1dd6-4e65-8a9d-7efb4ea83419', 'aa000000-0000-4000-8000-0000000000aa', 'pending'
    from public.assignments a
    where a.doctor_id = 'd10290cb-1dd6-4e65-8a9d-7efb4ea83419'
      and a.status <> 'canceled'
    limit 1;
    raise exception 'service role traded the demo doctor with a non-demo doctor';
  exception when others then
    if sqlerrm like '%service role traded the demo doctor%' then raise; end if;
    if sqlerrm not like '%demo doctors%' then raise; end if;
  end;
  if (select doctor_id from public.assignments where shift_id = 'aa000000-0000-4000-8000-0000000000dd')
     is distinct from 'aa000000-0000-4000-8000-0000000000aa' then
    raise exception 'service role changed the real assignment';
  end if;
end $$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claims', '{}', true);

-- ---------------------------------------------------------------------------
-- More than 1000 older shifts must not hide the Oct–Nov board.
-- The client window is the UTC start of the month containing 2026-09-30,
-- minus 7 days (2026-08-25), paged at 1000. An unfiltered oldest page of
-- 1000 does not include 20 Nov.
-- ---------------------------------------------------------------------------

insert into public.shifts (id, hospital_id, hospital_name, specialty, date, rate_floor)
select gen_random_uuid(),
       'de000000-0000-4000-8000-000000000001',
       'MD Shift Demo Medical Center',
       'Orthopedics',
       ((date '2020-01-01' + g.i) + time '12:00') at time zone 'UTC',
       100
from generate_series(0, 1099) as g(i);

insert into public.shifts (id, hospital_id, hospital_name, specialty, date, rate_floor)
select gen_random_uuid(),
       'aa000000-0000-4000-8000-0000000000cc',
       'Real Community Hospital',
       'History ' || (g.i % 50),
       ((date '2026-08-25' + (g.i / 50)) + time '12:00') at time zone 'UTC',
       100
from generate_series(0, 999) as g(i);

-- The demo doctor cannot see the real hospital's history rows. The same
-- 1000-row crowd has to sit on the demo hospital so the first window page
-- is still full and 20 Nov still lands on the next page.
insert into public.shifts (id, hospital_id, hospital_name, specialty, date, rate_floor)
select gen_random_uuid(),
       'de000000-0000-4000-8000-000000000001',
       'MD Shift Demo Medical Center',
       'History ' || (g.i % 50),
       ((date '2026-08-25' + (g.i / 50)) + time '12:00') at time zone 'UTC',
       100
from generate_series(0, 999) as g(i);

select set_config('request.jwt.claim.sub', 'd10290cb-1dd6-4e65-8a9d-7efb4ea83419', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"d10290cb-1dd6-4e65-8a9d-7efb4ea83419","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_hosp uuid := 'de000000-0000-4000-8000-000000000001';
  v_window timestamptz := timestamptz '2026-08-25 00:00:00+00';
  v_nov20 uuid;
  v_page0 int;
  v_oct_nov int;
  v_open int;
  v_assigned int;
begin
  select id into v_nov20
  from public.shifts
  where hospital_id = v_hosp
    and specialty = 'Orthopedics'
    and date = timestamptz '2026-11-20 12:00:00+00';
  if v_nov20 is null then
    raise exception '20 Nov Orthopedics shift is missing';
  end if;
  if (select count(*) from public.shifts where hospital_id = 'aa000000-0000-4000-8000-0000000000cc') <> 0 then
    raise exception 'demo doctor can see non-demo hospital shifts';
  end if;

  if exists (
    select 1 from (
      select id from public.shifts
      order by date asc, id asc
      limit 1000
    ) oldest
    where oldest.id = v_nov20
  ) then
    raise exception 'unfiltered first 1000 rows still include the 20 Nov shift';
  end if;

  select count(*) into v_page0
  from (
    select id from public.shifts
    where date >= v_window
    order by date asc, id asc
    limit 1000 offset 0
  ) page;
  if v_page0 <> 1000 then
    raise exception 'expected a full first window page, got %', v_page0;
  end if;
  if exists (
    select 1 from (
      select id from public.shifts
      where date >= v_window
      order by date asc, id asc
      limit 1000 offset 0
    ) page
    where page.id = v_nov20
  ) then
    raise exception '20 Nov fit on the first window page, so paging is not what saved it';
  end if;

  select count(*) into v_oct_nov
  from (
    (
      select id from public.shifts
      where date >= v_window
      order by date asc, id asc
      limit 1000 offset 0
    )
    union all
    (
      select id from public.shifts
      where date >= v_window
      order by date asc, id asc
      limit 1000 offset 1000
    )
  ) pages
  join public.shifts s on s.id = pages.id
  where s.hospital_id = v_hosp
    and s.date >= timestamptz '2026-10-01 00:00:00+00'
    and s.date < timestamptz '2026-12-01 00:00:00+00';
  if v_oct_nov <> 240 then
    raise exception 'paged window returned % of 240 Oct-Nov demo shifts', v_oct_nov;
  end if;

  select count(*) into v_assigned
  from (
    select id from public.shifts
    where date >= v_window
    order by date asc, id asc
    limit 1000 offset 1000
  ) page
  join public.assignments a on a.shift_id = page.id
  where page.id = v_nov20
    and a.doctor_id = auth.uid()
    and a.status <> 'canceled';
  if v_assigned <> 1 then
    raise exception '20 Nov assigned shift was not on a later page';
  end if;

  select count(*) into v_open
    from (
      select s.id
      from (
        (
          select id from public.shifts
          where date >= v_window
          order by date asc, id asc
          limit 1000 offset 0
        )
        union all
        (
          select id from public.shifts
          where date >= v_window
          order by date asc, id asc
          limit 1000 offset 1000
        )
      ) pages
    join public.shifts s on s.id = pages.id
    where s.hospital_id = v_hosp
      and s.date >= timestamptz '2026-10-01 00:00:00+00'
      and s.date < timestamptz '2026-12-01 00:00:00+00'
      and not exists (
        select 1 from public.shift_coverage c
        where c.shift_id = s.id and c.is_filled
      )
  ) open_shifts;
  if v_open <> 116 then
    raise exception 'paged window returned % open Oct-Nov shifts, expected 116', v_open;
  end if;
end $$;

reset role;

rollback;
