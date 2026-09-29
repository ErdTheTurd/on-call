-- Proves the lockdown migration against a local `supabase db reset`.
-- Runs as the database superuser, then switches into anon / authenticated /
-- service_role the same way PostgREST does (role + JWT claims).
-- The whole script is one transaction and rolls back, so it can be re-run.

\set ON_ERROR_STOP on

begin;

-- Fixed identities. Not real people.
-- doctor A  11111111-1111-4111-8111-111111111111
-- doctor B  22222222-2222-4222-8222-222222222222  (same hospital, trade partner)
-- doctor C  33333333-3333-4333-8333-333333333333  (no shared hospital)
-- hospital  44444444-4444-4444-8444-444444444444
-- other hosp 88888888-8888-4888-8888-888888888888
-- admin      55555555-5555-4555-8555-555555555555

-- Column set matches the local Supabase Postgres image (auth.users has confirmed_at,
-- not the newer generated email_confirmed_at / email_change_token_new pair).
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token, email_change
)
values
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-4111-8111-111111111111', 'authenticated', 'authenticated', 'doctor.a@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '22222222-2222-4222-8222-222222222222', 'authenticated', 'authenticated', 'doctor.b@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '33333333-3333-4333-8333-333333333333', 'authenticated', 'authenticated', 'doctor.c@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '44444444-4444-4444-8444-444444444444', 'authenticated', 'authenticated', 'hospital.admin@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '88888888-8888-4888-8888-888888888888', 'authenticated', 'authenticated', 'other.hospital@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '55555555-5555-4555-8555-555555555555', 'authenticated', 'authenticated', 'admin@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

-- Fixture rows are inserted as the table owner, which bypasses RLS.
insert into public.profiles (id, email, role, is_admin) values
  ('11111111-1111-4111-8111-111111111111', 'doctor.a@example.com', 'doctor', false),
  ('22222222-2222-4222-8222-222222222222', 'doctor.b@example.com', 'doctor', false),
  ('33333333-3333-4333-8333-333333333333', 'doctor.c@example.com', 'doctor', false),
  ('44444444-4444-4444-8444-444444444444', 'hospital.admin@example.com', 'hospital', false),
  ('88888888-8888-4888-8888-888888888888', 'other.hospital@example.com', 'hospital', false),
  ('55555555-5555-4555-8555-555555555555', 'admin@example.com', 'hospital', true);

insert into public.doctor_profiles (
  profile_id, first_name, last_name, credential, npi, specialties,
  verification_status, dea_number, license_number, license_state, email
) values
  ('11111111-1111-4111-8111-111111111111', 'Ada', 'Ames', 'MD', '1111111111', '{Cardiology}', 'pending', 'AA1111111', 'LIC-A', 'TX', 'doctor.a@example.com'),
  ('22222222-2222-4222-8222-222222222222', 'Bea', 'Blake', 'DO', '2222222222', '{Cardiology}', 'pending', 'BB2222222', 'LIC-B', 'TX', 'doctor.b@example.com'),
  ('33333333-3333-4333-8333-333333333333', 'Cy', 'Cole', 'MD', '3333333333', '{Surgery}', 'pending', 'CC3333333', 'LIC-C', 'CA', 'doctor.c@example.com');

insert into public.hospital_profiles (id, profile_id, name, npi, email, verification_status) values
  ('66666666-6666-4666-8666-666666666666', '44444444-4444-4444-8444-444444444444', 'Riverside General', '4444444444', 'hospital.admin@example.com', 'pending'),
  ('99999999-9999-4999-8999-999999999999', '88888888-8888-4888-8888-888888888888', 'Other Hospital', '8888888888', 'other.hospital@example.com', 'pending');

insert into public.hospital_doctors (hospital_id, doctor_id, auto_approve) values
  ('66666666-6666-4666-8666-666666666666', '11111111-1111-4111-8111-111111111111', false),
  ('66666666-6666-4666-8666-666666666666', '22222222-2222-4222-8222-222222222222', true);

insert into public.shifts (id, hospital_id, hospital_name, specialty, date, rate_floor) values
  ('77777777-7777-4777-8777-777777777777', '66666666-6666-4666-8666-666666666666', 'Riverside General', 'Cardiology', now() + interval '2 days', 1500);

insert into public.assignments (shift_id, doctor_id, status) values
  ('77777777-7777-4777-8777-777777777777', '11111111-1111-4111-8111-111111111111', 'scheduled');

insert into public.token_requests (doctor_id, hospital_id, shift_date, specialty, status) values
  ('11111111-1111-4111-8111-111111111111', '66666666-6666-4666-8666-666666666666', current_date + 2, 'Cardiology', 'pending');

insert into public.trade_requests (shift_id, from_doctor_id, to_doctor_id, state) values
  ('77777777-7777-4777-8777-777777777777', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 'pending');

insert into public.scheduling_policies (hospital_id, policy) values
  ('66666666-6666-4666-8666-666666666666', '{"granularity":"day"}');

insert into public.unavailable_days (hospital_id, date) values
  ('66666666-6666-4666-8666-666666666666', current_date + 9);

insert into public.proposed_rates (hospital_id, specialty, date, rate) values
  ('66666666-6666-4666-8666-666666666666', 'Cardiology', current_date + 2, 1600);

insert into public.penalty_ledger (doctor_id, hospital_id, shift_id, type, amount) values
  ('11111111-1111-4111-8111-111111111111', '66666666-6666-4666-8666-666666666666', '77777777-7777-4777-8777-777777777777', 'cancel', 100);

insert into public.doctor_tokens (doctor_id, tokens_remaining) values
  ('11111111-1111-4111-8111-111111111111', 3);

insert into public.hospital_savings_events (event_key, hospital_id, kind, amount, created_by) values
  ('rate_savings:test:a', '66666666-6666-4666-8666-666666666666', 'rate_savings', 200, '11111111-1111-4111-8111-111111111111');

-- ---------------------------------------------------------------------------
-- Doctor A sees their own credential row, including sensitive columns.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.doctor_profiles) <> 1 then
    raise exception 'doctor A should see only their own doctor_profiles row';
  end if;
  if not exists (
    select 1 from public.doctor_profiles
    where npi = '1111111111' and dea_number = 'AA1111111' and license_number = 'LIC-A' and email = 'doctor.a@example.com'
  ) then
    raise exception 'doctor A should be able to read their own NPI, DEA, license, and email';
  end if;
  if (select count(*) from public.profiles) <> 1 then
    raise exception 'doctor A should see only their own profiles row';
  end if;
  if (select count(*) from public.shifts) <> 1 then
    raise exception 'doctor A should see the open shift';
  end if;
  if (select count(*) from public.assignments) <> 1 then
    raise exception 'doctor A should see their assignment';
  end if;
  if (select count(*) from public.token_requests) <> 1 then
    raise exception 'doctor A should see their token request';
  end if;
  if (select count(*) from public.trade_requests) <> 1 then
    raise exception 'doctor A should see the trade they sent';
  end if;
  if (select count(*) from public.hospital_roster) <> 2 then
    raise exception 'doctor A should see both roster cards at their hospital';
  end if;
  if (select count(*) from public.doctor_directory where profile_id = '22222222-2222-4222-8222-222222222222') <> 1 then
    raise exception 'doctor A should see doctor B name card for trades';
  end if;
  if (select count(*) from public.doctor_directory where profile_id = '33333333-3333-4333-8333-333333333333') <> 0 then
    raise exception 'doctor A should not see an unrelated doctor';
  end if;
  if (select count(*) from public.hospital_profiles) <> 0 then
    raise exception 'doctor A should not read hospital credential rows';
  end if;
  if (select count(*) from public.penalty_ledger) <> 1 then
    raise exception 'doctor A should see their own penalty row';
  end if;
  if (select count(*) from public.doctor_tokens) <> 1 then
    raise exception 'doctor A should see their token balance';
  end if;
end $$;

update public.doctor_profiles set first_name = 'Adah' where profile_id = auth.uid();

insert into public.token_requests (doctor_id, hospital_id, shift_date, specialty, status)
values (auth.uid(), '66666666-6666-4666-8666-666666666666', current_date + 3, 'Cardiology', 'pending');

insert into public.hospital_savings_events (event_key, hospital_id, kind, amount, created_by)
values ('rate_savings:test:a2', '66666666-6666-4666-8666-666666666666', 'rate_savings', 50, auth.uid());

do $$
begin
  begin
    insert into public.hospital_doctors (hospital_id, doctor_id, auto_approve)
    values ('99999999-9999-4999-8999-999999999999', auth.uid(), true);
    raise exception 'doctor should not self-grant auto-approve';
  exception when others then
    if sqlerrm like '%doctor should not self-grant auto-approve%' then
      raise;
    end if;
  end;
end $$;

do $$
begin
  begin
    update public.profiles set is_admin = true where id = auth.uid();
    raise exception 'doctor A was able to grant themselves admin';
  exception when others then
    if sqlerrm not like '%not allowed to change admin status%' then
      raise;
    end if;
  end;
  begin
    update public.shifts set rate_floor = 1 where id = '77777777-7777-4777-8777-777777777777';
    if found then
      raise exception 'doctor A should not update a hospital shift';
    end if;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Doctor B shares the roster (safe columns only) and the trade, not A's secrets.
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if exists (select 1 from public.doctor_profiles where profile_id = '11111111-1111-4111-8111-111111111111') then
    raise exception 'doctor B can read doctor A credential row';
  end if;
  if exists (select 1 from public.doctor_profiles where npi = '1111111111' or dea_number = 'AA1111111' or email = 'doctor.a@example.com') then
    raise exception 'doctor B can read doctor A sensitive columns';
  end if;
  if (select count(*) from public.doctor_directory where profile_id = '11111111-1111-4111-8111-111111111111' and first_name = 'Adah') <> 1 then
    raise exception 'doctor B should see doctor A safe directory card';
  end if;
  if (select count(*) from public.trade_requests) <> 1 then
    raise exception 'doctor B should see the incoming trade';
  end if;
  if (select count(*) from public.token_requests) <> 0 then
    raise exception 'doctor B should not see doctor A token requests';
  end if;
  if (select count(*) from public.doctor_tokens) <> 0 then
    raise exception 'doctor B should not see doctor A token balance';
  end if;
  if (select count(*) from public.penalty_ledger) <> 0 then
    raise exception 'doctor B should not see doctor A penalties';
  end if;
  if (select count(*) from public.profiles where email = 'doctor.a@example.com') <> 0 then
    raise exception 'doctor B should not read doctor A account email';
  end if;
end $$;

do $$
begin
  begin
    perform npi from public.doctor_directory;
    raise exception 'doctor_directory unexpectedly has an npi column';
  exception when undefined_column then
    null;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Doctor C is authenticated but not involved. No sensitive data, no roster.
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if exists (select 1 from public.doctor_profiles where profile_id <> auth.uid()) then
    raise exception 'doctor C can read another doctor profile';
  end if;
  if exists (select 1 from public.doctor_directory where profile_id <> auth.uid()) then
    raise exception 'doctor C can see unrelated directory cards';
  end if;
  if (select count(*) from public.shifts) <> 1 then
    raise exception 'doctor C should still browse open shifts';
  end if;
  if (select count(*) from public.assignments) <> 0 then
    raise exception 'doctor C should not see someone else''s assignment';
  end if;
  if (select count(*) from public.trade_requests) <> 0 then
    raise exception 'doctor C should not see someone else''s trade';
  end if;
  if (select count(*) from public.hospital_savings_events) <> 0 then
    raise exception 'doctor C should not read hospital savings';
  end if;
  if (select count(*) from public.scheduling_policies) <> 0 then
    raise exception 'doctor C should not read hospital policy';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Hospital sees its roster without NPI/DEA/email, and its own scheduling rows.
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-8444-444444444444","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.doctor_profiles) <> 0 then
    raise exception 'hospital can read doctor credential table';
  end if;
  if (select count(*) from public.hospital_roster) <> 2 then
    raise exception 'hospital should see both doctors on its roster';
  end if;
  if (select email from public.hospital_profiles) is distinct from 'hospital.admin@example.com' then
    raise exception 'hospital should read its own profile email';
  end if;
  if (select count(*) from public.shifts) <> 1 then
    raise exception 'hospital should see its shift';
  end if;
  if (select count(*) from public.assignments) <> 1 then
    raise exception 'hospital should see the assignment on its shift';
  end if;
  if (select count(*) from public.token_requests) < 1 then
    raise exception 'hospital should see token requests';
  end if;
  if (select count(*) from public.trade_requests) <> 1 then
    raise exception 'hospital should see trades on its shift';
  end if;
  if (select count(*) from public.scheduling_policies) <> 1 then
    raise exception 'hospital should read its policy';
  end if;
  if (select count(*) from public.unavailable_days) <> 1 then
    raise exception 'hospital should read its blocked days';
  end if;
  if (select count(*) from public.proposed_rates) <> 1 then
    raise exception 'hospital should read its proposed rates';
  end if;
  if (select count(*) from public.penalty_ledger) <> 1 then
    raise exception 'hospital should read its penalty ledger';
  end if;
  if (select count(*) from public.hospital_savings_events) <> 2 then
    raise exception 'hospital should read its savings events';
  end if;
  if (select count(*) from public.profiles where id <> auth.uid()) <> 0 then
    raise exception 'hospital should not read other account emails';
  end if;
end $$;

update public.token_requests
  set status = 'approved'
  where doctor_id = '11111111-1111-4111-8111-111111111111';

insert into public.shifts (hospital_id, hospital_name, specialty, date, rate_floor)
values ('66666666-6666-4666-8666-666666666666', 'Riverside General', 'Cardiology', now() + interval '4 days', 1400);

update public.hospital_doctors
  set auto_approve = true
  where hospital_id = '66666666-6666-4666-8666-666666666666'
    and doctor_id = '11111111-1111-4111-8111-111111111111';

do $$
begin
  begin
    update public.doctor_profiles set first_name = 'Stolen' where profile_id = '11111111-1111-4111-8111-111111111111';
    if found then
      raise exception 'hospital was able to update a doctor credential row';
    end if;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- The other hospital sees none of Riverside's rows.
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claim.sub', '88888888-8888-4888-8888-888888888888', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"88888888-8888-4888-8888-888888888888","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.shifts) <> 0 then
    raise exception 'other hospital can see Riverside shifts';
  end if;
  if (select count(*) from public.hospital_roster) <> 0 then
    raise exception 'other hospital can see Riverside roster';
  end if;
  if (select count(*) from public.hospital_profiles where name = 'Riverside General') <> 0 then
    raise exception 'other hospital can read Riverside profile';
  end if;
  if (select count(*) from public.token_requests) <> 0 then
    raise exception 'other hospital can see Riverside token requests';
  end if;
  if (select count(*) from public.hospital_savings_events) <> 0 then
    raise exception 'other hospital can see Riverside savings';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Admin can review every application, including sensitive columns and emails.
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.doctor_profiles) <> 3 then
    raise exception 'admin should see every doctor profile';
  end if;
  if (select count(*) from public.doctor_profiles where npi = '1111111111' and dea_number = 'AA1111111') <> 1 then
    raise exception 'admin should see NPI and DEA for review';
  end if;
  if (select count(*) from public.hospital_profiles) <> 2 then
    raise exception 'admin should see every hospital profile';
  end if;
  if (select count(*) from public.profiles) <> 6 then
    raise exception 'admin should see every account email';
  end if;
  if (select count(*) from public.hospital_savings_events) <> 2 then
    raise exception 'admin should see every savings event';
  end if;
end $$;

update public.doctor_profiles
  set verification_status = 'verified', review_note = 'npi matched'
  where profile_id = '11111111-1111-4111-8111-111111111111';

-- ---------------------------------------------------------------------------
-- Owner edits must not undo the admin's decision or self-verify on insert.
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
set local role authenticated;

update public.doctor_profiles
  set first_name = 'Ada', verification_status = 'rejected', review_note = 'nope'
  where profile_id = auth.uid();

reset role;

do $$
begin
  if (select verification_status::text from public.doctor_profiles where profile_id = '11111111-1111-4111-8111-111111111111') is distinct from 'verified' then
    raise exception 'owner update overwrote the admin review status';
  end if;
  if (select review_note from public.doctor_profiles where profile_id = '11111111-1111-4111-8111-111111111111') is distinct from 'npi matched' then
    raise exception 'owner update overwrote the review note';
  end if;
  if (select first_name from public.doctor_profiles where profile_id = '11111111-1111-4111-8111-111111111111') is distinct from 'Ada' then
    raise exception 'owner should still be able to edit their name';
  end if;
  if (select is_admin from public.profiles where id = '11111111-1111-4111-8111-111111111111') then
    raise exception 'doctor A is admin';
  end if;
  if (select status::text from public.token_requests where doctor_id = '11111111-1111-4111-8111-111111111111' and shift_date = current_date + 2) is distinct from 'approved' then
    raise exception 'hospital approve did not stick';
  end if;
end $$;

-- A new doctor cannot insert themselves already verified.
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

update public.doctor_profiles
  set verification_status = 'verified'
  where profile_id = auth.uid();

reset role;

do $$
begin
  if (select verification_status::text from public.doctor_profiles where profile_id = '33333333-3333-4333-8333-333333333333') is distinct from 'pending' then
    raise exception 'doctor C self-verified';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Anon (the public website key) cannot read, update, or delete.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

do $$
begin
  begin
    perform 1 from public.doctor_profiles;
    raise exception 'anon read doctor_profiles should fail';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform 1 from public.hospital_profiles;
    raise exception 'anon read hospital_profiles should fail';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform 1 from public.profiles;
    raise exception 'anon read profiles should fail';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform 1 from public.shifts;
    raise exception 'anon read shifts should fail';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform 1 from public.trade_requests;
    raise exception 'anon read trades should fail';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform 1 from public.hospital_roster;
    raise exception 'anon read roster should fail';
  exception when insufficient_privilege then
    null;
  end;
  begin
    update public.doctor_profiles set first_name = 'hacked';
    raise exception 'anon update doctor_profiles should fail';
  exception when insufficient_privilege then
    null;
  end;
  begin
    delete from public.doctor_profiles;
    raise exception 'anon delete doctor_profiles should fail';
  exception when insufficient_privilege then
    null;
  end;
  begin
    delete from public.hospital_profiles;
    raise exception 'anon delete hospital_profiles should fail';
  exception when insufficient_privilege then
    null;
  end;
  begin
    update public.shifts set rate_floor = 0;
    raise exception 'anon update shifts should fail';
  exception when insufficient_privilege then
    null;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Service role (edge functions) still bypasses RLS.
-- ---------------------------------------------------------------------------
reset role;
set local role service_role;

insert into public.trade_requests (shift_id, from_doctor_id, to_doctor_id, state)
values ('77777777-7777-4777-8777-777777777777', '33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'pending');

do $$
begin
  if (select count(*) from public.trade_requests) <> 2 then
    raise exception 'service role should read and write trades for edge functions';
  end if;
  if not has_table_privilege('anon', 'public.doctor_profiles', 'select') then
    null;
  else
    raise exception 'anon still has select on doctor_profiles';
  end if;
  if has_table_privilege('anon', 'public.doctor_profiles', 'update')
     or has_table_privilege('anon', 'public.doctor_profiles', 'delete') then
    raise exception 'anon still has update or delete on doctor_profiles';
  end if;
  if has_table_privilege('anon', 'public.hospital_profiles', 'select') then
    raise exception 'anon still has select on hospital_profiles';
  end if;
  if has_table_privilege('anon', 'public.email_verification_challenges', 'select')
     or has_table_privilege('authenticated', 'public.email_verification_challenges', 'select')
     or has_table_privilege('anon', 'public.email_verification_ip_windows', 'select')
     or has_table_privilege('authenticated', 'public.email_verification_ip_windows', 'select') then
    raise exception 'email verification tables are readable by anon or authenticated';
  end if;
  if not has_table_privilege('service_role', 'public.email_verification_challenges', 'insert') then
    raise exception 'service role cannot write email verification challenges';
  end if;
end $$;

insert into public.email_verification_challenges (email, code_hash)
values ('work@hospital.test', 'hash');

reset role;

do $$
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and (qual = 'true' or with_check = 'true')
      and tablename in (
        'profiles', 'doctor_profiles', 'hospital_profiles', 'hospital_doctors',
        'shifts', 'assignments', 'token_requests', 'trade_requests',
        'unavailable_days', 'scheduling_policies', 'penalty_ledger',
        'doctor_points', 'doctor_tokens', 'doctor_preferences', 'proposed_rates',
        'hospital_savings_events'
      )
  ) then
    raise exception 'a public scheduling or profile policy is still USING true';
  end if;
end $$;

rollback;
