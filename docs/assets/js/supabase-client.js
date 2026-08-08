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

export async function fetchOpenShifts() {
  const supabase = getSupabase();
  const { data, error } = await supabase
    .from("shifts")
    .select("*")
    .gte("date", new Date().toISOString())
    .order("date", { ascending: true })
    .limit(50);
  if (error) throw error;
  return data ?? [];
}

export function appDeepLink(path = "") {
  const { appScheme } = getConfig();
  const clean = String(path || "").replace(/^\//, "");
  return `${appScheme}://${clean}`;
}

export function openInApp(path = "") {
  window.location.href = appDeepLink(path);
}
