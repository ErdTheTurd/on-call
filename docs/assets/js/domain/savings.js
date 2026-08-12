/**
 * Hospital savings telemetry.
 *
 * Every dollar we claim a hospital saved is written as one auditable event, so
 * the hospital's own card and the admin dashboard read the same number instead
 * of each re-deriving it. Two sources of savings today:
 *
 *   penalty_cancel / penalty_trade — money recovered when a doctor drops late
 *   rate_savings                   — escalation avoided by filling early: a shift
 *                                    left open climbs to a ceiling multiplier, so
 *                                    filling at today's rate is a real avoided cost
 */
import { getSupabase, isConfigured } from "../supabase-client.js";
import { currentRate, hoursUntilStart } from "../shift-math.js";

const TABLE = "hospital_savings_events";
const LOCAL_KEY = "hospital_savings_events_v1";

/** Worst case the escalator can reach — see `dayBreakpoints` / `hourBreakpoints`. */
const CEILING_MULTIPLIER = { day: 2.0, hour: 2.2 };

export const SAVINGS_KINDS = {
  penalty_cancel: "Late cancellation recovered",
  penalty_trade: "Late trade recovered",
  rate_savings: "Escalation avoided"
};

function readLocal() {
  try {
    const raw = JSON.parse(localStorage.getItem(LOCAL_KEY) || "[]");
    return Array.isArray(raw) ? raw : [];
  } catch {
    return [];
  }
}

function writeLocal(events) {
  localStorage.setItem(LOCAL_KEY, JSON.stringify(events.slice(-500)));
}

/**
 * Escalation avoided by filling now instead of letting the shift run to the wire.
 * Flat-rate shifts never escalate, so they save nothing by this measure.
 */
export function rateSavingsForFill(shift) {
  if (!shift) return 0;
  if (shift.escalationMode?.type === "flat") return 0;

  const perDay = shift.rateUnit !== "per hour";
  const floor = Number(shift.rateFloor) || 0;
  if (floor <= 0) return 0;

  const ceiling = floor * (perDay ? CEILING_MULTIPLIER.day : CEILING_MULTIPLIER.hour);
  const locked = currentRate(shift);
  const perUnit = Math.max(0, ceiling - locked);
  const units = perDay ? 1 : (shift.durationHours || 8);
  return Math.round(perUnit * units);
}

/** Deterministic so a retry, a second device, or a re-render can't double count. */
function eventKey(kind, shiftID, actorID) {
  return `${kind}:${shiftID || "none"}:${actorID || "anon"}`;
}

/**
 * Records one savings event locally, then mirrors it to Supabase.
 * Local write always succeeds so the hospital card works offline.
 */
export async function recordSavingsEvent({
  hospitalID,
  hospitalName = null,
  shiftID = null,
  specialty = null,
  kind,
  amount,
  actorID = null,
  metadata = {}
}) {
  const value = Math.max(0, Math.round(Number(amount) || 0));
  if (!hospitalID || !SAVINGS_KINDS[kind] || value <= 0) return { ok: false, skipped: true };
  // Sample data must never reach the real savings ledger.
  if (localStorage.getItem("oncall_demo_mode") === "1") return { ok: true, demo: true };

  const key = eventKey(kind, shiftID, actorID);
  const event = {
    event_key: key,
    hospital_id: hospitalID,
    hospital_name: hospitalName,
    shift_id: shiftID,
    specialty,
    kind,
    amount: value,
    occurred_at: new Date().toISOString(),
    source: "web",
    metadata
  };

  const existing = readLocal();
  if (!existing.some((e) => e.event_key === key)) {
    writeLocal([...existing, event]);
  }

  if (!isConfigured()) return { ok: true, offline: true };

  try {
    const supabase = getSupabase();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return { ok: true, offline: true };
    const { error } = await supabase
      .from(TABLE)
      .upsert({ ...event, created_by: user.id }, { onConflict: "event_key" });
    if (error) throw error;
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err?.message || "Could not report savings" };
  }
}

/** Locally cached events — what the hospital card renders from, synchronously. */
export function getSavingsEvents(hospitalID = null) {
  const events = readLocal();
  return hospitalID ? events.filter((e) => e.hospital_id === hospitalID) : events;
}

/**
 * Pulls this hospital's events (including ones doctors wrote) into the local
 * cache so the analytics card can render without awaiting a round trip.
 */
export async function refreshSavingsCache(hospitalID) {
  if (!hospitalID || !isConfigured()) return getSavingsEvents(hospitalID);
  const remote = await fetchSavingsEvents({ hospitalID });
  if (!remote.length) return getSavingsEvents(hospitalID);

  const merged = new Map();
  for (const event of [...readLocal(), ...remote]) {
    if (event?.event_key) merged.set(event.event_key, event);
  }
  const list = [...merged.values()].sort(
    (a, b) => new Date(a.occurred_at) - new Date(b.occurred_at)
  );
  writeLocal(list);
  return getSavingsEvents(hospitalID);
}

/** Savings rows this account is allowed to see (own hospital, or everything for admins). */
export async function fetchSavingsEvents({ hospitalID = null, limit = 2000 } = {}) {
  if (!isConfigured()) return readLocal();
  try {
    const supabase = getSupabase();
    let query = supabase
      .from(TABLE)
      .select("*")
      .order("occurred_at", { ascending: false })
      .limit(limit);
    if (hospitalID) query = query.eq("hospital_id", hospitalID);
    const { data, error } = await query;
    if (error) throw error;
    return data || [];
  } catch {
    return readLocal();
  }
}

function emptyTotals() {
  return { total: 0, penalties: 0, rateSavings: 0, events: 0 };
}

function addEvent(totals, event) {
  const amount = Number(event.amount) || 0;
  totals.total += amount;
  totals.events += 1;
  if (event.kind === "rate_savings") totals.rateSavings += amount;
  else totals.penalties += amount;
}

/** One hospital's savings, shaped for the hospital analytics card. */
export function summarizeSavings(events, { since = null } = {}) {
  const totals = emptyTotals();
  const bySpecialty = {};
  let earliest = null;

  for (const event of events) {
    const at = new Date(event.occurred_at || event.occurredAt || Date.now());
    if (since && at < since) continue;
    addEvent(totals, event);
    const sp = event.specialty || "General";
    bySpecialty[sp] = (bySpecialty[sp] || 0) + (Number(event.amount) || 0);
    if (!earliest || at < earliest) earliest = at;
  }

  const days = earliest
    ? Math.max(1, (Date.now() - earliest.getTime()) / 86400000)
    : 1;

  return {
    ...totals,
    perDay: totals.total / days,
    trackedSince: earliest,
    bySpecialty: Object.entries(bySpecialty).sort((a, b) => b[1] - a[1])
  };
}

/** Admin view: every hospital, ranked by total saved. */
export function groupSavingsByHospital(events) {
  const map = new Map();

  for (const event of events) {
    const id = event.hospital_id;
    if (!id) continue;
    if (!map.has(id)) {
      map.set(id, {
        hospitalID: id,
        hospitalName: event.hospital_name || "Unnamed hospital",
        lastAt: null,
        ...emptyTotals()
      });
    }
    const row = map.get(id);
    if (event.hospital_name) row.hospitalName = event.hospital_name;
    addEvent(row, event);
    const at = new Date(event.occurred_at);
    if (!row.lastAt || at > row.lastAt) row.lastAt = at;
  }

  return [...map.values()].sort((a, b) => b.total - a.total);
}

/** Hours of lead time a fill bought, for the event metadata trail. */
export function leadTimeHours(shift) {
  return Math.round(hoursUntilStart(shift));
}
