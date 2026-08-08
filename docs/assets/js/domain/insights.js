/** Hospital day coverage insights (ported from iOS HospitalDayInsights). */

import { SPECIALTIES, sameDay, startOfDay } from "../brand.js";
import {
  appStore, getProposedRate, getPolicy, isDayUnavailable, isShiftFilled, tokenRequestsForHospital
} from "../store.js";
import { currentRate } from "../shift-math.js";

export function trackedSpecialties(hospitalID) {
  const fromShifts = appStore.shifts.filter((s) => s.hospitalID === hospitalID).map((s) => s.specialty);
  const fromTokens = (appStore.tokens.requestedDays || [])
    .filter((t) => t.hospitalID === hospitalID)
    .map((t) => t.specialty);
  const fromRoster = appStore.roster.map((d) => d.specialty);
  const all = new Set([...fromShifts, ...fromTokens, ...fromRoster, ...SPECIALTIES]);
  const ordered = SPECIALTIES.filter((sp) => all.has(sp));
  const extras = [...all].filter((sp) => !SPECIALTIES.includes(sp)).sort();
  return ordered.length ? [...ordered, ...extras] : SPECIALTIES;
}

export function coverageFillLevel(rows) {
  const posted = rows.filter((r) => r.hasShiftPosted);
  if (!posted.length) return "none";
  const filled = posted.filter((r) => r.isFilled).length;
  if (filled === posted.length) return "all";
  if (filled === 0) return "none";
  return "partial";
}

export function hospitalDaySummary(date, hospitalID) {
  const day = startOfDay(date);
  const shifts = appStore.shifts.filter((s) => s.hospitalID === hospitalID && sameDay(s.start, day));
  const tokens = tokenRequestsForHospital(hospitalID, day);
  const blocked = isDayUnavailable(day, hospitalID);
  const roster = appStore.roster;
  const specialties = trackedSpecialties(hospitalID);
  const unitLabel = getPolicy(hospitalID).granularity === "hour" ? "/hr" : "/day";

  const specialtyRows = specialties.map((specialty) => {
    const shift = shifts.find((s) => s.specialty === specialty);
    const assignment = shift
      ? appStore.assignments.find((a) => a.shiftID === shift.id && !["canceled", "traded_complete"].includes(a.status))
      : null;

    let onCallDoctorName = null;
    let onCallCredential = null;
    if (assignment) {
      const token = tokens.find((t) => t.doctorID === assignment.doctorID && t.specialty === specialty);
      const doc = roster.find((d) => d.id === assignment.doctorID);
      onCallDoctorName = token?.doctorName || doc?.name || assignment.doctorName || "Assigned physician";
      onCallCredential = token?.credential || doc?.credential || null;
    }

    let paymentAmount = 0;
    let goingRate = null;
    let approvedRate = null;
    let proposedRate = null;
    let algorithmRate = null;
    let isProposedRateCustom = false;
    let rateUnitLabel = unitLabel;

    if (assignment && shift) {
      const approvedToken = tokens.find((t) =>
        t.doctorID === assignment.doctorID &&
        t.specialty === specialty &&
        (t.status === "approved" || t.status === "auto_approved")
      );
      const locked = approvedToken?.shiftRate ?? currentRate(shift);
      approvedRate = locked;
      goingRate = currentRate(shift);
      rateUnitLabel = shift.rateUnit === "per hour" ? "/hr" : "/day";
      paymentAmount = shift.rateUnit === "per hour" ? locked * (shift.durationHours || 8) : locked;
    } else if (shift) {
      goingRate = currentRate(shift);
      rateUnitLabel = shift.rateUnit === "per hour" ? "/hr" : "/day";
    } else {
      const proposal = getProposedRate(hospitalID, specialty, day);
      proposedRate = proposal.rate;
      algorithmRate = proposal.algorithmRate;
      isProposedRateCustom = proposal.isCustom;
    }

    const specialtyTokens = tokens
      .filter((t) => t.specialty === specialty)
      .map((t) => ({
        id: t.id,
        doctorName: t.doctorName,
        credential: t.credential,
        status: t.status,
        requestedAt: t.requestedAt,
        approvedAt: t.approvedAt,
        specialty: t.specialty,
        shiftRate: t.shiftRate
      }))
      .sort((a, b) => new Date(a.requestedAt) - new Date(b.requestedAt));

    return {
      id: specialty,
      specialty,
      shift,
      onCallDoctorName,
      onCallCredential,
      paymentAmount,
      goingRate,
      approvedRate,
      proposedRate,
      algorithmRate,
      isProposedRateCustom,
      rateUnitLabel,
      isFilled: !!assignment,
      hasShiftPosted: !!shift,
      tokenRequests: specialtyTokens
    };
  });

  const pendingRequestCount = specialtyRows
    .flatMap((r) => r.tokenRequests)
    .filter((t) => t.status === "pending").length;
  const approvedRequestCount = specialtyRows
    .flatMap((r) => r.tokenRequests)
    .filter((t) => t.status === "approved" || t.status === "auto_approved").length;
  const totalPaid = specialtyRows.filter((r) => r.isFilled).reduce((s, r) => s + r.paymentAmount, 0);
  const level = coverageFillLevel(specialtyRows);

  return {
    date: day,
    isBlocked: blocked,
    specialtyRows,
    pendingRequestCount,
    approvedRequestCount,
    totalPaid,
    coverageFillLevel: level,
    hoverUnfilledRows: specialtyRows.filter((r) => r.hasShiftPosted && !r.isFilled),
    hoverFilledRows: specialtyRows.filter((r) => r.isFilled),
    hoverUnpostedRows: specialtyRows.filter((r) => !r.hasShiftPosted && !r.isFilled)
  };
}

export function hospitalAnalytics(hospitalID) {
  const year = new Date().getFullYear();
  const assignments = appStore.assignments.filter((a) =>
    (!hospitalID || a.shift?.hospitalID === hospitalID) &&
    new Date(a.shift?.start || 0).getFullYear() === year
  );
  const ledger = appStore.penaltyLedger.filter((p) =>
    (!hospitalID || p.hospitalID === hospitalID) &&
    new Date(p.createdAt).getFullYear() === year
  );
  const noRealData = !assignments.length && !ledger.length;

  const traded = assignments.filter((a) => a.status === "traded_pending" || a.status === "traded_complete");
  const canceled = assignments.filter((a) => a.status === "canceled");
  const tradePercent = noRealData ? 18.4 : (traded.length / Math.max(1, assignments.length)) * 100;
  const cancelPercent = noRealData ? 11.8 : (canceled.length / Math.max(1, assignments.length)) * 100;

  function bucket(type, minDays, maxDays) {
    if (noRealData) {
      const mock = {
        trade: { 0: 12, 30: 16, 90: 6 },
        cancel: { 0: 9, 30: 10, 90: 4 }
      };
      return mock[type]?.[minDays] ?? 0;
    }
    return ledger.filter((entry) => {
      if (entry.type !== type) return false;
      const a = assignments.find((x) => x.shiftID === entry.shiftID || x.shift?.id === entry.shiftID);
      if (!a) return false;
      const d = (new Date(a.shift.start) - new Date(entry.createdAt)) / 86400000;
      if (d < 0) return false;
      return d >= minDays && (maxDays == null || d < maxDays);
    }).length;
  }

  const yearStart = new Date(year, 0, 1);
  const daysElapsed = Math.max(1, (Date.now() - yearStart.getTime()) / 86400000);
  const yearPenaltyRevenue = ledger.reduce((s, p) => s + Number(p.amount || 0), 0);
  const savingsPerDay = noRealData ? 147 : yearPenaltyRevenue / daysElapsed;

  const specialtyMap = {};
  for (const entry of ledger) {
    const a = assignments.find((x) => x.shiftID === entry.shiftID || x.shift?.id === entry.shiftID);
    const sp = a?.shift?.specialty || "General";
    specialtyMap[sp] = (specialtyMap[sp] || 0) + Number(entry.amount || 0);
  }
  const specialtyRevenues = Object.entries(specialtyMap)
    .map(([specialty, total]) => [specialty, total / daysElapsed])
    .sort((a, b) => b[1] - a[1]);

  if (noRealData && !specialtyRevenues.length) {
    specialtyRevenues.push(
      ["Emergency Medicine", 42],
      ["Cardiology", 31],
      ["Internal Medicine", 24],
      ["Surgery", 18]
    );
  }

  return {
    year,
    yr: String(year).slice(-2),
    tradedCount: noRealData ? 34 : traded.length,
    canceledCount: noRealData ? 23 : canceled.length,
    tradePercent,
    cancelPercent,
    tradeBuckets: [bucket("trade", 0, 30), bucket("trade", 30, 90), bucket("trade", 90, null)],
    cancelBuckets: [bucket("cancel", 0, 30), bucket("cancel", 30, 90), bucket("cancel", 90, null)],
    savingsPerDay,
    specialtyRevenues,
    openShifts: appStore.shifts.filter((s) => s.hospitalID === hospitalID && !isShiftFilled(s.id)).length,
    fillRate: (() => {
      const future = appStore.shifts.filter((s) => s.hospitalID === hospitalID);
      if (!future.length) return 0;
      return Math.round(future.filter((s) => isShiftFilled(s.id)).length / future.length * 100);
    })(),
    pendingTokens: (appStore.tokens.requestedDays || []).filter((t) =>
      t.hospitalID === hospitalID && t.status === "pending"
    ).length
  };
}

export function billingSummary(hospitalID) {
  const filled = appStore.shifts.filter((s) =>
    s.hospitalID === hospitalID && isShiftFilled(s.id)
  );
  const committedTotal = filled.reduce((sum, s) => {
    const rate = currentRate(s);
    return sum + (s.rateUnit === "per hour" ? rate * (s.durationHours || 8) : rate);
  }, 0);
  return {
    committedTotal: Math.round(committedTotal),
    filledShifts: filled
      .slice()
      .sort((a, b) => new Date(b.start) - new Date(a.start))
      .slice(0, 12)
  };
}
