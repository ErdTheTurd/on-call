/**
 * Client-side algorithm variable toggles / overrides.
 * Mirrors iOS AlgorithmPresetStore for Alter Shifts parity.
 */

const STORAGE_KEY = "algo_factor_prefs_v1";

export const PRICING_VARIABLE_CATALOG = [
  { id: "specialty", category: "Context", label: "Specialty demand index" },
  { id: "dow", category: "Context", label: "Day-of-week index" },
  { id: "season", category: "Context", label: "Seasonal index" },
  { id: "holiday", category: "Context", label: "Holiday premium" },
  { id: "quarter", category: "Context", label: "Quarter index" },
  { id: "monthPos", category: "Context", label: "Month-position index" },
  { id: "weekendAdj", category: "Context", label: "Weekend adjacency" },
  { id: "duration", category: "Context", label: "Shift duration" },
  { id: "scarcity", category: "Market", label: "Supply / demand scarcity" },
  { id: "fillHist", category: "Market", label: "Historical fill rate" },
  { id: "leadTime", category: "Market", label: "Lead-time urgency" },
  { id: "hospLoad", category: "Market", label: "Hospital-wide open load" },
  { id: "tokens", category: "Market", label: "Pending token demand" },
  { id: "rosterDepth", category: "Market", label: "Roster depth ratio" },
  { id: "autoPipe", category: "Market", label: "Auto-approve pipeline" },
  { id: "adjGap", category: "Market", label: "Adjacent coverage gaps" },
  { id: "fillTime", category: "Market", label: "Avg time-to-fill" },
  { id: "trades", category: "Market", label: "Trade friction" },
  { id: "cancelRisk", category: "Market", label: "Cancellation risk" },
  { id: "sxw", category: "Interaction", label: "Specialty × weekend" },
  { id: "hxs", category: "Interaction", label: "Holiday × scarcity" },
  { id: "lxs", category: "Interaction", label: "Lead-time × scarcity" }
];

function readPrefs() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return { disabled: [], overrides: {} };
    const parsed = JSON.parse(raw);
    return {
      disabled: Array.isArray(parsed.disabled) ? parsed.disabled : [],
      overrides: parsed.overrides && typeof parsed.overrides === "object" ? parsed.overrides : {}
    };
  } catch {
    return { disabled: [], overrides: {} };
  }
}

function writePrefs(prefs) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs));
}

export function getAlgoPrefs() {
  return readPrefs();
}

export function isFactorEnabled(id) {
  return !readPrefs().disabled.includes(id);
}

export function setFactorEnabled(id, enabled) {
  const prefs = readPrefs();
  if (enabled) {
    prefs.disabled = prefs.disabled.filter((x) => x !== id);
  } else if (!prefs.disabled.includes(id)) {
    prefs.disabled.push(id);
    delete prefs.overrides[id];
  }
  writePrefs(prefs);
  return prefs;
}

export function setFactorOverride(id, value) {
  const prefs = readPrefs();
  const n = Number(value);
  if (!Number.isFinite(n)) return prefs;
  prefs.overrides[id] = Math.min(2, Math.max(0.1, n));
  prefs.disabled = prefs.disabled.filter((x) => x !== id);
  writePrefs(prefs);
  return prefs;
}

export function clearFactorOverride(id) {
  const prefs = readPrefs();
  delete prefs.overrides[id];
  writePrefs(prefs);
  return prefs;
}

export function groupedCatalog() {
  const order = ["Context", "Market", "Interaction"];
  const map = {};
  for (const item of PRICING_VARIABLE_CATALOG) {
    (map[item.category] ||= []).push(item);
  }
  return order.filter((c) => map[c]?.length).map((c) => [c, map[c]]);
}
