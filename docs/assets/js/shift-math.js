import { startOfDay } from "./brand.js";

const hourBreakpoints = [[72,1],[48,1.15],[24,1.35],[12,1.6],[6,1.85],[2,2.2],[0,2.2]];
const dayBreakpoints = [[30,1],[14,1.1],[7,1.2],[3,1.35],[1,1.6],[0,2]];

function interpolate(value, breakpoints) {
  if (value <= 0) return breakpoints[breakpoints.length - 1][1];
  for (let i = 0; i < breakpoints.length - 1; i++) {
    const [h1, m1] = breakpoints[i];
    const [h2, m2] = breakpoints[i + 1];
    if (value <= h1 && value >= h2) {
      const t = (h1 - value) / (h1 - h2);
      return m1 + (m2 - m1) * t;
    }
  }
  return breakpoints[0][1];
}

export function hoursUntilStart(shift) {
  return Math.max(0, (new Date(shift.start).getTime() - Date.now()) / 3600000);
}

export function isPastShift(shift) {
  const end = new Date(shift.start);
  end.setHours(end.getHours() + (shift.durationHours || 24));
  return Date.now() >= end.getTime();
}

export function currentRate(shift) {
  const hours = hoursUntilStart(shift);
  const perDay = shift.rateUnit !== "per hour";
  const floor = Number(shift.rateFloor) || 0;
  if (shift.escalationMode?.type === "flat") {
    return Math.max(floor, Number(shift.escalationMode.rate) || floor);
  }
  const mult = perDay
    ? interpolate(hours / 24, dayBreakpoints)
    : interpolate(hours, hourBreakpoints);
  return floor * mult;
}

export function urgencyTier(shift) {
  if (isPastShift(shift)) return "past";
  const hours = hoursUntilStart(shift);
  const perDay = shift.rateUnit !== "per hour";
  if (perDay) {
    const days = hours / 24;
    if (days < 1) return "critical";
    if (days < 3) return "high";
    if (days < 7) return "moderate";
    return "low";
  }
  if (hours < 12) return "critical";
  if (hours < 24) return "high";
  if (hours < 48) return "moderate";
  return "low";
}

export function urgencyColor(tier) {
  switch (tier) {
    case "critical": return "#F87171";
    case "high": return "#FB923C";
    case "moderate": return "#FBBF24";
    case "low": return "#4F8EF7";
    default: return "rgba(255,255,255,0.35)";
  }
}

export function urgencyIcon(tier) {
  switch (tier) {
    case "critical": return "⚡";
    case "high": return "🔥";
    case "moderate": return "⏱";
    case "low": return "◦";
    default: return "·";
  }
}

export function normalizeShift(raw) {
  return {
    id: raw.id,
    hospitalID: raw.hospitalID || raw.hospital_id,
    hospital: raw.hospital || raw.hospital_name,
    specialty: raw.specialty,
    start: raw.start || raw.date,
    durationHours: raw.durationHours ?? raw.duration_hours ?? 24,
    rateFloor: Number(raw.rateFloor ?? raw.rate_floor ?? 0),
    rateUnit: raw.rateUnit || (raw.rate_unit === "per_hour" ? "per hour" : "per day"),
    escalationMode: raw.escalationMode || { type: "automatic" },
    usesAlgorithmPricing: raw.usesAlgorithmPricing ?? true
  };
}

export function shiftDate(shift) {
  return startOfDay(new Date(shift.start));
}
