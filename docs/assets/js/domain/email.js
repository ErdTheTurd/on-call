/** Onboarding email codes + hospital signup notify (via send-notification edge function). */

import { getSupabase, isConfigured, getConfig } from "../supabase-client.js";

const CODE_KEY = "oncall_email_verify_v1";
const OPS_EMAIL = "erdunn706@gmail.com";

function loadCodes() {
  try {
    return JSON.parse(sessionStorage.getItem(CODE_KEY) || "{}");
  } catch {
    return {};
  }
}

function saveCodes(map) {
  sessionStorage.setItem(CODE_KEY, JSON.stringify(map));
}

function generateCode() {
  return String(Math.floor(Math.random() * 1_000_000)).padStart(6, "0");
}

async function sendMail({ to, subject, html }) {
  if (!isConfigured()) throw new Error("Email sending is not configured.");
  const cfg = getConfig();
  const supabase = getSupabase();
  const { data: sessionData } = await supabase.auth.getSession();
  const token = sessionData?.session?.access_token || cfg.anonKey;
  const res = await fetch(`${cfg.supabaseUrl}/functions/v1/send-notification`, {
    method: "POST",
    headers: {
      apikey: cfg.anonKey,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ to, subject, html })
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `Could not send email (${res.status}).`);
  }
}

export async function sendOnboardingEmailCode(email, recipientName = "") {
  const normalized = String(email || "").trim().toLowerCase();
  if (!normalized.includes("@")) throw new Error("Enter a valid email first.");
  const code = generateCode();
  const map = loadCodes();
  map[normalized] = { code, expiry: Date.now() + 10 * 60 * 1000 };
  saveCodes(map);
  await sendMail({
    to: normalized,
    subject: "Your MD Shift verification code",
    html: `<div style="font-family:-apple-system,sans-serif;max-width:480px;margin:0 auto;padding:32px">
      <h2>MD Shift</h2>
      <p>Hi ${recipientName || "there"},</p>
      <p>Your verification code is:</p>
      <div style="background:#f0f4ff;border-radius:12px;padding:24px;text-align:center;margin:24px 0">
        <span style="font-size:42px;font-weight:700;letter-spacing:12px;color:#2563eb">${code}</span>
      </div>
      <p style="color:#888;font-size:14px">This code expires in 10 minutes.</p>
    </div>`
  });
  return true;
}

export function validateOnboardingEmailCode(email, code) {
  const normalized = String(email || "").trim().toLowerCase();
  const entered = String(code || "").replace(/\D/g, "");
  const map = loadCodes();
  const entry = map[normalized];
  if (!entry) return false;
  if (Date.now() > entry.expiry) {
    delete map[normalized];
    saveCodes(map);
    return false;
  }
  if (entry.code !== entered) return false;
  delete map[normalized];
  saveCodes(map);
  return true;
}

export async function notifyHospitalSignup({ name, email, npi, flags = [] }) {
  const safeName = String(name || "").trim() || "Hospital";
  const safeEmail = String(email || "").trim().toLowerCase();
  const flagBlock = flags.length
    ? `<ul>${flags.map((f) => `<li>${String(f)}</li>`).join("")}</ul>`
    : "<p>No automated review flags.</p>";

  await sendMail({
    to: OPS_EMAIL,
    subject: `New hospital signup — ${safeName}`,
    html: `<div style="font-family:-apple-system,sans-serif;max-width:560px;margin:0 auto;padding:32px">
      <h2>New hospital signup</h2>
      <p>A hospital just finished onboarding on MD Shift.</p>
      <ul>
        <li><strong>Hospital:</strong> ${safeName}</li>
        <li><strong>Work email:</strong> ${safeEmail}</li>
        <li><strong>NPI:</strong> ${npi || ""}</li>
      </ul>
      <p><strong>Flags</strong></p>
      ${flagBlock}
      <p>Please reach out to them to continue onboarding.</p>
    </div>`
  });

  if (safeEmail) {
    await sendMail({
      to: safeEmail,
      subject: "We'll be in touch — MD Shift",
      html: `<div style="font-family:-apple-system,sans-serif;max-width:560px;margin:0 auto;padding:32px">
        <h2>Thanks for joining MD Shift</h2>
        <p>Hi ${safeName} team,</p>
        <p>We received your hospital signup. Someone from our team will contact you at <strong>${safeEmail}</strong> shortly to finish setup and answer questions.</p>
        <p>If you need anything sooner, write erdunn706@gmail.com.</p>
      </div>`
    });
  }
}
