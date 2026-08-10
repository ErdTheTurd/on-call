/**
 * Authenticator-app MFA (TOTP) shared by web auth flows.
 * Keep in sync with SupabaseAuthService MFA methods on iOS.
 */
import { getSupabase, isConfigured } from "../supabase-client.js";

export async function getMfaAssurance() {
  if (!isConfigured()) return { currentLevel: null, nextLevel: null };
  const supabase = getSupabase();
  const { data, error } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (error) throw error;
  return data;
}

/** True when the user has verified TOTP and must complete a challenge (aal1 → aal2). */
export async function needsMfaChallenge() {
  const { currentLevel, nextLevel } = await getMfaAssurance();
  return currentLevel === "aal1" && nextLevel === "aal2";
}

export async function listTotpFactors() {
  if (!isConfigured()) return [];
  const supabase = getSupabase();
  const { data, error } = await supabase.auth.mfa.listFactors();
  if (error) throw error;
  return data?.totp || [];
}

export async function enrollTotp(friendlyName = "MD Shift") {
  const supabase = getSupabase();
  const { data, error } = await supabase.auth.mfa.enroll({
    factorType: "totp",
    friendlyName
  });
  if (error) throw error;
  return {
    factorId: data.id,
    secret: data.totp?.secret || "",
    qrCode: data.totp?.qr_code || "",
    uri: data.totp?.uri || ""
  };
}

export async function verifyTotp({ factorId, code }) {
  const supabase = getSupabase();
  const token = String(code || "").replace(/\D/g, "").slice(0, 6);
  if (token.length !== 6) throw new Error("Enter the 6-digit code from your authenticator app.");

  const challenge = await supabase.auth.mfa.challenge({ factorId });
  if (challenge.error) throw challenge.error;

  const verified = await supabase.auth.mfa.verify({
    factorId,
    challengeId: challenge.data.id,
    code: token
  });
  if (verified.error) throw verified.error;
  return verified.data;
}

export async function challengeAndVerifyFirstTotp(code) {
  const factors = await listTotpFactors();
  const factor = factors.find((f) => f.status === "verified") || factors[0];
  if (!factor?.id) throw new Error("No authenticator is set up on this account.");
  return verifyTotp({ factorId: factor.id, code });
}

export async function unenrollTotp(factorId) {
  const supabase = getSupabase();
  const { error } = await supabase.auth.mfa.unenroll({ factorId });
  if (error) throw error;
}
