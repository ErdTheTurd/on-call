import { escapeHtml, VERIFICATION, formatShiftDate } from "./brand.js";
import { currentRate, urgencyTier, urgencyColor, urgencyIcon } from "./shift-math.js";

export function icon(name) {
  const map = {
    home: "⌂", shifts: "↻", credentials: "✓", dashboard: "▦", calendar: "📅",
    doctors: "👥", wand: "✦", stethoscope: "🩺", hospital: "🏥", menu: "☰",
    sparkles: "✨", lock: "🔒", moon: "🌙", flame: "🔥", envelope: "✉",
    globe: "🌐", chevron: "›", check: "✓", clock: "⏱", dollar: "$"
  };
  return map[name] || "•";
}

export function verificationBadge(status, compact = false) {
  const v = VERIFICATION[status] || VERIFICATION.unverified;
  return `<span class="verify-badge ${escapeHtml(status)}">${v.icon}${compact ? "" : ` ${escapeHtml(v.label)}`}</span>`;
}

export function shiftRow(shift, opts = {}) {
  const tier = urgencyTier(shift);
  const color = urgencyColor(tier);
  const rate = Math.round(currentRate(shift));
  const unit = shift.rateUnit === "per hour" ? "/hr" : "/day";
  const duration = shift.rateUnit === "per hour" ? `${shift.durationHours}h` : "Full day";
  return `
    <article class="shift-row">
      <div class="shift-icon" style="background:${color}22;color:${color}">${urgencyIcon(tier)}</div>
      <div style="min-width:0;flex:1">
        <h3>${escapeHtml(shift.hospital)}</h3>
        <div class="shift-meta-line">${escapeHtml(shift.specialty)} · ${escapeHtml(duration)}</div>
        <div class="shift-bottom">
          <span class="rate-label" style="color:${color}">${icon("dollar")}${rate}${unit}</span>
          ${opts.showLock ? `<span class="urgency-badge">Rate locked</span>` : ""}
          <span class="urgency-badge" style="color:${color}">${tier.charAt(0).toUpperCase() + tier.slice(1)}</span>
          <span class="date-label">${formatShiftDate(shift.start, shift.rateUnit !== "per hour")}</span>
        </div>
      </div>
    </article>`;
}

export function tokenBadge(tokens) {
  const dots = Array.from({ length: tokens.dailyLimit }, (_, i) =>
    `<span class="token-dot ${i < tokens.tokensRemaining ? "" : "empty"}"></span>`
  ).join("");
  return `<div class="token-badge">${dots}<span>${tokens.tokensRemaining}/${tokens.dailyLimit} tokens</span></div>`;
}

export function pendingBanner(status, flags = []) {
  const flagged = status === "flagged";
  return `
    <section class="card verify-banner ${flagged ? "flagged" : ""}">
      <div style="display:flex;gap:10px;align-items:flex-start">
        <span style="font-size:1.2rem;color:${flagged ? "var(--danger)" : "var(--warning)"}">${flagged ? "!" : "⏱"}</span>
        <div>
          <div style="font-weight:600">${status === "pending" ? "Account Under Review" : "Verification Issue"}</div>
          <div class="subtitle" style="font-size:12px;margin-top:2px">
            ${status === "pending"
              ? "Browse shifts freely. You can't accept until our team approves your credentials."
              : "There was an issue with your verification. Contact support."}
          </div>
          ${flags.length && flagged ? flags.map((f) => `<div class="subtitle" style="font-size:12px">• ${escapeHtml(f)}</div>`).join("") : ""}
        </div>
      </div>
    </section>`;
}

export function credentialStatusCard(profile) {
  const verified = profile?.verificationStatus === "verified";
  return `
    <section class="card" style="display:flex;gap:14px;align-items:center">
      <span style="font-size:1.4rem;color:${verified ? "var(--success)" : "var(--warning)"}">${verified ? "✓" : "⏱"}</span>
      <div style="flex:1">
        <div style="font-weight:600">${verified ? "Credentials Current" : "Verification In Progress"}</div>
        <div class="subtitle">${escapeHtml(VERIFICATION[profile?.verificationStatus || "unverified"]?.label || "Complete onboarding to verify")}</div>
      </div>
      ${profile ? verificationBadge(profile.verificationStatus, true) : ""}
    </section>`;
}

export function sectionHeader(title, iconName) {
  return `<div class="section-header">${iconName ? `<span class="icon-wrap">${icon(iconName)}</span>` : ""}<span>${escapeHtml(title)}</span></div>`;
}

export function emptyState(title, subtitle, iconName = "moon") {
  return `
    <div class="empty-state card">
      <div class="empty-icon">${icon(iconName)}</div>
      <div style="font-weight:600;margin-bottom:6px">${escapeHtml(title)}</div>
      <div class="subtitle">${escapeHtml(subtitle)}</div>
    </div>`;
}

export function sheet(title, body, onClose) {
  return `
    <div class="sheet-backdrop" data-close-sheet>
      <div class="sheet-panel" role="dialog" aria-modal="true" data-sheet-panel>
        <div class="sheet-header">
          <h2>${escapeHtml(title)}</h2>
          <button class="btn-ghost" type="button" data-close-sheet>Done</button>
        </div>
        ${body}
      </div>
    </div>`;
}

export function navBar(title, menuAction = "menu") {
  return `
    <header class="nav-bar">
      <h1>${escapeHtml(title)}</h1>
      <button class="menu-btn" type="button" data-action="${menuAction}" aria-label="Menu">${icon("menu")}</button>
    </header>`;
}

export function tabBar(tabs, active, badge = 0) {
  return `
    <nav class="tab-bar" aria-label="Main">
      ${tabs.map((t) => `
        <button type="button" class="${t.id === active ? "active" : ""}" data-tab="${t.id}">
          <span class="tab-icon">${icon(t.icon)}</span>
          <span>${escapeHtml(t.label)}</span>
          ${t.id === "shifts" && badge > 0 ? `<span class="tab-badge">${badge}</span>` : ""}
        </button>`).join("")}
    </nav>`;
}
