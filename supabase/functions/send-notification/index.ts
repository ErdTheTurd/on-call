// Purpose-specific mail only. Not an open relay.
// Not deployed. The owner deploys this after reviewing AUTH_SETUP.md.
//
// Actions:
//   send_code        — pre-auth. Server makes a 6-digit code, emails it, then stores a hash.
//   verify_code      — pre-auth. Checks the hash and records that this exact address is verified.
//   hospital_signup  — signed-in user JWT. Emails ops and that verified address. HTML is built here.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const OPS_EMAIL_DEFAULT = "erdunn706@gmail.com"
const CODE_TTL_MS = 10 * 60 * 1000
const VERIFIED_TTL_MS = 24 * 60 * 60 * 1000
const MIN_RESEND_MS = 30 * 1000
const MAX_SENDS_PER_EMAIL = 5
const MAX_SENDS_PER_IP = 20
const WINDOW_MS = 60 * 60 * 1000
const MAX_ATTEMPTS = 5

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

function clientIp(req: Request): string {
  const forwarded = req.headers.get("x-forwarded-for") || ""
  const first = forwarded.split(",")[0]?.trim()
  return first || req.headers.get("cf-connecting-ip") || "unknown"
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

    if (action === "send_code") return await handleSendCode(req, admin, pepper, body)
    if (action === "verify_code") return await handleVerifyCode(req, admin, pepper, body)
    if (action === "hospital_signup") return await handleHospitalSignup(req, admin, anonKey, body)
    return json(req, 400, { error: "Unknown action." })
  } catch (err) {
    return json(req, 500, { error: err instanceof Error ? err.message : "Could not send email." })
  }
})

async function handleSendCode(req: Request, admin: ReturnType<typeof createClient>, pepper: string, body: Record<string, unknown>) {
  const email = normalizeEmail(body?.email)
  if (!validEmail(email)) return json(req, 400, { error: "Enter a valid email address." })

  const ipHash = await sha256(`${pepper}:ip:${clientIp(req)}`)
  const now = new Date()
  const { data: ipRow } = await admin.from("email_verification_ip_windows").select("*").eq("ip_hash", ipHash).maybeSingle()
  let ipCount = 1
  let ipWindow = now.toISOString()
  if (ipRow?.window_started_at && now.getTime() - new Date(ipRow.window_started_at).getTime() < WINDOW_MS) {
    ipCount = Number(ipRow.send_count || 0) + 1
    ipWindow = ipRow.window_started_at
    if (Number(ipRow.send_count || 0) >= MAX_SENDS_PER_IP) {
      return json(req, 429, { error: "Too many verification emails from this network. Try again later." })
    }
  }

  const { data: row } = await admin.from("email_verification_challenges").select("*").eq("email", email).maybeSingle()
  if (row?.last_sent_at && now.getTime() - new Date(row.last_sent_at).getTime() < MIN_RESEND_MS) {
    return json(req, 429, { error: "Wait a moment before requesting another code." })
  }
  let sends = 1
  let windowStart = now.toISOString()
  if (row?.window_started_at && now.getTime() - new Date(row.window_started_at).getTime() < WINDOW_MS) {
    sends = Number(row.sends_in_window || 0) + 1
    windowStart = row.window_started_at
    if (Number(row.sends_in_window || 0) >= MAX_SENDS_PER_EMAIL) {
      return json(req, 429, { error: "Too many codes sent to this email. Try again later." })
    }
  }

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

  // Send first. A failed send must not replace a code the inbox already has.
  await sendEmail(email, "Your MD Shift verification code", html)

  const codeHash = await sha256(`${pepper}:${email}:${code}`)
  const { error } = await admin.from("email_verification_challenges").upsert({
    email,
    code_hash: codeHash,
    expires_at: new Date(now.getTime() + CODE_TTL_MS).toISOString(),
    attempts: 0,
    verified_at: null,
    last_sent_at: now.toISOString(),
    sends_in_window: sends,
    window_started_at: windowStart,
  })
  if (error) return json(req, 500, { error: "Could not store the verification code." })

  await admin.from("email_verification_ip_windows").upsert({
    ip_hash: ipHash,
    window_started_at: ipWindow,
    send_count: ipCount,
  })

  return json(req, 200, { ok: true })
}

async function handleVerifyCode(req: Request, admin: ReturnType<typeof createClient>, pepper: string, body: Record<string, unknown>) {
  const email = normalizeEmail(body?.email)
  const code = String(body?.code || "").replace(/\D/g, "")
  if (!validEmail(email) || code.length !== 6) {
    return json(req, 400, { error: "Enter the 6-digit code from your email." })
  }

  const { data: row } = await admin.from("email_verification_challenges").select("*").eq("email", email).maybeSingle()
  if (!row?.code_hash || !row.expires_at || new Date(row.expires_at).getTime() < Date.now()) {
    return json(req, 400, { error: "That code is expired. Send a new one." })
  }
  if (Number(row.attempts || 0) >= MAX_ATTEMPTS) {
    return json(req, 400, { error: "Too many attempts. Send a new code." })
  }

  const expected = await sha256(`${pepper}:${email}:${code}`)
  if (!timingSafeEqual(expected, String(row.code_hash))) {
    await admin.from("email_verification_challenges").update({
      attempts: Number(row.attempts || 0) + 1,
    }).eq("email", email)
    return json(req, 400, { error: "Incorrect or expired code." })
  }

  const { error } = await admin.from("email_verification_challenges").update({
    code_hash: null,
    expires_at: null,
    attempts: 0,
    verified_at: new Date().toISOString(),
  }).eq("email", email)
  if (error) return json(req, 500, { error: "Could not record verification." })
  return json(req, 200, { ok: true, email })
}

async function handleHospitalSignup(
  req: Request,
  admin: ReturnType<typeof createClient>,
  anonKey: string,
  body: Record<string, unknown>,
) {
  const header = req.headers.get("authorization") || ""
  const jwt = header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : ""
  if (!jwt || jwt === anonKey) return json(req, 401, { error: "Sign in before finishing hospital signup." })

  const url = Deno.env.get("SUPABASE_URL")!
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  })
  const { data: userData, error: userError } = await userClient.auth.getUser()
  if (userError || !userData?.user) return json(req, 401, { error: "Sign in before finishing hospital signup." })

  const email = normalizeEmail(body?.email)
  if (!validEmail(email)) return json(req, 400, { error: "Enter the hospital work email." })

  const { data: row } = await admin.from("email_verification_challenges").select("verified_at, signup_notified_at").eq("email", email).maybeSingle()
  if (!row?.verified_at || Date.now() - new Date(row.verified_at).getTime() > VERIFIED_TTL_MS) {
    return json(req, 403, { error: "Verify that work email before we can send the signup notice." })
  }
  if (row.signup_notified_at && Date.now() - new Date(row.signup_notified_at).getTime() < WINDOW_MS) {
    return json(req, 429, { error: "A signup notice for this email was already sent. Try again later." })
  }

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
  await sendEmail(ops, `New hospital signup — ${subjectName}`, opsHtml)
  await sendEmail(email, "We'll be in touch — MD Shift", hospitalHtml)
  await admin.from("email_verification_challenges").update({
    signup_notified_at: new Date().toISOString(),
  }).eq("email", email)
  return json(req, 200, { ok: true })
}
