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
    let bg = "rgba(79,142,247,0.06)";
    if (!day.isPast && day.shiftCount > 0) {
      if (mode === "hospital") {
        // Coverage-style coloring with blue base for open demand
        if (day.shiftCount >= 4) bg = "rgba(239,68,68,0.45)";
        else if (day.shiftCount >= 2) bg = "rgba(234,179,8,0.40)";
        else bg = "rgba(79,142,247,0.38)";
      } else {
        const hours = day.urgency != null ? day.urgency / 3600000 : 72;
        if (hours < 12) bg = "rgba(239,68,68,0.55)";
        else if (hours < 24) bg = "rgba(249,115,22,0.50)";
        else if (hours < 48) bg = "rgba(234,179,8,0.42)";
        else bg = "rgba(79,142,247,0.42)";
      }
    }
    if (day.isPast) bg = "rgba(255,255,255,0.03)";
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
        <span><span class="legend-swatch" style="background:${urgencyColor("low")}"></span>Open / later</span>
        <span><span class="legend-swatch" style="background:${urgencyColor("moderate")}"></span>Soon</span>
        <span><span class="legend-swatch" style="background:${urgencyColor("high")}"></span>Urgent</span>
        <span><span class="legend-swatch" style="background:rgba(255,255,255,0.15)"></span>Past</span>
      </div>
    </section>`;
}
