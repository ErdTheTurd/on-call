/** On-call pricing engine + US holiday calendar (ported from iOS OnCallPricingEngine). */

const SPECIALTY_DEMAND = {
  "Emergency Medicine": 1.30,
  "Anesthesiology": 1.35,
  "Surgery": 1.30,
  "Orthopedics": 1.28,
  "Ob/Gyn": 1.25,
  "ENT": 1.22,
  "Neurology": 1.25,
  "Cardiology": 1.25,
  "Radiology": 1.20,
  "Psychiatry": 1.20,
  "Internal Medicine": 1.10,
  "Hospitalist": 1.05,
  "Pediatrics": 1.10
};

/** JS getDay(): 0=Sun … 6=Sat (maps from iOS Calendar weekday 1=Sun … 7=Sat). */
const DAY_OF_WEEK = { 0: 1.15, 1: 1.00, 2: 1.00, 3: 1.00, 4: 1.00, 5: 1.05, 6: 1.20 };

const PREMIUM_HOLIDAYS = [
  { name: "Christmas Day", premium: 0.10 },
  { name: "Christmas Eve", premium: 0.07 },
  { name: "Thanksgiving", premium: 0.10 },
  { name: "Easter Sunday", premium: 0.10 },
  { name: "New Year's Day", premium: 0.07 },
  { name: "New Year's Eve", premium: 0.05 },
  { name: "Independence Day", premium: 0.10 },
  { name: "Memorial Day", premium: 0.05 },
  { name: "Labor Day", premium: 0.05 }
];

function holidayNamed(name) {
  return PREMIUM_HOLIDAYS.find((h) => h.name === name) || null;
}

function isEaster(month, day, year) {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const easterMonth = Math.floor((h + l - 7 * m + 114) / 31);
  const easterDay = ((h + l - 7 * m + 114) % 31) + 1;
  return month === easterMonth && day === easterDay;
}

function isThanksgiving(date) {
  return date.getMonth() === 10 && date.getDay() === 4 &&
    Math.ceil(date.getDate() / 7) === 4;
}

function isMemorialDay(date) {
  if (date.getMonth() !== 4 || date.getDay() !== 1) return false;
  const next = new Date(date);
  next.setDate(next.getDate() + 7);
  return next.getMonth() === 5;
}

function isLaborDay(date) {
  return date.getMonth() === 8 && date.getDay() === 1 && date.getDate() <= 7;
}

export function holidayOn(dateISO) {
  const d = new Date(dateISO);
  const month = d.getMonth() + 1;
  const day = d.getDate();
  const year = d.getFullYear();

  switch (`${month}-${day}`) {
    case "12-25": return holidayNamed("Christmas Day");
    case "12-24": return holidayNamed("Christmas Eve");
    case "12-31": return holidayNamed("New Year's Eve");
    case "1-1": return holidayNamed("New Year's Day");
    case "7-4": return holidayNamed("Independence Day");
    default: break;
  }
  if (isEaster(month, day, year)) return holidayNamed("Easter Sunday");
  if (isThanksgiving(d)) return holidayNamed("Thanksgiving");
  if (isMemorialDay(d)) return holidayNamed("Memorial Day");
  if (isLaborDay(d)) return holidayNamed("Labor Day");
  return null;
}

export function holidayPremiumMultiplier(dateISO) {
  return 1.0 + (holidayOn(dateISO)?.premium ?? 0);
}

export const NEUTRAL_OBSERVABLES = {
  openShiftCount: 0,
  availableDoctorCount: 0,
  hospitalWideOpenShifts: 0,
  hospitalWideRosterSize: 0,
  recentFillRate: null,
  daysUntilShift: null,
  pendingTokenRequests: 0,
  autoApprovedDoctorCount: 0,
  adjacentUnfilledDays: 0,
  avgFillHours: null,
  pendingTradeCount: 0,
  recentCancelCount: 0,
  sampleSize: 0
};

function scarcity(openShifts, availableDoctors) {
  const demand = Math.max(0, openShifts) + 1;
  const supply = Math.max(0, availableDoctors) + 1;
  const raw = Math.pow(demand / supply, 0.35);
  return Math.min(1.30, Math.max(0.85, raw));
}

function fillPerformance(rate) {
  if (rate == null) return 1.0;
  if (rate < 0.40) return 1.18;
  if (rate < 0.60) return 1.10;
  if (rate < 0.80) return 1.02;
  if (rate < 0.95) return 0.98;
  return 0.94;
}

function leadTime(days) {
  if (days == null) return 1.0;
  if (days < 1) return 1.25;
  if (days < 3) return 1.15;
  if (days < 7) return 1.06;
  if (days < 14) return 1.00;
  return 0.97;
}

function avgFillTimeIndex(hours) {
  if (hours == null) return 1.0;
  if (hours > 72) return 1.12;
  if (hours > 48) return 1.06;
  if (hours < 12) return 0.97;
  return 1.0;
}

function tradeFrictionIndex(pending) {
  return Math.min(1.10, 1.0 + Math.max(0, pending) * 0.02);
}

function cancelRiskIndex(recent) {
  return Math.min(1.12, 1.0 + Math.max(0, recent) * 0.015);
}

function quantize(value, granularity) {
  const step = granularity === "hour" ? 5 : 25;
  return Math.round(value / step) * step;
}

function fmtMult(mult) {
  return `×${mult.toFixed(3)}`;
}

/**
 * Full pricing compute — mirrors iOS OnCallPricingEngine.compute.
 * Returns floor, confidence, and categorized PricingFactorComponent list.
 */
export function computeRate(specialty, dateISO, options = {}) {
  const {
    hospitalID,
    granularity = "day",
    baseMarketRate = 120,
    durationHours = 24,
    observables = NEUTRAL_OBSERVABLES,
    disabledFactorIDs = [],
    factorOverrides = {}
  } = options;
  const disabled = new Set(disabledFactorIDs);

  const day = new Date(dateISO);
  day.setHours(0, 0, 0, 0);
  const weekday = day.getDay(); // 0=Sun
  const month = day.getMonth() + 1;
  const dayOfMonth = day.getDate();
  const daysInMonth = new Date(day.getFullYear(), day.getMonth() + 1, 0).getDate();
  const quarter = Math.floor((month - 1) / 3) + 1;
  const unit = granularity === "day" ? "/day" : "/hr";

  const components = [];
  const factor = (id, category, label, mult, weight = 1.0, display = null) => {
    let effective = mult;
    let effectiveWeight = weight;
    if (disabled.has(id) && id !== "base" && id !== "confidence" && id !== "prior") {
      effective = 1.0;
      effectiveWeight = 0;
    } else if (factorOverrides[id] != null && Number.isFinite(Number(factorOverrides[id]))) {
      effective = Number(factorOverrides[id]);
    }
    components.push({
      id,
      category,
      label,
      displayValue: display ?? fmtMult(effective),
      multiplier: effective,
      weight: effectiveWeight,
      impact: (effective - 1.0) * effectiveWeight,
      enabled: !disabled.has(id)
    });
  };

  const base = granularity === "day" ? baseMarketRate * 10 : baseMarketRate;
  factor("base", "Context", "Base market rate", 1.0, 0, `$${Math.round(base)}${unit}`);

  const specialtyMult = SPECIALTY_DEMAND[specialty] ?? 1.0;
  factor("specialty", "Context", "Specialty demand index", specialtyMult, 1.0);

  const dowMult = DAY_OF_WEEK[weekday] ?? 1.0;
  factor("dow", "Context", "Day-of-week index", dowMult, 1.0);

  let seasonMult = 1.0;
  if ([11, 12, 1, 2].includes(month)) seasonMult = 1.12;
  else if ([6, 7, 8].includes(month)) seasonMult = 1.08;
  factor("season", "Context", "Seasonal index", seasonMult, 1.0);

  const holiday = holidayOn(day.toISOString());
  const holidayMult = 1.0 + (holiday?.premium ?? 0);
  if (holidayMult > 1.001) {
    factor(
      "holiday",
      "Context",
      `${holiday?.name ?? "Holiday"} premium`,
      holidayMult,
      1.0,
      `+${Math.round((holidayMult - 1) * 100)}%`
    );
  }

  const quarterMult = { 1: 1.06, 2: 1.00, 3: 1.04, 4: 1.08 }[quarter] ?? 1.0;
  factor("quarter", "Context", "Quarter index", quarterMult, 0.85);

  const fromEnd = daysInMonth - dayOfMonth;
  let monthPosMult = 1.0;
  if (fromEnd <= 2) monthPosMult = 1.05;
  else if (dayOfMonth <= 3) monthPosMult = 1.03;
  factor("monthPos", "Context", "Month-position index", monthPosMult, 0.75);

  let weekendAdjMult = 1.0;
  if (weekday === 5) weekendAdjMult = 1.04;      // Friday
  else if (weekday === 0) weekendAdjMult = 1.06; // Sunday
  else if (weekday === 1) weekendAdjMult = 1.03; // Monday
  factor("weekendAdj", "Context", "Weekend adjacency", weekendAdjMult, 0.9);

  let durationMult = 1.0;
  if (durationHours <= 8) durationMult = 1.08;
  else if (durationHours >= 24) durationMult = 0.96;
  factor("duration", "Context", "Shift duration", durationMult, 0.8);

  const o = { ...NEUTRAL_OBSERVABLES, ...observables };
  const scarcityMult = scarcity(o.openShiftCount, o.availableDoctorCount);
  factor("scarcity", "Market", "Supply / demand scarcity", scarcityMult, 1.0);

  const fillMult = fillPerformance(o.recentFillRate);
  factor("fillHist", "Market", "Historical fill rate", fillMult, 0.95);

  const leadMult = leadTime(o.daysUntilShift);
  factor("leadTime", "Market", "Lead-time urgency", leadMult, 1.0);

  const loadRatio = Math.max(0, o.hospitalWideOpenShifts) / Math.max(1, o.hospitalWideRosterSize);
  const loadMult = Math.min(1.20, Math.max(0.92, 1.0 + loadRatio * 0.08));
  factor("hospLoad", "Market", "Hospital-wide open load", loadMult, 0.9);

  let tokenMult = 1.0;
  if (o.pendingTokenRequests === 1) tokenMult = 1.03;
  else if (o.pendingTokenRequests === 2) tokenMult = 1.06;
  else if (o.pendingTokenRequests > 2) tokenMult = Math.min(1.15, 1.0 + o.pendingTokenRequests * 0.04);
  factor("tokens", "Market", "Pending token demand", tokenMult, 0.85);

  const depth = Math.max(0, o.availableDoctorCount) / Math.max(1, o.openShiftCount);
  let depthMult = 1.10;
  if (depth >= 3) depthMult = 0.94;
  else if (depth >= 1.5) depthMult = 0.98;
  else if (depth >= 0.75) depthMult = 1.02;
  factor("rosterDepth", "Market", "Roster depth ratio", depthMult, 0.8);

  const autoRoster = Math.max(1, o.availableDoctorCount || o.hospitalWideRosterSize || 0);
  const autoRatio = autoRoster > 0 ? o.autoApprovedDoctorCount / autoRoster : 0;
  const autoMult = Math.max(0.96, 1.0 - autoRatio * 0.06);
  factor("autoPipe", "Market", "Auto-approve pipeline", autoMult, 0.7);

  let adjMult = 1.0;
  if (o.adjacentUnfilledDays === 1) adjMult = 1.04;
  else if (o.adjacentUnfilledDays === 2) adjMult = 1.07;
  else if (o.adjacentUnfilledDays > 2) adjMult = Math.min(1.14, 1.0 + o.adjacentUnfilledDays * 0.035);
  factor("adjGap", "Market", "Adjacent coverage gaps", adjMult, 0.85);

  const fillTimeMult = avgFillTimeIndex(o.avgFillHours);
  factor("fillTime", "Market", "Avg time-to-fill", fillTimeMult, 0.75);

  const tradeMult = tradeFrictionIndex(o.pendingTradeCount);
  factor("trades", "Market", "Trade friction", tradeMult, 0.65);

  const cancelMult = cancelRiskIndex(o.recentCancelCount);
  factor("cancelRisk", "Market", "Cancellation risk", cancelMult, 0.7);

  const isWeekend = weekday === 0 || weekday === 6;
  const sxw = isWeekend ? 1.0 + Math.max(0, specialtyMult - 1.0) * 0.35 : 1.0;
  factor("sxw", "Interaction", "Specialty × weekend", sxw, 0.9);

  if (holidayMult > 1.001) {
    const h = holidayMult - 1.0;
    const s = Math.max(0, scarcityMult - 1.0);
    const hxs = 1.0 + h * s * 0.5;
    if (hxs > 1.001) factor("hxs", "Interaction", "Holiday × scarcity", hxs, 0.95);
  }

  const l = Math.max(0, leadMult - 1.0);
  const s2 = Math.max(0, scarcityMult - 1.0);
  factor("lxs", "Interaction", "Lead-time × scarcity", 1.0 + l * s2 * 0.4, 0.9);

  const confidence = Math.min(0.95, Math.max(0.35, 1.0 - Math.exp(-o.sampleSize / 12.0)));
  factor("confidence", "Meta", "Data confidence", 1.0, 0, `${Math.round(confidence * 100)}%`);

  const priorFloor = quantize(base * specialtyMult * 0.98, granularity);
  factor("prior", "Meta", "Prior anchor rate", 1.0, 0, `$${Math.round(priorFloor)}`);

  const priced = components.filter((c) => c.weight > 0 && c.id !== "base");
  let weightedLogSum = 0;
  let totalWeight = 0;
  for (const c of priced) {
    weightedLogSum += Math.log(Math.max(0.01, c.multiplier)) * c.weight;
    totalWeight += c.weight;
  }
  const meshMultiplier = Math.exp(weightedLogSum / Math.max(0.001, totalWeight));
  let rawFloor = base * meshMultiplier;
  rawFloor = confidence * rawFloor + (1.0 - confidence) * priorFloor;
  const floor = quantize(rawFloor, granularity);

  return {
    floor,
    peakRate: granularity === "day" ? floor * 2.0 : floor * 2.2,
    confidence,
    priorFloor,
    holidayName: holiday?.name ?? null,
    granularity,
    hospitalID,
    components,
    factorCount: components.length,
    variableCount: components.length,
    base
  };
}

/** Group components like iOS PricingFactorBreakdownView. */
export function groupPricingComponents(components = []) {
  const filtered = components.filter((c) => c.weight > 0 || c.id === "base");
  const order = ["Context", "Market", "Interaction", "Meta"];
  const map = {};
  for (const c of filtered) {
    (map[c.category] ||= []).push(c);
  }
  return order
    .filter((cat) => map[cat]?.length)
    .map((cat) => [cat, map[cat]]);
}

export function algorithmRate(specialty, dateISO, hospitalID, observables, granularity = "day", prefs = null) {
  return computeRate(specialty, dateISO, {
    hospitalID,
    observables,
    granularity,
    disabledFactorIDs: prefs?.disabled || [],
    factorOverrides: prefs?.overrides || {}
  }).floor;
}

export function rateBreakdown(specialty, dateISO, hospitalID, observables, granularity = "day", prefs = null) {
  return computeRate(specialty, dateISO, {
    hospitalID,
    observables,
    granularity,
    disabledFactorIDs: prefs?.disabled || [],
    factorOverrides: prefs?.overrides || {}
  });
}
