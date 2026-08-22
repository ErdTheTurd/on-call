import { escapeHtml, SPECIALTIES, startOfDay, formatShiftDate } from "../brand.js";
import {
  navBar, tabBar, shiftRow, pendingBanner, sectionHeader, emptyState, sheet,
  verificationBadge, icon, statBadge, adBanner, currency, ensureAdsNetwork
} from "../components.js";
import { isPlusActive, startPlusCheckout, isMonetizationLive } from "../domain/plus.js";
import { renderPlusSheet } from "../domain/plus-ui.js";
import { getSavingsEvents, summarizeSavings } from "../domain/savings.js";
import { renderCalendar, hospitalDayData, addMonths } from "../calendar.js";
import { hospitalDaySummary, hospitalAnalytics, billingSummary } from "../domain/insights.js";
import { bracketLabel } from "../domain/policy.js";
import {
  getAlgoPrefs, setFactorEnabled, setFactorOverride, groupedCatalog, isFactorEnabled
} from "../domain/algo-prefs.js";
import {
  appStore, ensureDemoShifts, openShiftCount, fillRatePercent, signOut,
  autoApprovedCount, tokenRequestsForHospital, approveToken, denyToken,
  toggleUnavailable, getPolicy, savePolicy, defaultPolicy,
  getProposedRate, setProposedRate, resetProposedRate, toggleRosterAutoApprove,
  seedMockDoctors, getRateBreakdown, saveAlterShift, findShiftForDay,
  tokenLimitForDoctor, setDoctorTokenLimit
} from "../store.js";

function alterDraftKey(date, specialty) {
  const day = startOfDay(date || new Date(Date.now() + 86400000)).toISOString();
  return `${day}::${specialty || SPECIALTIES[0]}`;
}

function resolveAlterUseAlgo(state, existing) {
  if (state.alterUseAlgo != null) return !!state.alterUseAlgo;
  // null/undefined on the shift means "default to algorithm"
  return existing?.usesAlgorithmPricing !== false;
}

function resolveAlterUseFlat(state, existing) {
  if (state.alterUseFlat != null) return !!state.alterUseFlat;
  return existing?.escalationMode?.type === "flat";
}

/** Snapshot current editor values so switching specialty/day doesn't clobber them. */
function captureAlterDraft(state, profile) {
  const specialty = state.alterSpecialty || SPECIALTIES[0];
  const date = state.alterDate || new Date(Date.now() + 86400000).toISOString();
  const existing = profile ? findShiftForDay(profile.id, specialty, date) : null;
  return {
    useAlgo: resolveAlterUseAlgo(state, existing),
    rateFloor: state.alterRateFloor,
    useFlat: resolveAlterUseFlat(state, existing),
    flatRate: state.alterFlatRate
  };
}

function hydrateAlterEditor(drafts, profile, date, specialty) {
  const draft = drafts?.[alterDraftKey(date, specialty)];
  if (draft) {
    return {
      alterUseAlgo: draft.useAlgo,
      alterRateFloor: draft.rateFloor,
      alterUseFlat: draft.useFlat,
      alterFlatRate: draft.flatRate
    };
  }
  const existing = profile ? findShiftForDay(profile.id, specialty, date) : null;
  return {
    alterUseAlgo: existing ? existing.usesAlgorithmPricing !== false : true,
    alterRateFloor: null,
    alterUseFlat: existing?.escalationMode?.type === "flat",
    alterFlatRate: existing?.escalationMode?.type === "flat"
      ? Number(existing.escalationMode.rate)
      : null
  };
}

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
      ${tab === "doctors" ? renderDoctors(state, profile) : ""}
      ${tabBar([
        { id: "dashboard", label: "Home", icon: "dashboard" },
        { id: "alter", label: "Alter Shifts", icon: "calendar" },
        { id: "doctors", label: "Doctors", icon: "doctors" }
      ], tab)}
      ${state.sheet ? renderHospitalSheet(state, profile) : ""}
      ${state.daySheet ? renderHospitalDaySheet(state.daySheet, profile, state) : ""}
    </div>`;
}

function renderHospitalDashboard(state, profile) {
  const month = state.calendarMonth ? new Date(state.calendarMonth) : new Date();
  const days = profile ? hospitalDayData(month, profile.id) : [];
  const selected = state.selectedDate ? new Date(state.selectedDate) : null;
  const focusOpen = Boolean(state.focusOpenDays);
  const openDayCount = days.filter((d) => d.level !== "all" && d.level !== null && !d.isPast).length;

  // The detail panel would otherwise sit empty until a day is picked, so it
  // opens on today — the day a scheduler cares about most.
  const insightDate = selected || startOfDay(new Date());
  const insight = profile ? hospitalDaySummary(insightDate, profile.id) : null;
  const allPending = profile
    ? tokenRequestsForHospital(profile.id).filter((r) => r.status === "pending")
    : [];

  return `
    ${navBar(profile?.name || "Home")}
    <main class="main-scroll stack">
      ${profile && profile.verificationStatus !== "verified" ? pendingBanner(profile.verificationStatus, profile.verificationFlags) : ""}
      ${allPending.length ? `
        <section class="card stack pending-approvals-card">
          ${sectionHeader(`Approve coverage requests (${allPending.length})`, "checkCircle")}
          <p class="subtitle" style="margin:0">Doctors are waiting. Approve here, or open Schedule Admin from the menu.</p>
          <div class="pending-approvals-list">
            ${allPending.slice(0, 8).map((t) => `
              <div class="token-mini pending-approval-row">
                <div style="flex:1;min-width:0">
                  <div style="font-weight:600">${escapeHtml(t.doctorName || "Doctor")}</div>
                  <div class="subtitle">${escapeHtml(t.specialty || "")} · ${formatShiftDate(t.date)}${t.hospitalName ? ` · ${escapeHtml(t.hospitalName)}` : ""}</div>
                </div>
                <span class="row-actions">
                  <button type="button" class="approve" data-approve-token="${t.id}">Approve</button>
                  <button type="button" class="deny" data-deny-token="${t.id}">Deny</button>
                </span>
              </div>`).join("")}
          </div>
          ${allPending.length > 8 ? `<button type="button" class="btn-secondary" data-open-sheet="schedule">See all in Schedule Admin</button>` : ""}
        </section>` : ""}
      <section class="card stack">
        ${sectionHeader("At a glance")}
        <div class="stat-row">
          ${statBadge({
            value: `${profile ? fillRatePercent(profile.id) : 0}%`,
            label: "Fill rate",
            hint: "Last 30 days",
            attrs: 'data-open-sheet="analytics"'
          })}
          ${statBadge({
            value: allPending.length,
            label: "Pending",
            hint: "Need your OK",
            attrs: 'data-open-sheet="schedule"'
          })}
          ${statBadge({
            value: openDayCount,
            label: "Open days",
            hint: focusOpen ? "In focus" : "This month",
            attrs: 'data-nav-tab="alter"'
          })}
        </div>
      </section>
      <div class="content-grid two-col">
        <div class="stack">
          ${profile ? renderCalendar({
            month, days, selectedDate: selected, mode: "hospital", focusOpen,
            title: "Coverage calendar",
            subtitle: focusOpen
              ? "Open days only — filled coverage pops away so gaps stay obvious."
              : "See what's filled, then open a day to set rates or approve coverage.",
            hint: focusOpen ? "Open coverage gaps" : "Select a day for details"
          }) : ""}
        </div>
        <div class="stack">
          ${insight ? renderDayInsight(insight, profile, insightDate) : ""}
          ${adBanner("dashboard", { show: !isPlusActive() })}
        </div>
      </div>
    </main>`;
}

function coverageClass(level) {
  return ({ all: "cov-all", partial: "cov-partial", none: "cov-none" })[level] || "cov-none";
}

function renderDayInsight(summary, profile, date) {
  const rows = summary.coverageFillLevel === "partial"
    ? [...summary.hoverUnfilledRows, ...summary.hoverFilledRows, ...summary.hoverUnpostedRows]
    : summary.specialtyRows;

  return `
    <section class="card stack">
      <div style="display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap">
        <div>
          <div class="subtitle" style="font-weight:600">${date.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}</div>
          <div class="coverage-chip ${coverageClass(summary.coverageFillLevel)}">${summary.isBlocked ? "Unavailable" : summary.coverageFillLevel === "all" ? "Fully covered" : summary.coverageFillLevel === "partial" ? "Partial coverage" : "Open coverage"}</div>
        </div>
        <button type="button" class="chip ${summary.isBlocked ? "active" : ""}" data-toggle-unavail="${date.toISOString()}">
          ${summary.isBlocked ? "Unavailable" : "Mark unavailable"}
        </button>
      </div>
      ${summary.totalPaid ? `<div class="subtitle">Committed payouts this day: <strong style="color:var(--accent)">${currency(summary.totalPaid)}</strong></div>` : ""}
      <div class="specialty-day-list">
        ${rows.filter((r) => r.hasShiftPosted || r.tokenRequests.length || r.proposedRate != null).slice(0, 12).map((r) => `
          <div class="specialty-day-row">
            <div style="flex:1;min-width:0">
              <div style="font-weight:600">${escapeHtml(r.specialty)}</div>
              <div class="subtitle">
                ${r.isFilled
                  ? `On call: ${escapeHtml(r.onCallDoctorName || "Doctor")}${r.onCallCredential ? `, ${escapeHtml(r.onCallCredential)}` : ""} · ${currency(r.paymentAmount)}${escapeHtml(r.rateUnitLabel)}`
                  : r.hasShiftPosted
                    ? `Open · ${currency(r.goingRate || 0)}${escapeHtml(r.rateUnitLabel)}`
                    : `Proposed · ${currency(r.proposedRate || 0)}${escapeHtml(r.rateUnitLabel)}${r.isProposedRateCustom ? " (custom)" : ""}`}
              </div>
              ${r.tokenRequests.filter((t) => t.status === "pending").map((t) => `
                <div class="token-mini">
                  <span>${escapeHtml(t.doctorName)}</span>
                  <span class="row-actions">
                    <button type="button" class="approve" data-approve-token="${t.id}">Approve</button>
                    <button type="button" class="deny" data-deny-token="${t.id}">Deny</button>
                  </span>
                </div>`).join("")}
            </div>
            ${!r.isFilled ? `<button type="button" class="btn-ghost" data-edit-rate-specialty="${escapeHtml(r.specialty)}" data-edit-rate-date="${date.toISOString()}">Rate</button>` : ""}
          </div>`).join("") || `<p class="subtitle">No specialty activity on this day.</p>`}
      </div>
      <button type="button" class="btn-secondary" data-open-day="${date.toISOString()}">Open full day detail</button>
    </section>`;
}

function renderAlterShifts(state, profile) {
  if (!profile) return emptyState("No hospital", "Complete onboarding first.");

  const month = state.alterCalendarMonth
    ? new Date(state.alterCalendarMonth)
    : (state.calendarMonth ? new Date(state.calendarMonth) : new Date());
  const selected = state.alterDate
    ? startOfDay(state.alterDate)
    : startOfDay(new Date(Date.now() + 86400000));
  const specialty = state.alterSpecialty || SPECIALTIES[0];
  const days = hospitalDayData(month, profile.id);
  const policy = getPolicy(profile.id);
  const isHourly = policy.granularity === "hour";
  const unit = isHourly ? "/hr" : "/day";
  const baseRate = Number(policy.specialtyBaseRates?.[specialty] || 0);
  const minRate = Math.max(isHourly ? 80 : 800, baseRate);

  const existing = findShiftForDay(profile.id, specialty, selected);
  const useAlgorithm = resolveAlterUseAlgo(state, existing);
  const useFlat = resolveAlterUseFlat(state, existing);

  const breakdown = getRateBreakdown(specialty, selected, profile.id);
  const algoFloor = Math.max(breakdown.floor, baseRate);
  let rateFloor = state.alterRateFloor != null
    ? Number(state.alterRateFloor)
    : (useAlgorithm ? algoFloor : Math.max(existing?.rateFloor || algoFloor, minRate));
  if (useAlgorithm) rateFloor = algoFloor;

  const flatRate = state.alterFlatRate != null
    ? Number(state.alterFlatRate)
    : (existing?.escalationMode?.rate || Math.max(rateFloor, isHourly ? 200 : 2000));

  const savedFlash = !!state.alterSaved;

  return `
    ${navBar("Alter Shifts")}
    <main class="main-scroll stack">
      <div class="content-grid two-col">
        <section class="card stack">
          ${sectionHeader("Pick a Day", "calendar")}
          <p class="subtitle">Each day has an on-call shift. Select a day below to view or customize it.</p>
          ${renderCalendar({ month, days, selectedDate: selected, mode: "hospital" })}
        </section>

        <section class="card stack alter-editor">
          ${sectionHeader(selected.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" }), "dashboard")}
          <div class="form-field">
            <label>Specialty</label>
            <select data-alter-specialty>
              ${SPECIALTIES.map((sp) => `<option value="${escapeHtml(sp)}" ${sp === specialty ? "selected" : ""}>${escapeHtml(sp)}</option>`).join("")}
            </select>
          </div>

          <label class="toggle-row">
            <span>Use MD Shift pricing algorithm</span>
            <input type="checkbox" data-alter-algo ${useAlgorithm ? "checked" : ""} />
          </label>

          <div class="divider"></div>

          <div class="alter-rate-row">
            <span class="subtitle">${useAlgorithm ? "Algorithm rate floor" : "Manual rate floor"}</span>
            <strong class="alter-rate-value">${currency(rateFloor)}${unit}</strong>
          </div>

          ${useAlgorithm ? `
            <p class="tertiary" style="font-size:12px;margin:0">
              ${breakdown.variableCount || breakdown.components?.length || 0} pricing variables · ${Math.round((breakdown.confidence || 0) * 100)}% confidence
            </p>
            ${baseRate > 0 ? `<p class="tertiary" style="font-size:12px;margin:0">Floor capped at base rate: ${currency(baseRate)}${unit}</p>` : ""}
            <button type="button" class="btn-ghost" style="justify-self:start;padding-left:0" data-recalc-rate>↻ Recalculate</button>

            <div class="algo-breakdown">
              <div class="algo-breakdown-title">Algorithm variables</div>
              <p class="tertiary" style="font-size:12px;margin:0 0 8px">Toggle on/off. Drag a slider to fine-tune scale (0.1–2.0).</p>
              ${groupedCatalog().map(([category, items]) => `
                <div class="algo-cat">${escapeHtml(category)}</div>
                ${items.map((item) => {
                  const component = (breakdown.components || []).find((c) => c.id === item.id);
                  const on = isFactorEnabled(item.id);
                  const shown = on
                    ? (component?.multiplier ?? 1)
                    : 1;
                  const prefs = getAlgoPrefs();
                  const override = prefs.overrides?.[item.id];
                  return `
                    <div class="algo-factor-row ${on ? "" : "is-off"}">
                      <label class="algo-factor-toggle">
                        <input type="checkbox" data-algo-toggle="${escapeHtml(item.id)}" ${on ? "checked" : ""} />
                        <span>
                          <strong>${escapeHtml(item.label)}</strong>
                          <span class="tertiary">${on ? (component?.displayValue || shown.toFixed(3)) : "Off"}</span>
                        </span>
                      </label>
                      ${on ? `
                        <input type="range" min="0.1" max="2" step="0.05"
                          value="${(override ?? shown).toFixed(2)}"
                          data-algo-scale="${escapeHtml(item.id)}"
                          aria-label="Scale for ${escapeHtml(item.label)}" />
                      ` : ""}
                    </div>`;
                }).join("")}
              `).join("")}
            </div>
          ` : `
            <div class="form-field">
              <label>Manual rate floor</label>
              <div class="stepper-row">
                <button type="button" class="icon-btn" data-step-floor="-1">−</button>
                <input type="number" data-alter-floor value="${Math.round(rateFloor)}" step="${isHourly ? 5 : 50}" min="${minRate}" max="${isHourly ? 400 : 5000}" />
                <button type="button" class="icon-btn" data-step-floor="1">+</button>
              </div>
              ${baseRate > 0 ? `<p class="tertiary" style="font-size:12px">Minimum: ${currency(minRate)}${unit} (specialty base rate)</p>` : ""}
            </div>
          `}

          <div class="divider"></div>

          <label class="toggle-row">
            <span>Override with flat rate</span>
            <input type="checkbox" data-alter-flat ${useFlat ? "checked" : ""} />
          </label>
          ${useFlat ? `
            <div class="alter-rate-row">
              <span class="subtitle">Flat rate</span>
              <strong class="alter-rate-value">${currency(flatRate)}${unit}</strong>
            </div>
            <div class="form-field">
              <div class="stepper-row">
                <button type="button" class="icon-btn" data-step-flat="-1">−</button>
                <input type="number" data-alter-flat-rate value="${Math.round(flatRate)}" step="${isHourly ? 5 : 50}" min="${Math.round(rateFloor)}" max="${isHourly ? 600 : 8000}" />
                <button type="button" class="icon-btn" data-step-flat="1">+</button>
              </div>
            </div>
          ` : ""}

          <button type="button" class="btn-primary" data-save-alter-shift>
            ${savedFlash ? "✓ Saved!" : "Save Shift for This Day"}
          </button>
        </section>
      </div>
    </main>`;
}

/**
 * Per-doctor daily token allowance. Shows the hospital default until someone
 * changes it, so an untouched roster reads as one consistent rule rather than
 * a wall of identical overrides.
 */
function tokenStepper(hospitalID, doctor) {
  if (!hospitalID) return "";
  const policy = getPolicy(hospitalID);
  const override = policy.doctorTokenLimits?.[doctor.id];
  const isCustom = Number.isFinite(override);
  const value = isCustom ? override : (policy.defaultDailyTokens ?? 3);

  return `
    <div class="token-allowance ${isCustom ? "custom" : ""}">
      <span class="tertiary">Tokens/day</span>
      <div class="token-stepper">
        <button type="button" data-token-limit="${doctor.id}" data-delta="-1"
                aria-label="Fewer tokens for ${escapeHtml(doctor.name)}" ${value <= 0 ? "disabled" : ""}>−</button>
        <strong>${value}</strong>
        <button type="button" data-token-limit="${doctor.id}" data-delta="1"
                aria-label="More tokens for ${escapeHtml(doctor.name)}" ${value >= 20 ? "disabled" : ""}>+</button>
      </div>
      ${isCustom
        ? `<button type="button" class="token-reset" data-token-reset="${doctor.id}">Use default</button>`
        : `<span class="tertiary token-default">Default</span>`}
    </div>`;
}

function renderDoctors(state, profile) {
  const roster = appStore.roster;
  const filter = state.doctorFilter || "All";
  const autoOnly = !!state.doctorAutoOnly;
  const specialties = ["All", ...[...new Set(roster.map((d) => d.specialty))].sort()];
  const filtered = roster.filter((d) =>
    (filter === "All" || d.specialty === filter) && (!autoOnly || d.isAutoApproved)
  );

  return `
    ${navBar("Doctors")}
    <main class="main-scroll stack">
      <div class="page-header">
        <div>
          <h2>Roster</h2>
          <p class="muted">Filter candidates and manage auto-approve.</p>
        </div>
        <button type="button" class="btn-secondary" style="width:auto;min-width:180px" data-seed-mocks>Seed demo doctors</button>
      </div>
      ${adBanner("doctors", { show: !isPlusActive() })}
      <section class="card stack">
        <label class="switch-row spread">
          <span>Auto-approved only</span>
          <input type="checkbox" data-doctor-auto-only ${autoOnly ? "checked" : ""} />
          <span class="switch"></span>
        </label>
        <div class="chip-grid">
          ${specialties.map((sp) => `
            <button type="button" class="chip ${filter === sp ? "active" : ""}" data-doctor-filter="${escapeHtml(sp)}">${escapeHtml(sp)}</button>
          `).join("")}
        </div>
      </section>
      ${filtered.length ? `<div class="roster-grid">${filtered.map((d) => `
        <section class="card doctor-card">
          <button type="button" class="doctor-identity" data-doctor-detail="${d.id}">
            <span class="avatar">${escapeHtml((d.name.replace(/^Dr\.?\s*/i, "")[0] || "D").toUpperCase())}</span>
            <span class="doctor-lines">
              <span class="doctor-name">
                ${escapeHtml(d.name)}
                ${d.isAutoApproved ? `<span class="pill pill-solid" style="background:var(--success)">AUTO</span>` : ""}
              </span>
              <span class="doctor-meta">${escapeHtml(d.specialty)} · NPI ${escapeHtml(d.npi)}</span>
              ${verificationBadge(d.verificationStatus, true)}
            </span>
          </button>
          <div class="doctor-controls">
            ${tokenStepper(profile?.id, d)}
            <label class="switch-row">
              <span class="tertiary">Auto-approve</span>
              <input type="checkbox" data-roster-auto="${d.id}" ${d.isAutoApproved ? "checked" : ""} />
              <span class="switch"></span>
            </label>
          </div>
        </section>`).join("")}</div>`
        : emptyState(
            roster.length ? "No doctors match filters" : "No doctors on roster yet",
            roster.length
              ? "Clear filters or switch specialty to see more of your roster."
              : "Approved doctors appear here once they request coverage. Auto-approve trusted specialists to fill faster.",
            "stethoscope"
          )}
    </main>`;
}

function renderHospitalSheet(state, profile) {
  const kind = typeof state.sheet === "string" ? state.sheet : "menu";

  if (kind === "policy") return renderPolicySheet(profile, state);
  if (kind === "analytics") return renderAnalyticsSheet(profile);
  if (kind === "billing") return renderBillingSheet(profile);
  if (kind === "plus") return sheet("MD Shift+", renderPlusSheet("hospital"));
  if (kind === "schedule") return renderScheduleAdminSheet(profile, state);
  if (kind === "openshifts") return renderOpenShiftsSheet(profile);
  if (kind === "doctor-detail") return renderDoctorDetailSheet(state.doctorDetailId, profile);

  const plusActive = isPlusActive();
  const monetizationLive = isMonetizationLive();
  const pendingCount = profile
    ? tokenRequestsForHospital(profile.id).filter((r) => r.status === "pending").length
    : 0;
  const body = `
    ${profile ? `
      <div class="menu-profile">
        <div class="avatar square">${icon("hospital")}</div>
        <div style="min-width:0;flex:1">
          <div style="font-weight:600">${escapeHtml(profile.name)}</div>
          <div class="subtitle">${escapeHtml(appStore.session?.email || `NPI: ${profile.npi}`)}</div>
          ${verificationBadge(profile.verificationStatus)}
          ${monetizationLive && plusActive ? `<span class="plus-pill">${icon("sparkles", { size: 12 })} Plus</span>` : ""}
        </div>
        <button type="button" class="menu-signout" data-sign-out>Sign out</button>
      </div>` : ""}
    <ul class="menu-list">
      ${monetizationLive ? `
      <section><div class="section-label">MD Shift+</div>
        <button class="menu-item plus-menu-item" type="button" data-open-sheet="plus">
          ${icon("sparkles")}<span>${plusActive ? "Manage MD Shift+" : "Get MD Shift+"}
          <span class="menu-item-sub">${plusActive ? "Ad-free · priority posting" : "$9.99/mo · ad-free + perks"}</span></span>
        </button>
      </section>` : ""}
      <section><div class="section-label">Management</div>
        <button class="menu-item" type="button" data-open-sheet="schedule">${icon("checkCircle")}<span>Schedule Admin${pendingCount ? ` (${pendingCount})` : ""}
          <span class="menu-item-sub">Approve or deny doctor day requests</span></span></button>
        <button class="menu-item" type="button" data-open-sheet="openshifts">${icon("calendar")}<span>Open Shifts</span></button>
        <button class="menu-item" type="button" data-nav-tab="alter">${icon("clock")}<span>Alter Shifts</span></button>
        <button class="menu-item" type="button" data-open-sheet="policy">${icon("slider")}<span>Policy Settings</span></button>
        <button class="menu-item" type="button" data-open-sheet="analytics">${icon("chart")}<span>Analytics</span></button>
        <button class="menu-item" type="button" data-open-sheet="billing">${icon("card")}<span>Billing</span></button>
      </section>
      <section><div class="section-label">Account</div>
        <label class="menu-item toggle-row"><span>Priority posting</span>
          <input type="checkbox" data-hospital-flag="priorityPosting" ${profile?.priorityPosting ? "checked" : ""} /></label>
        <label class="menu-item toggle-row"><span>Auto-pay filled shifts</span>
          <input type="checkbox" data-hospital-flag="autoPay" ${profile?.autoPay ? "checked" : ""} /></label>
      </section>
      <section><div class="section-label">Support</div>
        <a class="menu-item" href="/support/" target="_blank" rel="noopener">${icon("envelope")}
          <span>Contact support<span class="menu-item-sub">mdshift.net/support</span></span>
        </a>
      </section>
    </ul>`;
  return sheet("Menu", body);
}

function renderScheduleAdminSheet(profile, state) {
  if (!profile) return sheet("Schedule", emptyState("No profile"));
  const filter = state.adminFilter || null;
  const search = (state.adminSearch || "").toLowerCase();
  const rows = tokenRequestsForHospital(profile.id);
  const filtered = rows.filter((r) => {
    const matchSearch = !search ||
      (r.doctorName || "").toLowerCase().includes(search) ||
      (r.specialty || "").toLowerCase().includes(search);
    const matchStatus = !filter ||
      (filter === "approved"
        ? (r.status === "approved" || r.status === "auto_approved")
        : r.status === filter);
    return matchSearch && matchStatus;
  });

  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <div class="stat-row">
        <button type="button" class="stat-badge ${filter === "pending" ? "selected" : ""}" data-admin-filter="pending">
          <div class="value">${rows.filter((r) => r.status === "pending").length}</div>
          <div class="label">Pending</div>
        </button>
        <button type="button" class="stat-badge ${filter === "approved" ? "selected" : ""}" data-admin-filter="approved">
          <div class="value">${rows.filter((r) => r.status === "approved" || r.status === "auto_approved").length}</div>
          <div class="label">Approved</div>
        </button>
        <button type="button" class="stat-badge ${filter === "denied" ? "selected" : ""}" data-admin-filter="denied">
          <div class="value">${rows.filter((r) => r.status === "denied").length}</div>
          <div class="label">Denied</div>
        </button>
      </div>
      <div class="search-field">
        <span>🔍</span>
        <input type="search" placeholder="Search doctor or specialty…" data-admin-search value="${escapeHtml(state.adminSearch || "")}" />
      </div>
      ${filtered.length ? filtered.map((r) => {
        const daysOut = (new Date(r.date) - Date.now()) / 86400000;
        const urgency = daysOut < 1 ? "var(--danger)" : daysOut < 4 ? "var(--warning)" : "var(--success)";
        const d = new Date(r.date);
        return `
          <section class="card schedule-card">
            <div class="schedule-date" style="color:${urgency};background:${urgency}18">
              <div class="mo">${d.toLocaleDateString(undefined, { month: "short" })}</div>
              <div class="day">${d.getDate()}</div>
              <div class="wd">${d.toLocaleDateString(undefined, { weekday: "short" })}</div>
            </div>
            <div style="flex:1;min-width:0">
              <div style="font-weight:600">${escapeHtml(r.doctorName || "Doctor")}, ${escapeHtml(r.credential || "MD")}</div>
              <div class="subtitle">${escapeHtml(r.specialty)}</div>
              <div class="tertiary" style="font-size:11px">Requested ${new Date(r.requestedAt).toLocaleString()}</div>
            </div>
            <div style="text-align:right">
              <div style="font-weight:700;color:var(--accent)">${currency(r.shiftRate || 0)}/day</div>
              <span class="verify-badge ${escapeHtml(r.status)}">${escapeHtml(r.status.replace("_", " "))}</span>
              ${r.status === "pending" ? `
                <div class="trade-actions" style="margin-top:8px">
                  <button type="button" class="approve" data-approve-token="${r.id}">Approve</button>
                  <button type="button" class="deny" data-deny-token="${r.id}">Deny</button>
                </div>` : ""}
            </div>
          </section>`;
      }).join("") : emptyState(rows.length ? "No matches" : "No token requests yet.", "Doctors appear here when they spend tokens to request call days.")}
    </main>`;
  return sheet("Schedule", body);
}

function renderPolicySheet(profile, state) {
  if (!profile) return sheet("Policy", emptyState("No profile"));
  const policy = getPolicy(profile.id);
  const tab = state.policyTab || "general";
  const scale = policy.cancellationPenaltyScale || defaultPolicy().cancellationPenaltyScale;

  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <div class="chip-grid">
        <button type="button" class="chip ${tab === "general" ? "active" : ""}" data-policy-tab="general">General</button>
        <button type="button" class="chip ${tab === "cancel" ? "active" : ""}" data-policy-tab="cancel">Cancellation</button>
        <button type="button" class="chip ${tab === "rates" ? "active" : ""}" data-policy-tab="rates">Pay Rates</button>
        <button type="button" class="chip ${tab === "tokens" ? "active" : ""}" data-policy-tab="tokens">Tokens</button>
      </div>
      ${tab === "general" ? `
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
          <div class="form-field"><label>Trade penalty ($)</label>
            <input type="number" data-policy="tradePenaltyAmount" value="${policy.tradePenaltyAmount}" /></div>
          <div class="form-field"><label>Trade penalty lead time (hours)</label>
            <input type="number" data-policy="tradePenaltyHoursBeforeStart" value="${policy.tradePenaltyHoursBeforeStart}" /></div>
        </section>` : ""}
      ${tab === "cancel" ? `
        <section class="card stack">
          ${sectionHeader("Cancellation brackets")}
          <p class="subtitle">Penalty = base × percent. Percent is a multiplier (1.0–5.0).</p>
          ${scale.map((b, i) => `
            <div class="bracket-row">
              <div class="form-field"><label>Hours before</label>
                <input type="number" data-bracket-hours="${i}" value="${b.hoursBeforeStart}" /></div>
              <div class="form-field"><label>Multiplier</label>
                <input type="number" step="0.1" data-bracket-pct="${i}" value="${b.penaltyPercent}" /></div>
              <button type="button" class="btn-ghost" style="color:var(--danger)" data-remove-bracket="${i}">Remove</button>
            </div>
            <div class="tertiary" style="font-size:12px">${escapeHtml(bracketLabel(b, i > 0 ? scale[i - 1].hoursBeforeStart : null))}</div>
          `).join("")}
          <button type="button" class="btn-secondary" data-add-bracket>Add bracket</button>
        </section>` : ""}
      ${tab === "rates" ? `
        <section class="card stack">
          ${sectionHeader("Specialty base rates")}
          ${SPECIALTIES.map((sp) => `
            <div class="form-field"><label>${escapeHtml(sp)}</label>
              <input type="number" data-specialty-rate="${escapeHtml(sp)}" value="${policy.specialtyBaseRates?.[sp] ?? 500}" /></div>
          `).join("")}
        </section>
        <section class="card stack">
          ${sectionHeader("Per-doctor overrides")}
          ${appStore.roster.length ? appStore.roster.map((d) => `
            <div class="form-field"><label>${escapeHtml(d.name)}</label>
              <input type="number" data-doctor-rate="${d.id}" value="${policy.doctorBaseRates?.[d.id] ?? ""}" placeholder="Specialty default" /></div>
          `).join("") : `<p class="subtitle">No doctors on roster yet.</p>`}
        </section>` : ""}
      ${tab === "tokens" ? `
        <section class="card stack">
          ${sectionHeader("Daily request tokens")}
          <p class="subtitle">A token is spent when a physician requests a call day.
            Everyone gets the roster default unless you set an exception below.</p>
          <div class="form-field"><label>Roster default (per day)</label>
            <input type="number" min="0" max="20" data-policy="defaultDailyTokens"
                   value="${policy.defaultDailyTokens ?? 3}" /></div>
        </section>
        <section class="card stack">
          ${sectionHeader("Per-doctor exceptions")}
          ${appStore.roster.length ? appStore.roster.map((d) => `
            <div class="form-field"><label>${escapeHtml(d.name)}<span class="tertiary"> · ${escapeHtml(d.specialty)}</span></label>
              <input type="number" min="0" max="20" data-doctor-tokens="${d.id}"
                     value="${Number.isFinite(policy.doctorTokenLimits?.[d.id]) ? policy.doctorTokenLimits[d.id] : ""}"
                     placeholder="Roster default (${policy.defaultDailyTokens ?? 3})" /></div>
          `).join("") : `<p class="subtitle">No doctors on roster yet.</p>`}
        </section>` : ""}
      <button type="button" class="btn-primary" data-save-policy>Save Policy</button>
    </main>`;
  return sheet("Policy Settings", body);
}

/**
 * Savings the hospital can audit: every dollar here is a logged event, not a
 * derived estimate, and the same rows are what MD Shift sees.
 */
function renderSavingsCard(profile) {
  const events = getSavingsEvents(profile?.id);
  const s = summarizeSavings(events);

  if (!s.events) {
    return `
      <section class="card stack">
        ${sectionHeader("Verified savings", "dollar")}
        <p class="subtitle" style="margin:0">
          Nothing tracked yet. Savings start accruing when doctors fill shifts early
          (locking the rate before it escalates) and when late cancellations are recovered.
        </p>
      </section>`;
  }

  return `
    <section class="card stack">
      ${sectionHeader("Verified savings", "dollar")}
      <div style="display:flex;justify-content:space-between;align-items:baseline;gap:12px">
        <span class="subtitle">Total saved${s.trackedSince ? ` since ${s.trackedSince.toLocaleDateString()}` : ""}</span>
        <span style="font-size:1.8rem;font-weight:700;color:var(--success)">${currency(s.total)}</span>
      </div>
      <div class="divider"></div>
      <div style="display:flex;justify-content:space-between;gap:12px;font-size:14px">
        <span>Escalation avoided by early fills</span>
        <strong style="color:var(--success)">${currency(s.rateSavings)}</strong>
      </div>
      <div style="display:flex;justify-content:space-between;gap:12px;font-size:14px">
        <span>Late cancel &amp; trade penalties recovered</span>
        <strong style="color:var(--warning)">${currency(s.penalties)}</strong>
      </div>
      <div style="display:flex;justify-content:space-between;gap:12px;font-size:14px">
        <span>Average per day</span>
        <strong>${currency(s.perDay)}</strong>
      </div>
      <p class="tertiary" style="font-size:12px;margin:0">
        Based on ${s.events} tracked event${s.events === 1 ? "" : "s"}.
      </p>
    </section>
    ${s.bySpecialty.length ? `
      <section class="card stack">
        ${sectionHeader("Saved by specialty")}
        ${s.bySpecialty.map(([sp, amt]) => `
          <div style="display:flex;justify-content:space-between;gap:12px;font-size:14px">
            <span>${escapeHtml(sp)}</span>
            <strong style="color:var(--success)">${currency(amt)}</strong>
          </div>`).join("")}
      </section>` : ""}`;
}

function renderAnalyticsSheet(profile) {
  const a = hospitalAnalytics(profile?.id);
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <section class="card analytics-grid">
        <div class="analytics-cell">
          <div class="label">Avg Traded '${a.yr}</div>
          <div class="value accent">${a.tradePercent.toFixed(1)}%</div>
        </div>
        <div class="analytics-cell">
          <div class="label">Avg Canceled '${a.yr}</div>
          <div class="value danger">${a.cancelPercent.toFixed(1)}%</div>
        </div>
        <div class="analytics-cell">
          <div class="label">Total Traded '${a.yr}</div>
          <div class="value accent large">${a.tradedCount}</div>
        </div>
        <div class="analytics-cell">
          <div class="label">Total Canceled '${a.yr}</div>
          <div class="value danger large">${a.canceledCount}</div>
        </div>
      </section>
      <div class="content-grid two-col">
        <section class="card stack">
          ${sectionHeader("Traded lead times")}
          <div class="bucket-row"><span>&lt; 1 mo</span><strong>${a.tradeBuckets[0]}</strong></div>
          <div class="bucket-row"><span>1–3 mo</span><strong>${a.tradeBuckets[1]}</strong></div>
          <div class="bucket-row"><span>&gt; 3 mo</span><strong>${a.tradeBuckets[2]}</strong></div>
        </section>
        <section class="card stack">
          ${sectionHeader("Canceled lead times")}
          <div class="bucket-row"><span>&lt; 1 mo</span><strong>${a.cancelBuckets[0]}</strong></div>
          <div class="bucket-row"><span>1–3 mo</span><strong>${a.cancelBuckets[1]}</strong></div>
          <div class="bucket-row"><span>&gt; 3 mo</span><strong>${a.cancelBuckets[2]}</strong></div>
        </section>
      </div>
      ${renderSavingsCard(profile)}
      <section class="card stat-row">
        <div class="stat-badge"><div class="value">${a.openShifts}</div><div class="label">Open</div></div>
        <div class="stat-badge"><div class="value">${a.fillRate}%</div><div class="label">Fill rate</div></div>
        <div class="stat-badge"><div class="value">${a.pendingTokens}</div><div class="label">Pending tokens</div></div>
      </section>
    </main>`;
  return sheet("Analytics", body);
}

function renderBillingSheet(profile) {
  const billing = billingSummary(profile?.id);
  const ledger = appStore.penaltyLedger.filter((p) => p.hospitalID === profile?.id);
  const totalPenalties = ledger.reduce((s, p) => s + Number(p.amount || 0), 0);
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <section class="card stack">
        ${sectionHeader("This Month")}
        <div style="display:flex;justify-content:space-between;align-items:baseline">
          <span class="subtitle">Committed payouts</span>
          <span style="font-size:1.8rem;font-weight:700;color:var(--accent)">$${billing.committedTotal.toLocaleString()}</span>
        </div>
        <p class="tertiary" style="font-size:12px">Based on filled shifts at current rates.</p>
      </section>
      <section class="card stack">
        ${sectionHeader("Recent Filled Shifts")}
        ${billing.filledShifts.length ? billing.filledShifts.slice(0, 8).map((s) => `
          <div style="display:flex;justify-content:space-between;gap:12px;font-size:14px">
            <div>
              <div style="font-weight:600">${formatShiftDate(s.start)}</div>
              <div class="subtitle">${escapeHtml(s.specialty)}</div>
            </div>
            <span style="font-weight:700;color:var(--accent)">${currency(s.rateUnit === "per hour" ? (s.rateFloor || 0) * (s.durationHours || 8) : (s.rateFloor || 0))}</span>
          </div>`).join('<div class="divider"></div>') : `<p class="subtitle">No filled shifts yet.</p>`}
      </section>
      <section class="card">
        <div class="subtitle">Penalty revenue collected</div>
        <div style="font-size:1.5rem;font-weight:700;color:var(--warning)">$${totalPenalties.toLocaleString()}</div>
      </section>
    </main>`;
  return sheet("Billing", body);
}

function renderOpenShiftsSheet(profile) {
  const open = appStore.shifts.filter((s) =>
    s.hospitalID === profile?.id &&
    !appStore.assignments.some((a) => a.shiftID === s.id && !["canceled", "traded_complete"].includes(a.status))
  ).slice(0, 20);
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      ${open.length ? open.map((s) => `<section class="card">${shiftRow(s)}</section>`).join("") : emptyState("No open shifts", "All posted shifts are filled.")}
    </main>`;
  return sheet("Open Shifts", body);
}

function renderDoctorDetailSheet(doctorId, profile) {
  const d = appStore.roster.find((x) => x.id === doctorId);
  if (!d) return sheet("Doctor", emptyState("Not found"));
  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <section class="card stack">
        <div style="font-size:1.3rem;font-weight:700">${escapeHtml(d.name)}</div>
        <div class="subtitle">${escapeHtml(d.credential)} · ${escapeHtml(d.specialty)}</div>
        ${verificationBadge(d.verificationStatus)}
        <div class="divider"></div>
        <div><span class="tertiary">NPI</span><div>${escapeHtml(d.npi)}</div></div>
        <label class="toggle-row">
          <span>Auto-approve token requests</span>
          <input type="checkbox" data-roster-auto="${d.id}" ${d.isAutoApproved ? "checked" : ""} />
        </label>
      </section>
      <section class="card stack">
        ${sectionHeader("Daily request tokens")}
        <p class="subtitle">How many call days ${escapeHtml(d.name)} can request per day.
          Give your most reliable physicians more, and new ones fewer.</p>
        ${tokenStepper(profile?.id, d)}
      </section>
    </main>`;
  return sheet(d.name, body);
}

function renderHospitalDaySheet(dateISO, profile, state) {
  if (!profile) return "";
  const date = new Date(dateISO);
  const summary = hospitalDaySummary(date, profile.id);
  const editSpecialty = state.rateEditSpecialty;
  const proposed = editSpecialty ? getProposedRate(profile.id, editSpecialty, date) : null;

  const body = `
    <main class="main-scroll stack" style="padding:16px">
      ${renderDayInsight(summary, profile, date)}
      ${editSpecialty && proposed ? `
        <section class="card stack">
          ${sectionHeader(`Edit rate · ${escapeHtml(editSpecialty)}`)}
          <div class="subtitle">Algorithm ${currency(proposed.algorithmRate)} · Current ${currency(proposed.rate)}</div>
          <div class="form-field"><label>Proposed rate</label>
            <input type="number" step="25" data-day-rate-value value="${Math.round(proposed.rate)}" /></div>
          <div style="display:flex;gap:8px">
            <button type="button" class="btn-primary" style="flex:1" data-save-day-rate data-specialty="${escapeHtml(editSpecialty)}" data-date="${date.toISOString()}">Save</button>
            <button type="button" class="btn-bordered" data-clear-rate-edit>Close</button>
          </div>
        </section>` : ""}
    </main>`;
  return sheet(date.toLocaleDateString(undefined, { month: "short", day: "numeric" }), body);
}

export function bindHospital(root, state, update) {
  const profile = appStore.hospitalProfile;

  root.querySelector("[data-action='menu']")?.addEventListener("click", () => update({ sheet: "menu" }));
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
  root.querySelectorAll("[data-tab], [data-nav-tab]").forEach((btn) => {
    btn.addEventListener("click", () => update({
      tab: btn.dataset.tab || btn.dataset.navTab,
      sheet: false,
      daySheet: null
    }));
  });
  root.querySelectorAll("[data-close-sheet]").forEach((el) => {
    el.addEventListener("click", (e) => {
      if (el.classList.contains("sheet-backdrop") && e.target !== el) return;
      update({ sheet: false, daySheet: null, rateEditSpecialty: null });
    });
  });
  root.querySelectorAll("[data-sheet-panel]").forEach((panel) => {
    panel.addEventListener("click", (e) => e.stopPropagation());
  });
  root.querySelectorAll("[data-sign-out]").forEach((btn) => {
    btn.addEventListener("click", () => { signOut(); update({ route: "landing" }); });
  });

  root.querySelectorAll("[data-cal-nav]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const m = (state.tab === "alter" && state.alterCalendarMonth)
        ? new Date(state.alterCalendarMonth)
        : (state.calendarMonth ? new Date(state.calendarMonth) : new Date());
      const next = addMonths(m, Number(btn.dataset.calNav)).toISOString();
      if ((state.tab || "dashboard") === "alter") {
        update({ alterCalendarMonth: next, calendarMonth: next });
      } else {
        update({ calendarMonth: next });
      }
    });
  });
  root.querySelectorAll("[data-focus-toggle]").forEach((el) => {
    el.addEventListener("change", () => update({ focusOpenDays: el.checked }));
  });
  root.querySelectorAll("[data-cal-date]").forEach((btn) => {
    btn.addEventListener("click", () => {
      if ((state.tab || "dashboard") === "alter") {
        const prevDate = state.alterDate || new Date(Date.now() + 86400000).toISOString();
        const specialty = state.alterSpecialty || SPECIALTIES[0];
        const drafts = { ...(state.alterDrafts || {}) };
        drafts[alterDraftKey(prevDate, specialty)] = captureAlterDraft(state, profile);
        const nextDate = btn.dataset.calDate;
        update({
          alterDate: nextDate,
          selectedDate: nextDate,
          alterDrafts: drafts,
          ...hydrateAlterEditor(drafts, profile, nextDate, specialty),
          alterSaved: false
        });
      } else {
        update({
          selectedDate: btn.dataset.calDate,
          daySheet: btn.dataset.calDate
        });
      }
    });
  });
  root.querySelectorAll("[data-open-day]").forEach((btn) => {
    btn.addEventListener("click", () => update({ daySheet: btn.dataset.openDay }));
  });

  root.querySelectorAll("[data-approve-token]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      await approveToken(btn.dataset.approveToken);
      update({ sheet: state.sheet || false });
    });
  });
  root.querySelectorAll("[data-deny-token]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      await denyToken(btn.dataset.denyToken);
      update({ sheet: state.sheet || false });
    });
  });

  root.querySelectorAll("[data-algo-toggle]").forEach((el) => {
    el.addEventListener("change", () => {
      setFactorEnabled(el.dataset.algoToggle, el.checked);
      update({ alterRateFloor: null, alterSaved: false });
    });
  });
  root.querySelectorAll("[data-algo-scale]").forEach((el) => {
    el.addEventListener("change", () => {
      setFactorOverride(el.dataset.algoScale, el.value);
      update({ alterRateFloor: null, alterSaved: false });
    });
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

  root.querySelectorAll("[data-token-limit]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      if (!profile) return;
      const doctorId = btn.dataset.tokenLimit;
      const current = tokenLimitForDoctor(profile.id, doctorId);
      await setDoctorTokenLimit(profile.id, doctorId, current + Number(btn.dataset.delta));
    });
  });

  root.querySelectorAll("[data-token-reset]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      if (!profile) return;
      await setDoctorTokenLimit(profile.id, btn.dataset.tokenReset, null);
    });
  });
  root.querySelector("[data-seed-mocks]")?.addEventListener("click", () => {
    seedMockDoctors();
  });

  root.querySelectorAll("[data-doctor-filter]").forEach((btn) => {
    btn.addEventListener("click", () => update({ doctorFilter: btn.dataset.doctorFilter }));
  });
  root.querySelector("[data-doctor-auto-only]")?.addEventListener("change", (e) => {
    update({ doctorAutoOnly: e.target.checked });
  });
  root.querySelectorAll("[data-doctor-detail]").forEach((btn) => {
    btn.addEventListener("click", () => update({ sheet: "doctor-detail", doctorDetailId: btn.dataset.doctorDetail }));
  });

  root.querySelectorAll("[data-admin-filter]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const next = state.adminFilter === btn.dataset.adminFilter ? null : btn.dataset.adminFilter;
      update({ adminFilter: next, sheet: "schedule" });
    });
  });
  root.querySelector("[data-admin-search]")?.addEventListener("input", (e) => {
    update({ adminSearch: e.target.value, sheet: "schedule" });
  });

  root.querySelectorAll("[data-policy-tab]").forEach((btn) => {
    btn.addEventListener("click", () => update({ policyTab: btn.dataset.policyTab, sheet: "policy" }));
  });

  root.querySelector("[data-alter-specialty]")?.addEventListener("change", (e) => {
    const date = state.alterDate || new Date(Date.now() + 86400000).toISOString();
    const prevSpecialty = state.alterSpecialty || SPECIALTIES[0];
    const nextSpecialty = e.target.value;
    const drafts = { ...(state.alterDrafts || {}) };
    drafts[alterDraftKey(date, prevSpecialty)] = captureAlterDraft(state, profile);
    update({
      alterSpecialty: nextSpecialty,
      alterDrafts: drafts,
      ...hydrateAlterEditor(drafts, profile, date, nextSpecialty),
      alterSaved: false
    });
  });
  root.querySelector("[data-alter-algo]")?.addEventListener("change", (e) => {
    update({ alterUseAlgo: e.target.checked, alterRateFloor: null, alterSaved: false });
  });
  root.querySelector("[data-alter-flat]")?.addEventListener("change", (e) => {
    update({ alterUseFlat: e.target.checked, alterSaved: false });
  });
  root.querySelector("[data-recalc-rate]")?.addEventListener("click", () => {
    update({ alterRateFloor: null, alterSaved: false });
  });
  root.querySelector("[data-alter-floor]")?.addEventListener("change", (e) => {
    update({ alterRateFloor: Number(e.target.value), alterSaved: false });
  });
  root.querySelector("[data-alter-flat-rate]")?.addEventListener("change", (e) => {
    update({ alterFlatRate: Number(e.target.value), alterSaved: false });
  });
  root.querySelectorAll("[data-step-floor]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const policy = getPolicy(profile.id);
      const isHourly = policy.granularity === "hour";
      const step = isHourly ? 5 : 50;
      const input = root.querySelector("[data-alter-floor]");
      const next = Number(input?.value || 0) + Number(btn.dataset.stepFloor) * step;
      update({ alterRateFloor: next, alterSaved: false });
    });
  });
  root.querySelectorAll("[data-step-flat]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const policy = getPolicy(profile.id);
      const isHourly = policy.granularity === "hour";
      const step = isHourly ? 5 : 50;
      const input = root.querySelector("[data-alter-flat-rate]");
      const next = Number(input?.value || 0) + Number(btn.dataset.stepFlat) * step;
      update({ alterFlatRate: next, alterSaved: false });
    });
  });
  root.querySelector("[data-save-alter-shift]")?.addEventListener("click", async () => {
    if (!profile) return;
    const specialty = state.alterSpecialty || SPECIALTIES[0];
    const date = state.alterDate || new Date(Date.now() + 86400000).toISOString();
    const existing = findShiftForDay(profile.id, specialty, date);
    const useAlgorithm = resolveAlterUseAlgo(state, existing);
    const useFlat = resolveAlterUseFlat(state, existing);
    const breakdown = getRateBreakdown(specialty, date, profile.id);
    const baseRate = Number(getPolicy(profile.id).specialtyBaseRates?.[specialty] || 0);
    const rateFloor = useAlgorithm
      ? Math.max(breakdown.floor, baseRate)
      : Number(root.querySelector("[data-alter-floor]")?.value || state.alterRateFloor || breakdown.floor);
    const flatRate = Number(root.querySelector("[data-alter-flat-rate]")?.value || state.alterFlatRate || rateFloor);
    await saveAlterShift({
      hospitalID: profile.id,
      hospitalName: profile.name,
      specialty,
      date,
      rateFloor,
      useAlgorithm,
      useFlatRate: useFlat,
      flatRate
    });
    const drafts = { ...(state.alterDrafts || {}) };
    drafts[alterDraftKey(date, specialty)] = {
      useAlgo: useAlgorithm,
      rateFloor,
      useFlat,
      flatRate
    };
    update({
      alterSaved: true,
      alterRateFloor: rateFloor,
      alterFlatRate: flatRate,
      alterUseAlgo: useAlgorithm,
      alterUseFlat: useFlat,
      alterDrafts: drafts
    });
    setTimeout(() => update({ alterSaved: false }), 1500);
  });

  root.querySelectorAll("[data-edit-rate-specialty]").forEach((btn) => {
    btn.addEventListener("click", () => update({
      daySheet: btn.dataset.editRateDate,
      rateEditSpecialty: btn.dataset.editRateSpecialty
    }));
  });
  root.querySelector("[data-clear-rate-edit]")?.addEventListener("click", () => {
    update({ rateEditSpecialty: null, daySheet: state.daySheet });
  });
  root.querySelector("[data-save-day-rate]")?.addEventListener("click", async () => {
    if (!profile) return;
    const btn = root.querySelector("[data-save-day-rate]");
    const rate = Number(root.querySelector("[data-day-rate-value]")?.value);
    await setProposedRate(profile.id, btn.dataset.specialty, btn.dataset.date, rate);
    update({ rateEditSpecialty: null, daySheet: state.daySheet });
  });

  root.querySelector("[data-add-bracket]")?.addEventListener("click", () => {
    if (!profile) return;
    const policy = { ...getPolicy(profile.id) };
    policy.cancellationPenaltyScale = [...(policy.cancellationPenaltyScale || []), { hoursBeforeStart: 48, penaltyPercent: 1.5 }];
    appStore.savePolicies({ ...appStore.policies, [profile.id]: policy });
    update({ sheet: "policy", policyTab: "cancel" });
  });
  root.querySelectorAll("[data-remove-bracket]").forEach((btn) => {
    btn.addEventListener("click", () => {
      if (!profile) return;
      const policy = { ...getPolicy(profile.id) };
      const scale = [...(policy.cancellationPenaltyScale || [])];
      scale.splice(Number(btn.dataset.removeBracket), 1);
      policy.cancellationPenaltyScale = scale;
      appStore.savePolicies({ ...appStore.policies, [profile.id]: policy });
      update({ sheet: "policy", policyTab: "cancel" });
    });
  });

  root.querySelectorAll("[data-hospital-flag]").forEach((el) => {
    el.addEventListener("change", () => {
      if (!profile) return;
      appStore.saveHospitalProfile({ ...profile, [el.dataset.hospitalFlag]: el.checked });
    });
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
    const scale = [...(policy.cancellationPenaltyScale || defaultPolicy().cancellationPenaltyScale)];
    root.querySelectorAll("[data-bracket-hours]").forEach((el) => {
      const i = Number(el.dataset.bracketHours);
      if (scale[i]) scale[i] = { ...scale[i], hoursBeforeStart: Number(el.value) };
    });
    root.querySelectorAll("[data-bracket-pct]").forEach((el) => {
      const i = Number(el.dataset.bracketPct);
      if (scale[i]) scale[i] = { ...scale[i], penaltyPercent: Number(el.value) };
    });
    policy.cancellationPenaltyScale = scale;
    policy.specialtyBaseRates = { ...(policy.specialtyBaseRates || {}) };
    root.querySelectorAll("[data-specialty-rate]").forEach((el) => {
      policy.specialtyBaseRates[el.dataset.specialtyRate] = Number(el.value);
    });
    policy.doctorBaseRates = { ...(policy.doctorBaseRates || {}) };
    root.querySelectorAll("[data-doctor-rate]").forEach((el) => {
      const v = el.value;
      if (v === "") delete policy.doctorBaseRates[el.dataset.doctorRate];
      else policy.doctorBaseRates[el.dataset.doctorRate] = Number(v);
    });
    policy.doctorTokenLimits = { ...(policy.doctorTokenLimits || {}) };
    root.querySelectorAll("[data-doctor-tokens]").forEach((el) => {
      const v = el.value.trim();
      if (v === "") delete policy.doctorTokenLimits[el.dataset.doctorTokens];
      else policy.doctorTokenLimits[el.dataset.doctorTokens] = Math.max(0, Math.min(20, Number(v)));
    });
    await savePolicy(profile.id, policy);
    alert("Policy saved.");
  });
}
