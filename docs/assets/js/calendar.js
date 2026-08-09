import { startOfDay, sameDay } from "./brand.js";
import { currentRate } from "./shift-math.js";
import { openShifts, isShiftFilled, isDayUnavailable, appStore } from "./store.js";
import { icon } from "./lib/icons.js";

export function monthStart(date) {
  const d = new Date(date);
  d.setDate(1);
  return startOfDay(d);
}

export function addMonths(date, n) {
  const d = new Date(date);
  d.setMonth(d.getMonth() + n);
  return d;
}

function daysOfMonth(month) {
  const start = monthStart(month);
  const count = new Date(start.getFullYear(), start.getMonth() + 1, 0).getDate();
  return Array.from({ length: count }, (_, i) => new Date(start.getFullYear(), start.getMonth(), i + 1));
}

export function doctorDayData(month, profile) {
  const today = startOfDay(new Date());
  const shifts = openShifts(profile);
  const hospitalID = appStore.hospitalProfile?.id;

  return daysOfMonth(month).map((date) => {
    const dayShifts = shifts.filter((s) => sameDay(s.start, date));
    const rates = dayShifts.map((s) => currentRate(s));

    return {
      date,
      isPast: date < today,
      shiftCount: dayShifts.length,
      // Hours until the soonest open shift decides the heat of the cell.
      urgencyHours: dayShifts.length
        ? Math.min(...dayShifts.map((s) => (new Date(s.start) - Date.now()) / 3600000))
        : null,
      goingRate: rates.length ? Math.max(...rates) : null,
      isBlocked: hospitalID ? isDayUnavailable(date, hospitalID) : false
    };
  });
}

export function hospitalDayData(month, hospitalID) {
  const today = startOfDay(new Date());
  const shifts = appStore.shifts.filter((s) => s.hospitalID === hospitalID);

  return daysOfMonth(month).map((date) => {
    const posted = shifts.filter((s) => sameDay(s.start, date));
    const filled = posted.filter((s) => isShiftFilled(s.id)).length;

    let level = null;
    if (posted.length) {
      if (filled === posted.length) level = "all";
      else if (filled === 0) level = "none";
      else level = "partial";
    }

    return {
      date,
      isPast: date < today,
      shiftCount: posted.length - filled,
      level,
      isBlocked: isDayUnavailable(date, hospitalID)
    };
  });
}

/** "$850", "$1.2k", "$12k" — keeps the rate legible inside a calendar cell. */
function compactRate(value) {
  const n = Math.round(Number(value) || 0);
  if (n <= 0) return null;
  if (n >= 10000) return `$${Math.round(n / 1000)}k`;
  if (n >= 1000) {
    const k = n / 1000;
    return `$${k % 1 < 0.05 ? Math.round(k) : k.toFixed(1)}k`;
  }
  return `$${n}`;
}

function doctorFill(day) {
  if (day.isBlocked) return "rgba(255,255,255,0.06)";
  if (day.isPast) return "rgba(255,255,255,0.04)";
  if (!day.shiftCount) return "rgba(255,255,255,0.04)";

  const hours = day.urgencyHours ?? 72;
  if (hours < 12) return "rgba(239,68,68,0.60)";
  if (hours < 24) return "rgba(249,115,22,0.55)";
  if (hours < 48) return "rgba(234,179,8,0.45)";
  return "rgba(34,197,94,0.40)";
}

function hospitalFill(day) {
  if (day.isBlocked) return "rgba(255,255,255,0.06)";
  if (day.isPast) return "rgba(255,255,255,0.04)";

  switch (day.level) {
    case "all": return "rgba(34,197,94,0.55)";
    case "partial": return "rgba(234,179,8,0.55)";
    case "none": return "rgba(239,68,68,0.55)";
    default: return "rgba(255,255,255,0.04)";
  }
}

/** A day survives focus mode only if the reader could still act on it. */
function isOpenDay(day, mode) {
  if (day.isPast || day.isBlocked) return false;
  return mode === "hospital" ? day.level !== "all" && day.level !== null : day.shiftCount > 0;
}

function dayCell(day, { mode, selectedDate, compact }) {
  const selected = selectedDate && sameDay(day.date, selectedDate);
  const fill = mode === "hospital" ? hospitalFill(day) : doctorFill(day);
  const rate = mode === "doctor" && !day.isPast ? compactRate(day.goingRate) : null;

  return `
    <button type="button"
      class="cal-day${day.isPast ? " past" : ""}${selected ? " selected" : ""}${compact ? " compact" : ""}"
      data-cal-date="${day.date.toISOString()}"
      style="background:${fill}">
      <span class="cal-num">${day.date.getDate()}</span>
      ${rate ? `<span class="cal-rate">${rate}</span>` : ""}
      ${day.isBlocked ? `<span class="cal-blocked">${icon("close", { size: 9 })}</span>` : ""}
    </button>`;
}

function legend(mode) {
  const items = mode === "hospital"
    ? [
        ["rgba(34,197,94,0.55)", "All filled"],
        ["rgba(234,179,8,0.55)", "Partial"],
        ["rgba(239,68,68,0.55)", "None filled"],
        [null, "Blocked"]
      ]
    : [
        ["rgba(34,197,94,0.40)", "Open"],
        ["rgba(234,179,8,0.45)", "Soon"],
        ["rgba(239,68,68,0.60)", "Urgent"],
        [null, "Closed"]
      ];

  return `<div class="cal-legend">${items.map(([color, label]) => `
    <span>${color
      ? `<span class="legend-swatch" style="background:${color}"></span>`
      : `<span class="legend-swatch blocked">${icon("close", { size: 9 })}</span>`}${label}</span>`).join("")}</div>`;
}

/**
 * Month heatmap ported from `CalendarHeatmap.swift`.
 *
 * With `focusOpen` on, days that need no attention are dropped and the
 * survivors reflow into a tighter grid — the same idea as the iOS focus mode,
 * without the multi-stage pop animation.
 */
export function renderCalendar({ month, days, selectedDate, mode, focusOpen = false, title, subtitle, hint }) {
  const start = monthStart(month);
  const monthLabel = start.toLocaleDateString(undefined, { month: "long", year: "numeric" });
  const weekdays = ["S", "M", "T", "W", "T", "F", "S"];
  const openDays = days.filter((d) => isOpenDay(d, mode));

  let grid;
  if (focusOpen) {
    grid = openDays.length
      ? `<div class="cal-grid compact">${openDays.map((d) => dayCell(d, { mode, selectedDate, compact: true })).join("")}</div>`
      : `<p class="cal-empty">No open days this month — coverage looks complete.</p>`;
  } else {
    const blanks = Array.from({ length: start.getDay() }, () => `<span class="cal-day empty"></span>`);
    grid = `<div class="cal-grid">${blanks.join("")}${days.map((d) => dayCell(d, { mode, selectedDate, compact: false })).join("")}</div>`;
  }

  return `
    <section class="card calendar-card">
      ${title ? `<div class="cal-title">
        <h2>${title}</h2>
        ${subtitle ? `<p class="subtitle">${subtitle}</p>` : ""}
      </div>` : ""}
      <div class="cal-header">
        <button type="button" class="cal-nav" data-cal-nav="-1" aria-label="Previous month">${icon("chevronLeft", { size: 16 })}</button>
        <div class="month-label">${monthLabel}${hint ? `<span class="cal-hint">${hint}</span>` : ""}</div>
        <button type="button" class="cal-nav" data-cal-nav="1" aria-label="Next month">${icon("chevron", { size: 16 })}</button>
      </div>
      ${focusOpen ? "" : `<div class="cal-weekdays">${weekdays.map((d) => `<span>${d}</span>`).join("")}</div>`}
      ${grid}
      <label class="focus-toggle">
        <input type="checkbox" data-focus-toggle ${focusOpen ? "checked" : ""} />
        <span class="switch"></span>
        <span class="focus-copy">
          <span class="focus-title">Show open days only</span>
          <span class="focus-sub">${focusOpen
            ? (mode === "hospital" ? "Filled days pop away · gaps stay in view" : "Your booked days pop away · only free days remain")
            : (mode === "hospital" ? "Turn on to hunt unfilled coverage" : "Hide days you're already scheduled for")}</span>
        </span>
      </label>
      ${focusOpen ? "" : legend(mode)}
    </section>`;
}
