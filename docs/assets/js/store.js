import { uuid, startOfDay, sameDay, SPECIALTIES } from "./brand.js";
import { normalizeShift, isPastShift, currentRate } from "./shift-math.js";
import { getSupabase, isConfigured, upsertProfile } from "./supabase-client.js";
import { defaultPolicy, previewPenalty, normalizeCancellationScale, bracketLabel } from "./domain/policy.js";
import { algorithmRate, computeRate, rateBreakdown, groupPricingComponents } from "./domain/pricing.js";
import * as sync from "./domain/sync.js";

export const KEYS = {
  accounts: "accounts_v2",
  session: "oncall_session",
  savedRole: "saved_role",
  doctorProfile: "doctor_profile_v2",
  hospitalProfile: "hospital_profile_v2",
  hospitalShifts: "hospital_shifts_v1",
  assignments: "assigned_shifts_v1",
  tokens: "doctor_tokens_v2",
  roster: "doctor_roster_v1",
  policies: "hospital_scheduling_policy_v1",
  unavailable: "unavailable_days_v1",
  proposedRates: "proposed_rates_v1",
  penaltyLedger: "penalty_ledger_v1",
  doctorPrefs: "doctor_prefs_v1",
  trades: "shift_trade_service_v1"
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

function migrateLegacyKeys() {
  const legacyTokens = read("token_store_v1", null);
  if (legacyTokens && !localStorage.getItem(KEYS.tokens)) {
    write(KEYS.tokens, {
      tokensRemaining: legacyTokens.tokensRemaining ?? 3,
      dailyLimit: legacyTokens.dailyLimit ?? 3,
      lastResetDate: new Date().toISOString(),
      requestedDays: legacyTokens.requests || []
    });
  }
  const legacyHospital = read("hospital_profile_v1", null);
  if (legacyHospital && !localStorage.getItem(KEYS.hospitalProfile)) {
    write(KEYS.hospitalProfile, legacyHospital);
  }
}

migrateLegacyKeys();

export const DEFAULT_DAILY_TOKENS = 3;

function defaultTokens() {
  return {
    tokensRemaining: DEFAULT_DAILY_TOKENS,
    dailyLimit: DEFAULT_DAILY_TOKENS,
    lastResetDate: startOfDay(new Date()).toISOString(),
    requestedDays: []
  };
}

function defaultPrefs() {
  return {
    showOnlyMySpecialties: true,
    hiddenHospitalIDs: [],
    hiddenSpecialties: [],
    notifyNewShifts: true,
    notifyTradeRequests: true,
    notifyApprovals: true
  };
}

function refreshTokenDailyReset(tokens) {
  const today = startOfDay(new Date()).toISOString();
  if (tokens.lastResetDate && sameDay(tokens.lastResetDate, today)) return tokens;
  return { ...tokens, tokensRemaining: tokens.dailyLimit, lastResetDate: today };
}

/**
 * Applies a change to the doctor's allowance without refunding or revoking
 * tokens they already spent today: what they have left is the new allowance
 * minus today's usage, floored at zero.
 */
function applyTokenLimit(tokens, limit) {
  if (!Number.isFinite(limit) || limit === tokens.dailyLimit) return tokens;
  const usedToday = Math.max(0, (tokens.dailyLimit ?? limit) - (tokens.tokensRemaining ?? 0));
  return {
    ...tokens,
    dailyLimit: limit,
    tokensRemaining: Math.max(0, limit - usedToday)
  };
}

export const appStore = {
  listeners: new Set(),
  subscribe(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); },
  emit() { this.listeners.forEach((fn) => fn()); },

  get session() { return read(KEYS.session, null); },
  setSession(session) { write(KEYS.session, session); this.emit(); },
  clearSession() {
    localStorage.removeItem(KEYS.session);
    localStorage.removeItem(KEYS.savedRole);
    this.emit();
  },

  get savedRole() { return localStorage.getItem(KEYS.savedRole); },
  setSavedRole(role) { localStorage.setItem(KEYS.savedRole, role); this.emit(); },

  get accounts() { return read(KEYS.accounts, []); },
  saveAccounts(list) { write(KEYS.accounts, list); },

  get doctorProfile() {
    const p = read(KEYS.doctorProfile, null);
    if (!p) return null;
    // One specialty per doctor — keep the first if older profiles stored several.
    if (Array.isArray(p.specialties) && p.specialties.length > 1) {
      const trimmed = { ...p, specialties: [p.specialties[0]] };
      write(KEYS.doctorProfile, trimmed);
      return trimmed;
    }
    return p;
  },
  saveDoctorProfile(p) {
    const next = p && Array.isArray(p.specialties) && p.specialties.length
      ? { ...p, specialties: [p.specialties[0]] }
      : p;
    write(KEYS.doctorProfile, next);
    this.emit();
  },

  get hospitalProfile() { return read(KEYS.hospitalProfile, null); },
  saveHospitalProfile(p) { write(KEYS.hospitalProfile, p); this.emit(); },

  get shifts() { return read(KEYS.hospitalShifts, []).map(normalizeShift); },
  saveShifts(shifts) { write(KEYS.hospitalShifts, shifts); this.emit(); },

  get assignments() {
    const raw = read(KEYS.assignments, { shifts: [] });
    return Array.isArray(raw) ? raw : (raw.shifts || []);
  },
  saveAssignments(list) { write(KEYS.assignments, { shifts: list }); this.emit(); },

  get tokens() {
    const stored = refreshTokenDailyReset(read(KEYS.tokens, defaultTokens()));
    // The hospital owns the allowance, so pick it up here rather than waiting
    // for the next daily reset. Written without emitting: this getter runs
    // during render, and emitting would loop.
    const t = applyTokenLimit(stored, effectiveDailyTokenLimit(this.doctorProfile?.id));
    write(KEYS.tokens, t);
    return t;
  },
  saveTokens(state) { write(KEYS.tokens, state); this.emit(); },


  get roster() { return read(KEYS.roster, []); },
  saveRoster(list) { write(KEYS.roster, list); this.emit(); },

  get policies() { return read(KEYS.policies, {}); },
  savePolicies(map) { write(KEYS.policies, map); this.emit(); },

  get unavailable() { return read(KEYS.unavailable, {}); },
  saveUnavailable(map) { write(KEYS.unavailable, map); this.emit(); },

  get proposedRates() { return read(KEYS.proposedRates, []); },
  saveProposedRates(list) { write(KEYS.proposedRates, list); this.emit(); },

  get penaltyLedger() { return read(KEYS.penaltyLedger, []); },
  savePenaltyLedger(list) { write(KEYS.penaltyLedger, list); this.emit(); },

  get doctorPrefs() { return read(KEYS.doctorPrefs, defaultPrefs()); },
  saveDoctorPrefs(prefs) { write(KEYS.doctorPrefs, prefs); this.emit(); },

  get trades() { return read(KEYS.trades, { incoming: [], outgoing: [] }); },
  saveTrades(t) { write(KEYS.trades, t); this.emit(); }
};

const syncHooks = {
  readLocal(key) {
    switch (key) {
      case "doctorProfile": return appStore.doctorProfile;
      case "hospitalProfile": return appStore.hospitalProfile;
      case "shifts": return appStore.shifts;
      case "assignments": return appStore.assignments;
      case "tokens": return appStore.tokens;
      case "roster": return appStore.roster;
      case "policies": return appStore.policies;
      case "unavailable": return appStore.unavailable;
      default: return null;
    }
  },
  writeLocal(key, value) {
    switch (key) {
      case "shifts": appStore.saveShifts(value); break;
      case "assignments": appStore.saveAssignments(value); break;
      case "tokens": appStore.saveTokens(value); break;
      case "roster": appStore.saveRoster(value); break;
      case "policies": appStore.savePolicies(value); break;
      case "unavailable": appStore.saveUnavailable(value); break;
      default: break;
    }
  },
  emit: () => appStore.emit()
};

export async function syncEverything() {
  return sync.syncEverything(syncHooks);
}

async function afterMutation(fn) {
  if (!isConfigured()) return;
  try { await fn(); } catch { /* offline */ }
}

// ── Auth ─────────────────────────────────────────────────────────────

export function normalizeEmail(raw) {
  const value = String(raw || "").trim().toLowerCase();
  if (!value) return "";

  const aliases = {
    erdunn: "erdunn706@gmail.com",
    "erdunn706": "erdunn706@gmail.com",
    jdunn: "jdunn@eporthospine.com",
    "jdunn@eporthospine": "jdunn@eporthospine.com",
    admin: "info@erdanimates.shop",
    info: "info@erdanimates.shop"
  };
  if (aliases[value]) return aliases[value];
  if (!value.includes("@")) return `${value}@gmail.com`;
  // Incomplete domains like jdunn@eporthospine → .com
  if (value.endsWith("@eporthospine")) return `${value}.com`;
  return value;
}

export function accountExists(email) {
  return appStore.accounts.some((a) => a.email === email.toLowerCase());
}

export function registerAccount(email, password, role) {
  const normalized = email.toLowerCase();
  const existing = appStore.accounts.find((a) => a.email === normalized);
  if (existing) return existing.id;
  const account = { id: uuid(), email: normalized, passwordHash: password, role };
  appStore.saveAccounts([...appStore.accounts, account]);
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

export function signOut() {
  appStore.clearSession();
  if (isConfigured()) {
    try { getSupabase().auth.signOut(); } catch { /* ignore */ }
  }
}

// ── Onboarding finish ────────────────────────────────────────────────

export async function finishDoctorProfile(profile) {
  const p = { ...profile, id: profile.id || appStore.session?.userID || uuid() };
  if (appStore.session?.userID) p.userID = appStore.session.userID;
  appStore.saveDoctorProfile(p);
  registerDoctorOnRoster(p);
  await afterMutation(() => sync.upsertDoctorProfile(p));
  await syncEverything();
  return p;
}

export async function finishHospitalProfile(profile) {
  const policy = profile.schedulingPolicy || defaultPolicy();
  policy.cancellationPenaltyScale = normalizeCancellationScale(policy.cancellationPenaltyScale);
  const p = {
    ...profile,
    id: profile.id || uuid(),
    schedulingPolicy: policy
  };
  if (appStore.session?.userID) p.userID = appStore.session.userID;
  appStore.saveHospitalProfile(p);
  const policies = { ...appStore.policies, [p.id]: policy };
  appStore.savePolicies(policies);
  await afterMutation(() => sync.upsertHospitalProfile(p));
  ensureDemoShifts(p.id, p.name);
  seedMockDoctors();
  await syncEverything();
  return p;
}

// ── Policy ───────────────────────────────────────────────────────────

export function getPolicy(hospitalID) {
  const policies = appStore.policies;
  if (policies[hospitalID]) return { ...defaultPolicy(), ...policies[hospitalID] };
  const hp = appStore.hospitalProfile;
  if (hp?.id === hospitalID && hp.schedulingPolicy) {
    return { ...defaultPolicy(), ...hp.schedulingPolicy };
  }
  return defaultPolicy();
}

// ── Daily token allowances ───────────────────────────────────────────

/** What one hospital allows a given doctor per day. */
export function tokenLimitForDoctor(hospitalID, doctorID) {
  const policy = getPolicy(hospitalID);
  const override = policy.doctorTokenLimits?.[doctorID];
  if (Number.isFinite(override)) return override;
  const fallback = policy.defaultDailyTokens;
  return Number.isFinite(fallback) ? fallback : DEFAULT_DAILY_TOKENS;
}

/**
 * A doctor holds one pool of tokens but may sit on several rosters, so the
 * most generous hospital wins. Anything else would let one hospital throttle
 * a doctor's requests to another.
 */
export function effectiveDailyTokenLimit(doctorID) {
  if (!doctorID) return DEFAULT_DAILY_TOKENS;
  const policies = appStore.policies || {};
  let limit = null;

  for (const [hospitalID, stored] of Object.entries(policies)) {
    if (!stored) continue;
    const candidate = tokenLimitForDoctor(hospitalID, doctorID);
    if (!Number.isFinite(candidate)) continue;
    limit = limit == null ? candidate : Math.max(limit, candidate);
  }

  return limit == null ? DEFAULT_DAILY_TOKENS : limit;
}

/** Sets one doctor's allowance at one hospital. Passing null clears it. */
export async function setDoctorTokenLimit(hospitalID, doctorID, limit) {
  const policy = { ...getPolicy(hospitalID) };
  const limits = { ...(policy.doctorTokenLimits || {}) };

  if (limit == null) delete limits[doctorID];
  else limits[doctorID] = Math.max(0, Math.min(20, Math.round(limit)));

  policy.doctorTokenLimits = limits;
  await savePolicy(hospitalID, policy);
}

export async function savePolicy(hospitalID, policy) {
  const normalized = { ...policy };
  normalized.cancellationPenaltyScale = normalizeCancellationScale(normalized.cancellationPenaltyScale);
  const policies = { ...appStore.policies, [hospitalID]: normalized };
  appStore.savePolicies(policies);
  const hp = appStore.hospitalProfile;
  if (hp?.id === hospitalID) {
    appStore.saveHospitalProfile({ ...hp, schedulingPolicy: normalized });
  }
  await afterMutation(() => sync.upsertPolicy(hospitalID, normalized));
}

// ── Demo / shifts ────────────────────────────────────────────────────

export const DEMO_HOSPITAL_ID = "00000000-0000-4000-8000-000000000001";

// Shown to real accounts while the marketplace fills out, so it must read like
// a hospital rather than a placeholder.
const PLACEHOLDER_HOSPITAL_NAME = "Riverside General";

export function demoHospital() {
  return { id: DEMO_HOSPITAL_ID, name: PLACEHOLDER_HOSPITAL_NAME };
}

/**
 * Anyone who used the app before the rename has the old placeholder saved in
 * their browser, and the generator will not revisit those days.
 */
(function renameStoredPlaceholder() {
  const legacy = "Demo Medical Center";
  const rename = (shift) =>
    shift?.hospital === legacy ? { ...shift, hospital: PLACEHOLDER_HOSPITAL_NAME } : shift;

  const shifts = read(KEYS.hospitalShifts, []);
  if (shifts.some((s) => s.hospital === legacy)) {
    write(KEYS.hospitalShifts, shifts.map(rename));
  }

  const raw = read(KEYS.assignments, { shifts: [] });
  const list = Array.isArray(raw) ? raw : (raw.shifts || []);
  if (list.some((a) => a.shift?.hospital === legacy)) {
    write(KEYS.assignments, { shifts: list.map((a) => ({ ...a, shift: rename(a.shift) })) });
  }
})();

export function pricingObservables(specialty, date, hospitalID) {
  const day = startOfDay(date);
  const roster = appStore.roster;
  const assignments = appStore.assignments;
  const tokens = appStore.tokens.requestedDays || [];
  const hospitalShifts = appStore.shifts.filter((s) => s.hospitalID === hospitalID);
  const specialtyShifts = hospitalShifts.filter((s) => s.specialty === specialty);
  const openCount = specialtyShifts.filter((s) => !isPastShift(s) && !isShiftFilled(s.id)).length;
  const specialtyDoctors = roster.filter((d) => d.specialty === specialty && d.verificationStatus === "verified");
  const hospitalWideOpen = hospitalShifts.filter((s) => !isPastShift(s) && !isShiftFilled(s.id)).length;
  const hospitalRoster = roster.filter((d) => d.verificationStatus === "verified").length;
  const pastShifts = specialtyShifts.filter(isPastShift);
  const recentFillRate = pastShifts.length
    ? pastShifts.filter((s) => isShiftFilled(s.id)).length / pastShifts.length
    : null;
  const daysUntil = (day - startOfDay(new Date())) / 86400000;
  const pendingTokens = tokens.filter((t) =>
    t.hospitalID === hospitalID && sameDay(t.date, day) && t.specialty === specialty && t.status === "pending"
  ).length;
  const autoApproved = specialtyDoctors.filter((d) => d.isAutoApproved).length;
  let adjacentUnfilled = 0;
  for (const offset of [-2, -1, 1, 2]) {
    const adj = new Date(day);
    adj.setDate(adj.getDate() + offset);
    const adjShifts = specialtyShifts.filter((s) => sameDay(s.start, adj) && !isPastShift(s));
    if (adjShifts.some((s) => !isShiftFilled(s.id))) adjacentUnfilled++;
  }

  const pendingTradeCount = (appStore.trades.incoming || []).length
    + assignments.filter((a) => a.status === "traded_pending" && a.shift?.hospitalID === hospitalID).length;
  const recentCancelCount = appStore.penaltyLedger.filter((p) =>
    p.hospitalID === hospitalID && p.type === "cancel"
    && (Date.now() - new Date(p.createdAt).getTime()) < 30 * 86400000
  ).length;

  // Rough avg fill hours from assignment lag when available.
  let avgFillHours = null;
  const filledWithAssign = specialtyShifts
    .map((s) => {
      const a = assignments.find((x) => x.shiftID === s.id && x.assignedAt);
      if (!a) return null;
      return (new Date(a.assignedAt) - new Date(s.start)) / 3600000;
    })
    .filter((h) => h != null && h >= 0);
  if (filledWithAssign.length) {
    avgFillHours = filledWithAssign.reduce((s, h) => s + h, 0) / filledWithAssign.length;
  }

  return {
    openShiftCount: openCount,
    availableDoctorCount: specialtyDoctors.length,
    hospitalWideOpenShifts: hospitalWideOpen,
    hospitalWideRosterSize: hospitalRoster,
    recentFillRate,
    daysUntilShift: daysUntil,
    pendingTokenRequests: pendingTokens,
    autoApprovedDoctorCount: autoApproved,
    adjacentUnfilledDays: adjacentUnfilled,
    avgFillHours,
    pendingTradeCount,
    recentCancelCount,
    sampleSize: pastShifts.length + specialtyShifts.length
  };
}

export function ensureDemoShifts(hospitalID, hospitalName) {
  const hid = hospitalID || DEMO_HOSPITAL_ID;
  const hname = hospitalName || PLACEHOLDER_HOSPITAL_NAME;
  const policy = getPolicy(hid);
  let shifts = [...appStore.shifts];
  const existing = shifts.filter((s) => s.hospitalID === hid && !isPastShift(s));
  if (existing.length >= 30) return;

  const start = startOfDay(new Date());
  for (let offset = 0; offset < 60; offset++) {
    const date = new Date(start);
    date.setDate(date.getDate() + offset);
    for (const specialty of SPECIALTIES) {
      if (shifts.some((s) => s.hospitalID === hid && s.specialty === specialty && sameDay(s.start, date))) {
        continue;
      }
      const proposed = getProposedRate(hid, specialty, date);
      const rateFloor = proposed.rate;
      shifts.push({
        id: uuid(),
        hospitalID: hid,
        hospital: hname,
        specialty,
        start: date.toISOString(),
        durationHours: policy.granularity === "hour" ? 8 : 24,
        rateFloor,
        rateUnit: policy.granularity === "hour" ? "per hour" : "per day",
        escalationMode: { type: "automatic" },
        usesAlgorithmPricing: true
      });
    }
  }
  appStore.saveShifts(shifts);
}

export function getProposedRate(hospitalID, specialty, date) {
  const day = startOfDay(date);
  const entries = appStore.proposedRates;
  const custom = entries.find((e) =>
    e.hospitalID === hospitalID && e.specialty === specialty && sameDay(e.date, day)
  );
  const obs = pricingObservables(specialty, day, hospitalID);
  const granularity = getPolicy(hospitalID).granularity;
  const algo = algorithmRate(specialty, day.toISOString(), hospitalID, obs, granularity);
  return { rate: custom?.rate ?? algo, algorithmRate: algo, isCustom: !!custom };
}

export async function setProposedRate(hospitalID, specialty, date, rate) {
  const day = startOfDay(date).toISOString();
  let entries = appStore.proposedRates.filter((e) =>
    !(e.hospitalID === hospitalID && e.specialty === specialty && sameDay(e.date, day))
  );
  entries.push({ hospitalID, specialty, date: day, rate });
  appStore.saveProposedRates(entries);

  let shifts = appStore.shifts.map((s) => {
    if (s.hospitalID === hospitalID && s.specialty === specialty && sameDay(s.start, day)) {
      return { ...s, rateFloor: rate };
    }
    return s;
  });
  appStore.saveShifts(shifts);

  await afterMutation(async () => {
    if (isConfigured()) {
      const supabase = getSupabase();
      await supabase.from("proposed_rates").upsert({
        hospital_id: hospitalID,
        specialty,
        date: day.slice(0, 10),
        rate
      });
    }
    for (const s of shifts.filter((x) => x.hospitalID === hospitalID && x.specialty === specialty && sameDay(x.start, day))) {
      await sync.upsertShift(s);
    }
  });
}

export async function resetProposedRate(hospitalID, specialty, date) {
  const day = startOfDay(date).toISOString();
  const entries = appStore.proposedRates.filter((e) =>
    !(e.hospitalID === hospitalID && e.specialty === specialty && sameDay(e.date, day))
  );
  appStore.saveProposedRates(entries);
  const { algorithmRate: algo } = getProposedRate(hospitalID, specialty, date);
  await setProposedRate(hospitalID, specialty, date, algo);
}

/** Save Alter Shifts editor state onto the day's shift (mirrors iOS saveShift). */
export async function saveAlterShift({
  hospitalID,
  hospitalName,
  specialty,
  date,
  rateFloor,
  useAlgorithm,
  useFlatRate,
  flatRate
}) {
  const day = startOfDay(date);
  const policy = getPolicy(hospitalID);
  const isHourly = policy.granularity === "hour";
  let shifts = [...appStore.shifts];
  let existing = shifts.find((s) =>
    s.hospitalID === hospitalID && s.specialty === specialty && sameDay(s.start, day)
  );

  const shift = {
    id: existing?.id || uuid(),
    hospitalID,
    hospital: hospitalName || "Hospital",
    specialty,
    start: day.toISOString(),
    durationHours: isHourly ? 12 : 24,
    rateFloor: Number(rateFloor),
    rateUnit: isHourly ? "per hour" : "per day",
    escalationMode: useFlatRate
      ? { type: "flat", rate: Number(flatRate) }
      : { type: "automatic" },
    usesAlgorithmPricing: !!useAlgorithm
  };

  if (existing) {
    shifts = shifts.map((s) => (s.id === existing.id ? { ...s, ...shift, id: existing.id } : s));
  } else {
    shifts.push(shift);
  }
  appStore.saveShifts(shifts);

  // Keep proposed-rate store in sync when algorithm or manual floor changes.
  if (useAlgorithm || !useFlatRate) {
    let entries = appStore.proposedRates.filter((e) =>
      !(e.hospitalID === hospitalID && e.specialty === specialty && sameDay(e.date, day))
    );
    if (!useAlgorithm) {
      entries.push({ hospitalID, specialty, date: day.toISOString(), rate: Number(rateFloor) });
    }
    appStore.saveProposedRates(entries);
  }

  await afterMutation(() => sync.upsertShift(shift));
  return shift;
}

export function findShiftForDay(hospitalID, specialty, date) {
  return appStore.shifts.find((s) =>
    s.hospitalID === hospitalID && s.specialty === specialty && sameDay(s.start, date)
  ) || null;
}

export function openShifts(profile) {
  const prefs = appStore.doctorPrefs;
  const mySpecialty = profile?.specialties?.[0];
  return appStore.shifts
    .filter((s) => !isPastShift(s) && !isShiftFilled(s.id))
    .filter((s) => !isDayUnavailable(s.start, s.hospitalID))
    .filter((s) => {
      if (prefs.hiddenHospitalIDs.includes(s.hospitalID)) return false;
      // Doctors only ever see their one assigned specialty.
      if (mySpecialty) return s.specialty === mySpecialty;
      return true;
    });
}

export function isShiftFilled(shiftID) {
  return appStore.assignments.some(
    (a) => a.shiftID === shiftID && !["canceled", "traded_complete"].includes(a.status)
  );
}

export function activeAssignments() {
  return appStore.assignments.filter((a) =>
    a.status === "scheduled" || a.status === "traded_pending"
  );
}

export function pendingTradeCount() {
  const trades = appStore.trades;
  return (trades.incoming?.length || 0) + appStore.assignments.filter((a) => a.status === "traded_pending").length;
}

export function incomingTrades() {
  return appStore.trades.incoming || [];
}

export function recommendedShifts(limit = 3) {
  return openShifts(appStore.doctorProfile)
    .sort((a, b) => new Date(a.start) - new Date(b.start))
    .slice(0, limit);
}

export function shiftsForDate(date, profile) {
  return openShifts(profile).filter((s) => sameDay(s.start, date));
}

export function openShiftCount(hospitalID) {
  return appStore.shifts.filter(
    (s) => s.hospitalID === hospitalID && !isPastShift(s) && !isShiftFilled(s.id)
  ).length;
}

export function fillRatePercent(hospitalID) {
  const future = appStore.shifts.filter((s) => s.hospitalID === hospitalID && !isPastShift(s));
  if (!future.length) return 0;
  return Math.round(future.filter((s) => isShiftFilled(s.id)).length / future.length * 100);
}

export function autoApprovedCount() {
  return appStore.roster.filter((d) => d.isAutoApproved).length;
}

// ── Unavailable days ─────────────────────────────────────────────────

export function isDayUnavailable(date, hospitalID) {
  const map = appStore.unavailable;
  const dates = map[hospitalID] || [];
  return dates.some((d) => sameDay(d, date));
}

export async function toggleUnavailable(hospitalID, date) {
  const map = { ...appStore.unavailable };
  const dates = [...(map[hospitalID] || [])];
  const dayISO = startOfDay(date).toISOString();
  const idx = dates.findIndex((d) => sameDay(d, dayISO));
  let blocked;
  if (idx >= 0) {
    dates.splice(idx, 1);
    blocked = false;
  } else {
    dates.push(dayISO);
    blocked = true;
  }
  map[hospitalID] = dates;
  appStore.saveUnavailable(map);
  await afterMutation(() => sync.setUnavailable(hospitalID, date, blocked));
}

// ── Tokens ───────────────────────────────────────────────────────────

export function tokenRequestsForHospital(hospitalID, date) {
  return (appStore.tokens.requestedDays || []).filter((r) =>
    r.hospitalID === hospitalID && (!date || sameDay(r.date, date))
  );
}

export function canAcceptOnDay(date, hospitalID, doctorID) {
  const req = (appStore.tokens.requestedDays || []).find((r) =>
    r.doctorID === doctorID && r.hospitalID === hospitalID && sameDay(r.date, date)
  );
  if (!req) return false;
  return req.status === "approved" || req.status === "auto_approved";
}

export function requestStatusForDay(date, doctorID) {
  return (appStore.tokens.requestedDays || []).find((r) =>
    r.doctorID === doctorID && sameDay(r.date, date)
  ) || null;
}

export async function requestToken(date, hospitalID, hospitalName, specialty, doctor, shiftRate = null) {
  const tokens = { ...appStore.tokens };
  if (tokens.tokensRemaining <= 0) return { ok: false, error: "No tokens remaining today." };

  const day = startOfDay(date);
  if ((tokens.requestedDays || []).some((r) =>
    r.doctorID === doctor.id && sameDay(r.date, day)
  )) {
    return { ok: false, error: "You already requested this day." };
  }

  const policy = getPolicy(hospitalID);
  let status = "pending";
  let approvedAt = null;
  const roster = appStore.roster;
  const autoApproved = roster.find((d) => d.id === doctor.id)?.isAutoApproved;

  if (!policy.administratorApproveShifts && doctor.verificationStatus === "verified") {
    status = "auto_approved";
    approvedAt = new Date().toISOString();
  } else if (autoApproved) {
    status = "auto_approved";
    approvedAt = new Date().toISOString();
  }

  const { rate } = getProposedRate(hospitalID, specialty, day);
  const req = {
    id: uuid(),
    doctorID: doctor.id,
    doctorName: `${doctor.firstName} ${doctor.lastName}`,
    credential: doctor.credential,
    hospitalID,
    hospitalName,
    date: day.toISOString(),
    specialty,
    status,
    requestedAt: new Date().toISOString(),
    approvedAt,
    shiftRate: shiftRate ?? rate
  };

  if (status !== "auto_approved") tokens.tokensRemaining -= 1;
  tokens.requestedDays = [...(tokens.requestedDays || []), req];
  appStore.saveTokens(tokens);

  await afterMutation(() => sync.submitTokenRequest(req));
  return { ok: true, request: req };
}

export async function approveToken(id) {
  const tokens = { ...appStore.tokens };
  const idx = (tokens.requestedDays || []).findIndex((r) => r.id === id);
  if (idx < 0) return;
  tokens.requestedDays[idx].status = "approved";
  tokens.requestedDays[idx].approvedAt = new Date().toISOString();
  appStore.saveTokens(tokens);
  await afterMutation(() => sync.updateTokenStatus(id, "approved"));
}

export async function denyToken(id) {
  const tokens = { ...appStore.tokens };
  const idx = (tokens.requestedDays || []).findIndex((r) => r.id === id);
  if (idx < 0) return;
  if (tokens.requestedDays[idx].status === "pending") {
    tokens.tokensRemaining = Math.min(tokens.tokensRemaining + 1, tokens.dailyLimit);
  }
  tokens.requestedDays[idx].status = "denied";
  appStore.saveTokens(tokens);
  await afterMutation(() => sync.updateTokenStatus(id, "denied"));
}

export async function cancelTokenRequest(id) {
  const tokens = { ...appStore.tokens };
  const idx = (tokens.requestedDays || []).findIndex((r) => r.id === id);
  if (idx < 0) return { ok: false, error: "Request not found." };
  const req = tokens.requestedDays[idx];
  if (req.status !== "pending") return { ok: false, error: "Only pending requests can be canceled." };
  tokens.requestedDays.splice(idx, 1);
  tokens.tokensRemaining = Math.min(tokens.tokensRemaining + 1, tokens.dailyLimit);
  appStore.saveTokens(tokens);
  await afterMutation(() => sync.updateTokenStatus(id, "canceled").catch(() => {}));
  return { ok: true };
}

// ── Assignments ──────────────────────────────────────────────────────

export async function acceptShift(shift, doctor) {
  if (isShiftFilled(shift.id)) return { ok: false, error: "Shift already filled." };
  if (!canAcceptOnDay(shift.start, shift.hospitalID, doctor.id)) {
    return { ok: false, error: "Request and get approval for this day before accepting." };
  }

  const assignment = {
    id: uuid(),
    shiftID: shift.id,
    shift,
    doctorID: doctor.id,
    doctorName: `${doctor.firstName} ${doctor.lastName}`,
    status: "scheduled",
    assignedAt: new Date().toISOString()
  };

  appStore.saveAssignments([...appStore.assignments, assignment]);


  await afterMutation(async () => {
    await sync.createAssignment(shift.id, doctor.id, {
      hospitalID: shift.hospitalID,
      shiftDate: shift.start,
      shift
    });
    await sync.upsertShift(shift);
  });

  return { ok: true, assignment };
}

export async function cancelShift(assignment) {
  const policy = getPolicy(assignment.shift.hospitalID);
  const preview = previewPenalty(
    "cancel",
    policy,
    assignment.shift.start,
    currentRate(assignment.shift)
  );
  if (!preview.allowed) return { ok: false, error: preview.blockedReason };

  let penalty = preview.penaltyAmount;
  await afterMutation(async () => {
    const res = await sync.cancelAssignment(assignment.shiftID, assignment.doctorID);
    if (res?.penalty != null) penalty = res.penalty;
  });

  const list = appStore.assignments.map((a) =>
    a.id === assignment.id ? { ...a, status: "canceled" } : a
  );
  appStore.saveAssignments(list);

  recordPenalty({
    doctorID: assignment.doctorID,
    hospitalID: assignment.shift.hospitalID,
    shiftID: assignment.shiftID,
    type: "cancel",
    amount: penalty
  });

  return { ok: true, penalty };
}

export async function requestTrade(assignment, toDoctor) {
  const policy = getPolicy(assignment.shift.hospitalID);
  const preview = previewPenalty("trade", policy, assignment.shift.start);
  if (!preview.allowed) return { ok: false, error: preview.blockedReason };

  const list = appStore.assignments.map((a) =>
    a.id === assignment.id ? { ...a, status: "traded_pending" } : a
  );
  appStore.saveAssignments(list);

  const trade = {
    id: uuid(),
    shiftID: assignment.shiftID,
    fromDoctorID: assignment.doctorID,
    toDoctorID: toDoctor.id,
    toDoctorName: toDoctor.name,
    state: "pending",
    createdAt: new Date().toISOString()
  };

  const trades = appStore.trades;
  trades.outgoing = [...(trades.outgoing || []), trade];
  appStore.saveTrades(trades);

  await afterMutation(() =>
    sync.requestTrade(assignment.shiftID, assignment.doctorID, toDoctor.id)
  );

  return { ok: true, trade, preview };
}

export async function respondTrade(trade, accept) {
  const policy = getPolicy(
    appStore.assignments.find((a) => a.shiftID === trade.shiftID)?.shift?.hospitalID
  );
  let penalty = 0;
  if (accept) {
    const shift = appStore.assignments.find((a) => a.shiftID === trade.shiftID)?.shift;
    if (shift) {
      penalty = previewPenalty("trade", policy, shift.start).penaltyAmount;
    }
  }

  await afterMutation(() => sync.respondTrade(trade.id, accept));

  let list = appStore.assignments;
  if (accept) {
    list = list.map((a) =>
      a.shiftID === trade.shiftID
        ? { ...a, doctorID: trade.toDoctorID, doctorName: trade.toDoctorName || a.doctorName, status: "scheduled" }
        : a
    );
    if (penalty > 0) {
      recordPenalty({
        doctorID: trade.fromDoctorID,
        hospitalID: list.find((a) => a.shiftID === trade.shiftID)?.shift?.hospitalID,
        shiftID: trade.shiftID,
        type: "trade",
        amount: penalty
      });
    }
  } else {
    list = list.map((a) =>
      a.shiftID === trade.shiftID && a.status === "traded_pending"
        ? { ...a, status: "scheduled" }
        : a
    );
  }
  appStore.saveAssignments(list);

  const trades = appStore.trades;
  trades.incoming = (trades.incoming || []).filter((t) => t.id !== trade.id);
  appStore.saveTrades(trades);
  return { ok: true, penalty };
}

/** Counter an incoming trade by changing the compensation asked. */
export async function counterTrade(trade, compensationAmount) {
  const amount = Math.max(0, Math.min(1000, Math.round(Number(compensationAmount) || 0)));
  const trades = appStore.trades;
  const incoming = (trades.incoming || []).map((t) =>
    t.id === trade.id
      ? {
          ...t,
          compensationAmount: amount,
          state: "countered",
          counteredAt: new Date().toISOString()
        }
      : t
  );
  // After countering, it leaves the inbox — the other party sees the revised ask.
  trades.incoming = incoming.filter((t) => t.id !== trade.id);
  trades.outgoing = [
    ...(trades.outgoing || []),
    {
      ...trade,
      compensationAmount: amount,
      state: "countered",
      counteredAt: new Date().toISOString(),
      fromDoctorID: trade.toDoctorID,
      toDoctorID: trade.fromDoctorID,
      fromDoctorName: trade.toDoctorName,
      toDoctorName: trade.fromDoctorName
    }
  ];
  appStore.saveTrades(trades);
  await afterMutation(() => sync.respondTrade?.(trade.id, false));
  return { ok: true, amount };
}

function recordPenalty(entry) {
  const ledger = [...appStore.penaltyLedger, {
    id: uuid(),
    ...entry,
    createdAt: new Date().toISOString()
  }];
  appStore.savePenaltyLedger(ledger);
}

export function penaltyPreview(action, assignment) {
  const policy = getPolicy(assignment.shift.hospitalID);
  return previewPenalty(action, policy, assignment.shift.start, currentRate(assignment.shift));
}

export function earningsSummary() {
  const active = activeAssignments();
  const projected = active.reduce((sum, a) => sum + currentRate(a.shift), 0);
  const completed = appStore.assignments.filter((a) =>
    a.status === "scheduled" && isPastShift(a.shift)
  );
  const earned = completed.reduce((sum, a) => sum + currentRate(a.shift), 0);
  const history = appStore.assignments.filter((a) =>
    a.status === "canceled" || a.status === "traded_complete" || isPastShift(a.shift)
  );
  return {
    projected,
    earned: Math.round(earned),
    avgPerShift: completed.length ? Math.round(earned / completed.length) : 0,
    completedCount: completed.length,
    activeCount: active.length,
    history,
    completed
  };
}

export function getRateBreakdown(specialty, date, hospitalID) {
  const day = startOfDay(date);
  const obs = pricingObservables(specialty, day, hospitalID);
  const granularity = getPolicy(hospitalID).granularity;
  return rateBreakdown(specialty, day.toISOString(), hospitalID, obs, granularity);
}

export function startPeriodicSync(intervalMs = 20000) {
  if (typeof window === "undefined") return () => {};
  if (window.__oncallSyncTimer) clearInterval(window.__oncallSyncTimer);
  window.__oncallSyncTimer = setInterval(() => {
    if (isConfigured() && appStore.session) syncEverything().catch(() => {});
  }, intervalMs);
  return () => clearInterval(window.__oncallSyncTimer);
}

// ── Roster ─────────────────────────────────────────────────────────

export function registerDoctorOnRoster(profile) {
  const summary = {
    id: profile.id,
    name: `${profile.firstName} ${profile.lastName}`,
    credential: profile.credential,
    specialty: profile.specialties?.[0] || "Internal Medicine",
    npi: profile.npi,
    isAutoApproved: false,
    verificationStatus: profile.verificationStatus
  };
  const roster = [...appStore.roster];
  const idx = roster.findIndex((d) => d.id === profile.id);
  if (idx >= 0) roster[idx] = summary;
  else roster.push(summary);
  appStore.saveRoster(roster);
}

export async function toggleRosterAutoApprove(doctorId) {
  const roster = appStore.roster.map((d) =>
    d.id === doctorId ? { ...d, isAutoApproved: !d.isAutoApproved } : d
  );
  appStore.saveRoster(roster);
  const doc = roster.find((d) => d.id === doctorId);
  if (doc?.isAutoApproved) autoApprovePendingTokens(doctorId);
  const hospitalId = appStore.hospitalProfile?.id;
  if (hospitalId) {
    await afterMutation(() => sync.upsertRosterLink(hospitalId, doctorId, doc?.isAutoApproved));
  }
}

function autoApprovePendingTokens(doctorId) {
  const tokens = { ...appStore.tokens };
  let changed = false;
  tokens.requestedDays = (tokens.requestedDays || []).map((r) => {
    if (r.doctorID === doctorId && r.status === "pending") {
      changed = true;
      tokens.tokensRemaining = Math.min(tokens.tokensRemaining + 1, tokens.dailyLimit);
      return { ...r, status: "auto_approved", approvedAt: new Date().toISOString() };
    }
    return r;
  });
  if (changed) appStore.saveTokens(tokens);
}

export function eligibleTradePartners(specialty, excludingDoctorId) {
  return appStore.roster.filter((d) =>
    d.id !== excludingDoctorId &&
    d.specialty === specialty &&
    d.verificationStatus === "verified"
  );
}

const MOCK_DOCTOR_IDS = [
  "E1000001-0000-0000-0000-000000000000",
  "E2000001-0000-0000-0000-000000000000",
  "E3000001-0000-0000-0000-000000000000",
  "E4000001-0000-0000-0000-000000000000",
  "E5000001-0000-0000-0000-000000000000",
  "E6000001-0000-0000-0000-000000000000",
  "E7000001-0000-0000-0000-000000000000"
];

export function seedMockDoctors() {
  if (MOCK_DOCTOR_IDS.every((id) => appStore.roster.some((d) => d.id === id))) return;
  const mocks = [
    { id: MOCK_DOCTOR_IDS[0], name: "Dr. James Carter", credential: "MD", specialty: "Cardiology", npi: "1932756480", isAutoApproved: true, verificationStatus: "verified" },
    { id: MOCK_DOCTOR_IDS[1], name: "Dr. Lisa Chen", credential: "MD", specialty: "Cardiology", npi: "1073648291", isAutoApproved: true, verificationStatus: "verified" },
    { id: MOCK_DOCTOR_IDS[2], name: "Dr. Maria Santos", credential: "MD", specialty: "Emergency Medicine", npi: "1548372916", isAutoApproved: true, verificationStatus: "verified" },
    { id: MOCK_DOCTOR_IDS[3], name: "Dr. David Park", credential: "DO", specialty: "Orthopedics", npi: "1629384750", isAutoApproved: true, verificationStatus: "verified" },
    { id: MOCK_DOCTOR_IDS[4], name: "Dr. Sarah Kim", credential: "MD", specialty: "Surgery", npi: "1807263549", isAutoApproved: true, verificationStatus: "verified" },
    { id: MOCK_DOCTOR_IDS[5], name: "Dr. Robert Nguyen", credential: "MD", specialty: "Internal Medicine", npi: "1394827163", isAutoApproved: true, verificationStatus: "verified" },
    { id: MOCK_DOCTOR_IDS[6], name: "Dr. Emily Walsh", credential: "MD", specialty: "Emergency Medicine", npi: "1265839407", isAutoApproved: true, verificationStatus: "verified" }
  ];
  const roster = [...appStore.roster];
  for (const m of mocks) {
    if (!roster.some((d) => d.id === m.id)) roster.push(m);
  }
  appStore.saveRoster(roster);
}

// ── Preferences ──────────────────────────────────────────────────────

export function savePreferences(prefs) {
  appStore.saveDoctorPrefs({ ...appStore.doctorPrefs, ...prefs });
}

/** @deprecated use syncEverything */
export async function syncShiftsFromSupabase(hospitalID) {
  await syncEverything();
}

export { algorithmRate, computeRate, rateBreakdown, groupPricingComponents, previewPenalty, defaultPolicy, bracketLabel };
