// Purpose-specific mail only. Not an open relay.
// Not deployed. The owner deploys this after applying the review-findings migration.
//
// Actions (each requires the signed-in user's JWT, not the anon key):
//   send_code        — Server makes a 6-digit code, emails it, then stores a hash for that user.
//   verify_code      — Checks the hash and records that this user verified this address.
//   hospital_signup  — Emails ops and that user's verified address. HTML is built here.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const OPS_EMAIL_DEFAULT = "erdunn706@gmail.com"
const CODE_TTL_MS = 10 * 60 * 1000
const MIN_RESEND_SECONDS = 30
const MAX_SENDS_PER_EMAIL = 5
const MAX_SENDS_PER_IP = 20
const MAX_SENDS_PER_USER = 5
const WINDOW_SECONDS = 60 * 60
const MAX_ATTEMPTS = 5

const BLOCKED_EMAIL_DOMAINS = new Set([
  "gmail.com", "googlemail.com", "yahoo.com", "ymail.com",
  "hotmail.com", "outlook.com", "live.com", "msn.com",
  "icloud.com", "me.com", "mac.com", "aol.com",
  "protonmail.com", "proton.me", "tutanota.com",
  "privaterelay.appleid.com",
])

const ALLOWED_ORIGINS = new Set([
  "https://mdshift.net",
  "https://www.mdshift.net",
])

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin")
  const local = !!origin && (origin.startsWith("http://localhost:") || origin.startsWith("http://127.0.0.1:"))
  const allowed = !origin || ALLOWED_ORIGINS.has(origin) || local
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  }
  if (allowed && origin) headers["Access-Control-Allow-Origin"] = origin
  return headers
}

function json(req: Request, status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  })
}

function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

function normalizeEmail(value: unknown): string {
  return String(value ?? "").trim().toLowerCase()
}

function validEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 320
}

function emailDomain(email: string): string {
  return email.split("@")[1] || ""
}

function isPersonalDomain(email: string): boolean {
  const domain = emailDomain(email)
  if (BLOCKED_EMAIL_DOMAINS.has(domain)) return true
  for (const blocked of BLOCKED_EMAIL_DOMAINS) {
    if (domain.endsWith(`.${blocked}`)) return true
  }
  return false
}

async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("")
}

function timingSafeEqual(a: string, b: string): boolean {
  const ae = new TextEncoder().encode(a)
  const be = new TextEncoder().encode(b)
  if (ae.length !== be.length) return false
  let diff = 0
  for (let i = 0; i < ae.length; i++) diff |= ae[i] ^ be[i]
  return diff === 0
}

function newCode(): string {
  const buf = new Uint32Array(1)
  crypto.getRandomValues(buf)
  return String(buf[0] % 1_000_000).padStart(6, "0")
}

// Cloudflare sets cf-connecting-ip and overwrites a client-supplied value.
// X-Forwarded-For is appended by proxies, so the leftmost hop is caller-controlled.
function clientIp(req: Request): string {
  const cf = (req.headers.get("cf-connecting-ip") || "").trim()
  if (cf) return cf
  const hops = (req.headers.get("x-forwarded-for") || "")
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean)
  if (hops.length) return hops[hops.length - 1]
  const real = (req.headers.get("x-real-ip") || "").trim()
  return real || "unknown"
}

function bearerJwt(req: Request, anonKey: string): string {
  const header = req.headers.get("authorization") || ""
  const jwt = header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : ""
  if (!jwt || jwt === anonKey) return ""
  return jwt
}

async function userIdFromJwt(
  req: Request,
  admin: ReturnType<typeof createClient>,
  anonKey: string,
): Promise<{ id: string } | Response> {
  const jwt = bearerJwt(req, anonKey)
  if (!jwt) return json(req, 401, { error: "Sign in before continuing." })
  const { data, error } = await admin.auth.getUser(jwt)
  if (error || !data?.user?.id) return json(req, 401, { error: "Sign in before continuing." })
  return { id: data.user.id }
}

async function sendEmail(to: string, subject: string, html: string) {
  const resendKey = Deno.env.get("RESEND_API_KEY")
  const sendgridKey = Deno.env.get("SENDGRID_API_KEY")
  const from = Deno.env.get("RESEND_FROM_EMAIL") ?? Deno.env.get("SENDGRID_FROM") ?? "noreply@mdshift.net"

  if (resendKey) {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: `MD Shift <${from}>`,
        to: [to],
        subject,
        html,
      }),
    })
    if (!res.ok) {
      const detail = await res.text()
      throw new Error(detail || "Email provider rejected the message.")
    }
    return
  }

  if (sendgridKey) {
    const res = await fetch("https://api.sendgrid.com/v3/mail/send", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${sendgridKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        personalizations: [{ to: [{ email: to }] }],
        from: { email: from, name: "MD Shift" },
        subject,
        content: [{ type: "text/html", value: html }],
      }),
    })
    if (!res.ok) {
      const detail = await res.text()
      throw new Error(detail || "Email provider rejected the message.")
    }
    return
  }

  throw new Error("No RESEND_API_KEY or SENDGRID_API_KEY configured")
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }
  if (req.method !== "POST") return json(req, 405, { error: "POST only." })

  const origin = req.headers.get("origin")
  if (origin && !corsHeaders(req)["Access-Control-Allow-Origin"]) {
    return json(req, 403, { error: "Origin not allowed." })
  }

  try {
    const body = await req.json()
    if (body && (Object.prototype.hasOwnProperty.call(body, "html")
      || Object.prototype.hasOwnProperty.call(body, "subject")
      || Object.prototype.hasOwnProperty.call(body, "to"))) {
      return json(req, 400, { error: "This function does not accept a recipient, subject, or HTML body." })
    }

    const url = Deno.env.get("SUPABASE_URL")
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")
    const pepper = Deno.env.get("EMAIL_CODE_PEPPER")
    if (!url || !serviceKey || !anonKey || !pepper) {
      return json(req, 500, { error: "Email verification is not configured." })
    }

    const admin = createClient(url, serviceKey)
    const action = String(body?.action || "")

    if (action === "send_code") return await handleSendCode(req, admin, anonKey, pepper, body)
    if (action === "verify_code") return await handleVerifyCode(req, admin, anonKey, pepper, body)
    if (action === "hospital_signup") return await handleHospitalSignup(req, admin, anonKey, body)
    return json(req, 400, { error: "Unknown action." })
  } catch (err) {
    return json(req, 500, { error: err instanceof Error ? err.message : "Could not send email." })
  }
})

async function handleSendCode(
  req: Request,
  admin: ReturnType<typeof createClient>,
  anonKey: string,
  pepper: string,
  body: Record<string, unknown>,
) {
  const user = await userIdFromJwt(req, admin, anonKey)
  if (user instanceof Response) return user

  const email = normalizeEmail(body?.email)
  if (!validEmail(email)) return json(req, 400, { error: "Enter a valid email address." })
  if (isPersonalDomain(email)) {
    return json(req, 400, { error: "Please use your institutional or hospital email, not a personal address." })
  }

  const ipHash = await sha256(`${pepper}:ip:${clientIp(req)}`)
  const { data: reserved, error: reserveError } = await admin.rpc("reserve_verification_send", {
    p_user_id: user.id,
    p_email: email,
    p_ip_hash: ipHash,
    p_max_per_email: MAX_SENDS_PER_EMAIL,
    p_max_per_ip: MAX_SENDS_PER_IP,
    p_max_per_user: MAX_SENDS_PER_USER,
    p_window_seconds: WINDOW_SECONDS,
    p_min_resend_seconds: MIN_RESEND_SECONDS,
  })
  if (reserveError) return json(req, 500, { error: "Could not send a verification code." })
  if (reserved === "resend") return json(req, 429, { error: "Wait a moment before requesting another code." })
  if (reserved === "email_limit") return json(req, 429, { error: "Too many codes sent to this email. Try again later." })
  if (reserved === "ip_limit") return json(req, 429, { error: "Too many verification emails from this network. Try again later." })
  if (reserved === "user_limit") return json(req, 429, { error: "Too many verification emails for this account. Try again later." })
  if (reserved !== "ok") return json(req, 400, { error: "Enter a valid email address." })

  const code = newCode()
  const recipientName = escapeHtml(String(body?.recipientName || "there").slice(0, 120))
  const html = `<div style="font-family:-apple-system,sans-serif;max-width:480px;margin:0 auto;padding:32px">
    <h2>MD Shift</h2>
    <p>Hi ${recipientName},</p>
    <p>Your verification code is:</p>
    <div style="background:#f0f4ff;border-radius:12px;padding:24px;text-align:center;margin:24px 0">
      <span style="font-size:42px;font-weight:700;letter-spacing:12px;color:#2563eb">${code}</span>
    </div>
    <p style="color:#888;font-size:14px">This code expires in 10 minutes. If you did not request it, you can ignore this email.</p>
  </div>`

  try {
    await sendEmail(email, "Your MD Shift verification code", html)
  } catch {
    return json(req, 502, { error: "Could not send email." })
  }

  const codeHash = await sha256(`${pepper}:${email}:${code}`)
  const { error } = await admin.rpc("store_verification_code", {
    p_user_id: user.id,
    p_email: email,
    p_code_hash: codeHash,
    p_expires_at: new Date(Date.now() + CODE_TTL_MS).toISOString(),
  })
  if (error) return json(req, 500, { error: "Could not store the verification code." })
  return json(req, 200, { ok: true })
}

async function handleVerifyCode(
  req: Request,
  admin: ReturnType<typeof createClient>,
  anonKey: string,
  pepper: string,
  body: Record<string, unknown>,
) {
  const user = await userIdFromJwt(req, admin, anonKey)
  if (user instanceof Response) return user

  const email = normalizeEmail(body?.email)
  const code = String(body?.code || "").replace(/\D/g, "")
  if (!validEmail(email) || code.length !== 6) {
    return json(req, 400, { error: "Enter the 6-digit code from your email." })
  }

  const { data: rows, error: rpcError } = await admin.rpc("consume_email_attempt", {
    p_user_id: user.id,
    p_email: email,
    p_max: MAX_ATTEMPTS,
  })
  if (rpcError) return json(req, 500, { error: "Could not check the code." })
  const row = Array.isArray(rows) ? rows[0] : null
  if (!row?.code_hash) {
    return json(req, 400, { error: "Incorrect, expired, or too many attempts. Send a new code." })
  }

  const expected = await sha256(`${pepper}:${email}:${code}`)
  if (!timingSafeEqual(expected, String(row.code_hash))) {
    return json(req, 400, { error: "Incorrect or expired code." })
  }

  const { data: verified, error } = await admin.rpc("complete_email_verification", {
    p_user_id: user.id,
    p_email: email,
    p_code_hash: expected,
  })
  if (error) return json(req, 500, { error: "Could not record verification." })
  if (verified !== true) return json(req, 400, { error: "Incorrect or expired code." })
  return json(req, 200, { ok: true, email })
}

async function handleHospitalSignup(
  req: Request,
  admin: ReturnType<typeof createClient>,
  anonKey: string,
  body: Record<string, unknown>,
) {
  const user = await userIdFromJwt(req, admin, anonKey)
  if (user instanceof Response) return user

  const email = normalizeEmail(body?.email)
  if (!validEmail(email)) return json(req, 400, { error: "Enter the hospital work email." })
  if (isPersonalDomain(email)) {
    return json(req, 400, { error: "Please use your institutional or hospital email, not a personal address." })
  }

  const { data: claim, error: claimError } = await admin.rpc("claim_hospital_signup_notice", {
    p_user_id: user.id,
    p_email: email,
  })
  if (claimError) return json(req, 500, { error: "Could not send the signup notice." })
  if (claim === "unverified") {
    return json(req, 403, { error: "Verify that work email before we can send the signup notice." })
  }
  if (claim === "already_sent") return json(req, 200, { ok: true })
  if (claim !== "ok") return json(req, 403, { error: "Verify that work email before we can send the signup notice." })

  const name = escapeHtml(String(body?.name || "Hospital").trim().slice(0, 200) || "Hospital")
  const npi = escapeHtml(String(body?.npi || "").replace(/\D/g, "").slice(0, 10))
  const safeEmail = escapeHtml(email)
  const flags = Array.isArray(body?.flags) ? body.flags.slice(0, 20) : []
  const flagBlock = flags.length
    ? `<ul>${flags.map((flag) => `<li>${escapeHtml(String(flag).slice(0, 500))}</li>`).join("")}</ul>`
    : "<p>No automated review flags.</p>"

  const ops = normalizeEmail(Deno.env.get("OPS_EMAIL") || OPS_EMAIL_DEFAULT)
  const opsHtml = `<div style="font-family:-apple-system,sans-serif;max-width:560px;margin:0 auto;padding:32px">
    <h2>New hospital signup</h2>
    <p>A hospital just finished onboarding on MD Shift.</p>
    <ul>
      <li><strong>Hospital:</strong> ${name}</li>
      <li><strong>Work email:</strong> ${safeEmail}</li>
      <li><strong>NPI:</strong> ${npi}</li>
    </ul>
    <p><strong>Flags</strong></p>
    ${flagBlock}
    <p>Please reach out to them to continue onboarding.</p>
  </div>`
  const hospitalHtml = `<div style="font-family:-apple-system,sans-serif;max-width:560px;margin:0 auto;padding:32px">
    <h2>Thanks for joining MD Shift</h2>
    <p>Hi ${name} team,</p>
    <p>We received your hospital signup. Someone from our team will contact you at <strong>${safeEmail}</strong> shortly to finish setup and answer questions.</p>
    <p>If you need anything sooner, write ${escapeHtml(ops)}.</p>
  </div>`

  const subjectName = String(body?.name || "Hospital").replace(/[\r\n]/g, " ").slice(0, 120)
  try {
    await sendEmail(ops, `New hospital signup — ${subjectName}`, opsHtml)
    await sendEmail(email, "We'll be in touch — MD Shift", hospitalHtml)
  } catch {
    await admin
      .from("email_verification_challenges")
      .update({ signup_notified_at: null })
      .eq("user_id", user.id)
      .eq("email", email)
    return json(req, 502, { error: "Could not send the signup notice. Try again." })
  }
  return json(req, 200, { ok: true })
}
