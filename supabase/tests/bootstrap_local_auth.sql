-- Local stand-in for the Supabase auth schema when `supabase start` is not running.
-- Not a migration. Do not apply this on the hosted project.

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

alter role service_role bypassrls;
grant anon, authenticated, service_role to postgres;

create schema if not exists auth;

create table if not exists auth.users (
  instance_id uuid,
  id uuid primary key,
  aud text,
  role text,
  email text,
  encrypted_password text,
  confirmed_at timestamptz,
  raw_app_meta_data jsonb,
  raw_user_meta_data jsonb,
  created_at timestamptz,
  updated_at timestamptz,
  confirmation_token text,
  recovery_token text,
  email_change_token text,
  email_change text
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.role', true), '');
$$;

-- Columns the hosted GoTrue schema has. The App Review seed inserts them.
-- Nullable or defaulted so the older lockdown fixture inserts still work.
alter table auth.users add column if not exists email_confirmed_at timestamptz;
alter table auth.users add column if not exists email_change_token_new text default '';
alter table auth.users add column if not exists email_change_token_current text default '';
alter table auth.users add column if not exists reauthentication_token text default '';
alter table auth.users add column if not exists phone_change text default '';
alter table auth.users add column if not exists phone_change_token text default '';
alter table auth.users add column if not exists banned_until timestamptz;
alter table auth.users add column if not exists is_sso_user boolean not null default false;
alter table auth.users add column if not exists is_anonymous boolean not null default false;

create table if not exists auth.mfa_factors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  status text
);

grant usage on schema auth to postgres, anon, authenticated, service_role;
grant execute on function auth.uid() to postgres, anon, authenticated, service_role;
grant execute on function auth.role() to postgres, anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

-- Present on hosted Supabase. The review migration revokes client execute.
create or replace function public.rls_auto_enable()
returns void
language sql
as $$ select 1 $$;

grant execute on function public.rls_auto_enable() to anon, authenticated;
