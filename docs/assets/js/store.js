import { uuid, startOfDay, sameDay, SPECIALTIES } from "./brand.js";
import { normalizeShift, isPastShift, currentRate } from "./shift-math.js";
import { getSupabase, isConfigured, upsertProfile } from "./supabase-client.js";

const KEYS = {
  accounts: "accounts_v2",
  session: "oncall_session",
  doctorProfile: "doctor_profile_v2",
  hospitalProfile: "hospital_profile_v1",
  hospitalShifts: "hospital_shifts_v1",
  assignments: "assigned_shifts_v1",
  tokens: "token_store_v1",
  points: "points_store_v1",
  doctorPrefs: "doctor_prefs_v1",
  savedRole: "saved_role"
};

function read(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function write(key, value) {
  localStorage.setItem(key, JSON.stringify(value));
}

export const appStore = {
  listeners: new Set(),
  subscribe(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); },
  emit() { this.listeners.forEach((fn) => fn()); },

  get session() { return read(KEYS.session, null); },
  setSession(session) { write(KEYS.session, session); this.emit(); },
  clearSession() { localStorage.removeItem(KEYS.session); localStorage.removeItem(KEYS.savedRole); this.emit(); },

  get savedRole() { return localStorage.getItem(KEYS.savedRole); },
  setSavedRole(role) { localStorage.setItem(KEYS.savedRole, role); this.emit(); },

  get accounts() { return read(KEYS.accounts, []); },
  saveAccounts(list) { write(KEYS.accounts, list); },

  get doctorProfile() { return read(KEYS.doctorProfile, null); },
  saveDoctorProfile(p) { write(KEYS.doctorProfile, p); this.emit(); },

  get hospitalProfile() { return read(KEYS.hospitalProfile, null); },
  saveHospitalProfile(p) { write(KEYS.hospitalProfile, p); this.emit(); },

  get shifts() {
    return read(KEYS.hospitalShifts, []).map(normalizeShift);
  },
  saveShifts(shifts) {
    write(KEYS.hospitalShifts, shifts);
    this.emit();
  },

  get assignments() { return read(KEYS.assignments, []); },
  saveAssignments(list) { write(KEYS.assignments, list); this.emit(); },

  get tokens() {
    return read(KEYS.tokens, { dailyLimit: 3, tokensRemaining: 3, requests: [] });
  },
  saveTokens(state) { write(KEYS.tokens, state); this.emit(); },

  get points() {
    return read(KEYS.points, {
      totalPoints: 0,
      currentStreak: 0,
      level: { name: "Intern", minPoints: 0, icon: "🩺" },
      nextLevel: { name: "Resident", minPoints: 100 },
      recentEvents: []
    });
  },
  savePoints(state) { write(KEYS.points, state); this.emit(); },

  get doctorPrefs() {
    return read(KEYS.doctorPrefs, {
      showOnlyMySpecialties: true,
      hiddenHospitalIDs: [],
      hiddenSpecialties: [],
      notifyNewShifts: true,
      notifyTradeRequests: true,
      notifyApprovals: true
    });
  },
  saveDoctorPrefs(prefs) { write(KEYS.doctorPrefs, prefs); this.emit(); }
};

export function accountExists(email) {
  return appStore.accounts.some((a) => a.email === email.toLowerCase());
}

export function registerAccount(email, password, role) {
  const normalized = email.toLowerCase();
  const existing = appStore.accounts.find((a) => a.email === normalized);
  if (existing) return existing.id;
  const account = { id: uuid(), email: normalized, passwordHash: password, role };
  const all = [...appStore.accounts, account];
  appStore.saveAccounts(all);
  return account.id;
}

export function signInLocal(email, password) {
  const acct = appStore.accounts.find((a) => a.email === email.toLowerCase());
  if (!acct || acct.passwordHash !== password) return null;
  return acct;
}

export async function signInRemote(email, password) {
  const supabase = getSupabase();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  const user = data.user;
  const { data: profile } = await supabase.from("profiles").select("role").eq("id", user.id).maybeSingle();
  const role = profile?.role ? profile.role.charAt(0).toUpperCase() + profile.role.slice(1) : "Doctor";
  return { userID: user.id, email: user.email, role };
}

export async function signUpRemote(email, password, role) {
  const supabase = getSupabase();
  const { data, error } = await supabase.auth.signUp({ email, password });
  if (error) throw error;
  const userID = data.user.id;
  await upsertProfile(userID, email, role.toLowerCase());
  return { userID, email, role };
}

export function beginSession({ userID, email, role }) {
  appStore.setSession({ userID, email, role });
  appStore.setSavedRole(role);
}

export function authState() {
  const session = appStore.session;
  if (!session) return { kind: "loggedOut" };
  const role = session.role;
  const hasProfile = role === "Doctor" ? !!appStore.doctorProfile : !!appStore.hospitalProfile;
  if (!hasProfile) return { kind: "needsOnboarding", role };
  return { kind: "authenticated", role };
}

const DEMO_HOSPITAL_ID = "00000000-0000-4000-8000-000000000001";

export function demoHospital() {
  return { id: DEMO_HOSPITAL_ID, name: "Demo Medical Center" };
}

export function ensureDemoShifts(hospitalID, hospitalName) {
  const hid = hospitalID || DEMO_HOSPITAL_ID;
  const hname = hospitalName || "Demo Medical Center";
  let shifts = appStore.shifts;
  const existing = shifts.filter((s) => s.hospitalID === hid && !isPastShift(s));
  if (existing.length >= 30) return;

  const start = startOfDay(new Date());
  for (let offset = 0; offset < 60; offset++) {
    const date = new Date(start);
    date.setDate(date.getDate() + offset);
    for (const specialty of SPECIALTIES) {
      const exists = shifts.some(
        (s) => s.hospitalID === hid && s.specialty === specialty && sameDay(s.start, date)
      );
      if (exists) continue;
      shifts.push({
        id: uuid(),
        hospitalID: hid,
        hospital: hname,
        specialty,
        start: date.toISOString(),
        durationHours: 24,
        rateFloor: 800 + Math.floor(Math.random() * 400),
        rateUnit: "per day",
        escalationMode: { type: "automatic" },
        usesAlgorithmPricing: true
      });
    }
  }
  appStore.saveShifts(shifts);
}

export function openShifts(profile) {
  const prefs = appStore.doctorPrefs;
  return appStore.shifts
    .filter((s) => !isPastShift(s) && !isShiftFilled(s.id))
    .filter((s) => {
      if (prefs.hiddenHospitalIDs.includes(s.hospitalID)) return false;
      if (prefs.hiddenSpecialties.includes(s.specialty)) return false;
      if (prefs.showOnlyMySpecialties && profile?.specialties?.length) {
        return profile.specialties.includes(s.specialty);
      }
      return true;
    });
}

export function isShiftFilled(shiftID) {
  return appStore.assignments.some(
    (a) => a.shiftID === shiftID && !["canceled", "traded_complete"].includes(a.status)
  );
}

export function activeAssignments() {
  return appStore.assignments.filter((a) => a.status === "scheduled" || a.status === "traded_pending");
}

export function pendingTradeCount() {
  return appStore.assignments.filter((a) => a.status === "traded_pending").length;
}

export function acceptShift(shift, doctor) {
  if (isShiftFilled(shift.id)) return;
  const list = [...appStore.assignments, {
    id: uuid(),
    shiftID: shift.id,
    shift,
    doctorID: doctor.id,
    doctorName: `${doctor.firstName} ${doctor.lastName}`,
    status: "scheduled",
    assignedAt: new Date().toISOString()
  }];
  appStore.saveAssignments(list);
  awardPoints(25, "Accepted shift");
}

export function awardPoints(amount, label) {
  const pts = appStore.points;
  pts.totalPoints += amount;
  pts.recentEvents = [{ event: { label, points: amount, icon: "★" } }, ...pts.recentEvents].slice(0, 10);
  if (pts.totalPoints >= 100) {
    pts.level = { name: "Resident", minPoints: 100, icon: "⭐" };
    pts.nextLevel = { name: "Attending", minPoints: 500 };
  }
  appStore.savePoints(pts);
}

export function openShiftCount(hospitalID) {
  return appStore.shifts.filter(
    (s) => s.hospitalID === hospitalID && !isPastShift(s) && !isShiftFilled(s.id)
  ).length;
}

export function fillRatePercent(hospitalID) {
  const future = appStore.shifts.filter((s) => s.hospitalID === hospitalID && !isPastShift(s));
  if (!future.length) return 0;
  const filled = future.filter((s) => isShiftFilled(s.id)).length;
  return Math.round((filled / future.length) * 100);
}

export async function syncShiftsFromSupabase(hospitalID) {
  if (!isConfigured()) return;
  try {
    const supabase = getSupabase();
    let query = supabase.from("shifts").select("*").gte("date", new Date().toISOString()).order("date");
    if (hospitalID) query = query.eq("hospital_id", hospitalID);
    const { data, error } = await query.limit(200);
    if (error || !data?.length) return;
    const mapped = data.map((row) => normalizeShift({
      id: row.id,
      hospital_id: row.hospital_id,
      hospital_name: row.hospital_name,
      specialty: row.specialty,
      date: row.date,
      rate_floor: row.rate_floor,
      rate_unit: row.rate_unit,
      duration_hours: row.duration_hours
    }));
    const local = appStore.shifts.filter((s) => !mapped.some((m) => m.id === s.id));
    appStore.saveShifts([...local, ...mapped]);
  } catch {
    /* offline */
  }
}

export function recommendedShifts(limit = 3) {
  return openShifts(appStore.doctorProfile)
    .sort((a, b) => new Date(a.start) - new Date(b.start))
    .slice(0, limit);
}

export function shiftsForDate(date, profile) {
  return openShifts(profile).filter((s) => sameDay(s.start, date));
}

export function requestToken(date, hospitalID, hospitalName, specialty, doctorID) {
  const tokens = appStore.tokens;
  if (tokens.tokensRemaining <= 0) return { ok: false, error: "No tokens remaining today." };
  tokens.tokensRemaining -= 1;
  tokens.requests.push({
    id: uuid(),
    date: startOfDay(date).toISOString(),
    hospitalID,
    hospitalName,
    specialty,
    doctorID,
    status: "pending",
    requestedAt: new Date().toISOString()
  });
  appStore.saveTokens(tokens);
  return { ok: true };
}

export function signOut() {
  appStore.clearSession();
  if (isConfigured()) {
    try { getSupabase().auth.signOut(); } catch { /* ignore */ }
  }
}
