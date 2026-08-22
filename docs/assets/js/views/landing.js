import { bindReveals, bindCounters, bindStickyHeader, bindDotField } from "../lib/motion.js";
import { BRAND, brandLockup } from "../brand.js";

/**
 * Public marketing page. No product state is read here.
 * Growth figures are framed as expectations (not live counts). Demo CTAs open
 * mock sample data so the product is walkable before real accounts exist.
 */
export function renderLanding() {
  return `
    <div class="site" id="top">
      <div class="site-dotfield" aria-hidden="true">
        <canvas class="site-dotfield-canvas"></canvas>
      </div>
      ${header()}
      ${hero()}
      ${statBand()}
      ${bothSides()}
      ${features()}
      ${closing()}
      ${footer()}
    </div>`;
}

function logo() {
  return brandLockup();
}

function header() {
  return `
    <header class="site-header">
      <a class="site-brand" href="#top">${logo()}</a>
      <nav class="site-nav">
        <a href="#features">Features</a>
        <a href="#for-doctors">For doctors</a>
        <a href="#for-hospitals">For hospitals</a>
      </nav>
      <div class="site-actions">
        <button type="button" class="btn-quiet" data-goto-auth>Log in</button>
        <button type="button" class="btn-solid" data-goto-auth>Get started</button>
      </div>
    </header>`;
}

function hero() {
  return `
    <section class="hero">
      <span class="pill reveal">Live now · demos use mock sample data</span>
      <h1 class="hero-title reveal">
        <span class="hero-shift-hit" data-hero-shift-hit>
          <span class="hero-shift-stack" data-hero-shift>
            <span class="hero-shift-roman" aria-hidden="true">Shift</span>
            <span class="hero-shift-italic">Shift</span>
          </span>
        </span> what's possible.<br /><span class="accent">With MD Shift.</span>
      </h1>
      <p class="hero-sub reveal">
        The platform built for doctors who need flexibility and hospitals that
        need coverage. No friction. No gaps.
      </p>
      <div class="hero-actions reveal">
        <button type="button" class="btn-solid lg" data-demo-role="Doctor">For doctors ${arrow()}</button>
        <button type="button" class="btn-outline lg" data-demo-role="Hospital">For hospitals ${arrow()}</button>
      </div>
      <p class="hero-note reveal">Opens mock sample data — no signup required. Create a real account when you're ready.</p>
    </section>`;
}

function arrow() {
  return `<svg class="arrow" viewBox="0 0 16 16" fill="none" aria-hidden="true">
    <path d="M3 8h9m0 0L8.5 4.5M12 8l-3.5 3.5" stroke="currentColor" stroke-width="1.7"
          stroke-linecap="round" stroke-linejoin="round"/>
  </svg>`;
}

function statBand() {
  // Expectational targets — never imply these are live production counts.
  const stats = [
    { lead: "Expecting", value: "over 10k", label: "doctors on the platform" },
    { lead: "Expecting", value: "500+", label: "hospitals onboarded" },
    { lead: "Built for", value: "scale", label: "high-volume shift trading" }
  ];

  return `
    <section class="stat-band" aria-label="Growth targets">
      <div class="stat-band-inner">
        ${stats.map((s) => `
          <div class="stat reveal">
            <div class="stat-lead">${s.lead}</div>
            <div class="stat-value"><span class="stat-emphasis">${s.value}</span></div>
            <div class="stat-label">${s.label}</div>
          </div>`).join("")}
      </div>
    </section>`;
}

function bothSides() {
  return `
    <section class="section">
      <div class="section-head center reveal">
        <h2>Built for both sides of the schedule.</h2>
        <p>Whether you're trading a shift or managing an entire department, ${BRAND.name} has you covered.</p>
      </div>

      <div class="split">
        <article class="split-card reveal" id="for-doctors">
          <span class="eyebrow">For doctors</span>
          <h3>Trade shifts in one tap.</h3>
          <p>
            Post a shift, find a match, confirm — done. Set your availability once
            and let ${BRAND.name} handle the rest.
          </p>
          ${week([
            { day: "Mon", tone: "on" }, { day: "Tue", tone: "" }, { day: "Wed", tone: "on" },
            { day: "Thu", tone: "" }, { day: "Fri", tone: "swap", mark: "⇄" },
            { day: "Sat", tone: "" }, { day: "Sun", tone: "" }
          ])}
          <p class="week-note">Friday is out for swap</p>
          <button type="button" class="btn-solid" data-demo-role="Doctor">Explore doctor demo ${arrow()}</button>
        </article>

        <article class="split-card reveal" id="for-hospitals">
          <span class="eyebrow">For hospitals</span>
          <h3>Full coverage. Zero gaps.</h3>
          <p>
            See your entire roster in real time. Identify coverage gaps before they
            become crises, and approve trades from one dashboard.
          </p>
          ${week([
            { day: "Mon", tone: "on" }, { day: "Tue", tone: "on" }, { day: "Wed", tone: "gap", mark: "!" },
            { day: "Thu", tone: "on" }, { day: "Fri", tone: "on" },
            { day: "Sat", tone: "" }, { day: "Sun", tone: "" }
          ])}
          <p class="week-note gap"><span class="gap-dot"></span>1 coverage gap detected</p>
          <button type="button" class="btn-solid" data-demo-role="Hospital">Explore hospital demo ${arrow()}</button>
        </article>
      </div>
    </section>`;
}

function week(days) {
  return `
    <div class="week">
      ${days.map((d) => `
        <div class="week-day">
          <span class="week-label">${d.day}</span>
          <span class="week-cell ${d.tone}">${d.mark || (d.tone ? "•" : "–")}</span>
        </div>`).join("")}
    </div>`;
}

function features() {
  const items = [
    ["One-tap shift trading", "Post, match, and confirm shift trades in seconds. No emails, no phone calls."],
    ["Real-time coverage gaps", "Hospitals see open slots the moment they appear — and fill them before patient care is affected."],
    ["Rates that react", "Pricing escalates as a shift approaches, so the hard days clear early instead of at midnight."],
    ["Instant notifications", "Push and email alerts keep both sides moving without anyone chasing a reply."],
    ["Verified clinicians only", "NPI and licence checks happen up front, so claiming a shift takes a tap and not a phone call."],
    ["Audit trail & reporting", "Every trade, approval and schedule change is recorded and exportable."]
  ];

  return `
    <section class="section alt" id="features">
      <div class="section-head reveal">
        <span class="eyebrow">Platform features</span>
        <h2>Everything you need. Nothing you don't.</h2>
      </div>
      <div class="card-grid">
        ${items.map(([title, body]) => `
          <article class="feature reveal">
            <span class="dash"></span>
            <h3>${title}</h3>
            <p>${body}</p>
          </article>`).join("")}
      </div>
    </section>`;
}

function closing() {
  return `
    <section class="section">
      <div class="cta-band reveal">
        <div>
          <h2>Ready to fix your scheduling?</h2>
          <p>We're expecting over 10,000 doctors and 500+ hospitals on ${BRAND.name}. Explore with mock sample data, or create a real account.</p>
        </div>
        <div class="cta-actions">
          <button type="button" class="btn-solid lg" data-demo-role="Hospital">Explore hospital demo</button>
          <button type="button" class="btn-outline lg" data-demo-role="Doctor">Explore doctor demo</button>
        </div>
      </div>
    </section>`;
}

function footer() {
  const columns = [
    ["Product", ["Features", "Security", "Changelog"]],
    ["For doctors", ["Shift trading", "Availability", "Notifications"]],
    ["For hospitals", ["Roster management", "Coverage gaps", "Reporting"]],
    ["Company", ["About", "Careers", "Contact"]]
  ];

  return `
    <footer class="site-footer">
      <div class="footer-top">
        <div class="footer-brand">
          <a class="site-brand" href="#top">${logo()}</a>
          <p>Shift trading and scheduling built for the pace of modern healthcare.</p>
        </div>
        ${columns.map(([title, links]) => `
          <div class="footer-col">
            <h4>${title}</h4>
            ${links.map((l) => `<span>${l}</span>`).join("")}
          </div>`).join("")}
      </div>
      <div class="footer-bottom">
        <div class="footer-legal">
          <span>© ${new Date().getFullYear()} ${BRAND.name}. All rights reserved. · <a href="/support/">Support</a> · <a href="/privacypolicy/">Privacy Policy</a></span>
          <span class="footer-disclaimer">Growth targets are expectations, not live counts. Demo walks use mock sample data. Real accounts sync to your hospital when you sign up.</span>
        </div>
        <button type="button" class="btn-quiet" data-goto-auth>Log in</button>
      </div>
    </footer>`;
}

export function bindLanding(root, { onSignIn, onDemo }) {
  root.querySelectorAll("[data-goto-auth]").forEach((el) => {
    el.addEventListener("click", () => onSignIn());
  });
  root.querySelectorAll("[data-demo-role]").forEach((el) => {
    el.addEventListener("click", () => onDemo(el.dataset.demoRole));
  });

  root.querySelectorAll(".site-nav a, .site-brand").forEach((link) => {
    link.addEventListener("click", (event) => {
      const target = root.querySelector(link.getAttribute("href"));
      if (!target) return;
      event.preventDefault();
      target.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  });

  bindReveals(root);
  bindCounters(root);
  bindStickyHeader(root);
  bindDotField(root);
  bindHeroShiftItalic(root);
}

function bindHeroShiftItalic(root) {
  const el = root.querySelector("[data-hero-shift]");
  if (!el) return;
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduce) {
    el.classList.add("is-italic");
    return;
  }
  window.setTimeout(() => {
    el.classList.add("is-italic");
  }, 2000);
}
