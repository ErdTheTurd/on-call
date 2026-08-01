import { escapeHtml } from "../brand.js";
import {
  navBar, tabBar, shiftRow, pendingBanner, sectionHeader, emptyState, sheet, verificationBadge, icon
} from "../components.js";
import { renderCalendar, hospitalDayData, addMonths } from "../calendar.js";
import {
  appStore, ensureDemoShifts, openShiftCount, fillRatePercent, openShifts, signOut
} from "../store.js";

export function renderHospitalApp(state) {
  const profile = appStore.hospitalProfile;
  const tab = state.tab || "dashboard";
  if (profile) ensureDemoShifts(profile.id, profile.name);

  return `
    <div class="app-shell">
      <div class="bg-gradient"><div class="blob-bottom"></div></div>
      ${tab === "dashboard" ? renderHospitalDashboard(state, profile) : ""}
      ${tab === "alter" ? renderAlterShifts(profile) : ""}
      ${tab === "doctors" ? renderDoctors() : ""}
      ${tabBar([
        { id: "dashboard", label: "Dashboard", icon: "dashboard" },
        { id: "alter", label: "Alter Shifts", icon: "calendar" },
        { id: "doctors", label: "Doctors", icon: "doctors" }
      ], tab)}
      ${state.sheet ? renderHospitalSheet(profile) : ""}
    </div>`;
}

function renderHospitalDashboard(state, profile) {
  const month = state.calendarMonth ? new Date(state.calendarMonth) : new Date();
  const days = profile ? hospitalDayData(month, profile.id) : [];

  return `
    ${navBar(profile?.name || "Dashboard")}
    <main class="main-scroll stack">
      ${profile && profile.verificationStatus !== "verified" ? pendingBanner(profile.verificationStatus, profile.verificationFlags) : ""}
      ${profile ? renderCalendar({ month, days, selectedDate: null, mode: "hospital" }) : ""}
      <section class="card stat-row">
        <button type="button" class="stat-badge" data-nav-tab="alter">
          <div class="value">${profile ? openShiftCount(profile.id) : 0}</div>
          <div class="label">Open\nShifts</div>
        </button>
        <button type="button" class="stat-badge" data-open-sheet>
          <div class="value">${profile ? fillRatePercent(profile.id) : 0}%</div>
          <div class="label">Fill Rate\n30 days</div>
        </button>
        <button type="button" class="stat-badge" data-nav-tab="doctors">
          <div class="value">0</div>
          <div class="label">Auto‑Approved\nDoctors</div>
        </button>
      </section>
    </main>`;
}

function renderAlterShifts(profile) {
  const shifts = profile ? appStore.shifts.filter((s) => s.hospitalID === profile.id).slice(0, 20) : [];
  return `
    ${navBar("Alter Shifts")}
    <main class="main-scroll stack">
      ${shifts.length ? shifts.map((s) => `<section class="card">${shiftRow(s)}</section>`).join("") : emptyState("No shifts", "Shifts are generated automatically for your hospital calendar.")}
    </main>`;
}

function renderDoctors() {
  return `
    ${navBar("Doctors")}
    <main class="main-scroll stack">
      ${emptyState("Doctor roster", "Manage auto-approved doctors from the iOS app.", "doctors")}
    </main>`;
}

function renderHospitalSheet(profile) {
  const body = `
    ${profile ? `
      <div class="menu-profile">
        <div class="avatar square">${icon("hospital")}</div>
        <div>
          <div style="font-weight:600">${escapeHtml(profile.name)}</div>
          <div class="subtitle">NPI: ${escapeHtml(profile.npi)}</div>
          ${verificationBadge(profile.verificationStatus)}
        </div>
      </div>` : ""}
    <ul class="menu-list">
      <section><div class="section-label">Management</div>
        <button class="menu-item" type="button" data-nav-tab="alter">${icon("calendar")}<span>Open Shifts</span></button>
        <button class="menu-item" type="button">${icon("dashboard")}<span>Analytics</span></button>
        <button class="menu-item" type="button">${icon("dollar")}<span>Billing</span></button>
      </section>
      <section><div class="section-label">Account</div>
        <button class="menu-item danger" type="button" data-sign-out>${icon("lock")}<span>Sign Out</span></button>
      </section>
    </ul>`;
  return sheet("Dashboard", body);
}

export function bindHospital(root, state, update) {
  root.querySelector("[data-action='menu']")?.addEventListener("click", () => update({ sheet: true }));
  root.querySelector("[data-open-sheet]")?.addEventListener("click", () => update({ sheet: true }));
  root.querySelectorAll("[data-tab], [data-nav-tab]").forEach((btn) => {
    btn.addEventListener("click", () => update({ tab: btn.dataset.tab || btn.dataset.navTab, sheet: false }));
  });
  root.querySelectorAll("[data-close-sheet]").forEach((el) => {
    el.addEventListener("click", () => update({ sheet: false }));
  });
  root.querySelector("[data-sign-out]")?.addEventListener("click", () => { signOut(); update({ route: "auth" }); });
  root.querySelectorAll("[data-cal-nav]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const m = state.calendarMonth ? new Date(state.calendarMonth) : new Date();
      update({ calendarMonth: addMonths(m, Number(btn.dataset.calNav)).toISOString() });
    });
  });
}
