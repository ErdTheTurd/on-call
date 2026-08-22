import { escapeHtml, formatShiftDate, doctorSpecialty } from "../brand.js";
import {
  navBar, tabBar, shiftRow, tokenBadge, pendingBanner,
  credentialStatusCard, sectionHeader, emptyState, sheet, verificationBadge, icon, currency, adBanner, ensureAdsNetwork
} from "../components.js";
import { isPlusActive, startPlusCheckout, isMonetizationLive } from "../domain/plus.js";
import { renderPlusSheet } from "../domain/plus-ui.js";
import { renderCalendar, doctorDayData, addMonths } from "../calendar.js";
import { holidayOn, holidayPremiumMultiplier } from "../domain/pricing.js";
import { currentRate } from "../shift-math.js";
import {
  appStore, recommendedShifts, shiftsForDate, activeAssignments,
  pendingTradeCount, acceptShift, requestToken, cancelTokenRequest, ensureDemoShifts, signOut, demoHospital,
  cancelShift, requestTrade, respondTrade, counterTrade, counterAlternateDays, penaltyPreview, eligibleTradePartners,
  openShifts, canAcceptOnDay, requestStatusForDay, incomingTrades, earningsSummary, savePreferences
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
      ${state.tradeSheet ? renderTradeSheet(state.tradeSheet, state) : ""}
    </div>`;
}

function renderDoctorHome(state, profile) {
  const month = state.calendarMonth ? new Date(state.calendarMonth) : new Date();
  const days = doctorDayData(month, profile);
  const selected = state.selectedDate ? new Date(state.selectedDate) : null;
  const dayShifts = selected ? shiftsForDate(selected, profile) : [];
  const rec = recommendedShifts();
  const tokenReqs = (appStore.tokens.requestedDays || []).slice(0, 5);

  const specialty = doctorSpecialty(profile) || "Internal Medicine";
  const focusOpen = Boolean(state.focusOpenDays);

  return `
    ${navBar(profile ? `Dr. ${profile.lastName}` : "MD Shift")}
    <main class="main-scroll stack">
      ${profile && profile.verificationStatus !== "verified" ? pendingBanner(profile.verificationStatus, profile.verificationFlags) : ""}
      <div class="content-grid two-col">
        <div class="stack">
          <div class="token-row">
            ${tokenBadge(appStore.tokens)}
            <button type="button" class="btn-ghost" data-open-sheet="dashboard">Dashboard ${icon("chevron", { size: 14 })}</button>
          </div>
          ${renderCalendar({
            month, days, selectedDate: selected, mode: "doctor", focusOpen,
            hint: focusOpen ? "Open days only" : "Select a day to request call"
          })}
          ${selected ? `
            <section class="card stack">
              ${sectionHeader(selected.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" }), "calendar")}
              ${dayShifts.length
                ? dayShifts.map((s, i) => `${shiftRow(s)}${i < dayShifts.length - 1 ? '<div class="divider"></div>' : ""}`).join("")
                : `<p class="subtitle">${icon("moon", { size: 16 })} No open ${escapeHtml(specialty)} shifts</p>`}
              <button type="button" class="btn-primary" data-open-day="${selected.toISOString()}">
                ${dayShifts.length ? "Apply for this day" : "Request this day"}
              </button>
            </section>` : ""}
        </div>
        <div class="stack">
          <section class="card stack">
            ${sectionHeader("Recommended", "sparkles")}
            ${rec.length
              ? rec.map((s, i) => `${shiftRow(s)}${i < rec.length - 1 ? '<div class="divider"></div>' : ""}`).join("")
              : `<p class="subtitle">No open shifts in your specialty right now. Check back after hospitals post coverage.</p>`}
          </section>
          ${adBanner("doctor-home", { show: !isPlusActive() })}
          ${tokenReqs.length ? `
            <section class="card stack">
              ${sectionHeader("Requested Days")}
              ${tokenReqs.map((r) => `
                <div style="display:flex;justify-content:space-between;align-items:center;gap:12px;font-size:14px">
                  <span>${new Date(r.date).toLocaleDateString()} · ${escapeHtml(r.specialty)}</span>
                  <span class="verify-badge ${escapeHtml(r.status)}">${escapeHtml(statusLabel(r.status))}</span>
                </div>`).join("")}
              <button type="button" class="btn-ghost" data-open-sheet="requested" style="justify-self:start;padding-left:0">View all ›</button>
            </section>` : ""}
          ${credentialStatusCard(profile)}
        </div>
      </div>
    </main>`;
}

function statusLabel(status) {
  return ({
    pending: "Pending",
    approved: "Admin Approved",
    denied: "Denied",
    auto_approved: "Auto-Approved"
  })[status] || status;
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
            ${trades.map((t) => {
              const from = t.fromDoctorName || "A colleague";
              const theirs = t.offeredDate ? formatShiftDate(t.offeredDate) : null;
              const yours = t.requestedDate ? formatShiftDate(t.requestedDate) : null;
              const pay = Number(t.compensationAmount) || 0;
              const counterOpen = state.counterTradeId === t.id;
              const counterComp = Number(state.counterComp ?? pay);
              const altDays = counterOpen ? counterAlternateDays(t) : [];
              const selectedAlt = state.counterAltShiftId
                || altDays[0]?.shiftID
                || null;
              return `
              <div class="trade-card">
                <div class="trade-from">${escapeHtml(from)} wants to swap</div>
                ${theirs && yours ? `
                  <div class="trade-swap">
                    <span>They cover <strong>${escapeHtml(yours)}</strong></span>
                    <span>You cover <strong>${escapeHtml(theirs)}</strong></span>
                  </div>` : `<div class="subtitle">Shift trade request</div>`}
                ${pay > 0 ? `<div class="trade-pay">They offer you $${pay.toLocaleString()}</div>` : ""}
                <div class="trade-actions">
                  <button type="button" class="approve" data-respond-trade="${t.id}" data-accept="1">Accept</button>
                  <button type="button" class="counter" data-open-counter="${t.id}">Counter</button>
                  <button type="button" class="deny" data-respond-trade="${t.id}" data-accept="0">Decline</button>
                </div>
                ${counterOpen ? `
                  <div class="trade-counter-panel">
                    <div class="subtitle" style="font-weight:600;margin-bottom:6px">Offer a different day of yours</div>
                    ${altDays.length ? `
                      <div class="chip-grid" style="margin-bottom:10px">
                        ${altDays.map((a) => `
                          <button type="button" class="chip ${selectedAlt === a.shiftID ? "active" : ""}"
                                  data-counter-alt="${a.shiftID}">
                            ${escapeHtml(formatShiftDate(a.shift.start))}
                          </button>`).join("")}
                      </div>` : `<p class="subtitle" style="color:var(--danger)">No other scheduled days to counter with.</p>`}
                    <div class="counter-row">
                      <span class="subtitle" style="font-weight:600">Ask them for</span>
                      <strong style="color:var(--accent)">$${Math.round(counterComp).toLocaleString()}</strong>
                    </div>
                    <input type="range" min="0" max="1000" step="25"
                           value="${Math.round(counterComp)}"
                           data-counter-comp="${t.id}" />
                    <p class="subtitle" style="font-size:12px;margin:0">${
                      counterComp === pay
                        ? `Same as their $${pay.toLocaleString()} offer`
                        : counterComp > pay
                          ? `$${Math.round(counterComp - pay).toLocaleString()} more than they offered`
                          : `$${Math.round(pay - counterComp).toLocaleString()} less than they offered`
                    }</p>
                    <div class="trade-actions">
                      <button type="button" class="counter" data-send-counter="${t.id}" ${altDays.length ? "" : "disabled"}>Send counter</button>
                      <button type="button" class="deny" data-close-counter="${t.id}">Cancel</button>
                    </div>
                  </div>` : ""}
              </div>`;
            }).join("")}
          </div>
        </section>` : ""}
      ${active.length ? `<div class="roster-grid">${active.map((a) => {
        const cancelPrev = penaltyPreview("cancel", a);
        const tradePrev = penaltyPreview("trade", a);
        return `
        <section class="card stack" data-assignment="${a.id}">
          ${shiftRow(a.shift, { showLock: true })}
          <div class="subtitle">${formatShiftDate(a.shift.start)} · ${escapeHtml(a.doctorName)}</div>
          ${a.status === "traded_pending" ? `<span class="pill pill-quiet" style="color:var(--warning)">Trade pending approval</span>` : ""}
          <div class="trade-actions" style="margin-top:8px">
            <button type="button" class="deny" data-cancel-shift="${a.id}" ${cancelPrev.allowed ? "" : "disabled"}>
              Cancel${cancelPrev.penaltyAmount > 0 ? ` · ${currency(cancelPrev.penaltyAmount)} fee` : ""}
            </button>
            <button type="button" class="approve" data-trade-shift="${a.id}" ${tradePrev.allowed ? "" : "disabled"}>
              Trade
            </button>
          </div>
          ${!cancelPrev.allowed ? `<p class="subtitle" style="font-size:11px">${escapeHtml(cancelPrev.blockedReason)}</p>` : ""}
        </section>`;
      }).join("")}</div>` : emptyState("No assigned shifts", "Request a day with a token, get approval, then accept the shift.")}
    </main>`;
}

function renderCredentials(profile) {
  const prefs = appStore.doctorPrefs;
  const hospitals = [...new Set(appStore.shifts.map((s) => ({ id: s.hospitalID, name: s.hospital })))];
  const uniqueHospitals = [];
  const seen = new Set();
  for (const h of hospitals) {
    if (!seen.has(h.id)) { seen.add(h.id); uniqueHospitals.push(h); }
  }

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
                ${profile.deaNumber ? `<div class="divider"></div><div><span class="tertiary">DEA</span><div>${escapeHtml(profile.deaNumber)}</div></div>` : ""}
                <div class="divider"></div>
                <div><span class="tertiary">License</span><div>${escapeHtml(profile.licenseNumber)} · ${escapeHtml(profile.licenseState)}</div></div>
                <div class="divider"></div>
                <div><span class="tertiary">Specialty</span>
                  <div class="tag-row"><span class="tag">${escapeHtml((profile.specialties || [])[0] || "—")}</span></div>
                </div>
              </div>
            </section>
            <section class="card stack">
              <div class="row-spread">
                ${sectionHeader("Verification", "credentials")}
                ${verificationBadge(profile.verificationStatus)}
              </div>
              <p class="subtitle">Document uploads sync from the iOS app. Web upload support uses the same credential records.</p>
              ${(profile.documents || []).length ? profile.documents.map((d) => `
                <div class="list-row"><strong>${escapeHtml(d.type || "Document")}</strong><span class="muted">${escapeHtml(d.status || "uploaded")}</span></div>
              `).join("") : `<div class="empty-inline">No documents uploaded yet.</div>`}
            </section>
            <section class="card stack">
              ${sectionHeader("Account security", "lock")}
              <p class="subtitle" style="margin:0">
                Email verification uses a 6-digit code. Authenticator 2FA (Google Authenticator / Authy) is prompted after sign-in
                and required on later logins once enabled — same on web and iOS.
              </p>
            </section>
          </div>
          <section class="card stack">
            ${sectionHeader("Preferences")}
            <p class="subtitle" style="margin:0">Home only shows shifts in <strong>${escapeHtml((profile.specialties || [])[0] || "your specialty")}</strong>.</p>
            ${[
              ["notifyNewShifts", "New matching shifts"],
              ["notifyTradeRequests", "Incoming trade requests"],
              ["notifyApprovals", "Approvals & status updates"]
            ].map(([key, label]) => `
              <label class="switch-row spread">
                <span>${label}</span>
                <input type="checkbox" data-pref="${key}" ${prefs[key] ? "checked" : ""} />
                <span class="switch"></span>
              </label>`).join("")}
            ${uniqueHospitals.length ? `
              <div class="divider"></div>
              <div class="subtitle" style="font-weight:600">Hidden hospitals</div>
              <div class="chip-grid">
                ${uniqueHospitals.map((h) => `
                  <button type="button" class="chip ${(prefs.hiddenHospitalIDs || []).includes(h.id) ? "active" : ""}" data-hide-hospital="${h.id}">${escapeHtml(h.name)}</button>
                `).join("")}
              </div>` : ""}
          </section>
        </div>` : emptyState("No profile", "Complete onboarding to view credentials.")}
    </main>`;
}

function renderDoctorMenuSheet(sheetKind) {
  const profile = appStore.doctorProfile;
  const earnings = earningsSummary();
  const requested = appStore.tokens.requestedDays || [];

  if (sheetKind === "preferences") return renderPreferencesSheet();
  if (sheetKind === "requested") return renderRequestedSheet(requested);
  if (sheetKind === "earnings") return renderEarningsSheet(earnings);
  if (sheetKind === "history") return renderHistorySheet(earnings.history || []);
  if (sheetKind === "plus") return sheet("MD Shift+", renderPlusSheet("doctor"));

  const plusActive = isPlusActive();
  const monetizationLive = isMonetizationLive();
  const body = `
    <div class="menu-profile">
      <div class="avatar">${escapeHtml((profile?.firstName?.[0] || "") + (profile?.lastName?.[0] || ""))}</div>
      <div style="min-width:0;flex:1">
        <div style="font-weight:600">${escapeHtml(profile?.firstName || "")} ${escapeHtml(profile?.lastName || "")}${profile ? `, ${profile.credential}` : ""}</div>
        <div class="subtitle">${escapeHtml(appStore.session?.email || profile?.specialties?.[0] || "")}</div>
        ${profile ? verificationBadge(profile.verificationStatus) : ""}
        ${monetizationLive && plusActive ? `<span class="plus-pill">${icon("sparkles", { size: 12 })} Plus</span>` : ""}
      </div>
      <button type="button" class="menu-signout" data-sign-out>Sign out</button>
    </div>
    <ul class="menu-list">
      ${monetizationLive ? `
      <section><div class="section-label">MD Shift+</div>
        <button class="menu-item plus-menu-item" type="button" data-open-sheet="plus">
          ${icon("sparkles")}<span>${plusActive ? "Manage MD Shift+" : "Get MD Shift+"}
          <span class="menu-item-sub">${plusActive ? "Ad-free · extra tokens" : "$9.99/mo · ad-free + perks"}</span></span>
        </button>
      </section>` : ""}
      <section><div class="section-label">Earnings</div>
        <div class="card" style="margin:0 16px 8px;padding:14px">
          <div style="display:flex;justify-content:space-between">
            <span class="tertiary">Projected</span>
            <span style="font-weight:700;color:var(--success)">${currency(earnings.projected)}</span>
          </div>
          <div style="display:flex;justify-content:space-between;margin-top:6px;font-size:12px">
            <span class="tertiary">${earnings.activeCount} active shifts</span>
            <span class="tertiary">${earnings.completedCount} completed</span>
          </div>
        </div>
        <button class="menu-item" type="button" data-open-sheet="earnings">${icon("dollar")}<span>Earnings detail</span></button>
      </section>
      <section><div class="section-label">Schedule</div>
        <button class="menu-item" type="button" data-nav-tab="shifts">${icon("calendar")}<span>My Shifts</span></button>
        <button class="menu-item" type="button" data-open-sheet="requested">${icon("plus")}<span>Requested Days (${requested.length})</span></button>
        <button class="menu-item" type="button" data-open-sheet="history">${icon("clock")}<span>Shift History</span></button>
        <button class="menu-item" type="button" data-open-sheet="preferences">${icon("slider")}<span>Preferences</span></button>
        <button class="menu-item" type="button" data-nav-tab="credentials">${icon("person")}<span>My Info &amp; Documents</span></button>
      </section>
      <section><div class="section-label">Support</div>
        <a class="menu-item" href="/support/" target="_blank" rel="noopener">${icon("envelope")}
          <span>Contact support<span class="menu-item-sub">mdshift.net/support</span></span>
        </a>
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
        <label class="toggle-row"><span>Show only my specialty</span>
          <input type="checkbox" data-pref="showOnlyMySpecialties" checked disabled />
        </label>
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

function renderRequestedSheet(requested) {
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      ${requested.length ? requested.map((r) => `
        <section class="card" style="display:flex;justify-content:space-between;gap:12px;align-items:center">
          <div>
            <div style="font-weight:600">${new Date(r.date).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" })}</div>
            <div class="subtitle">${escapeHtml(r.hospitalName || "Hospital")} · ${escapeHtml(r.specialty)}</div>
            <span class="verify-badge ${escapeHtml(r.status)}">${escapeHtml(statusLabel(r.status))}</span>
          </div>
          ${r.status === "pending" ? `<button type="button" class="btn-ghost" style="color:var(--danger)" data-cancel-request="${r.id}">Cancel</button>` : ""}
        </section>`).join("") : emptyState("No requests", "Apply to a day from the home calendar to spend a token.")}
    </main>`;
  return sheet("Requested Days", body);
}

function renderEarningsSheet(earnings) {
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <section class="card stat-row">
        <div class="stat-badge"><div class="value">$${earnings.earned}</div><div class="label">Earned</div></div>
        <div class="stat-badge"><div class="value">${earnings.completedCount}</div><div class="label">Shifts</div></div>
        <div class="stat-badge"><div class="value">$${earnings.avgPerShift}</div><div class="label">Avg / shift</div></div>
      </section>
      <section class="card stack">
        ${sectionHeader("Projected")}
        <div style="font-size:1.6rem;font-weight:700;color:var(--success)">${currency(earnings.projected)}</div>
        <p class="subtitle">${earnings.activeCount} active assignments</p>
      </section>
      ${earnings.completed?.length ? `
        <section class="card stack">
          ${sectionHeader("Recent completed")}
          ${earnings.completed.slice(0, 8).map((a) => `
            <div style="display:flex;justify-content:space-between;gap:12px;font-size:14px">
              <span>${formatShiftDate(a.shift.start)} · ${escapeHtml(a.shift.specialty)}</span>
              <span style="color:var(--accent);font-weight:700">${currency(currentRate(a.shift))}</span>
            </div>`).join("")}
        </section>` : ""}
    </main>`;
  return sheet("Earnings", body);
}

function renderHistorySheet(history) {
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      ${history.length ? history.slice(0, 20).map((a) => `
        <section class="card" style="display:flex;justify-content:space-between;gap:12px">
          <div>
            <div style="font-weight:600">${formatShiftDate(a.shift.start)} · ${escapeHtml(a.shift.specialty)}</div>
            <div class="subtitle">${escapeHtml(a.shift.hospital)}</div>
          </div>
          <span class="verify-badge ${a.status === "canceled" ? "flagged" : "verified"}">${escapeHtml(a.status)}</span>
        </section>`).join("") : emptyState("No history", "Completed and canceled shifts appear here.")}
    </main>`;
  return sheet("Shift History", body);
}

function renderDaySheet(dateISO, profile) {
  const date = new Date(dateISO);
  const shifts = shiftsForDate(date, profile);
  const demo = demoHospital();
  const holiday = holidayOn(date.toISOString());
  const premium = holidayPremiumMultiplier(date.toISOString());
  const existing = profile ? requestStatusForDay(date, profile.id) : null;
  // Prefer the hospital on an open shift that day, then any open specialty shift, then demo.
  const hospitalHint = shifts[0]
    || openShifts(profile)[0]
    || { hospitalID: demo.id, hospital: demo.name, specialty: doctorSpecialty(profile) || "Internal Medicine" };
  const approved = profile && existing && canAcceptOnDay(date, existing.hospitalID || hospitalHint.hospitalID, profile.id);

  const body = `
    <main class="main-scroll stack" style="padding-bottom:24px">
      <section class="card" style="text-align:center">
        <div class="subtitle">${date.toLocaleDateString(undefined, { weekday: "long" })}</div>
        <div class="page-title" style="font-size:1.4rem">${date.toLocaleDateString(undefined, { month: "long", day: "numeric", year: "numeric" })}</div>
        ${holiday ? `<div class="holiday-pill">${escapeHtml(holiday.name)} — +${Math.round(holiday.premium * 100)}% premium</div>` : ""}
      </section>
      <div style="display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap">
        ${tokenBadge(appStore.tokens)}
        <span class="token-error tertiary" data-token-error></span>
      </div>
      ${existing ? `
        <section class="card" style="display:flex;align-items:center;gap:12px">
          <span style="font-size:1.4rem;color:var(--success)">✓</span>
          <div style="flex:1">
            <div style="font-weight:600">Request submitted</div>
            <div class="subtitle">${escapeHtml(statusLabel(existing.status))} · ${escapeHtml(existing.hospitalName || "")}</div>
          </div>
          ${existing.status === "pending" ? `<button type="button" class="btn-ghost" style="color:var(--danger)" data-cancel-request="${existing.id}">Cancel</button>` : ""}
        </section>` : ""}
      ${shifts.length ? shifts.map((s) => {
        const adjusted = Math.round(currentRate(s) * premium);
        const canAccept = approved && canAcceptOnDay(s.start, s.hospitalID, profile?.id);
        return `
        <section class="card stack">
          ${shiftRow(s)}
          <div style="display:flex;justify-content:space-between;align-items:flex-end;gap:12px;flex-wrap:wrap">
            <div>
              <div class="tertiary" style="font-size:12px">Est. earnings</div>
              <div class="money-lg">${currency(adjusted)}</div>
              ${premium > 1 ? `<div class="subtitle" style="font-size:11px;color:var(--warning)">Includes ${Math.round((premium - 1) * 100)}% holiday premium</div>` : ""}
            </div>
            ${existing
              ? (canAccept
                ? `<button type="button" class="btn-primary" style="width:auto;min-width:140px;padding:0 20px" data-accept-shift="${s.id}">Accept Shift</button>`
                : `<span class="subtitle">Day ${statusLabel(existing.status).toLowerCase()}</span>`)
              : `<button type="button" class="btn-primary" style="width:auto;min-width:120px;padding:0 20px" data-apply-shift="${s.id}" ${appStore.tokens.tokensRemaining === 0 ? "disabled" : ""}>Apply</button>`}
          </div>
        </section>`;
      }).join("") : `
        <section class="card empty-state">
          <div class="empty-icon">${icon("moon", { size: 28 })}</div>
          <div class="empty-title">No open shifts on this day</div>
          <p class="subtitle">You can still request call at ${escapeHtml(hospitalHint.hospital || hospitalHint.name || "the hospital")} — they may post later.</p>
          ${!existing ? `<button type="button" class="btn-primary" data-request-day
            data-hospital-id="${escapeHtml(hospitalHint.hospitalID)}"
            data-hospital-name="${escapeHtml(hospitalHint.hospital || hospitalHint.name || "")}"
            data-specialty="${escapeHtml(hospitalHint.specialty || doctorSpecialty(profile) || "")}"
            ${appStore.tokens.tokensRemaining === 0 ? "disabled" : ""}>Request This Day</button>` : ""}
        </section>`}
    </main>`;
  return sheet("Available Shifts", body);
}

function renderTradeSheet(assignmentId, state = {}) {
  const assignment = appStore.assignments.find((a) => a.id === assignmentId);
  if (!assignment) return "";
  const partners = eligibleTradePartners(assignment.shift.specialty, assignment.doctorID);
  const selectedPartner = state.tradePartnerId
    ? partners.find((d) => d.id === state.tradePartnerId)
    : null;
  const compensation = Number(state.tradeComp ?? 0);
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <p class="subtitle">Select a verified colleague to trade with:</p>
      ${partners.length ? partners.map((d) => `
        <button type="button" class="menu-item ${selectedPartner?.id === d.id ? "active" : ""}" data-select-trade-partner="${d.id}">
          <span>${escapeHtml(d.name)}, ${escapeHtml(d.credential)}</span>
          <span class="tertiary">${escapeHtml(d.specialty)}</span>
        </button>`).join("") : emptyState("No partners", "No verified doctors in this specialty on the roster.")}
      ${selectedPartner ? `
        <section class="card stack">
          <div class="counter-row">
            <span class="subtitle" style="font-weight:600">Compensation to them</span>
            <strong style="color:var(--accent)" data-trade-comp-label>$${Math.round(compensation).toLocaleString()}</strong>
          </div>
          <input type="range" min="0" max="1000" step="25" value="${Math.round(compensation)}" data-trade-comp />
          <button type="button" class="btn-primary" data-trade-to="${selectedPartner.id}" data-assignment="${assignmentId}">
            Send trade request
          </button>
        </section>` : ""}
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
    el.addEventListener("click", (e) => {
      if (el.classList.contains("sheet-backdrop") && e.target !== el) return;
      update({ sheet: false, daySheet: null, tradeSheet: null });
    });
  });
  root.querySelectorAll("[data-sheet-panel]").forEach((panel) => {
    panel.addEventListener("click", (e) => e.stopPropagation());
  });
  root.querySelectorAll("[data-sign-out]").forEach((btn) => {
    btn.addEventListener("click", () => { signOut(); update({ route: "landing" }); });
  });
  root.querySelectorAll("[data-open-sheet]").forEach((btn) => {
    btn.addEventListener("click", () => update({ sheet: btn.dataset.openSheet || true }));
  });
  root.querySelectorAll("[data-plus-checkout]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      btn.disabled = true;
      const res = await startPlusCheckout();
      if (!res.ok) {
        btn.disabled = false;
        alert(res.error || "Could not start checkout.");
      }
    });
  });
  ensureAdsNetwork();
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
  root.querySelectorAll("[data-focus-toggle]").forEach((el) => {
    el.addEventListener("change", () => update({ focusOpenDays: el.checked }));
  });
  root.querySelectorAll("[data-pref]").forEach((el) => {
    el.addEventListener("change", () => {
      savePreferences({ [el.dataset.pref]: el.checked });
    });
  });
  root.querySelectorAll("[data-hide-specialty]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const prefs = appStore.doctorPrefs;
      const set = new Set(prefs.hiddenSpecialties || []);
      const sp = btn.dataset.hideSpecialty;
      set.has(sp) ? set.delete(sp) : set.add(sp);
      savePreferences({ hiddenSpecialties: [...set] });
    });
  });
  root.querySelectorAll("[data-hide-hospital]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const prefs = appStore.doctorPrefs;
      const set = new Set(prefs.hiddenHospitalIDs || []);
      const id = btn.dataset.hideHospital;
      set.has(id) ? set.delete(id) : set.add(id);
      savePreferences({ hiddenHospitalIDs: [...set] });
    });
  });
  root.querySelectorAll("[data-apply-shift]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const shift = appStore.shifts.find((s) => s.id === btn.dataset.applyShift);
      const profile = appStore.doctorProfile;
      if (!shift || !profile) return;
      const res = await requestToken(
        shift.start,
        shift.hospitalID,
        shift.hospital,
        shift.specialty,
        profile,
        currentRate(shift)
      );
      const errEl = root.querySelector("[data-token-error]");
      if (!res.ok) {
        if (errEl) errEl.textContent = res.error;
        else alert(res.error);
      } else {
        update({ daySheet: state.daySheet });
      }
    });
  });
  root.querySelectorAll("[data-accept-shift]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const shift = appStore.shifts.find((s) => s.id === btn.dataset.acceptShift);
      const profile = appStore.doctorProfile;
      if (shift && profile) {
        const res = await acceptShift(shift, profile);
        if (!res.ok) alert(res.error);
        else update({ daySheet: null, tab: "shifts" });
      }
    });
  });
  root.querySelector("[data-request-day]")?.addEventListener("click", async () => {
    const profile = appStore.doctorProfile;
    const date = state.daySheet;
    if (!profile || !date) return;
    const btn = root.querySelector("[data-request-day]");
    const demo = demoHospital();
    const hospitalID = btn?.dataset.hospitalId || openShifts(profile)[0]?.hospitalID || demo.id;
    const hospitalName = btn?.dataset.hospitalName || openShifts(profile)[0]?.hospital || demo.name;
    const specialty = btn?.dataset.specialty || doctorSpecialty(profile) || "Internal Medicine";
    const res = await requestToken(date, hospitalID, hospitalName, specialty, profile);
    const errEl = root.querySelector("[data-token-error]");
    if (!res.ok) {
      if (errEl) errEl.textContent = res.error;
      else alert(res.error);
    } else update({ daySheet: state.daySheet });
  });
  root.querySelectorAll("[data-cancel-request]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const res = await cancelTokenRequest(btn.dataset.cancelRequest);
      if (!res.ok) alert(res.error);
      else update({ daySheet: state.daySheet, sheet: state.sheet });
    });
  });
  root.querySelectorAll("[data-cancel-shift]").forEach((btn) => {
    btn.addEventListener("click", async (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (btn.disabled) {
        const reason = btn.closest("section")?.querySelector(".subtitle")?.textContent;
        alert(reason || "Canceling is blocked this close to shift start.");
        return;
      }
      const a = appStore.assignments.find((x) => x.id === btn.dataset.cancelShift);
      if (!a) return;
      const feeHint = btn.textContent.includes("fee") ? `\n\n${btn.textContent.trim()}` : "";
      if (!window.confirm(`Cancel this shift?${feeHint}`)) return;
      const res = await cancelShift(a);
      if (!res.ok) alert(res.error || "Could not cancel.");
      else {
        if (res.penalty > 0) alert(`Canceled. Penalty: $${res.penalty}`);
        update({ tab: state.tab || "shifts" });
      }
    });
  });
  root.querySelectorAll("[data-trade-shift]").forEach((btn) => {
    btn.addEventListener("click", () => update({
      tradeSheet: btn.dataset.tradeShift,
      tradePartnerId: null,
      tradeComp: 0
    }));
  });
  root.querySelectorAll("[data-select-trade-partner]").forEach((btn) => {
    btn.addEventListener("click", () => update({ tradePartnerId: btn.dataset.selectTradePartner }));
  });
  root.querySelector("[data-trade-comp]")?.addEventListener("change", (e) => {
    update({ tradeComp: Number(e.target.value) || 0 });
  });
  // Live label without full re-render (avoids choppy slider).
  root.querySelector("[data-trade-comp]")?.addEventListener("input", (e) => {
    const label = root.querySelector("[data-trade-comp-label]");
    if (label) label.textContent = `$${Math.round(Number(e.target.value) || 0)}`;
  });
  root.querySelectorAll("[data-trade-to]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const assignment = appStore.assignments.find((a) => a.id === btn.dataset.assignment);
      const partner = appStore.roster.find((d) => d.id === btn.dataset.tradeTo);
      if (!assignment || !partner) return;
      const res = await requestTrade(assignment, partner, {
        compensationAmount: Number(state.tradeComp) || 0
      });
      if (!res.ok) alert(res.error);
      else update({ tradeSheet: null, tradePartnerId: null, tradeComp: 0 });
    });
  });
  root.querySelectorAll("[data-respond-trade]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const trade = incomingTrades().find((t) => t.id === btn.dataset.respondTrade);
      if (!trade) return;
      const accept = btn.dataset.accept === "1";
      await respondTrade(trade, accept);
      update({ counterTradeId: null, counterComp: null, counterAltShiftId: null });
    });
  });
  root.querySelectorAll("[data-open-counter]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const trade = incomingTrades().find((t) => t.id === btn.dataset.openCounter);
      if (!trade) return;
      const alts = counterAlternateDays(trade);
      if (!alts.length) {
        alert("No other scheduled days available to counter with.");
        return;
      }
      update({
        counterTradeId: trade.id,
        counterComp: Number(trade.compensationAmount) || 0,
        counterAltShiftId: alts[0].shiftID
      });
    });
  });
  root.querySelectorAll("[data-close-counter]").forEach((btn) => {
    btn.addEventListener("click", () => update({
      counterTradeId: null,
      counterComp: null,
      counterAltShiftId: null
    }));
  });
  root.querySelectorAll("[data-counter-alt]").forEach((btn) => {
    btn.addEventListener("click", () => update({ counterAltShiftId: btn.dataset.counterAlt }));
  });
  root.querySelectorAll("[data-counter-comp]").forEach((el) => {
    el.addEventListener("change", () => {
      update({ counterComp: Number(el.value) || 0 });
    });
    el.addEventListener("input", () => {
      const label = el.closest(".card, .stack, div")?.querySelector("strong");
      if (label) label.textContent = `$${Math.round(Number(el.value) || 0).toLocaleString()}`;
    });
  });
  root.querySelectorAll("[data-send-counter]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const trade = incomingTrades().find((t) => t.id === btn.dataset.sendCounter);
      if (!trade) return;
      const amount = Number(state.counterComp ?? trade.compensationAmount) || 0;
      const altId = state.counterAltShiftId;
      const alt = activeAssignments().find((a) => a.shiftID === altId) || counterAlternateDays(trade)[0];
      const res = await counterTrade(trade, amount, alt);
      if (!res.ok) alert(res.error || "Could not send counter");
      else update({ counterTradeId: null, counterComp: null, counterAltShiftId: null });
    });
  });
}
