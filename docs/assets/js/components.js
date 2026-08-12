import { escapeHtml, VERIFICATION, formatShiftDate } from "./brand.js";
import { currentRate, urgencyTier, urgencyColor, urgencyIcon, urgencyBadge } from "./shift-math.js";
import { icon } from "./lib/icons.js";

export { icon };

export function currency(value) {
  return `$${Math.round(Number(value) || 0).toLocaleString("en-US")}`;
}

export function verificationBadge(status, compact = false) {
  const v = VERIFICATION[status] || VERIFICATION.unverified;
  const glyph = ({
    verified: "checkCircle",
    pending: "clock",
    flagged: "warning",
    waitlisted: "clock",
    rejected: "xmarkCircle"
  })[status] || "xmarkCircle";

  return `<span class="verify-badge ${escapeHtml(status)}">
    ${icon(glyph, { size: 13 })}${compact ? "" : `<span>${escapeHtml(v.label)}</span>`}
  </span>`;
}

/**
 * The app's core list item. Mirrors `ShiftRow` in ContentView.swift: an
 * urgency-tinted icon tile, hospital name, "specialty · duration", then a
 * footer with the live rate, optional badges, and the date pushed right.
 */
export function shiftRow(shift, opts = {}) {
  const tier = urgencyTier(shift);
  const color = urgencyColor(tier);
  const rate = currency(currentRate(shift));
  const unit = shift.rateUnit === "per hour" ? "/hr" : "/day";
  const duration = shift.rateUnit === "per hour" ? `${shift.durationHours}h` : "Full day";
  const badge = urgencyBadge(tier);

  return `
    <article class="shift-row">
      <div class="shift-icon" style="background:${color}26;color:${color}">${icon(urgencyIcon(tier), { size: 20 })}</div>
      <div class="shift-body">
        <h3>${escapeHtml(shift.hospital)}</h3>
        <div class="shift-meta-line">${escapeHtml(shift.specialty)} · ${escapeHtml(duration)}</div>
        <div class="shift-bottom">
          <span class="rate-label" style="color:${color}">${icon("dollar", { size: 15 })}${rate}${unit}</span>
          ${opts.showLock ? `<span class="pill pill-quiet">${icon("lock", { size: 11 })} Rate locked</span>` : ""}
          ${badge ? `<span class="pill pill-solid" style="background:${color}">${badge}</span>` : ""}
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
      <span class="verify-banner-icon">${icon(flagged ? "warning" : "clock", { size: 22 })}</span>
      <div>
        <div class="verify-banner-title">${status === "pending" ? "Account Under Review" : "Verification Issue"}</div>
        <p class="subtitle">
          ${status === "pending"
            ? "Browse shifts freely. You can't accept until our team approves your credentials."
            : "There was an issue with your verification. Contact support."}
        </p>
        ${flags.length && flagged
          ? flags.map((f) => `<p class="subtitle">• ${escapeHtml(f)}</p>`).join("")
          : ""}
      </div>
    </section>`;
}

export function credentialStatusCard(profile) {
  const verified = profile?.verificationStatus === "verified";
  return `
    <section class="card cred-status">
      <span class="cred-status-icon ${verified ? "ok" : "wait"}">${icon(verified ? "checkCircle" : "clock", { size: 24 })}</span>
      <div style="flex:1;min-width:0">
        <div class="cred-status-title">${verified ? "Credentials Current" : "Verification In Progress"}</div>
        <div class="subtitle">${escapeHtml(VERIFICATION[profile?.verificationStatus || "unverified"]?.label || "Complete onboarding to verify")}</div>
      </div>
      ${profile ? verificationBadge(profile.verificationStatus, true) : ""}
    </section>`;
}

export function sectionHeader(title, iconName) {
  return `<div class="section-header">
    ${iconName ? `<span class="icon-wrap">${icon(iconName, { size: 14 })}</span>` : ""}
    <span>${escapeHtml(title)}</span>
  </div>`;
}

export function emptyState(title, subtitle, iconName = "moon", action) {
  return `
    <div class="empty-state card">
      <div class="empty-icon">${icon(iconName, { size: 28 })}</div>
      <div class="empty-title">${escapeHtml(title)}</div>
      <p class="subtitle">${escapeHtml(subtitle)}</p>
      ${action ? `<button type="button" class="btn-primary" data-action="${escapeHtml(action.action)}">${escapeHtml(action.label)}</button>` : ""}
    </div>`;
}

/**
 * Tappable summary tile from the hospital "At a glance" card. `hint` is the
 * quiet third line that tells the reader what window the number covers.
 */
export function statBadge({ value, label, hint, attrs = "" }) {
  return `
    <button type="button" class="stat-badge" ${attrs}>
      <span class="stat-value">${escapeHtml(String(value))}</span>
      <span class="stat-label">${escapeHtml(label)}</span>
      ${hint ? `<span class="stat-hint">${escapeHtml(hint)}</span>` : ""}
    </button>`;
}

export function sheet(title, body) {
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
      <button class="menu-btn" type="button" data-action="${menuAction}" aria-label="Menu">${icon("menu", { size: 22 })}</button>
    </header>`;
}

export function tabBar(tabs, active, badge = 0) {
  return `
    <nav class="tab-bar" aria-label="Main">
      ${tabs.map((t) => `
        <button type="button" class="${t.id === active ? "active" : ""}" data-tab="${t.id}">
          <span class="tab-icon">${icon(t.icon, { size: 22 })}</span>
          <span class="tab-label">${escapeHtml(t.label)}</span>
          ${t.id === "shifts" && badge > 0 ? `<span class="tab-badge">${badge}</span>` : ""}
        </button>`).join("")}
    </nav>`;
}

const AD_SLOTS = [
  { title: "LocumTenens.com", copy: "Fill critical gaps this weekend", cta: "Learn more", tint: "#4F8EF7", url: "https://www.locumtenens.com/" },
  { title: "MedMal Direct", copy: "Malpractice quotes for call docs", cta: "Get a quote", tint: "#34D399", url: "https://www.medmaldirect.com/" },
  { title: "Doximity", copy: "Network with physicians nationwide", cta: "Join free", tint: "#A78BFA", url: "https://www.doximity.com/" },
  { title: "CME List", copy: "Accredited CME that fits call weeks", cta: "Browse CME", tint: "#FBBF24", url: "https://www.cmelist.com/" }
];

/**
 * Real sponsored slot (click-out) or Google AdSense when configured.
 * Hidden for MD Shift+ members — pass `show: false` or use `shouldShowAds()`.
 */
export function adBanner(placement = "dashboard", opts = {}) {
  if (opts.show === false) return "";
  const cfg = window.ON_CALL_CONFIG || {};
  const client = cfg.adsenseClient || "";
  const slotId = cfg.adsenseBannerSlot || "";

  if (client && slotId && String(client).startsWith("ca-pub-")) {
    return `
      <aside class="ad-banner ad-banner-network" data-ad-placement="${escapeHtml(placement)}">
        <ins class="adsbygoogle"
             style="display:block;min-height:72px;width:100%"
             data-ad-client="${escapeHtml(client)}"
             data-ad-slot="${escapeHtml(slotId)}"
             data-ad-format="horizontal"
             data-full-width-responsive="true"></ins>
      </aside>`;
  }

  const index = [...placement].reduce((sum, ch) => sum + ch.charCodeAt(0), 0) % AD_SLOTS.length;
  const slot = AD_SLOTS[index];

  return `
    <a class="ad-banner" href="${escapeHtml(slot.url)}" target="_blank" rel="noopener sponsored"
       data-ad-placement="${escapeHtml(placement)}" aria-label="Sponsored: ${escapeHtml(slot.title)}">
      <span class="ad-icon" style="background:${slot.tint}26;color:${slot.tint}">${icon("megaphone", { size: 18 })}</span>
      <div class="ad-body">
        <div class="ad-head"><span class="ad-tag">Ad</span><span class="ad-title">${escapeHtml(slot.title)}</span></div>
        <div class="ad-copy">${escapeHtml(slot.copy)}</div>
      </div>
      <span class="ad-cta" style="background:${slot.tint}">${escapeHtml(slot.cta)}</span>
    </a>`;
}

/** Load AdSense once when client id is present. */
export function ensureAdsNetwork() {
  const cfg = window.ON_CALL_CONFIG || {};
  const client = cfg.adsenseClient || "";
  if (!client || !String(client).startsWith("ca-pub-")) return;
  if (document.querySelector(`script[data-mdshift-adsense="${client}"]`)) {
    try { (window.adsbygoogle = window.adsbygoogle || []).push({}); } catch { /* noop */ }
    return;
  }
  const s = document.createElement("script");
  s.async = true;
  s.crossOrigin = "anonymous";
  s.dataset.mdshiftAdsense = client;
  s.src = `https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${encodeURIComponent(client)}`;
  s.onload = () => {
    try { (window.adsbygoogle = window.adsbygoogle || []).push({}); } catch { /* noop */ }
  };
  document.head.appendChild(s);
}

/** Success confirmation matching iOS `ActionSuccessBanner`. */
export function successBanner(title, subtitle) {
  return `
    <div class="success-banner">
      ${icon("checkCircle", { size: 22 })}
      <div>
        <div class="success-title">${escapeHtml(title)}</div>
        ${subtitle ? `<div class="subtitle">${escapeHtml(subtitle)}</div>` : ""}
      </div>
    </div>`;
}
