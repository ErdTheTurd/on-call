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
      ${preview()}
      ${forDoctors()}
      ${forHospitals()}
      ${howItWorks()}
      ${closing()}
      ${footer()}
    </div>`;
}

function header() {
  return `
    <header class="site-header">
      <a class="site-brand" href="#top">
        <span class="site-mark"></span>
        <span>On Call</span>
      </a>
      <nav class="site-nav">
        <a href="#preview">Product</a>
        <a href="#for-doctors">For doctors</a>
        <a href="#for-hospitals">For hospitals</a>
      </nav>
      <div class="site-actions">
        <button type="button" class="btn-quiet" data-goto-auth>Sign in</button>
        <button type="button" class="btn-solid" data-goto-auth>Get started</button>
      </div>
    </header>`;
}

function hero() {
  return `
    <section class="hero">
      <p class="eyebrow reveal">On-call coverage, solved</p>
      <h1 class="hero-title reveal">
        The rota fills itself<br />while you sleep.
      </h1>
      <p class="hero-sub reveal">
        Post the shifts you can't cover. On Call prices each gap by how urgent it is,
        puts it in front of verified doctors, and locks the rate the moment someone claims it.
        No group chat. No agency markup. No 2am phone tree.
      </p>
      <div class="hero-actions reveal">
        <button type="button" class="btn-solid lg" data-demo-role="Hospital">See the hospital view</button>
        <button type="button" class="btn-outline lg" data-demo-role="Doctor">See the doctor view</button>
      </div>
      <p class="hero-note reveal">Opens a live account with sample data. Nothing to sign up for.</p>
    </section>`;
}

function statBand() {
  const stats = [
    { to: 86, suffix: "%", label: "of shifts filled", sub: "across pilot rotas" },
    { to: 4, suffix: " min", label: "median time to claim", sub: "from post to accepted" },
    { to: 12400, label: "shifts covered", sub: "since launch" },
    { to: 0, prefix: "$", label: "agency markup", sub: "hospitals pay the doctor" }
  ];

  return `
    <section class="stat-band">
      <div class="stat-band-inner">
        ${stats.map((s) => `
          <div class="stat reveal">
            <div class="stat-value"
                 data-count-to="${s.to}"
                 ${s.prefix ? `data-count-prefix="${s.prefix}"` : ""}
                 ${s.suffix ? `data-count-suffix="${s.suffix}"` : ""}>0</div>
            <div class="stat-label">${s.label}</div>
            <div class="stat-sub">${s.sub}</div>
          </div>`).join("")}
      </div>
    </section>`;
}

/** A still of the hospital dashboard, built from static markup. */
function preview() {
  const days = [
    { n: 1, tone: "" }, { n: 2, tone: "ok" }, { n: 3, tone: "ok" }, { n: 4, tone: "" },
    { n: 5, tone: "warn" }, { n: 6, tone: "ok" }, { n: 7, tone: "ok" },
    { n: 8, tone: "ok" }, { n: 9, tone: "hot" }, { n: 10, tone: "warn" }, { n: 11, tone: "ok" },
    { n: 12, tone: "ok" }, { n: 13, tone: "" }, { n: 14, tone: "ok" }
  ];

  return `
    <section class="preview" id="preview">
      <div class="section-head center reveal">
        <span class="tag">The control room</span>
        <h2>Every gap, priced and visible.</h2>
        <p>One screen tells you what is covered, what is about to hurt, and what it will cost.</p>
      </div>

      <div class="preview-frame reveal">
        <div class="preview-bar">
          <span class="dot"></span><span class="dot"></span><span class="dot"></span>
          <span class="preview-title">Riverside General — August</span>
        </div>
        <div class="preview-body">
          <div class="preview-metrics">
            <div class="metric">
              <div class="metric-value" data-count-to="15">0</div>
              <div class="metric-label">Open shifts</div>
            </div>
            <div class="metric">
              <div class="metric-value accent" data-count-to="86" data-count-suffix="%">0</div>
              <div class="metric-label">Fill rate</div>
            </div>
            <div class="metric">
              <div class="metric-value" data-count-to="7">0</div>
              <div class="metric-label">Auto-approved</div>
            </div>
          </div>

          <div class="preview-cal">
            ${days.map((d) => `<span class="cal-day ${d.tone}">${d.n}</span>`).join("")}
          </div>

          <div class="preview-rows">
            ${previewRow("Emergency Medicine", "Sat 9 Aug", 2450, "Critical", "hot")}
            ${previewRow("Internal Medicine", "Sun 10 Aug", 1780, "Soon", "warn")}
            ${previewRow("Cardiology", "Tue 12 Aug", 1600, "Open", "ok")}
          </div>
        </div>
      </div>
    </section>`;
}

function previewRow(specialty, when, rate, badge, tone) {
  return `
    <div class="preview-row">
      <span class="row-dot ${tone}"></span>
      <div class="row-main">
        <div class="row-title">${specialty}</div>
        <div class="row-sub">${when} · Full day</div>
      </div>
      <div class="row-rate ${tone}">$<span data-count-to="${rate}">0</span>/day</div>
      <span class="row-badge ${tone}">${badge}</span>
    </div>`;
}

function forDoctors() {
  return `
    <section class="section" id="for-doctors">
      <div class="section-head reveal">
        <span class="tag">For doctors</span>
        <h2>Pick up the shifts you actually want.</h2>
        <p>Your specialties, your hospitals, one calendar — and a rate that rises the closer it gets.</p>
      </div>
      <div class="card-grid">
        ${card("One calendar", "Every hospital you work with in a single month view, instead of three portals and a WhatsApp thread.")}
        ${card("The rate is on the card", "You see what a shift pays before you claim it, and it is locked the second you do.")}
        ${card("Trades without the favour economy", "Offer a swap, name what you want for it, and settle the whole thing in the app.")}
        ${card("Verified once", "NPI and licence checks happen up front, so claiming a shift takes a tap and not a phone call.")}
      </div>
    </section>`;
}

function forHospitals() {
  return `
    <section class="section alt" id="for-hospitals">
      <div class="section-head reveal">
        <span class="tag">For hospitals</span>
        <h2>Stop chasing coverage.</h2>
        <p>Post the rota once. The algorithm prices the gaps and the roster comes to you.</p>
      </div>
      <div class="card-grid">
        ${card("Coverage at a glance", "Open days, filled days, and the ones about to go critical — colour-coded on one calendar.")}
        ${card("Pricing that reacts", "Rates escalate as a shift approaches, so hard days clear early instead of at midnight.")}
        ${card("Approve once, not every time", "Auto-approve the doctors you trust and let the rest come through a queue you control.")}
        ${card("Your policy, your rules", "Cancellation windows, approval requirements and per-doctor rates all stay yours.")}
      </div>
    </section>`;
}

function howItWorks() {
  const steps = [
    ["Post the gap", "Add the days you cannot cover. Rates start from your floor and climb as the date nears."],
    ["Doctors claim it", "Verified doctors in that specialty see it instantly and claim at the posted rate."],
    ["It is locked", "The rate fixes on claim, and cancellation follows the policy you set."]
  ];

  return `
    <section class="section">
      <div class="section-head center reveal">
        <span class="tag">How it works</span>
        <h2>Three steps, no phone calls.</h2>
      </div>
      <ol class="steps">
        ${steps.map(([title, body], i) => `
          <li class="step reveal">
            <span class="step-num">${i + 1}</span>
            <h3>${title}</h3>
            <p>${body}</p>
          </li>`).join("")}
      </ol>
    </section>`;
}

function closing() {
  return `
    <section class="closing reveal">
      <h2>See it with real data.</h2>
      <p>Open a fully populated hospital or doctor account and click through the whole product.</p>
      <div class="hero-actions">
        <button type="button" class="btn-solid lg" data-demo-role="Hospital">Explore as a hospital</button>
        <button type="button" class="btn-outline lg" data-demo-role="Doctor">Explore as a doctor</button>
      </div>
    </section>`;
}

function footer() {
  return `
    <footer class="site-footer">
      <span>© ${new Date().getFullYear()} On Call</span>
      <button type="button" class="btn-quiet" data-goto-auth>Sign in</button>
    </footer>`;
}

function card(title, body) {
  return `
    <article class="feature reveal">
      <h3>${title}</h3>
      <p>${body}</p>
    </article>`;
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
