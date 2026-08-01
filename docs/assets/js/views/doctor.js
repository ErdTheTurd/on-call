import { escapeHtml, formatShiftDate } from "../brand.js";
import {
  navBar, tabBar, shiftRow, pointsCard, tokenBadge, pendingBanner,
  credentialStatusCard, sectionHeader, emptyState, sheet, verificationBadge, icon
} from "../components.js";
import { renderCalendar, doctorDayData, monthStart, addMonths } from "../calendar.js";
import {
  appStore, openShifts, recommendedShifts, shiftsForDate, activeAssignments,
  pendingTradeCount, acceptShift, requestToken, ensureDemoShifts, signOut, demoHospital
} from "../store.js";

export function renderDoctorApp(state) {
  const profile = appStore.doctorProfile;
  const tab = state.tab || "home";
  const demo = demoHospital();
  ensureDemoShifts(appStore.hospitalProfile?.id || demo.id, appStore.hospitalProfile?.name || demo.name);

  return `
    <div class="app-shell">
      <div class="bg-gradient"><div class="blob-bottom"></div></div>
      ${tab === "home" ? renderDoctorHome(state, profile) : ""}
      ${tab === "shifts" ? renderMyShifts(profile) : ""}
      ${tab === "credentials" ? renderCredentials(profile) : ""}
      ${tabBar([
        { id: "home", label: "Home", icon: "home" },
        { id: "shifts", label: "My Shifts", icon: "shifts" },
        { id: "credentials", label: "Credentials", icon: "credentials" }
      ], tab, pendingTradeCount())}
      ${state.sheet ? renderDoctorSheet(state.sheet) : ""}
      ${state.daySheet ? renderDaySheet(state.daySheet, profile) : ""}
    </div>`;
}

function renderDoctorHome(state, profile) {
  const month = state.calendarMonth ? new Date(state.calendarMonth) : new Date();
  const days = doctorDayData(month, profile);
  const selected = state.selectedDate ? new Date(state.selectedDate) : null;
  const dayShifts = selected ? shiftsForDate(selected, profile) : [];
  const rec = recommendedShifts();

  return `
    ${navBar(profile ? `Dr. ${profile.lastName}` : "On‑Call")}
    <main class="main-scroll stack">
      ${profile && profile.verificationStatus !== "verified" ? pendingBanner(profile.verificationStatus, profile.verificationFlags) : ""}
      ${pointsCard(appStore.points)}
      <div style="display:flex;align-items:center;justify-content:space-between;padding:0 2px">
        ${tokenBadge(appStore.tokens)}
        <span class="tertiary" style="font-size:12px">Tap a day to request call</span>
      </div>
      ${renderCalendar({ month, days, selectedDate: selected, mode: "doctor" })}
      ${selected ? `
        <section class="card">
          <div class="subtitle" style="font-weight:600;margin-bottom:10px">${selected.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}</div>
          ${dayShifts.length ? dayShifts.map((s, i) => `${shiftRow(s)}${i < dayShifts.length - 1 ? '<div class="divider"></div>' : ""}`).join("") : `<div class="subtitle">${icon("moon")} No open shifts</div>`}
        </section>` : ""}
      <section class="card stack">
        ${sectionHeader("Recommended", "sparkles")}
        ${rec.length ? rec.map((s, i) => `${shiftRow(s)}${i < rec.length - 1 ? '<div class="divider"></div>' : ""}`).join("") : `<p class="subtitle">No open shifts right now. Check back after hospitals post coverage.</p>`}
      </section>
      ${credentialStatusCard(profile)}
    </main>`;
}

function renderMyShifts(profile) {
  const active = activeAssignments();
  return `
    ${navBar("My Shifts")}
    <main class="main-scroll stack">
      ${active.length ? active.map((a) => `
        <section class="card stack">
          ${shiftRow(a.shift, { showLock: true })}
          <div class="subtitle">Assigned to ${escapeHtml(a.doctorName)} · ${formatShiftDate(a.shift.start)}</div>
          ${a.status === "traded_pending" ? `<span class="urgency-badge" style="color:var(--warning)">Trade pending</span>` : ""}
        </section>`).join("") : emptyState("No assigned shifts", "Accept shifts from the home calendar or recommended list.")}
    </main>`;
}

function renderCredentials(profile) {
  return `
    ${navBar("Credentials")}
    <main class="main-scroll stack">
      ${profile ? `
        <section class="card stack">
          ${sectionHeader("Identity")}
          <div style="display:grid;gap:10px;font-size:0.95rem">
            <div><span class="tertiary">Name</span><div>${escapeHtml(profile.firstName)} ${escapeHtml(profile.lastName)}, ${escapeHtml(profile.credential)}</div></div>
            <div class="divider"></div>
            <div><span class="tertiary">NPI</span><div>${escapeHtml(profile.npi)}</div></div>
            <div class="divider"></div>
            <div><span class="tertiary">License</span><div>${escapeHtml(profile.licenseNumber)} · ${escapeHtml(profile.licenseState)}</div></div>
            <div class="divider"></div>
            <div><span class="tertiary">Email</span><div>${escapeHtml(profile.email)}</div></div>
          </div>
        </section>
        <section class="card stack">
          ${sectionHeader("Verification", "credentials")}
          <div style="display:flex;align-items:center;gap:10px">${verificationBadge(profile.verificationStatus)}</div>
          <p class="subtitle">Upload state license, DEA certificate, malpractice COI, and board certification from the iOS app.</p>
        </section>` : emptyState("No profile", "Complete onboarding to view credentials.")}
    </main>`;
}

function renderDoctorSheet(sheet) {
  const profile = appStore.doctorProfile;
  const body = `
    <div class="menu-profile">
      <div class="avatar">${escapeHtml((profile?.firstName?.[0] || "") + (profile?.lastName?.[0] || ""))}</div>
      <div>
        <div style="font-weight:600">${escapeHtml(profile?.firstName || "")} ${escapeHtml(profile?.lastName || "")}${profile ? `, ${profile.credential}` : ""}</div>
        <div class="subtitle">${escapeHtml(profile?.specialties?.[0] || "")}</div>
        ${profile ? verificationBadge(profile.verificationStatus) : ""}
      </div>
    </div>
    <ul class="menu-list">
      <section><div class="section-label">Rewards</div>
        <button class="menu-item" type="button" data-nav="points">${icon("sparkles")}<span>Points & Level · ${appStore.points.totalPoints} pts</span></button>
      </section>
      <section><div class="section-label">Schedule</div>
        <button class="menu-item" type="button" data-nav-tab="shifts">${icon("calendar")}<span>My Shifts</span></button>
      </section>
      <section><div class="section-label">Account</div>
        <button class="menu-item danger" type="button" data-sign-out>${icon("lock")}<span>Sign Out</span></button>
      </section>
    </ul>`;
  return sheet("Dashboard", body);
}

function renderDaySheet(dateISO, profile) {
  const date = new Date(dateISO);
  const shifts = shiftsForDate(date, profile);
  const body = `
    <main class="main-scroll stack" style="padding-bottom:24px">
      <section class="card" style="text-align:center">
        <div class="subtitle">${date.toLocaleDateString(undefined, { weekday: "long" })}</div>
        <div class="page-title" style="font-size:1.4rem">${date.toLocaleDateString(undefined, { month: "long", day: "numeric", year: "numeric" })}</div>
      </section>
      <div style="display:flex;justify-content:space-between;align-items:center">${tokenBadge(appStore.tokens)}</div>
      ${shifts.length ? shifts.map((s) => `
        <section class="card stack">
          ${shiftRow(s)}
          <button type="button" class="btn-primary" data-accept-shift="${s.id}">Request / Accept</button>
        </section>`).join("") : `
        <section class="card empty-state">${icon("moon")}<div>No open shifts on this day</div>
          <button type="button" class="btn-primary" style="margin-top:12px" data-request-day>Request This Day</button>
        </section>`}
    </main>`;
  return sheet(date.toLocaleDateString(undefined, { month: "short", day: "numeric" }), body);
}

export function bindDoctor(root, state, update) {
  root.querySelector("[data-action='menu']")?.addEventListener("click", () => update({ sheet: true }));
  root.querySelectorAll("[data-tab]").forEach((btn) => {
    btn.addEventListener("click", () => update({ tab: btn.dataset.tab, sheet: false, daySheet: null }));
  });
  root.querySelectorAll("[data-close-sheet]").forEach((el) => {
    el.addEventListener("click", () => update({ sheet: false, daySheet: null }));
  });
  root.querySelector("[data-sign-out]")?.addEventListener("click", () => { signOut(); update({ route: "auth" }); });
  root.querySelectorAll("[data-cal-nav]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const m = state.calendarMonth ? new Date(state.calendarMonth) : new Date();
      update({ calendarMonth: addMonths(m, Number(btn.dataset.calNav)).toISOString() });
    });
  });
  root.querySelectorAll("[data-cal-date]").forEach((btn) => {
    btn.addEventListener("click", () => update({ selectedDate: btn.dataset.calDate, daySheet: btn.dataset.calDate }));
  });
  root.querySelectorAll("[data-accept-shift]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const shift = appStore.shifts.find((s) => s.id === btn.dataset.acceptShift);
      const profile = appStore.doctorProfile;
      if (shift && profile) {
        acceptShift(shift, profile);
        update({ daySheet: null });
      }
    });
  });
  root.querySelector("[data-request-day]")?.addEventListener("click", () => {
    const profile = appStore.doctorProfile;
    const date = state.daySheet;
    const res = requestToken(date, profile?.id, "Hospital", profile?.specialties?.[0] || "Internal Medicine", profile?.id);
    if (!res.ok) alert(res.error);
    update({ daySheet: null });
  });
}
