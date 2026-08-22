import { getConfig, getSupabase, isConfigured } from "../supabase-client.js";

export const PLUS_PRICE_LABEL = "$9.99/mo";
export const PLUS_TOKEN_BONUS = 2;

/**
 * Monetization is deferred ~1 year after launch. Keep Plus/checkout code,
 * but hide upgrade CTAs until this flips (or config.monetizationLive is true).
 */
export function isMonetizationLive() {
  try {
    if (getConfig()?.monetizationLive === true) return true;
  } catch { /* ignore */ }
  return false;
}

const KEY = "md_shift_plus";

export const PLUS_FEATURES = {
  shared: [
    { title: "Ad-free workspace", detail: "Sponsored slots disappear across Dashboard and Doctors." },
    { title: "Priority badge", detail: "Requests and posts carry a calm Plus mark so hospitals and doctors notice faster." },
    { title: "Faster support lane", detail: "Same inbox — tagged Plus so we triage you first." },
  ],
  doctor: [
    { title: "+2 daily tokens", detail: "Request more call days without waiting for reset." },
    { title: "Earnings clarity", detail: "Projected vs completed breakdown stays one tap away." },
  ],
  hospital: [
    { title: "Coverage control room", detail: "Analytics and alter tools feel snappier with Plus shortcuts." },
    { title: "Priority posting", detail: "Open shifts surface higher when doctors browse." },
  ],
};

function readLocal() {
  try {
    return JSON.parse(localStorage.getItem(KEY) || "null") || { active: false, until: null };
  } catch {
    return { active: false, until: null };
  }
}

function writeLocal(membership) {
  localStorage.setItem(KEY, JSON.stringify(membership));
}

export function getPlusMembership() {
  return readLocal();
}

export function isPlusActive() {
  // Pre-monetization: everyone gets the ad-free experience.
  if (!isMonetizationLive()) return true;
  const m = readLocal();
  if (!m?.active) return false;
  if (m.until && new Date(m.until).getTime() < Date.now()) return false;
  return true;
}

export function setPlusMembership(partial) {
  const next = { ...readLocal(), ...partial };
  writeLocal(next);
  return next;
}

export async function refreshPlusMembership() {
  if (!isConfigured()) return getPlusMembership();
  try {
    const supabase = getSupabase();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return getPlusMembership();
    const { data, error } = await supabase
      .from("profiles")
      .select("plus_active, plus_until, stripe_subscription_id")
      .eq("id", user.id)
      .maybeSingle();
    if (error) throw error;
    const membership = {
      active: Boolean(data?.plus_active),
      until: data?.plus_until || null,
      subscriptionId: data?.stripe_subscription_id || null,
    };
    writeLocal(membership);
    return membership;
  } catch {
    return getPlusMembership();
  }
}

/** Opens Stripe Checkout / Payment Link for MD Shift+. */
export async function startPlusCheckout() {
  const cfg = getConfig();
  if (cfg.stripePlusPaymentLink) {
    const url = new URL(cfg.stripePlusPaymentLink);
    try {
      const supabase = getSupabase();
      const { data: { user } } = await supabase.auth.getUser();
      if (user?.id) url.searchParams.set("client_reference_id", user.id);
      if (user?.email) url.searchParams.set("prefilled_email", user.email);
    } catch { /* local / demo */ }
    window.location.href = url.toString();
    return { ok: true, mode: "payment_link" };
  }

  if (!isConfigured()) {
    return { ok: false, error: "Sign in with a live account to subscribe." };
  }

  const supabase = getSupabase();
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) {
    return { ok: false, error: "Session expired. Sign in again." };
  }

  const res = await fetch(`${cfg.supabaseUrl}/functions/v1/create-plus-checkout`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      apikey: cfg.supabaseAnonKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({}),
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    return { ok: false, error: payload.error || "Could not start checkout." };
  }
  if (payload.url) {
    window.location.href = payload.url;
    return { ok: true, mode: payload.mode || "checkout" };
  }
  return { ok: false, error: "Checkout URL missing." };
}

export function plusTokenBonus() {
  return isPlusActive() ? PLUS_TOKEN_BONUS : 0;
}
