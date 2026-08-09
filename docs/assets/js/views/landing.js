import { bindReveals, bindCounters, bindStickyHeader } from "../lib/motion.js";

/**
 * Public marketing page. No product state is read here — every figure is
 * illustrative, so the page renders identically for a first-time visitor.
 */
export function renderLanding() {
  return `
    <div class="site" id="top">
      ${header()}
      ${hero()}
      ${statBand()}
      ${bothSides()}
      ${features()}
      ${testimonial()}
      ${closing()}
      ${footer()}
    </div>`;
}

function logo() {
  return `
    <span class="logo">
      <svg viewBox="0 0 28 28" fill="none" aria-hidden="true">
        <rect width="28" height="28" rx="8" fill="var(--blue)"/>
        <path d="M5.5 14.5h3.2l2.1-4.6 3.4 9.2 2.2-4.6h6.1"
              stroke="#fff" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
      <span>On Call</span>
    </span>`;
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
      <span class="pill reveal">Now live for all specialties</span>
      <h1 class="hero-title reveal">
        Shift trading.<br /><span class="accent">Perfectly scheduled.</span>
      </h1>
      <p class="hero-sub reveal">
        The platform built for doctors who need flexibility and hospitals that
        need coverage. No friction. No gaps.
      </p>
      <div class="hero-actions reveal">
        <button type="button" class="btn-solid lg" data-demo-role="Doctor">For doctors ${arrow()}</button>
        <button type="button" class="btn-outline lg" data-demo-role="Hospital">For hospitals ${arrow()}</button>
      </div>
      <p class="hero-note reveal">Opens a live account with sample data. Nothing to sign up for.</p>
    </section>`;
}

function arrow() {
  return `<svg class="arrow" viewBox="0 0 16 16" fill="none" aria-hidden="true">
    <path d="M3 8h9m0 0L8.5 4.5M12 8l-3.5 3.5" stroke="currentColor" stroke-width="1.7"
          stroke-linecap="round" stroke-linejoin="round"/>
  </svg>`;
}

function statBand() {
  const stats = [
    { to: 10, suffix: "k", label: "Doctors active" },
    { to: 500, label: "Hospitals onboarded" },
    { to: 2, decimals: 1, suffix: "M", label: "Shifts traded" }
  ];

  return `
    <section class="stat-band">
      <div class="stat-band-inner">
        ${stats.map((s) => `
          <div class="stat reveal">
            <div class="stat-value">
              <span data-count-to="${s.to}"
                    ${s.decimals ? `data-count-decimals="${s.decimals}"` : ""}
                    ${s.suffix ? `data-count-suffix="${s.suffix}"` : ""}>0</span><span class="plus">+</span>
            </div>
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
        <p>Whether you're trading a shift or managing an entire department, On Call has you covered.</p>
      </div>

      <div class="split">
        <article class="split-card reveal" id="for-doctors">
          <span class="eyebrow">For doctors</span>
          <h3>Trade shifts in one tap.</h3>
          <p>
            Post a shift, find a match, confirm — done. Set your availability once
            and let On Call handle the rest.
          </p>
          ${week([
            { day: "Mon", tone: "on" }, { day: "Tue", tone: "" }, { day: "Wed", tone: "on" },
            { day: "Thu", tone: "" }, { day: "Fri", tone: "swap", mark: "⇄" },
            { day: "Sat", tone: "" }, { day: "Sun", tone: "" }
          ])}
          <p class="week-note">Friday is out for swap</p>
          <button type="button" class="btn-solid" data-demo-role="Doctor">Get started as a doctor ${arrow()}</button>
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
          <button type="button" class="btn-solid" data-demo-role="Hospital">Get started as a hospital ${arrow()}</button>
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

function testimonial() {
  return `
    <section class="section narrow">
      <figure class="quote reveal">
        <span class="dash"></span>
        <blockquote>
          "On Call cut our scheduling admin time by 70%. Our residents actually
          use it — which says everything."
        </blockquote>
        <figcaption>
          <strong>Dr. Sarah Chen</strong>
          <span>Chief of Emergency Medicine, Metro General Health System</span>
        </figcaption>
      </figure>
    </section>`;
}

function closing() {
  return `
    <section class="section">
      <div class="cta-band reveal">
        <div>
          <h2>Ready to fix your scheduling?</h2>
          <p>Join 10,000+ doctors and 500+ hospitals already on On Call.</p>
        </div>
        <div class="cta-actions">
          <button type="button" class="btn-solid lg" data-demo-role="Hospital">Start free trial</button>
          <button type="button" class="btn-outline lg" data-demo-role="Doctor">Request a demo</button>
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
        <span>© ${new Date().getFullYear()} On Call. All rights reserved.</span>
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
}
