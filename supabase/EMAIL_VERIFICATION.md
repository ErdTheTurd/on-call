# Email verification (hosted Supabase)

Password accounts must confirm with a **6-digit email code** before signing in.

Delivery uses **Resend SMTP** — see [AUTH_SETUP.md](./AUTH_SETUP.md) section **0. Resend SMTP**.

Local `config.toml` sets `enable_confirmations = true`, `otp_length = 6`, and Resend SMTP via `env(RESEND_API_KEY)`.
