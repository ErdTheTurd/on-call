-- Server-side onboarding email codes. The anon key cannot read or write these rows.
-- Only the service role (the send-notification function) can.
-- Not applied to the hosted project by this file alone.

create table if not exists public.email_verification_challenges (
  email text primary key,
  code_hash text,
  expires_at timestamptz,
  attempts int not null default 0,
  verified_at timestamptz,
  last_sent_at timestamptz,
  sends_in_window int not null default 0,
  window_started_at timestamptz,
  signup_notified_at timestamptz
);

create table if not exists public.email_verification_ip_windows (
  ip_hash text primary key,
  window_started_at timestamptz not null default now(),
  send_count int not null default 0
);

alter table public.email_verification_challenges enable row level security;
alter table public.email_verification_ip_windows enable row level security;

revoke all on public.email_verification_challenges from public, anon, authenticated;
revoke all on public.email_verification_ip_windows from public, anon, authenticated;

grant all on public.email_verification_challenges to service_role;
grant all on public.email_verification_ip_windows to service_role;
