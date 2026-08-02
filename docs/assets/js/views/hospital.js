import { escapeHtml, SPECIALTIES, startOfDay, sameDay } from "../brand.js";
import {
  navBar, tabBar, shiftRow, pendingBanner, sectionHeader, emptyState, sheet, verificationBadge, icon
} from "../components.js";
import { renderCalendar, hospitalDayData, addMonths } from "../calendar.js";
import {
  appStore, ensureDemoShifts, openShiftCount, fillRatePercent, signOut,
  autoApprovedCount, tokenRequestsForHospital, approveToken, denyToken,
  toggleUnavailable, isDayUnavailable, getPolicy, savePolicy, defaultPolicy,
  getProposedRate, setProposedRate, resetProposedRate, toggleRosterAutoApprove,
  seedMockDoctors
} from "../store.js";

export function renderHospitalApp(state) {
  const profile = appStore.hospitalProfile;
  const tab = state.tab || "dashboard";
  if (profile) {
    ensureDemoShifts(profile.id, profile.name);
    seedMockDoctors();
  }

  return `
    <div class="app-shell">
      <div class="bg-gradient"><div class="blob-bottom"></div></div>
      ${tab === "dashboard" ? renderHospitalDashboard(state, profile) : ""}
      ${tab === "alter" ? renderAlterShifts(state, profile) : ""}
      ${tab === "doctors" ? renderDoctors(profile) : ""}
      ${tabBar([
        { id: "dashboard", label: "Dashboard", icon: "dashboard" },
        { id: "alter", label: "Alter Shifts", icon: "calendar" },
        { id: "doctors", label: "Doctors", icon: "doctors" }
      ], tab)}
      ${state.sheet ? renderHospitalSheet(state, profile) : ""}
      ${state.daySheet ? renderHospitalDaySheet(state.daySheet, profile) : ""}
    </div>`;
}

function renderHospitalDashboard(state, profile) {
  const month = state.calendarMonth ? new Date(state.calendarMonth) : new Date();
  const days = profile ? hospitalDayData(month, profile.id) : [];
  const selected = state.selectedDate ? new Date(state.selectedDate) : null;

  return `
    ${navBar(profile?.name || "Dashboard")}
    <main class="main-scroll stack">
      ${profile && profile.verificationStatus !== "verified" ? pendingBanner(profile.verificationStatus, profile.verificationFlags) : ""}
      <div class="content-grid two-col">
        <div class="stack">
          ${profile ? renderCalendar({ month, days, selectedDate: selected, mode: "hospital" }) : ""}
          ${selected && profile ? renderDayDetail(selected, profile) : ""}
        </div>
        <div class="stack">
          <section class="card stat-row">
            <button type="button" class="stat-badge" data-nav-tab="alter">
              <div class="value">${profile ? openShiftCount(profile.id) : 0}</div>
              <div class="label">Open\nShifts</div>
            </button>
            <button type="button" class="stat-badge" data-open-sheet="analytics">
              <div class="value">${profile ? fillRatePercent(profile.id) : 0}%</div>
              <div class="label">Fill Rate\n30 days</div>
            </button>
            <button type="button" class="stat-badge" data-nav-tab="doctors">
              <div class="value">${autoApprovedCount()}</div>
              <div class="label">Auto‑Approved\nDoctors</div>
            </button>
          </section>
          <section class="card stack">
            ${sectionHeader("Quick actions")}
            <button type="button" class="btn-secondary" data-nav-tab="alter">Alter shift rates</button>
            <button type="button" class="btn-secondary" data-open-sheet="policy">Scheduling policy</button>
            <button type="button" class="btn-secondary" data-open-sheet="schedule">Schedule admin</button>
          </section>
        </div>
      </div>
    </main>`;
}

function renderDayDetail(date, profile) {
  const tokens = tokenRequestsForHospital(profile.id, date);
  const pending = tokens.filter((t) => t.status === "pending");
  const shifts = appStore.shifts.filter((s) => s.hospitalID === profile.id && sameDay(s.start, date));
  const blocked = isDayUnavailable(date, profile.id);

  return `
    <section class="card stack">
      <div style="display:flex;justify-content:space-between;align-items:center">
        <div class="subtitle" style="font-weight:600">${date.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}</div>
        <button type="button" class="chip ${blocked ? "active" : ""}" data-toggle-unavail="${date.toISOString()}">
          ${blocked ? "Unavailable" : "Mark unavailable"}
        </button>
      </div>
      ${shifts.length ? shifts.map((s) => shiftRow(s)).join('<div class="divider"></div>') : `<p class="subtitle">No shifts scheduled</p>`}
      ${pending.length ? `
        <div class="divider"></div>
        ${sectionHeader("Pending Tokens (${pending.length})")}
        ${pending.map((t) => `
          <div class="trade-card">
            <div><strong>${escapeHtml(t.doctorName || "Doctor")}</strong> · ${escapeHtml(t.specialty)}</div>
            <div class="subtitle">${escapeHtml(t.credential || "MD")}</div>
            <div class="trade-actions">
              <button type="button" class="approve" data-approve-token="${t.id}">Approve</button>
              <button type="button" class="deny" data-deny-token="${t.id}">Deny</button>
            </div>
          </div>`).join("")}` : ""}
    </section>`;
}

function renderAlterShifts(state, profile) {
  if (!profile) return emptyState("No hospital", "Complete onboarding first.");

  const editDate = state.alterDate ? new Date(state.alterDate) : startOfDay(new Date());
  const specialty = state.alterSpecialty || SPECIALTIES[0];
  const proposed = getProposedRate(profile.id, specialty, editDate);
  const unit = getPolicy(profile.id).granularity === "hour" ? "/hr" : "/day";

  return `
    ${navBar("Alter Shifts")}
    <main class="main-scroll stack">
      <div class="content-grid two-col">
        <div class="stack">
          <section class="card stack">
            ${sectionHeader("Date & Specialty")}
            <div class="form-field">
              <label>Date</label>
              <input type="date" data-alter-date value="${editDate.toISOString().slice(0, 10)}" />
            </div>
            <div class="form-field">
              <label>Specialty</label>
              <select data-alter-specialty>
                ${SPECIALTIES.map((sp) => `<option value="${escapeHtml(sp)}" ${sp === specialty ? "selected" : ""}>${escapeHtml(sp)}</option>`).join("")}
              </select>
            </div>
          </section>
          <section class="card stack">
            ${sectionHeader("Rate Editor")}
            <div style="display:flex;justify-content:space-between;align-items:baseline">
              <span class="tertiary">Algorithm rate</span>
              <span style="font-weight:700;color:var(--accent)">$${Math.round(proposed.algorithmRate)}${unit}</span>
            </div>
            <div class="form-field">
              <label>Proposed rate ${proposed.isCustom ? "(custom)" : ""}</label>
              <input type="number" step="25" data-alter-rate value="${Math.round(proposed.rate)}" />
            </div>
            <div style="display:flex;gap:8px;flex-wrap:wrap">
              <button type="button" class="btn-primary" style="flex:1;min-width:140px" data-save-rate>Save Rate</button>
              <button type="button" class="btn-bordered" data-reset-rate>Reset to algorithm</button>
            </div>
          </section>
        </div>
        <section class="card stack">
          ${sectionHeader("Upcoming shifts")}
          ${appStore.shifts.filter((s) => s.hospitalID === profile.id).slice(0, 15).map((s) =>
            `<div>${shiftRow(s)}</div>`
          ).join('<div class="divider"></div>') || `<p class="subtitle">No upcoming shifts.</p>`}
        </section>
      </div>
    </main>`;
}

function renderDoctors(profile) {
  const roster = appStore.roster;
  return `
    ${navBar("Doctors")}
    <main class="main-scroll stack">
      <div class="page-header">
        <div>
          <h2>Roster</h2>
          <p class="muted">Manage doctors and auto-approve settings.</p>
        </div>
        <button type="button" class="btn-secondary" style="width:auto;min-width:180px" data-seed-mocks>Seed demo doctors</button>
      </div>
      ${roster.length ? `<div class="roster-grid">${roster.map((d) => `
        <section class="card" style="display:flex;align-items:center;gap:14px">
          <div style="flex:1;min-width:0">
            <div style="font-weight:600;font-size:1.05rem">${escapeHtml(d.name)}</div>
            <div class="subtitle">${escapeHtml(d.specialty)} · NPI ${escapeHtml(d.npi)}</div>
            ${verificationBadge(d.verificationStatus, true)}
          </div>
          <label class="toggle-row" style="flex-direction:column;align-items:flex-end;gap:4px">
            <span style="font-size:11px" class="tertiary">Auto-approve</span>
            <input type="checkbox" data-roster-auto="${d.id}" ${d.isAutoApproved ? "checked" : ""} />
          </label>
        </section>`).join("")}</div>` : emptyState("Doctor roster", "Doctors appear when they register or you seed demo doctors.", "doctors")}
    </main>`;
}

function renderHospitalSheet(state, profile) {
  const kind = typeof state.sheet === "string" ? state.sheet : "menu";

  if (kind === "policy") return renderPolicySheet(profile);
  if (kind === "analytics") return renderAnalyticsSheet(profile);
  if (kind === "billing") return renderBillingSheet(profile);
  if (kind === "schedule") return renderScheduleAdminSheet(profile);

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
        <button class="menu-item" type="button" data-nav-tab="alter">${icon("calendar")}<span>Alter Shifts</span></button>
        <button class="menu-item" type="button" data-open-sheet="schedule">${icon("dashboard")}<span>Schedule Admin</span></button>
        <button class="menu-item" type="button" data-open-sheet="policy">${icon("credentials")}<span>Policy Settings</span></button>
        <button class="menu-item" type="button" data-open-sheet="analytics">${icon("sparkles")}<span>Analytics</span></button>
        <button class="menu-item" type="button" data-open-sheet="billing">${icon("dollar")}<span>Billing</span></button>
      </section>
      <section><div class="section-label">Account</div>
        <button class="menu-item danger" type="button" data-sign-out>${icon("lock")}<span>Sign Out</span></button>
      </section>
    </ul>`;
  return sheet("Menu", body);
}

function renderPolicySheet(profile) {
  if (!profile) return sheet("Policy", emptyState("No profile"));
  const policy = getPolicy(profile.id);
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <section class="card stack">
        ${sectionHeader("Scheduling")}
        <label class="toggle-row">
          <span>Administrator must approve shifts</span>
          <input type="checkbox" data-policy="administratorApproveShifts" ${policy.administratorApproveShifts ? "checked" : ""} />
        </label>
        <div class="form-field">
          <label>Granularity</label>
          <select data-policy="granularity">
            <option value="day" ${policy.granularity === "day" ? "selected" : ""}>Per day</option>
            <option value="hour" ${policy.granularity === "hour" ? "selected" : ""}>Per hour</option>
          </select>
        </div>
      </section>
      <section class="card stack">
        ${sectionHeader("Penalty Windows")}
        <div class="form-field"><label>Cancel window (hours)</label>
          <input type="number" data-policy="cancelWindowHours" value="${policy.cancelWindowHours}" /></div>
        <div class="form-field"><label>Trade window (hours)</label>
          <input type="number" data-policy="tradeWindowHours" value="${policy.tradeWindowHours}" /></div>
        <div class="form-field"><label>Base penalty ($)</label>
          <input type="number" data-policy="basePenaltyAmount" value="${policy.basePenaltyAmount}" /></div>
        <label class="toggle-row">
          <span>Trade penalties enabled</span>
          <input type="checkbox" data-policy="tradePenaltiesEnabled" ${policy.tradePenaltiesEnabled ? "checked" : ""} />
        </label>
        <button type="button" class="btn-primary" data-save-policy>Save Policy</button>
      </section>
    </main>`;
  return sheet("Policy Settings", body);
}

function renderAnalyticsSheet(profile) {
  const open = profile ? openShiftCount(profile.id) : 0;
  const fill = profile ? fillRatePercent(profile.id) : 0;
  const tokens = profile ? tokenRequestsForHospital(profile.id) : [];
  const pending = tokens.filter((t) => t.status === "pending").length;
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <section class="card stat-row">
        <div class="stat-badge"><div class="value">${open}</div><div class="label">Open</div></div>
        <div class="stat-badge"><div class="value">${fill}%</div><div class="label">Fill rate</div></div>
        <div class="stat-badge"><div class="value">${pending}</div><div class="label">Pending tokens</div></div>
      </section>
      <section class="card stack">
        ${sectionHeader("Coverage")}
        <p class="subtitle">${appStore.assignments.filter((a) => a.shift?.hospitalID === profile?.id && a.status === "scheduled").length} active assignments</p>
        <p class="subtitle">${appStore.penaltyLedger.filter((p) => p.hospitalID === profile?.id).length} penalty events recorded</p>
      </section>
    </main>`;
  return sheet("Analytics", body);
}

function renderBillingSheet(profile) {
  const ledger = appStore.penaltyLedger.filter((p) => p.hospitalID === profile?.id);
  const totalPenalties = ledger.reduce((s, p) => s + Number(p.amount || 0), 0);
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <section class="card">
        <div class="subtitle">Total penalties collected</div>
        <div style="font-size:1.8rem;font-weight:700;color:var(--warning)">$${totalPenalties.toLocaleString()}</div>
      </section>
      ${ledger.length ? `
        <section class="card stack">
          ${sectionHeader("Penalty Ledger")}
          ${ledger.slice(0, 10).map((p) => `
            <div style="display:flex;justify-content:space-between;font-size:13px">
              <span>${p.type} · ${new Date(p.createdAt).toLocaleDateString()}</span>
              <span style="color:var(--warning)">$${p.amount}</span>
            </div>`).join("")}
        </section>` : emptyState("No penalties", "Penalty charges appear when doctors cancel or trade inside policy windows.")}
    </main>`;
  return sheet("Billing", body);
}

function renderScheduleAdminSheet(profile) {
  const policy = profile ? getPolicy(profile.id) : defaultPolicy();
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <section class="card stack">
        ${sectionHeader("Quick Actions")}
        <button type="button" class="btn-secondary" data-nav-tab="alter">Open rate editor</button>
        <button type="button" class="btn-secondary" data-open-sheet="policy">Edit scheduling policy</button>
        <button type="button" class="btn-secondary" data-seed-mocks>Seed demo doctors</button>
      </section>
      <section class="card stack">
        ${sectionHeader("Current Policy")}
        <p class="subtitle">Granularity: ${policy.granularity}</p>
        <p class="subtitle">Admin approval: ${policy.administratorApproveShifts ? "Required" : "Auto for verified"}</p>
        <p class="subtitle">Cancel window: ${policy.cancelWindowHours}h · Trade window: ${policy.tradeWindowHours}h</p>
      </section>
    </main>`;
  return sheet("Schedule Admin", body);
}

function renderHospitalDaySheet(dateISO, profile) {
  if (!profile) return "";
  const date = new Date(dateISO);
  return sheet(
    date.toLocaleDateString(undefined, { month: "short", day: "numeric" }),
    `<main class="main-scroll stack" style="padding:16px">${renderDayDetail(date, profile)}</main>`
  );
}

export function bindHospital(root, state, update) {
  const profile = appStore.hospitalProfile;

  root.querySelector("[data-action='menu']")?.addEventListener("click", () => update({ sheet: "menu" }));
  root.querySelectorAll("[data-open-sheet]").forEach((btn) => {
    btn.addEventListener("click", () => update({ sheet: btn.dataset.openSheet || true }));
  });
  root.querySelectorAll("[data-tab], [data-nav-tab]").forEach((btn) => {
    btn.addEventListener("click", () => update({
      tab: btn.dataset.tab || btn.dataset.navTab,
      sheet: false,
      daySheet: null
    }));
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
    btn.addEventListener("click", () => update({
      selectedDate: btn.dataset.calDate,
      daySheet: btn.dataset.calDate
    }));
  });

  root.querySelectorAll("[data-approve-token]").forEach((btn) => {
    btn.addEventListener("click", async () => { await approveToken(btn.dataset.approveToken); });
  });
  root.querySelectorAll("[data-deny-token]").forEach((btn) => {
    btn.addEventListener("click", async () => { await denyToken(btn.dataset.denyToken); });
  });
  root.querySelectorAll("[data-toggle-unavail]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      if (profile) await toggleUnavailable(profile.id, btn.dataset.toggleUnavail);
    });
  });
  root.querySelectorAll("[data-roster-auto]").forEach((el) => {
    el.addEventListener("change", async () => {
      await toggleRosterAutoApprove(el.dataset.rosterAuto);
    });
  });
  root.querySelector("[data-seed-mocks]")?.addEventListener("click", () => {
    seedMockDoctors();
  });

  root.querySelector("[data-alter-date]")?.addEventListener("change", (e) => {
    update({ alterDate: e.target.value, alterSpecialty: state.alterSpecialty });
  });
  root.querySelector("[data-alter-specialty]")?.addEventListener("change", (e) => {
    update({ alterSpecialty: e.target.value, alterDate: state.alterDate });
  });
  root.querySelector("[data-save-rate]")?.addEventListener("click", async () => {
    if (!profile) return;
    const date = state.alterDate || new Date().toISOString().slice(0, 10);
    const specialty = state.alterSpecialty || SPECIALTIES[0];
    const rate = Number(root.querySelector("[data-alter-rate]")?.value);
    await setProposedRate(profile.id, specialty, date, rate);
    alert("Rate saved.");
  });
  root.querySelector("[data-reset-rate]")?.addEventListener("click", async () => {
    if (!profile) return;
    const date = state.alterDate || new Date().toISOString().slice(0, 10);
    const specialty = state.alterSpecialty || SPECIALTIES[0];
    await resetProposedRate(profile.id, specialty, date);
    update({ alterDate: date, alterSpecialty: specialty });
  });

  root.querySelector("[data-save-policy]")?.addEventListener("click", async () => {
    if (!profile) return;
    const policy = { ...getPolicy(profile.id) };
    root.querySelectorAll("[data-policy]").forEach((el) => {
      const key = el.dataset.policy;
      if (el.type === "checkbox") policy[key] = el.checked;
      else if (el.type === "number") policy[key] = Number(el.value);
      else policy[key] = el.value;
    });
    await savePolicy(profile.id, policy);
    alert("Policy saved.");
  });
}
