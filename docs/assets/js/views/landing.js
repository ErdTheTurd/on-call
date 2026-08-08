import { icon } from "../components.js";

/**
 * Public front door. Everything here is marketing — the product itself sits
 * behind the sign-in button in the header.
 */
export function renderLanding() {
  return `
    <div class="landing">
      <header class="landing-nav">
        <a class="landing-brand" href="#top">
          <span class="landing-spark">${icon("sparkles")}</span>
          <span>On Call</span>
        </a>
        <nav class="landing-links">
          <a href="#for-doctors">For doctors</a>
          <a href="#for-hospitals">For hospitals</a>
        </nav>
        <div class="landing-cta">
          <button type="button" class="landing-signin" data-goto-auth>Sign in</button>
          <button type="button" class="landing-start" data-goto-auth>Get started</button>
        </div>
      </header>

      <section class="landing-hero" id="top">
        <p class="landing-eyebrow reveal">Built for the people who keep the lights on</p>
        <h1 class="landing-title reveal">On-call scheduling<br />that fills itself.</h1>
        <p class="landing-sub reveal">
          Post a shift, let the rate find the market, and watch verified doctors claim it —
          without the group chat, the spreadsheet, or the 2am phone tree.
        </p>
        <div class="landing-hero-cta reveal">
          <button type="button" class="landing-start lg" data-demo-role="Hospital">See the hospital view</button>
          <button type="button" class="landing-ghost lg" data-demo-role="Doctor">See the doctor view</button>
        </div>
        <p class="landing-note reveal">Live sample data. No account needed.</p>

        <div class="landing-stats reveal">
          <div><strong>86%</strong><span>shifts filled</span></div>
          <div><strong>4 min</strong><span>median claim time</span></div>
          <div><strong>0</strong><span>phone trees</span></div>
        </div>
      </section>

      <section class="landing-section" id="for-doctors">
        <div class="landing-section-head reveal">
          <span class="landing-tag">For doctors</span>
          <h2>Pick up the shifts you actually want.</h2>
          <p>Your specialties, your hospitals, your calendar — and a rate that rises the closer it gets.</p>
        </div>
        <div class="landing-grid">
          ${feature("calendar", "One calendar", "Every hospital you work with in a single month view. No more cross-checking three portals.")}
          ${feature("dollar", "Rates you can see", "The rate is on the card before you claim it, and it is locked the moment you do.")}
          ${feature("shifts", "Trade without the favour economy", "Offer a swap, name your compensation, and settle it in the app.")}
          ${feature("flame", "Credit for showing up", "Streaks and levels that recognise the people covering the hard nights.")}
        </div>
      </section>

      <section class="landing-section alt" id="for-hospitals">
        <div class="landing-section-head reveal">
          <span class="landing-tag">For hospitals</span>
          <h2>Stop chasing coverage.</h2>
          <p>Post the rota once. The algorithm prices the gaps and the roster comes to you.</p>
        </div>
        <div class="landing-grid">
          ${feature("dashboard", "Fill rate at a glance", "Open days, coverage, and the ones about to go critical — on one screen.")}
          ${feature("clock", "Pricing that reacts", "Rates escalate as a shift approaches, so the hard days clear before they hurt.")}
          ${feature("check", "Verified before they claim", "NPI and licence checks run up front. Auto-approve the people you trust.")}
          ${feature("lock", "Policy you control", "Cancellation windows, approval rules, and per-doctor rates stay yours.")}
        </div>
      </section>

      <section class="landing-close reveal">
        <h2>See it with real data.</h2>
        <p>Open a seeded hospital or doctor account and click through the whole thing.</p>
        <div class="landing-hero-cta">
          <button type="button" class="landing-start lg" data-demo-role="Hospital">Explore as a hospital</button>
          <button type="button" class="landing-ghost lg" data-demo-role="Doctor">Explore as a doctor</button>
        </div>
      </section>

      <footer class="landing-foot">
        <span>© ${new Date().getFullYear()} On Call</span>
        <button type="button" class="btn-ghost" data-goto-auth>Sign in</button>
      </footer>
    </div>`;
}

function feature(name, title, body) {
  return `
    <article class="landing-card reveal">
      <span class="landing-card-icon">${icon(name)}</span>
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

  root.querySelectorAll('.landing-links a, .landing-brand').forEach((link) => {
    link.addEventListener("click", (event) => {
      const target = root.querySelector(link.getAttribute("href"));
      if (!target) return;
      event.preventDefault();
      target.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  });

  revealOnScroll(root);
  trackNavElevation(root);
}

/** Fades sections in as they arrive. Falls back to visible if unsupported. */
function revealOnScroll(root) {
  const items = [...root.querySelectorAll(".reveal")];
  if (!("IntersectionObserver" in window)) {
    items.forEach((el) => el.classList.add("in"));
    return;
  }

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("in");
      observer.unobserve(entry.target);
    }
  }, { threshold: 0.12, rootMargin: "0px 0px -40px 0px" });

  items.forEach((el, i) => {
    el.style.setProperty("--reveal-delay", `${Math.min(i % 4, 3) * 70}ms`);
    observer.observe(el);
  });
}

/** Gives the header a background once the hero scrolls under it. */
function trackNavElevation(root) {
  const nav = root.querySelector(".landing-nav");
  if (!nav) return;
  const onScroll = () => nav.classList.toggle("scrolled", window.scrollY > 12);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });
}
