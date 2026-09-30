-- Local stand-in for the rows the hosted project already has before the seed.
-- Not a migration. The seed itself does not create the doctor auth user or the
-- hospital auth user.

\set ON_ERROR_STOP on

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  email_change_token_current, reauthentication_token, phone_change, phone_change_token,
  is_sso_user, is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000',
  'b9f7ecaa-e7b0-4bba-8753-d25efaaf6e25',
  'authenticated', 'authenticated', 'info@erdanimates.shop', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now(),
  '', '', '', '', '', '', '', '', false, false
) on conflict (id) do nothing;

insert into public.profiles (id, email, role, is_admin)
values ('b9f7ecaa-e7b0-4bba-8753-d25efaaf6e25', 'info@erdanimates.shop', 'hospital', true)
on conflict (id) do update set is_admin = true;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  email_change_token_current, reauthentication_token, phone_change, phone_change_token,
  is_sso_user, is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000',
  'd10290cb-1dd6-4e65-8a9d-7efb4ea83419',
  'authenticated', 'authenticated', 'jdunn@eporthospine.com', '', now(),
  '{"provider":"email","providers":["email"]}', '{"role":"doctor"}', now(), now(),
  '', '', '', '', '', '', '', '', false, false
) on conflict (id) do nothing;

insert into public.profiles (id, email, role)
values ('d10290cb-1dd6-4e65-8a9d-7efb4ea83419', 'jdunn@eporthospine.com', 'doctor')
on conflict (id) do nothing;

-- The live doctor row currently holds a real NPI. The seed must replace it.
insert into public.doctor_profiles (
  profile_id, first_name, last_name, credential, npi, specialties, verification_status, email
)
select
  'd10290cb-1dd6-4e65-8a9d-7efb4ea83419', 'J', 'Dunn', 'MD', '1679576722',
  '{Orthopedics}', 'pending', 'jdunn@eporthospine.com'
where not exists (
  select 1 from public.doctor_profiles
  where profile_id = 'd10290cb-1dd6-4e65-8a9d-7efb4ea83419'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  email_change_token_current, reauthentication_token, phone_change, phone_change_token,
  is_sso_user, is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000',
  'de000000-0000-4000-8000-0000000000aa',
  'authenticated', 'authenticated', 'review-hospital@mdshift.net', '', now(),
  '{"provider":"email","providers":["email"],"mdshift_demo":true}',
  '{"role":"hospital"}', now(), now(),
  '', '', '', '', '', '', '', '', false, false
) on conflict (id) do update set email_confirmed_at = coalesce(auth.users.email_confirmed_at, now());
