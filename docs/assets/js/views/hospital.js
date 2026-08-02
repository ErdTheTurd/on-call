import { escapeHtml, SPECIALTIES, startOfDay, formatShiftDate } from "../brand.js";
import {
  navBar, tabBar, shiftRow, pendingBanner, sectionHeader, emptyState, sheet, verificationBadge, icon
} from "../components.js";
import { renderCalendar, hospitalDayData, addMonths } from "../calendar.js";
import { hospitalDaySummary, hospitalAnalytics, billingSummary } from "../domain/insights.js";
import { bracketLabel } from "../domain/policy.js";
import {
  appStore, ensureDemoShifts, openShiftCount, fillRatePercent, signOut,
  autoApprovedCount, tokenRequestsForHospital, approveToken, denyToken,
  toggleUnavailable, getPolicy, savePolicy, defaultPolicy,
  getProposedRate, setProposedRate, resetProposedRate, toggleRosterAutoApprove,
  seedMockDoctors, getRateBreakdown
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
      ${tab === "doctors" ? renderDoctors(state, profile) : ""}
      ${tabBar([
        { id: "dashboard", label: "Dashboard", icon: "dashboard" },
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
  const summary = selected && profile ? hospitalDaySummary(selected, profile.id) : null;

  return `
    ${navBar(profile?.name || "Dashboard")}
    <main class="main-scroll stack">
      ${profile && profile.verificationStatus !== "verified" ? pendingBanner(profile.verificationStatus, profile.verificationFlags) : ""}
      <div class="content-grid two-col">
        <div class="stack">
          ${profile ? renderCalendar({ month, days, selectedDate: selected, mode: "hospital" }) : ""}
          ${summary ? renderDayInsight(summary, profile, selected) : ""}
        </div>
        <div class="stack">
          <section class="card stat-row">
            <button type="button" class="stat-badge" data-open-sheet="openshifts">
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
            <button type="button" class="btn-secondary" data-open-sheet="schedule">Schedule admin</button>
            <button type="button" class="btn-secondary" data-nav-tab="alter">Alter shift rates</button>
            <button type="button" class="btn-secondary" data-open-sheet="policy">Scheduling policy</button>
            <button type="button" class="btn-secondary" data-open-sheet="analytics">Analytics</button>
            <button type="button" class="btn-secondary" data-open-sheet="billing">Billing</button>
          </section>
          ${summary && summary.pendingRequestCount ? `
            <section class="card stack">
              ${sectionHeader(`Pending tokens (${summary.pendingRequestCount})`)}
              <button type="button" class="btn-primary" data-open-sheet="schedule">Review in Schedule Admin</button>
            </section>` : ""}
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
      ${summary.totalPaid ? `<div class="subtitle">Committed payouts this day: <strong style="color:var(--accent)">$${Math.round(summary.totalPaid)}</strong></div>` : ""}
      <div class="specialty-day-list">
        ${rows.filter((r) => r.hasShiftPosted || r.tokenRequests.length || r.proposedRate != null).slice(0, 12).map((r) => `
          <div class="specialty-day-row">
            <div style="flex:1;min-width:0">
              <div style="font-weight:600">${escapeHtml(r.specialty)}</div>
              <div class="subtitle">
                ${r.isFilled
                  ? `On call: ${escapeHtml(r.onCallDoctorName || "Doctor")}${r.onCallCredential ? `, ${escapeHtml(r.onCallCredential)}` : ""} · $${Math.round(r.paymentAmount)}${escapeHtml(r.rateUnitLabel)}`
                  : r.hasShiftPosted
                    ? `Open · $${Math.round(r.goingRate || 0)}${escapeHtml(r.rateUnitLabel)}`
                    : `Proposed · $${Math.round(r.proposedRate || 0)}${escapeHtml(r.rateUnitLabel)}${r.isProposedRateCustom ? " (custom)" : ""}`}
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

  const editDate = state.alterDate ? new Date(state.alterDate) : startOfDay(new Date());
  const specialty = state.alterSpecialty || SPECIALTIES[0];
  const proposed = getProposedRate(profile.id, specialty, editDate);
  const unit = getPolicy(profile.id).granularity === "hour" ? "/hr" : "/day";
  const breakdown = getRateBreakdown(specialty, editDate, profile.id);
  const useAlgo = state.alterUseAlgo !== false;

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
            <label class="toggle-row">
              <span>Use algorithm pricing</span>
              <input type="checkbox" data-alter-algo ${useAlgo ? "checked" : ""} />
            </label>
          </section>
          <section class="card stack">
            ${sectionHeader("Rate Editor")}
            <div style="display:flex;justify-content:space-between;align-items:baseline">
              <span class="tertiary">Algorithm rate</span>
              <span style="font-weight:700;color:var(--accent)">$${Math.round(proposed.algorithmRate)}${unit}</span>
            </div>
            <div class="subtitle">Confidence ${Math.round((breakdown.confidence || 0) * 100)}%${breakdown.holidayName ? ` · ${escapeHtml(breakdown.holidayName)}` : ""}</div>
            <div class="form-field">
              <label>Proposed rate ${proposed.isCustom ? "(custom)" : ""}</label>
              <input type="number" step="25" data-alter-rate value="${Math.round(useAlgo && !proposed.isCustom ? proposed.algorithmRate : proposed.rate)}" ${useAlgo && !state.alterOverride ? "" : ""} />
            </div>
            <div style="display:flex;gap:8px;flex-wrap:wrap">
              <button type="button" class="btn-primary" style="flex:1;min-width:140px" data-save-rate>Save Rate</button>
              <button type="button" class="btn-bordered" data-reset-rate>Reset to algorithm</button>
            </div>
          </section>
          <section class="card stack">
            ${sectionHeader("Algorithm factors")}
            <div class="factor-list">
              ${(breakdown.components || []).slice(0, 12).map((c) => `
                <div class="factor-row">
                  <span>${escapeHtml(c.label)}</span>
                  <span style="font-weight:600;color:${c.mult >= 1 ? "var(--success)" : "var(--warning)"}">×${c.mult.toFixed(2)}</span>
                </div>`).join("")}
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
      <section class="card stack">
        <label class="toggle-row">
          <span>Auto-approved only</span>
          <input type="checkbox" data-doctor-auto-only ${autoOnly ? "checked" : ""} />
        </label>
        <div class="chip-grid">
          ${specialties.map((sp) => `
            <button type="button" class="chip ${filter === sp ? "active" : ""}" data-doctor-filter="${escapeHtml(sp)}">${escapeHtml(sp)}</button>
          `).join("")}
        </div>
      </section>
      ${filtered.length ? `<div class="roster-grid">${filtered.map((d) => `
        <section class="card" style="display:flex;align-items:center;gap:14px">
          <button type="button" class="btn-ghost" style="flex:1;min-width:0;text-align:left;padding:0" data-doctor-detail="${d.id}">
            <div style="font-weight:600;font-size:1.05rem">${escapeHtml(d.name)}</div>
            <div class="subtitle">${escapeHtml(d.specialty)} · NPI ${escapeHtml(d.npi)}</div>
            ${verificationBadge(d.verificationStatus, true)}
          </button>
          <label class="toggle-row" style="flex-direction:column;align-items:flex-end;gap:4px">
            <span style="font-size:11px" class="tertiary">Auto-approve</span>
            <input type="checkbox" data-roster-auto="${d.id}" ${d.isAutoApproved ? "checked" : ""} />
          </label>
        </section>`).join("")}</div>` : emptyState("Doctor roster", "No doctors match filters.", "doctors")}
    </main>`;
}

function renderHospitalSheet(state, profile) {
  const kind = typeof state.sheet === "string" ? state.sheet : "menu";

  if (kind === "policy") return renderPolicySheet(profile, state);
  if (kind === "analytics") return renderAnalyticsSheet(profile);
  if (kind === "billing") return renderBillingSheet(profile);
  if (kind === "schedule") return renderScheduleAdminSheet(profile, state);
  if (kind === "openshifts") return renderOpenShiftsSheet(profile);
  if (kind === "doctor-detail") return renderDoctorDetailSheet(state.doctorDetailId);

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
        <button class="menu-item" type="button" data-open-sheet="openshifts">${icon("calendar")}<span>Open Shifts</span></button>
        <button class="menu-item" type="button" data-nav-tab="alter">${icon("calendar")}<span>Alter Shifts</span></button>
        <button class="menu-item" type="button" data-open-sheet="schedule">${icon("dashboard")}<span>Schedule Admin</span></button>
        <button class="menu-item" type="button" data-open-sheet="policy">${icon("credentials")}<span>Policy Settings</span></button>
        <button class="menu-item" type="button" data-open-sheet="analytics">${icon("sparkles")}<span>Analytics</span></button>
        <button class="menu-item" type="button" data-open-sheet="billing">${icon("dollar")}<span>Billing</span></button>
      </section>
      <section><div class="section-label">Account</div>
        <label class="menu-item" style="cursor:default"><span>Priority posting</span>
          <input type="checkbox" data-hospital-flag="priorityPosting" ${profile?.priorityPosting ? "checked" : ""} /></label>
        <label class="menu-item" style="cursor:default"><span>Auto-pay filled shifts</span>
          <input type="checkbox" data-hospital-flag="autoPay" ${profile?.autoPay ? "checked" : ""} /></label>
        <button class="menu-item danger" type="button" data-sign-out>${icon("lock")}<span>Sign Out</span></button>
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
              <div style="font-weight:700;color:var(--accent)">$${Math.round(r.shiftRate || 0)}/day</div>
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
      <button type="button" class="btn-primary" data-save-policy>Save Policy</button>
    </main>`;
  return sheet("Policy Settings", body);
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
      <section class="card" style="display:flex;justify-content:space-between;align-items:center;gap:12px">
        <div>
          <div style="font-weight:600">Amount Saved per Day</div>
          <div class="subtitle">Penalty revenue recovered overall</div>
        </div>
        <div style="font-size:1.6rem;font-weight:700;color:var(--success)">$${Math.round(a.savingsPerDay)}</div>
      </section>
      <section class="card stack">
        ${sectionHeader("By Specialty")}
        ${a.specialtyRevenues.map(([sp, amt]) => `
          <div style="display:flex;justify-content:space-between;gap:12px;font-size:14px">
            <span>${escapeHtml(sp)}</span>
            <strong style="color:var(--success)">$${Math.round(amt)}/day</strong>
          </div>`).join("")}
      </section>
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
            <span style="font-weight:700;color:var(--accent)">$${Math.round(s.rateUnit === "per hour" ? (s.rateFloor || 0) * (s.durationHours || 8) : (s.rateFloor || 0))}</span>
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

function renderDoctorDetailSheet(doctorId) {
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
          <div class="subtitle">Algorithm $${Math.round(proposed.algorithmRate)} · Current $${Math.round(proposed.rate)}</div>
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
  root.querySelectorAll("[data-tab], [data-nav-tab]").forEach((btn) => {
    btn.addEventListener("click", () => update({
      tab: btn.dataset.tab || btn.dataset.navTab,
      sheet: false,
      daySheet: null
    }));
  });
  root.querySelectorAll("[data-close-sheet]").forEach((el) => {
    el.addEventListener("click", () => update({ sheet: false, daySheet: null, rateEditSpecialty: null }));
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
  root.querySelectorAll("[data-open-day]").forEach((btn) => {
    btn.addEventListener("click", () => update({ daySheet: btn.dataset.openDay }));
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

  root.querySelector("[data-alter-date]")?.addEventListener("change", (e) => {
    update({ alterDate: e.target.value, alterSpecialty: state.alterSpecialty });
  });
  root.querySelector("[data-alter-specialty]")?.addEventListener("change", (e) => {
    update({ alterSpecialty: e.target.value, alterDate: state.alterDate });
  });
  root.querySelector("[data-alter-algo]")?.addEventListener("change", (e) => {
    update({ alterUseAlgo: e.target.checked });
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
    await savePolicy(profile.id, policy);
    alert("Policy saved.");
  });
}
