/** Hospital work-email codes and signup notices. The server owns the code and the email HTML. */

import { getSupabase, isConfigured, getConfig } from "../supabase-client.js";

async function callMail(action, payload, { requireUser = false } = {}) {
  if (!isConfigured()) throw new Error("Email sending is not configured.");
  const cfg = getConfig();
  const supabase = getSupabase();
  const { data: sessionData } = await supabase.auth.getSession();
  const userToken = sessionData?.session?.access_token || "";
  if (requireUser && !userToken) throw new Error("Sign in before finishing hospital signup.");
  const token = userToken || cfg.supabaseAnonKey;
  const res = await fetch(`${cfg.supabaseUrl}/functions/v1/send-notification`, {
    method: "POST",
    headers: {
      apikey: cfg.supabaseAnonKey,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ action, ...payload })
  });
  let body = {};
  try { body = await res.json(); } catch { body = {}; }
  if (!res.ok) throw new Error(body.error || `Could not send email (${res.status}).`);
  return body;
}

export async function sendOnboardingEmailCode(email, recipientName = "") {
  const normalized = String(email || "").trim().toLowerCase();
  if (!normalized.includes("@")) throw new Error("Enter a valid email first.");
  await callMail("send_code", { email: normalized, recipientName });
  return true;
}

export async function validateOnboardingEmailCode(email, code) {
  const normalized = String(email || "").trim().toLowerCase();
  const entered = String(code || "").replace(/\D/g, "");
  if (entered.length !== 6) throw new Error("Enter the 6-digit code from your email.");
  const body = await callMail("verify_code", { email: normalized, code: entered });
  if (body?.ok !== true || String(body.email || "").toLowerCase() !== normalized) {
    throw new Error("Incorrect or expired code.");
  }
  return true;
}

export async function notifyHospitalSignup({ name, email, npi, flags = [] }) {
  await callMail("hospital_signup", {
    name,
    email: String(email || "").trim().toLowerCase(),
    npi,
    flags
  }, { requireUser: true });
}
