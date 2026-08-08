import { getSupabase, isConfigured } from "../supabase-client.js";

export const REVIEW_STATUSES = ["pending", "verified", "waitlisted", "rejected"];

// reviewed_by is a second foreign key to profiles, so the applicant join has to
// name the constraint or PostgREST refuses the embed as ambiguous.
const DOCTOR_SELECT = [
  "profile_id", "first_name", "last_name", "credential", "npi", "specialties",
  "verification_status", "verification_flags", "submitted_at", "reviewed_at", "review_note",
  "applicant:profiles!doctor_profiles_profile_id_fkey(email)"
].join(",");

const HOSPITAL_SELECT = [
  "id", "name", "npi", "verification_status", "verification_flags",
  "submitted_at", "reviewed_at", "review_note",
  "applicant:profiles!hospital_profiles_profile_id_fkey(email)"
].join(",");

/** True only when the signed-in user has been granted admin in the SQL editor. */
export async function isAdminUser(userId) {
  if (!isConfigured() || !userId) return false;
  try {
    const { data, error } = await getSupabase()
      .from("profiles")
      .select("is_admin")
      .eq("id", userId)
      .maybeSingle();
    if (error) return false;
    return Boolean(data?.is_admin);
  } catch {
    return false;
  }
}

function toDoctor(row) {
  const name = [row.first_name, row.last_name].filter(Boolean).join(" ").trim();
  return {
    key: `doctor:${row.profile_id}`,
    kind: "doctor",
    id: row.profile_id,
    name: name || "Unnamed doctor",
    credential: row.credential || "",
    detail: (row.specialties || []).join(" · "),
    email: row.applicant?.email || "",
    npi: row.npi || "",
    status: row.verification_status || "pending",
    flags: row.verification_flags || [],
    submittedAt: row.submitted_at,
    reviewedAt: row.reviewed_at,
    note: row.review_note || ""
  };
}

function toHospital(row) {
  return {
    key: `hospital:${row.id}`,
    kind: "hospital",
    id: row.id,
    name: row.name || "Unnamed hospital",
    credential: "",
    detail: "Hospital",
    email: row.applicant?.email || "",
    npi: row.npi || "",
    status: row.verification_status || "pending",
    flags: row.verification_flags || [],
    submittedAt: row.submitted_at,
    reviewedAt: row.reviewed_at,
    note: row.review_note || ""
  };
}

/** Oldest application first — the person who has been waiting longest is on top. */
function byOldestFirst(a, b) {
  return new Date(a.submittedAt || 0) - new Date(b.submittedAt || 0);
}

export async function fetchApplications() {
  const supabase = getSupabase();
  const [doctors, hospitals] = await Promise.all([
    supabase.from("doctor_profiles").select(DOCTOR_SELECT),
    supabase.from("hospital_profiles").select(HOSPITAL_SELECT)
  ]);
  if (doctors.error) throw doctors.error;
  if (hospitals.error) throw hospitals.error;

  return [
    ...(doctors.data || []).map(toDoctor),
    ...(hospitals.data || []).map(toHospital)
  ].sort(byOldestFirst);
}

export async function setApplicationStatus(application, status, note = null) {
  if (!REVIEW_STATUSES.includes(status)) throw new Error(`Unknown status: ${status}`);
  const supabase = getSupabase();
  const { data: auth } = await supabase.auth.getUser();

  const table = application.kind === "doctor" ? "doctor_profiles" : "hospital_profiles";
  const idColumn = application.kind === "doctor" ? "profile_id" : "id";

  const { error } = await supabase
    .from(table)
    .update({
      verification_status: status,
      reviewed_at: new Date().toISOString(),
      reviewed_by: auth?.user?.id ?? null,
      review_note: note
    })
    .eq(idColumn, application.id);

  if (error) throw error;
}
