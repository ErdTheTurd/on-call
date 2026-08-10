# Email verification (hosted Supabase)

Enable Confirm email in the dashboard so new accounts cannot sign in until they
click the link. Local `config.toml` already sets `enable_confirmations = true`.

## Dashboard (required once)

1. Open Auth → Providers → Email
   https://supabase.com/dashboard/project/yrnndfpvovuvjlzgivgu/auth/providers
2. Turn **Confirm email** ON
3. Auth → URL Configuration
   - Site URL: `https://mdshift.net`
   - Redirect URLs include:
     - `https://mdshift.net/**`
     - `https://mdshift.net/callback.html`
     - `https://erdtheturd.github.io/on-call/docs/callback.html` (optional legacy)

## Existing accounts

Users who already have a `public.profiles` row can be confirmed so they are not
locked out when Confirm email is enabled:

```sql
update auth.users
set email_confirmed_at = coalesce(email_confirmed_at, now()),
    confirmed_at = coalesce(confirmed_at, now())
where id in (select id from public.profiles)
  and email_confirmed_at is null;
```

Run that in the SQL editor before or right after enabling Confirm email.
