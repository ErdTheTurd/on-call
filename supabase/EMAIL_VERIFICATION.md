# Email verification (hosted Supabase)

Password accounts must confirm with a **6-digit email code** before signing in.
See [AUTH_SETUP.md](./AUTH_SETUP.md) for the Confirm signup template (token only, no magic link)
and for Google / Apple provider setup.

Local `config.toml` already sets `enable_confirmations = true` and `otp_length = 6`.
