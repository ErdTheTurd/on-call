import { escapeHtml, formatShiftDate, SPECIALTIES } from "../brand.js";
import {
  navBar, tabBar, shiftRow, pointsCard, tokenBadge, pendingBanner,
  credentialStatusCard, sectionHeader, emptyState, sheet, verificationBadge, icon
} from "../components.js";
import { renderCalendar, doctorDayData, addMonths } from "../calendar.js";
import {
  appStore, openShifts, recommendedShifts, shiftsForDate, activeAssignments,
  pendingTradeCount, acceptShift, requestToken, ensureDemoShifts, signOut, demoHospital,
  cancelShift, requestTrade, respondTrade, penaltyPreview, eligibleTradePartners,
  incomingTrades, earningsSummary, savePreferences, tokenRequestsForHospital
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
      ${tab === "shifts" ? renderMyShifts(state, profile) : ""}
      ${tab === "credentials" ? renderCredentials(profile) : ""}
      ${tabBar([
        { id: "home", label: "Home", icon: "home" },
        { id: "shifts", label: "My Shifts", icon: "shifts" },
        { id: "credentials", label: "Credentials", icon: "credentials" }
      ], tab, pendingTradeCount())}
      ${state.sheet ? renderDoctorMenuSheet(state.sheet) : ""}
      ${state.daySheet ? renderDaySheet(state.daySheet, profile) : ""}
      ${state.tradeSheet ? renderTradeSheet(state.tradeSheet) : ""}
    </div>`;
}

function renderDoctorHome(state, profile) {
  const month = state.calendarMonth ? new Date(state.calendarMonth) : new Date();
  const days = doctorDayData(month, profile);
  const selected = state.selectedDate ? new Date(state.selectedDate) : null;
  const dayShifts = selected ? shiftsForDate(selected, profile) : [];
  const rec = recommendedShifts();
  const tokenReqs = (appStore.tokens.requestedDays || []).slice(0, 5);

  return `
    ${navBar(profile ? `Dr. ${profile.lastName}` : "On‑Call")}
    <main class="main-scroll stack">
      ${profile && profile.verificationStatus !== "verified" ? pendingBanner(profile.verificationStatus, profile.verificationFlags) : ""}
      <div class="content-grid two-col">
        <div class="stack">
          ${pointsCard(appStore.points)}
          <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap">
            ${tokenBadge(appStore.tokens)}
            <button type="button" class="btn-ghost" data-open-sheet="dashboard">Dashboard ›</button>
          </div>
          ${renderCalendar({ month, days, selectedDate: selected, mode: "doctor" })}
          ${selected ? `
            <section class="card">
              <div class="subtitle" style="font-weight:600;margin-bottom:10px">${selected.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}</div>
              ${dayShifts.length ? dayShifts.map((s, i) => `${shiftRow(s)}${i < dayShifts.length - 1 ? '<div class="divider"></div>' : ""}`).join("") : `<div class="subtitle">${icon("moon")} No open shifts</div>`}
              ${dayShifts.length ? `<button type="button" class="btn-primary" style="margin-top:12px;width:100%" data-open-day="${selected.toISOString()}">Apply for this day</button>` : ""}
            </section>` : ""}
        </div>
        <div class="stack">
          <section class="card stack">
            ${sectionHeader("Recommended", "sparkles")}
            ${rec.length ? rec.map((s, i) => `${shiftRow(s)}${i < rec.length - 1 ? '<div class="divider"></div>' : ""}`).join("") : `<p class="subtitle">No open shifts right now.</p>`}
          </section>
          ${tokenReqs.length ? `
            <section class="card stack">
              ${sectionHeader("Requested Days")}
              ${tokenReqs.map((r) => `
                <div style="display:flex;justify-content:space-between;align-items:center;gap:12px;font-size:14px">
                  <span>${new Date(r.date).toLocaleDateString()} · ${escapeHtml(r.specialty)}</span>
                  <span class="verify-badge ${escapeHtml(r.status)}">${escapeHtml(r.status.replace("_", " "))}</span>
                </div>`).join("")}
            </section>` : ""}
          ${credentialStatusCard(profile)}
        </div>
      </div>
    </main>`;
}

function renderMyShifts(state, profile) {
  const active = activeAssignments();
  const trades = incomingTrades();

  return `
    ${navBar("My Shifts")}
    <main class="main-scroll stack">
      ${trades.length ? `
        <section class="card stack">
          ${sectionHeader("Incoming Trades", "shifts")}
          <div class="roster-grid">
            ${trades.map((t) => `
              <div class="trade-card">
                <div class="subtitle">Shift trade from colleague</div>
                <div class="trade-actions">
                  <button type="button" class="approve" data-respond-trade="${t.id}" data-accept="1">Accept</button>
                  <button type="button" class="deny" data-respond-trade="${t.id}" data-accept="0">Decline</button>
                </div>
              </div>`).join("")}
          </div>
        </section>` : ""}
      ${active.length ? `<div class="roster-grid">${active.map((a) => {
        const cancelPrev = penaltyPreview("cancel", a);
        const tradePrev = penaltyPreview("trade", a);
        return `
        <section class="card stack" data-assignment="${a.id}">
          ${shiftRow(a.shift, { showLock: true })}
          <div class="subtitle">${formatShiftDate(a.shift.start)} · ${escapeHtml(a.doctorName)}</div>
          ${a.status === "traded_pending" ? `<span class="urgency-badge" style="color:var(--warning)">Trade pending</span>` : ""}
          <div class="trade-actions" style="margin-top:8px">
            <button type="button" class="deny" data-cancel-shift="${a.id}" ${cancelPrev.allowed ? "" : "disabled"}>
              Cancel${cancelPrev.penaltyAmount > 0 ? ` ($${cancelPrev.penaltyAmount})` : ""}
            </button>
            <button type="button" class="approve" data-trade-shift="${a.id}" ${tradePrev.allowed ? "" : "disabled"}>
              Trade
            </button>
          </div>
          ${!cancelPrev.allowed ? `<p class="subtitle" style="font-size:11px">${escapeHtml(cancelPrev.blockedReason)}</p>` : ""}
        </section>`;
      }).join("")}</div>` : emptyState("No assigned shifts", "Accept shifts from the home calendar or recommended list.")}
    </main>`;
}

function renderCredentials(profile) {
  const prefs = appStore.doctorPrefs;
  return `
    ${navBar("Credentials")}
    <main class="main-scroll stack">
      ${profile ? `
        <div class="content-grid two-col">
          <div class="stack">
            <section class="card stack">
              ${sectionHeader("Identity")}
              <div style="display:grid;gap:12px;font-size:1rem">
                <div><span class="tertiary">Name</span><div>${escapeHtml(profile.firstName)} ${escapeHtml(profile.lastName)}, ${escapeHtml(profile.credential)}</div></div>
                <div class="divider"></div>
                <div><span class="tertiary">NPI</span><div>${escapeHtml(profile.npi)}</div></div>
                <div class="divider"></div>
                <div><span class="tertiary">License</span><div>${escapeHtml(profile.licenseNumber)} · ${escapeHtml(profile.licenseState)}</div></div>
                <div class="divider"></div>
                <div><span class="tertiary">Specialties</span><div>${(profile.specialties || []).map(escapeHtml).join(", ")}</div></div>
              </div>
            </section>
            <section class="card stack">
              ${sectionHeader("Verification", "credentials")}
              ${verificationBadge(profile.verificationStatus)}
              <p class="subtitle">Upload documents from the iOS app for full verification.</p>
            </section>
          </div>
          <section class="card stack">
            ${sectionHeader("Preferences")}
            <label class="toggle-row">
              <span>Only my specialties</span>
              <input type="checkbox" data-pref="showOnlyMySpecialties" ${prefs.showOnlyMySpecialties ? "checked" : ""} />
            </label>
            <label class="toggle-row">
              <span>Notify new shifts</span>
              <input type="checkbox" data-pref="notifyNewShifts" ${prefs.notifyNewShifts ? "checked" : ""} />
            </label>
            <label class="toggle-row">
              <span>Notify trade requests</span>
              <input type="checkbox" data-pref="notifyTradeRequests" ${prefs.notifyTradeRequests ? "checked" : ""} />
            </label>
            <label class="toggle-row">
              <span>Notify approvals</span>
              <input type="checkbox" data-pref="notifyApprovals" ${prefs.notifyApprovals ? "checked" : ""} />
            </label>
          </section>
        </div>` : emptyState("No profile", "Complete onboarding to view credentials.")}
    </main>`;
}

function renderDoctorMenuSheet(sheetKind) {
  const profile = appStore.doctorProfile;
  const earnings = earningsSummary();
  const history = appStore.assignments.filter((a) => a.status === "canceled" || a.status === "scheduled");
  const requested = appStore.tokens.requestedDays || [];

  if (sheetKind === "preferences") {
    return renderPreferencesSheet();
  }

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
      <section><div class="section-label">Earnings</div>
        <div class="card" style="margin:0 16px 8px;padding:14px">
          <div style="display:flex;justify-content:space-between">
            <span class="tertiary">Projected</span>
            <span style="font-weight:700;color:var(--success)">$${Math.round(earnings.projected).toLocaleString()}</span>
          </div>
          <div style="display:flex;justify-content:space-between;margin-top:6px;font-size:12px">
            <span class="tertiary">${earnings.activeCount} active shifts</span>
            <span class="tertiary">${earnings.completedCount} in history</span>
          </div>
        </div>
      </section>
      <section><div class="section-label">Rewards</div>
        <button class="menu-item" type="button">${icon("sparkles")}<span>Points · ${appStore.points.totalPoints} pts</span></button>
      </section>
      <section><div class="section-label">Schedule</div>
        <button class="menu-item" type="button" data-nav-tab="shifts">${icon("calendar")}<span>My Shifts</span></button>
        <button class="menu-item" type="button" data-open-sheet="preferences">${icon("credentials")}<span>Preferences</span></button>
      </section>
      ${requested.length ? `
        <section><div class="section-label">Requested Days (${requested.length})</div>
          ${requested.slice(0, 6).map((r) => `
            <div class="menu-item" style="cursor:default">
              <span>${new Date(r.date).toLocaleDateString()} · ${escapeHtml(r.hospitalName || "Hospital")}</span>
              <span class="verify-badge ${r.status}" style="margin-left:auto;font-size:11px">${r.status}</span>
            </div>`).join("")}
        </section>` : ""}
      ${history.length ? `
        <section><div class="section-label">History</div>
          ${history.slice(0, 5).map((a) => `
            <div class="menu-item" style="cursor:default;font-size:13px">
              <span>${formatShiftDate(a.shift.start)} · ${escapeHtml(a.shift.specialty)}</span>
              <span class="tertiary">${a.status}</span>
            </div>`).join("")}
        </section>` : ""}
      <section><div class="section-label">Account</div>
        <button class="menu-item danger" type="button" data-sign-out>${icon("lock")}<span>Sign Out</span></button>
      </section>
    </ul>`;
  return sheet("Dashboard", body);
}

function renderPreferencesSheet() {
  const prefs = appStore.doctorPrefs;
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <section class="card stack">
        ${sectionHeader("Shift Filters")}
        <label class="toggle-row"><span>Show only my specialties</span>
          <input type="checkbox" data-pref="showOnlyMySpecialties" ${prefs.showOnlyMySpecialties ? "checked" : ""} /></label>
      </section>
      <section class="card stack">
        ${sectionHeader("Notifications")}
        <label class="toggle-row"><span>New shifts</span>
          <input type="checkbox" data-pref="notifyNewShifts" ${prefs.notifyNewShifts ? "checked" : ""} /></label>
        <label class="toggle-row"><span>Trade requests</span>
          <input type="checkbox" data-pref="notifyTradeRequests" ${prefs.notifyTradeRequests ? "checked" : ""} /></label>
        <label class="toggle-row"><span>Token approvals</span>
          <input type="checkbox" data-pref="notifyApprovals" ${prefs.notifyApprovals ? "checked" : ""} /></label>
      </section>
    </main>`;
  return sheet("Preferences", body);
}

function renderDaySheet(dateISO, profile) {
  const date = new Date(dateISO);
  const shifts = shiftsForDate(date, profile);
  const demo = demoHospital();
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
          <button type="button" class="btn-primary" style="margin-top:12px" data-request-day>Request This Day (Token)</button>
        </section>`}
    </main>`;
  return sheet(date.toLocaleDateString(undefined, { month: "short", day: "numeric" }), body);
}

function renderTradeSheet(assignmentId) {
  const assignment = appStore.assignments.find((a) => a.id === assignmentId);
  if (!assignment) return "";
  const partners = eligibleTradePartners(assignment.shift.specialty, assignment.doctorID);
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <p class="subtitle">Select a verified colleague to trade with:</p>
      ${partners.length ? partners.map((d) => `
        <button type="button" class="menu-item" data-trade-to="${d.id}" data-assignment="${assignmentId}">
          <span>${escapeHtml(d.name)}, ${escapeHtml(d.credential)}</span>
          <span class="tertiary">${escapeHtml(d.specialty)}</span>
        </button>`).join("") : emptyState("No partners", "No verified doctors in this specialty on the roster.")}
    </main>`;
  return sheet("Request Trade", body);
}

export function bindDoctor(root, state, update) {
  root.querySelector("[data-action='menu']")?.addEventListener("click", () => update({ sheet: "dashboard" }));
  root.querySelectorAll("[data-tab]").forEach((btn) => {
    btn.addEventListener("click", () => update({ tab: btn.dataset.tab, sheet: false, daySheet: null, tradeSheet: null }));
  });
  root.querySelectorAll("[data-nav-tab]").forEach((btn) => {
    btn.addEventListener("click", () => update({ tab: btn.dataset.navTab, sheet: false }));
  });
  root.querySelectorAll("[data-close-sheet]").forEach((el) => {
    el.addEventListener("click", () => update({ sheet: false, daySheet: null, tradeSheet: null }));
  });
  root.querySelector("[data-sign-out]")?.addEventListener("click", () => { signOut(); update({ route: "auth" }); });
  root.querySelectorAll("[data-open-sheet]").forEach((btn) => {
    btn.addEventListener("click", () => update({ sheet: btn.dataset.openSheet || true }));
  });
  root.querySelectorAll("[data-open-day]").forEach((btn) => {
    btn.addEventListener("click", () => update({ daySheet: btn.dataset.openDay }));
  });
  root.querySelectorAll("[data-cal-nav]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const m = state.calendarMonth ? new Date(state.calendarMonth) : new Date();
      update({ calendarMonth: addMonths(m, Number(btn.dataset.calNav)).toISOString() });
    });
  });
  root.querySelectorAll("[data-cal-date]").forEach((btn) => {
    btn.addEventListener("click", () => update({ selectedDate: btn.dataset.calDate, daySheet: btn.dataset.calDate }));
  });
  root.querySelectorAll("[data-pref]").forEach((el) => {
    el.addEventListener("change", () => {
      savePreferences({ [el.dataset.pref]: el.checked });
    });
  });
  root.querySelectorAll("[data-accept-shift]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const shift = appStore.shifts.find((s) => s.id === btn.dataset.acceptShift);
      const profile = appStore.doctorProfile;
      if (shift && profile) {
        const res = await acceptShift(shift, profile);
        if (!res.ok) alert(res.error);
        else update({ daySheet: null });
      }
    });
  });
  root.querySelector("[data-request-day]")?.addEventListener("click", async () => {
    const profile = appStore.doctorProfile;
    const date = state.daySheet;
    const demo = demoHospital();
    const res = await requestToken(
      date,
      demo.id,
      demo.name,
      profile?.specialties?.[0] || "Internal Medicine",
      profile
    );
    if (!res.ok) alert(res.error);
    else update({ daySheet: null });
  });
  root.querySelectorAll("[data-cancel-shift]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const a = appStore.assignments.find((x) => x.id === btn.dataset.cancelShift);
      if (!a || !confirm("Cancel this shift?")) return;
      const res = await cancelShift(a);
      if (!res.ok) alert(res.error);
      else if (res.penalty > 0) alert(`Canceled. Penalty: $${res.penalty}`);
    });
  });
  root.querySelectorAll("[data-trade-shift]").forEach((btn) => {
    btn.addEventListener("click", () => update({ tradeSheet: btn.dataset.tradeShift }));
  });
  root.querySelectorAll("[data-trade-to]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const assignment = appStore.assignments.find((a) => a.id === btn.dataset.assignment);
      const partner = appStore.roster.find((d) => d.id === btn.dataset.tradeTo);
      if (!assignment || !partner) return;
      const res = await requestTrade(assignment, partner);
      if (!res.ok) alert(res.error);
      else update({ tradeSheet: null });
    });
  });
  root.querySelectorAll("[data-respond-trade]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const trade = incomingTrades().find((t) => t.id === btn.dataset.respondTrade);
      if (!trade) return;
      const accept = btn.dataset.accept === "1";
      await respondTrade(trade, accept);
    });
  });
}
