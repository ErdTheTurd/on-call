/** Scheduling policy + penalty calculator (ported from iOS SchedulingPolicy / PenaltyCalculator). */

export function defaultPolicy() {
  return {
    granularity: "day",
    administratorApproveShifts: false,
    cancellationPenaltyScale: [{ hoursBeforeStart: 24, penaltyPercent: 2.0 }],
    tradePenaltyScale: [
      { hoursBeforeStart: 24, penaltyPercent: 0.25 },
      { hoursBeforeStart: 72, penaltyPercent: 0.1 },
      { hoursBeforeStart: 99999, penaltyPercent: 0.0 }
    ],
    cancelWindowHours: 6,
    tradeWindowHours: 12,
    basePenaltyAmount: 250,
    tradePenaltiesEnabled: true,
    tradePenaltyAmount: 250,
    tradePenaltyHoursBeforeStart: 72,
    specialtyBaseRates: {},
    doctorBaseRates: {},
    // Daily request tokens. The default applies to the whole roster;
    // doctorTokenLimits holds per-doctor exceptions keyed by doctor id.
    defaultDailyTokens: 3,
    doctorTokenLimits: {}
  };
}

export function normalizeCancellationScale(scale) {
  const maxHours = 90 * 24;
  let clamped = (scale || []).map((b) => {
    let p = { ...b };
    if (p.penaltyPercent < 1.0) p.penaltyPercent = 1.0;
    if (p.penaltyPercent > 5.0) p.penaltyPercent = 5.0;
    if (p.hoursBeforeStart > maxHours) p.hoursBeforeStart = maxHours;
    if (p.hoursBeforeStart < 0) p.hoursBeforeStart = 0;
    return p;
  }).sort((a, b) => a.hoursBeforeStart - b.hoursBeforeStart);

  for (let i = 1; i < clamped.length; i++) {
    if (clamped[i].hoursBeforeStart < clamped[i - 1].hoursBeforeStart) {
      clamped[i].hoursBeforeStart = clamped[i - 1].hoursBeforeStart;
    }
  }
  return clamped.length ? clamped : defaultPolicy().cancellationPenaltyScale;
}

function hoursUntil(startISO, now = new Date()) {
  return Math.max(0, (new Date(startISO).getTime() - now.getTime()) / 3600000);
}

function percentFor(hoursRemaining, scale) {
  const sorted = [...scale].sort((a, b) => a.hoursBeforeStart - b.hoursBeforeStart);
  for (const bracket of sorted) {
    if (hoursRemaining <= bracket.hoursBeforeStart) {
      return Math.max(1.0, Math.min(5.0, bracket.penaltyPercent));
    }
  }
  return 1.0;
}

function tradePenalty(hoursRemaining, policy) {
  if (!policy.tradePenaltiesEnabled) return { percent: 0, amount: 0 };
  if (hoursRemaining <= policy.tradePenaltyHoursBeforeStart) {
    return { percent: 1.0, amount: round2(policy.tradePenaltyAmount) };
  }
  return { percent: 0, amount: 0 };
}

function round2(n) {
  return Math.round(Number(n) * 100) / 100;
}

/**
 * @param {"cancel"|"trade"} action
 * @param {object} policy
 * @param {string} shiftStartISO
 * @param {number} [baseAmount]
 * @param {Date} [now]
 */
export function previewPenalty(action, policy, shiftStartISO, baseAmount, now = new Date()) {
  const p = { ...defaultPolicy(), ...policy };
  p.cancellationPenaltyScale = normalizeCancellationScale(p.cancellationPenaltyScale);
  const hours = hoursUntil(shiftStartISO, now);
  const window = action === "cancel" ? p.cancelWindowHours : p.tradeWindowHours;
  const base = baseAmount ?? p.basePenaltyAmount;

  let percent;
  let amount;
  if (action === "cancel") {
    percent = percentFor(hours, p.cancellationPenaltyScale);
    amount = round2(base * percent);
  } else {
    const t = tradePenalty(hours, p);
    percent = t.percent;
    amount = t.amount;
  }

  const allowed = hours > window;
  let blockedReason = null;
  if (!allowed) {
    blockedReason = action === "cancel"
      ? `Canceling is blocked within ${window} hours of shift start.`
      : `Trading is blocked within ${window} hours of shift start.`;
  }

  return {
    allowed,
    penaltyAmount: amount,
    penaltyPercent: percent,
    hoursRemaining: hours,
    windowHours: window,
    action,
    blockedReason
  };
}

export function isActionAllowed(action, policy, shiftStartISO, now = new Date()) {
  return previewPenalty(action, policy, shiftStartISO, undefined, now).allowed;
}

export function bracketLabel(bracket, previousHours) {
  const pct = Math.round(bracket.penaltyPercent * 100);
  const window = formatLeadTime(bracket.hoursBeforeStart);
  if (previousHours != null) {
    return `${formatLeadTime(previousHours)}–${window} out: ${pct}% of base`;
  }
  return `Within ${window}: ${pct}% of base`;
}

function formatLeadTime(hours) {
  if (hours >= 99999) return "any time";
  if (hours >= 168 && hours % 168 === 0) return `${hours / 168}w`;
  if (hours >= 24 && hours % 24 === 0) return `${hours / 24}d`;
  return `${hours}h`;
}
