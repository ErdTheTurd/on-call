import { escapeHtml } from "../brand.js";
import { navBar, emptyState, verificationBadge, icon } from "../components.js";

/** Anything that still needs a human decision, whatever route it arrived by. */
const NEEDS_REVIEW = new Set(["pending", "flagged", "unverified"]);

const FILTERS = [
  { id: "review", label: "Needs review" },
  { id: "verified", label: "Approved" },
  { id: "waitlisted", label: "Waitlisted" },
  { id: "rejected", label: "Rejected" }
];

const KINDS = [
  { id: "all", label: "Everyone" },
  { id: "doctor", label: "Doctors" },
  { id: "hospital", label: "Hospitals" }
];

const SECTIONS = [
  { id: "approvals", label: "Approvals" },
  { id: "savings", label: "Hospital savings" }
];

function matchesFilter(app, filter) {
  if (filter === "review") return NEEDS_REVIEW.has(app.status);
  return app.status === filter;
}

function countFor(items, filter) {
  return items.filter((a) => matchesFilter(a, filter)).length;
}

function daysWaiting(submittedAt) {
  if (!submittedAt) return null;
  const days = Math.floor((Date.now() - new Date(submittedAt)) / 86400000);
  return Number.isFinite(days) && days >= 0 ? days : null;
}

function waitingLabel(app) {
  const days = daysWaiting(app.submittedAt);
  if (days === null) return "Submitted date unknown";
  if (days === 0) return "Applied today";
  if (days === 1) return "Waiting 1 day";
  return `Waiting ${days} days`;
}

function decidedLabel(app) {
  if (!app.reviewedAt) return "";
  return `Decided ${new Date(app.reviewedAt).toLocaleDateString(undefined, { month: "short", day: "numeric" })}`;
}

function applicationCard(app, admin) {
  const busy = admin.busyKey === app.key;
  const confirming = admin.confirmKey === app.key;
  const needsReview = NEEDS_REVIEW.has(app.status);
  const title = app.kind === "doctor" && app.credential
    ? `${app.name}, ${app.credential}`
    : app.name;

  return `
    <section class="card approval-card">
      <div class="approval-head">
        <span class="approval-kind" aria-hidden>${icon(app.kind === "doctor" ? "stethoscope" : "hospital")}</span>
        <div class="approval-identity">
          <h3>${escapeHtml(title)}</h3>
          <div class="subtitle">${escapeHtml(app.detail || (app.kind === "doctor" ? "Doctor" : "Hospital"))}</div>
        </div>
        ${verificationBadge(app.status)}
      </div>

      <dl class="approval-facts">
        <div><dt>Email</dt><dd>${escapeHtml(app.email || "Not provided")}</dd></div>
        <div><dt>NPI</dt><dd>${escapeHtml(app.npi || "Not provided")}</dd></div>
        <div><dt>Status</dt><dd>${escapeHtml(needsReview ? waitingLabel(app) : decidedLabel(app) || waitingLabel(app))}</dd></div>
      </dl>

      ${app.flags?.length ? `
        <ul class="approval-flags">
          ${app.flags.map((f) => `<li>${escapeHtml(f)}</li>`).join("")}
        </ul>` : ""}

      ${confirming ? `
        <div class="approval-confirm">
          <p>Reject ${escapeHtml(app.name)}? They lose access until someone reopens the application.</p>
          <div class="approval-actions">
            <button type="button" class="reject" data-decide="rejected" data-key="${escapeHtml(app.key)}" ${busy ? "disabled" : ""}>Yes, reject</button>
            <button type="button" class="quiet" data-cancel-confirm ${busy ? "disabled" : ""}>Keep in review</button>
          </div>
        </div>`
      : needsReview ? `
        <div class="approval-actions">
          <button type="button" class="approve" data-decide="verified" data-key="${escapeHtml(app.key)}" ${busy ? "disabled" : ""}>
            ${busy ? `<span class="spinner"></span>` : "Approve"}
          </button>
          <button type="button" class="waitlist" data-decide="waitlisted" data-key="${escapeHtml(app.key)}" ${busy ? "disabled" : ""}>Waitlist</button>
          <button type="button" class="quiet" data-confirm-reject data-key="${escapeHtml(app.key)}" ${busy ? "disabled" : ""}>Reject</button>
        </div>`
      : `
        <div class="approval-actions">
          <button type="button" class="quiet" data-decide="pending" data-key="${escapeHtml(app.key)}" ${busy ? "disabled" : ""}>
            ${busy ? `<span class="spinner"></span>` : "Move back to review"}
          </button>
        </div>`}
    </section>`;
}

function currency(value) {
  return `$${Math.round(Number(value) || 0).toLocaleString("en-US")}`;
}

/**
 * Savings roll-up across every hospital. Rows come straight from
 * `hospital_savings_events`, so what an admin sees here is exactly what the
 * hospital sees on its own dashboard.
 */
function renderSavingsSection(admin) {
  const savings = admin.savings || {};
  if (savings.loading) {
    return `<div class="approval-loading"><span class="spinner"></span><p class="subtitle">Loading savings…</p></div>`;
  }
  if (savings.error) {
    return `
      <section class="card">
        <div style="font-weight:600;margin-bottom:6px">Couldn't load savings</div>
        <p class="subtitle">${escapeHtml(savings.error)}</p>
        <button type="button" class="btn-secondary" style="margin-top:12px" data-savings-retry>Try again</button>
      </section>`;
  }

  const rows = savings.rows || [];
  if (!rows.length) {
    return emptyState(
      "No savings tracked yet",
      "Hospitals appear here once doctors fill shifts early or late cancellations are recovered.",
      "check"
    );
  }

  const totals = rows.reduce((acc, r) => ({
    total: acc.total + r.total,
    penalties: acc.penalties + r.penalties,
    rateSavings: acc.rateSavings + r.rateSavings,
    events: acc.events + r.events
  }), { total: 0, penalties: 0, rateSavings: 0, events: 0 });

  return `
    <section class="card analytics-grid">
      <div class="analytics-cell">
        <div class="label">Total saved</div>
        <div class="value accent large">${currency(totals.total)}</div>
      </div>
      <div class="analytics-cell">
        <div class="label">Hospitals saving</div>
        <div class="value large">${rows.length}</div>
      </div>
      <div class="analytics-cell">
        <div class="label">Escalation avoided</div>
        <div class="value accent">${currency(totals.rateSavings)}</div>
      </div>
      <div class="analytics-cell">
        <div class="label">Penalties recovered</div>
        <div class="value">${currency(totals.penalties)}</div>
      </div>
    </section>
    ${rows.map((r) => `
      <section class="card savings-row">
        <div style="min-width:0;flex:1">
          <div style="font-weight:600">${escapeHtml(r.hospitalName)}</div>
          <div class="subtitle">
            ${currency(r.rateSavings)} early-fill · ${currency(r.penalties)} recovered · ${r.events} event${r.events === 1 ? "" : "s"}
          </div>
          ${r.lastAt ? `<div class="tertiary" style="font-size:11px">Last ${new Date(r.lastAt).toLocaleDateString()}</div>` : ""}
        </div>
        <div style="text-align:right">
          <div style="font-size:1.35rem;font-weight:700;color:var(--success)">${currency(r.total)}</div>
          <div class="tertiary" style="font-size:11px">saved</div>
        </div>
      </section>`).join("")}`;
}

export function renderAdminApp(admin) {
  const section = admin.section || "approvals";
  const filter = admin.filter || "review";
  const kind = admin.kind || "all";
  const search = (admin.search || "").trim().toLowerCase();

  const items = admin.items || [];
  const visible = items.filter((app) => {
    if (!matchesFilter(app, filter)) return false;
    if (kind !== "all" && app.kind !== kind) return false;
    if (!search) return true;
    return `${app.name} ${app.email} ${app.npi} ${app.detail}`.toLowerCase().includes(search);
  });

  let body;
  if (admin.loading) {
    body = `<div class="approval-loading"><span class="spinner"></span><p class="subtitle">Loading applications…</p></div>`;
  } else if (admin.error) {
    body = `
      <section class="card">
        <div style="font-weight:600;margin-bottom:6px">Couldn't load applications</div>
        <p class="subtitle">${escapeHtml(admin.error)}</p>
        <button type="button" class="btn-secondary" style="margin-top:12px" data-admin-retry>Try again</button>
      </section>`;
  } else if (!visible.length) {
    body = items.length
      ? emptyState("Nothing here", "No applications match this filter.", "check")
      : emptyState("Queue is clear", "New doctor and hospital applications land here the moment they finish onboarding.", "check");
  } else {
    body = visible.map((app) => applicationCard(app, admin)).join("");
  }

  return `
    <div class="app-shell">
      <div class="bg-gradient"><div class="blob-bottom"></div></div>
      ${navBar(section === "savings" ? "Savings" : "Approvals", "admin-menu")}
      <main class="main-scroll stack" style="padding:0 var(--page-pad) 40px">
        ${admin.toast ? `<div class="approval-toast">${icon("check")} ${escapeHtml(admin.toast)}</div>` : ""}

        <div class="chip-grid">
          ${SECTIONS.map((s) => `
            <button type="button" class="chip ${section === s.id ? "active" : ""}" data-admin-section="${s.id}">${escapeHtml(s.label)}</button>`).join("")}
        </div>

        ${section === "savings" ? renderSavingsSection(admin) : `
          <div class="stat-row approvals-stats">
            ${FILTERS.map((f) => `
              <button type="button" class="stat-badge ${filter === f.id ? "selected" : ""}" data-approvals-filter="${f.id}">
                <div class="value">${countFor(items, f.id)}</div>
                <div class="label">${escapeHtml(f.label)}</div>
              </button>`).join("")}
          </div>

          <div class="chip-grid">
            ${KINDS.map((k) => `
              <button type="button" class="chip ${kind === k.id ? "active" : ""}" data-approvals-kind="${k.id}">${escapeHtml(k.label)}</button>`).join("")}
          </div>

          <div class="search-field">
            <span>${icon("doctors")}</span>
            <input type="search" placeholder="Search name, email or NPI…" data-approvals-search value="${escapeHtml(admin.search || "")}" />
          </div>

          ${body}
        `}
      </main>
      ${admin.menuOpen ? renderAdminMenu(admin) : ""}
    </div>`;
}

function renderAdminMenu(admin) {
  return `
    <div class="sheet-backdrop" data-close-admin-menu>
      <div class="sheet-panel" role="dialog" aria-modal="true" data-sheet-panel>
        <div class="sheet-header">
          <h2>Admin</h2>
          <button class="btn-ghost" type="button" data-close-admin-menu>Done</button>
        </div>
        <div class="stack" style="padding:0 var(--page-pad) 32px">
          <section class="card">
            <div style="font-weight:600">${escapeHtml(admin.email || "Signed in")}</div>
            <div class="subtitle">You can review applications. You can't see doctor or hospital workspaces.</div>
          </section>
          <button type="button" class="btn-secondary" data-admin-refresh>Refresh queue</button>
          <button type="button" class="btn-bordered" data-admin-sign-out>Sign out</button>
        </div>
      </div>
    </div>`;
}

export function bindAdmin(root, admin, handlers) {
  const { onPatch, onDecide, onRefresh, onSignOut, onSection, onSavingsRefresh } = handlers;

  root.querySelectorAll("[data-admin-section]").forEach((btn) => {
    btn.addEventListener("click", () => onSection(btn.dataset.adminSection));
  });
  root.querySelector("[data-savings-retry]")?.addEventListener("click", () => onSavingsRefresh());

  root.querySelector("[data-action='admin-menu']")?.addEventListener("click", () => onPatch({ menuOpen: true }));
  root.querySelectorAll("[data-close-admin-menu]").forEach((el) => {
    el.addEventListener("click", (e) => {
      if (el.classList.contains("sheet-backdrop") && e.target !== el) return;
      onPatch({ menuOpen: false });
    });
  });
  root.querySelectorAll("[data-sheet-panel]").forEach((panel) => {
    panel.addEventListener("click", (e) => e.stopPropagation());
  });

  root.querySelectorAll("[data-approvals-filter]").forEach((btn) => {
    btn.addEventListener("click", () => onPatch({ filter: btn.dataset.approvalsFilter, confirmKey: null, toast: null }));
  });
  root.querySelectorAll("[data-approvals-kind]").forEach((btn) => {
    btn.addEventListener("click", () => onPatch({ kind: btn.dataset.approvalsKind, confirmKey: null }));
  });

  const searchInput = root.querySelector("[data-approvals-search]");
  searchInput?.addEventListener("input", (e) => {
    onPatch({ search: e.target.value, keepFocus: true });
  });

  root.querySelectorAll("[data-confirm-reject]").forEach((btn) => {
    btn.addEventListener("click", () => onPatch({ confirmKey: btn.dataset.key, toast: null }));
  });
  root.querySelector("[data-cancel-confirm]")?.addEventListener("click", () => onPatch({ confirmKey: null }));

  root.querySelectorAll("[data-decide]").forEach((btn) => {
    btn.addEventListener("click", () => onDecide(btn.dataset.key, btn.dataset.decide));
  });

  root.querySelector("[data-admin-retry]")?.addEventListener("click", () => onRefresh());
  root.querySelector("[data-admin-refresh]")?.addEventListener("click", () => onRefresh());
  root.querySelector("[data-admin-sign-out]")?.addEventListener("click", () => onSignOut());
}
