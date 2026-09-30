import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export function getConfig() {
  return window.ON_CALL_CONFIG || {};
}

export function isConfigured() {
  const { supabaseUrl, supabaseAnonKey } = getConfig();
  return Boolean(
    supabaseUrl &&
    supabaseAnonKey &&
    !supabaseUrl.includes("your-project") &&
    !supabaseAnonKey.includes("your-anon-key")
  );
}

let client;

export function getSupabase() {
  if (!isConfigured()) {
    throw new Error("Supabase is not configured. Copy docs/assets/js/config.example.js to config.js.");
  }
  if (!client) {
    const { supabaseUrl, supabaseAnonKey } = getConfig();
    client = createClient(supabaseUrl, supabaseAnonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    });
  }
  return client;
}

export async function getSessionUser() {
  const supabase = getSupabase();
  const { data, error } = await supabase.auth.getSession();
  if (error) throw error;
  return data.session?.user ?? null;
}

export async function getUserRole(userId) {
  const supabase = getSupabase();
  const { data, error } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", userId)
    .maybeSingle();
  if (error) throw error;
  return data?.role ?? null;
}

export async function upsertProfile(userId, email, role) {
  const supabase = getSupabase();
  const { error } = await supabase.from("profiles").upsert({
    id: userId,
    email,
    role: role.toLowerCase()
  });
  if (error) throw error;
}

/** PostgREST silently caps a response at max_rows (1000 on the live project). */
export const POSTGREST_PAGE = 1000;

/** UTC start of the current month, minus 7 days. */
export function shiftWindowStart(now = new Date()) {
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  start.setUTCDate(start.getUTCDate() - 7);
  return start.toISOString();
}

/**
 * Reads every page. A failed page throws so the caller does not keep a short list.
 * `makeQuery(from, to)` must build a fresh query; range is inclusive.
 */
export async function fetchAllPages(makeQuery) {
  const rows = [];
  for (let page = 0; page < 40; page++) {
    const from = page * POSTGREST_PAGE;
    const to = from + POSTGREST_PAGE - 1;
    const { data, error } = await makeQuery(from, to);
    if (error) throw error;
    const batch = data || [];
    rows.push(...batch);
    if (batch.length < POSTGREST_PAGE) return rows;
  }
  throw new Error("The server returned more rows than this sync can load. Nothing was replaced.");
}

export async function fetchOpenShifts() {
  const supabase = getSupabase();
  const windowStart = shiftWindowStart();
  return fetchAllPages((from, to) => supabase
    .from("shifts")
    .select("*")
    .gte("date", windowStart)
    .order("date", { ascending: true })
    .order("id", { ascending: true })
    .range(from, to));
}

export function appDeepLink(path = "") {
  const { appScheme } = getConfig();
  const clean = String(path || "").replace(/^\//, "");
  return `${appScheme}://${clean}`;
}

export function openInApp(path = "") {
  window.location.href = appDeepLink(path);
}
