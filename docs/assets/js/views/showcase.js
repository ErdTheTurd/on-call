import { escapeHtml, BRAND, brandLockup } from "../brand.js";
import { icon } from "../components.js";

const SHOTS = [
  { id: "doctor-home", label: "Doctor Home", blurb: "Assigned coverage at a glance" },
  { id: "open-shifts", label: "Open Shifts", blurb: "Claim open call with locked rates" },
  { id: "hospital-dash", label: "Hospital Dashboard", blurb: "Fill rate and gaps under control" },
  { id: "alter-rates", label: "Alter Rates", blurb: "Smart Algo or locked hospital rates" },
  { id: "approvals", label: "Approvals", blurb: "Verify doctors before they cover" },
  { id: "analytics", label: "Analytics", blurb: "Savings you can audit" }
];

function shotDoctorHome() {
  return `
    <div class="shot-grid">
      <div class="shot-card">
        <div class="shot-row">
          <div>
            <div class="shot-title">Good evening, Dr. Dunn</div>
            <div class="subtitle">2 shifts this week · Orthopedics</div>
          </div>
          ${icon("stethoscope")}
        </div>
        <div class="shot-metrics">
          <div><strong>3</strong><span>Tokens</span></div>
          <div><strong>2</strong><span>Assigned</span></div>
          <div><strong>1</strong><span>Trades</span></div>
        </div>
      </div>
      <div class="shot-card">
        <h3>Upcoming</h3>
        ${shiftLine("Fri", "Average Hospital", "$1,450", "Confirmed", "ok")}
        ${shiftLine("Sun", "Riverside General", "$1,650", "Confirmed", "ok")}
        ${shiftLine("Wed", "Average Hospital", "$1,450", "Trade pending", "warn")}
      </div>
    </div>`;
}

function shiftLine(day, place, rate, status, tone) {
  return `
    <div class="shot-shift">
      <div class="shot-day">${escapeHtml(day)}</div>
      <div class="shot-shift-body">
        <div class="shot-title">${escapeHtml(place)}</div>
        <div class="subtitle">${escapeHtml(rate)}</div>
      </div>
      <span class="shot-pill ${tone}">${escapeHtml(status)}</span>
    </div>`;
}

function shotOpenShifts() {
  return `
    <div class="shot-grid">
      <div class="shot-card">
        <div class="shot-kicker">Orthopedics · Locked rate</div>
        <div class="shot-title">Average Hospital</div>
        <div class="subtitle">Sat Sep 5 · 24h call</div>
        <div class="shot-row" style="margin-top:12px">
          <strong class="shot-rate">$1,850 / day</strong>
          <span class="shot-cta">Claim</span>
        </div>
      </div>
      <div class="shot-card">
        <div class="shot-kicker">Emergency · Smart Algo</div>
        <div class="shot-title">Riverside General</div>
        <div class="subtitle">Mon Sep 7 · 24h call</div>
        <div class="shot-row" style="margin-top:12px">
          <strong class="shot-rate">$1,620 / day</strong>
          <span class="shot-cta">Claim</span>
        </div>
      </div>
    </div>`;
}

function shotHospitalDash() {
  return `
    <div class="shot-grid">
      <div class="shot-metrics">
        <div><strong class="ok">94%</strong><span>Fill rate</span></div>
        <div><strong class="warn">3</strong><span>Open</span></div>
        <div><strong>5</strong><span>Pending</span></div>
      </div>
      <div class="shot-card">
        <h3>Tonight</h3>
        ${cov("Orthopedics", "Dr. Dunn", true)}
        ${cov("Emergency", "Dr. Ellison", true)}
        ${cov("Anesthesiology", "Unfilled", false)}
      </div>
    </div>`;
}

function cov(spec, who, filled) {
  return `
    <div class="shot-shift">
      <div class="shot-shift-body">
        <div class="shot-title">${escapeHtml(spec)}</div>
        <div class="subtitle">${escapeHtml(who)}</div>
      </div>
      <span class="shot-pill ${filled ? "ok" : "warn"}">${filled ? "Filled" : "Needs cover"}</span>
    </div>`;
}

function shotAlterRates() {
  return `
    <div class="shot-grid">
      <div class="shot-card">
        <div class="shot-title">Saturday · Orthopedics</div>
        <div class="shot-kicker">Smart Algo · $1,450 → $1,850</div>
        <div class="shot-bar"><span style="width:72%"></span></div>
        <p class="subtitle">Escalating as the shift approaches. Floor locked at hospital policy.</p>
      </div>
      <div class="shot-card">
        <div class="shot-title">Monday · Emergency</div>
        <div class="shot-kicker ok">Locked rate</div>
        <strong class="shot-rate">$1,600 / day</strong>
        <p class="subtitle">Hospital proprietary rate — no algo range, no ambiguity.</p>
      </div>
    </div>`;
}

function shotApprovals() {
  return `
    <div class="shot-grid">
      ${approval("Maya Ellison, MD", "Emergency Medicine · NPI 1487290365", "Waiting 2 days")}
      ${approval("Carlos Rivera, DO", "Orthopedics · NPI 1678934210", "Applied today")}
      ${approval("Riverside General", "Hospital · NPI 1902847365", "Waiting 1 day")}
    </div>`;
}

function approval(name, detail, wait) {
  return `
    <div class="shot-card">
      <div class="shot-row">
        <div>
          <div class="shot-title">${escapeHtml(name)}</div>
          <div class="subtitle">${escapeHtml(detail)}</div>
        </div>
        <span class="shot-pill warn">${escapeHtml(wait)}</span>
      </div>
      <div class="shot-actions">
        <span class="shot-cta ok">Approve</span>
        <span class="shot-cta quiet">Waitlist</span>
        <span class="shot-cta danger">Reject</span>
      </div>
    </div>`;
}

function shotAnalytics() {
  return `
    <div class="shot-grid">
      <div class="shot-metrics">
        <div><strong class="ok">$48,200</strong><span>Saved this month</span></div>
        <div><strong>$1,606</strong><span>Per day avg</span></div>
      </div>
      <div class="shot-card">
        <h3>Where it came from</h3>
        <div class="shot-money"><span>Early fills vs escalation</span><strong class="ok">$31,400</strong></div>
        <div class="shot-money"><span>Late cancel penalties</span><strong class="warn">$9,800</strong></div>
        <div class="shot-money"><span>Trade settlements</span><strong>$7,000</strong></div>
        <p class="subtitle" style="margin-top:10px">Every dollar is an auditable event.</p>
      </div>
    </div>`;
}

function renderShot(id) {
  switch (id) {
    case "doctor-home": return shotDoctorHome();
    case "open-shifts": return shotOpenShifts();
    case "hospital-dash": return shotHospitalDash();
    case "alter-rates": return shotAlterRates();
    case "approvals": return shotApprovals();
    case "analytics": return shotAnalytics();
    default: return shotDoctorHome();
  }
}

export function renderShowcase(state = {}) {
  const shot = state.shot || "doctor-home";
  const meta = SHOTS.find((s) => s.id === shot) || SHOTS[0];
  return `
    <div class="app-shell showcase-shell">
      <header class="showcase-top">
        <div class="site-brand">${brandLockup({ size: 24 })}</div>
        <div class="showcase-meta">
          <span class="pill">Screenshot kit</span>
          <button type="button" class="btn-ghost" data-showcase-signout>Sign out</button>
        </div>
      </header>
      <div class="showcase-chips">
        ${SHOTS.map((s) => `
          <button type="button" class="showcase-chip ${s.id === shot ? "active" : ""}" data-showcase-shot="${s.id}">
            ${escapeHtml(s.label)}
          </button>`).join("")}
      </div>
      <main class="main-scroll showcase-main">
        <div class="showcase-head">
          <h1>${escapeHtml(meta.label)}</h1>
          <p class="subtitle">${escapeHtml(meta.blurb)}</p>
        </div>
        ${renderShot(shot)}
        <p class="showcase-hint">
          App Store Connect needs <strong>1284 × 2778</strong> (or 1242 × 2688).
          Use the ready PNGs in <code>AppStoreScreenshots/</code> — do not upload a raw device screenshot from a newer Pro Max.
        </p>
      </main>
    </div>`;
}

export function bindShowcase(root, { onShot, onSignOut }) {
  root.querySelectorAll("[data-showcase-shot]").forEach((btn) => {
    btn.addEventListener("click", () => onShot?.(btn.dataset.showcaseShot));
  });
  root.querySelector("[data-showcase-signout]")?.addEventListener("click", () => onSignOut?.());
}
