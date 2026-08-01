import { startOfDay, sameDay } from "./brand.js";
import { urgencyColor } from "./shift-math.js";
import { openShifts, isShiftFilled, appStore } from "./store.js";

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

export function doctorDayData(month, profile) {
  const start = monthStart(month);
  const year = start.getFullYear();
  const mon = start.getMonth();
  const daysInMonth = new Date(year, mon + 1, 0).getDate();
  const today = startOfDay(new Date());
  const shifts = openShifts(profile);

  return Array.from({ length: daysInMonth }, (_, i) => {
    const date = new Date(year, mon, i + 1);
    const dayShifts = shifts.filter((s) => sameDay(s.start, date));
    const isPast = date < today;
    return {
      date,
      isPast,
      shiftCount: dayShifts.length,
      urgency: dayShifts.length ? Math.min(...dayShifts.map((s) => new Date(s.start) - Date.now())) : null
    };
  });
}

export function hospitalDayData(month, hospitalID) {
  const start = monthStart(month);
  const year = start.getFullYear();
  const mon = start.getMonth();
  const daysInMonth = new Date(year, mon + 1, 0).getDate();
  const today = startOfDay(new Date());
  const shifts = appStore.shifts.filter((s) => s.hospitalID === hospitalID);

  return Array.from({ length: daysInMonth }, (_, i) => {
    const date = new Date(year, mon, i + 1);
    const dayShifts = shifts.filter((s) => sameDay(s.start, date));
    const open = dayShifts.filter((s) => !isShiftFilled(s.id) && new Date(s.start) >= today);
    return { date, isPast: date < today, shiftCount: open.length };
  });
}

export function renderCalendar({ month, days, selectedDate, mode, onSelect }) {
  const start = monthStart(month);
  const firstDow = start.getDay();
  const monthLabel = start.toLocaleDateString(undefined, { month: "long", year: "numeric" });
  const cells = [];

  for (let i = 0; i < firstDow; i++) cells.push(`<button class="cal-day empty" type="button" tabindex="-1"></button>`);

  days.forEach((day) => {
    const selected = selectedDate && sameDay(day.date, selectedDate);
    let bg = "rgba(255,255,255,0.04)";
    if (!day.isPast && day.shiftCount > 0) {
      bg = mode === "hospital"
        ? (day.shiftCount >= 3 ? "rgba(248,113,113,0.25)" : "rgba(251,191,36,0.22)")
        : "rgba(79,142,247,0.22)";
    }
    if (day.isPast) bg = "rgba(255,255,255,0.02)";
    cells.push(`
      <button type="button" class="cal-day ${day.isPast ? "past" : ""} ${selected ? "selected" : ""}"
        data-cal-date="${day.date.toISOString()}"
        style="background:${bg}">
        ${day.date.getDate()}
        ${day.shiftCount > 0 && !day.isPast ? `<span class="dot-count"></span>` : ""}
      </button>`);
  });

  return `
    <section class="card calendar-card">
      <div class="cal-header">
        <button type="button" class="cal-nav" data-cal-nav="-1">‹</button>
        <div class="month-label">${monthLabel}</div>
        <button type="button" class="cal-nav" data-cal-nav="1">›</button>
      </div>
      <div class="cal-weekdays">${["S","M","T","W","T","F","S"].map((d) => `<span>${d}</span>`).join("")}</div>
      <div class="cal-grid">${cells.join("")}</div>
      <div class="cal-legend">
        <span><span class="legend-swatch" style="background:${urgencyColor("low")}"></span>Open shifts</span>
        <span><span class="legend-swatch" style="background:rgba(255,255,255,0.15)"></span>Past</span>
        ${mode === "hospital" ? `<span class="tertiary">Long press for coverage · Tap for details</span>` : `<span class="tertiary">Tap a day to request call</span>`}
      </div>
    </section>`;
}
