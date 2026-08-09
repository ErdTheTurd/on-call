/**
 * Scroll-triggered motion for the marketing pages.
 *
 * Everything here is opt-out: if the browser reports a motion preference, or
 * IntersectionObserver is missing, elements land in their final state instead
 * of animating. Nothing is ever left invisible.
 */

const REDUCED = typeof window !== "undefined"
  && window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

/** Ease-out curve — quick off the line, gentle into place. */
function easeOut(t) {
  return 1 - Math.pow(1 - t, 3);
}

function formatNumber(value, { decimals = 0, prefix = "", suffix = "" }) {
  const rounded = decimals > 0 ? value.toFixed(decimals) : Math.round(value).toString();
  const [whole, fraction] = rounded.split(".");
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return `${prefix}${fraction ? `${grouped}.${fraction}` : grouped}${suffix}`;
}

/**
 * Counts an element from zero to its target. Reads configuration from data
 * attributes so markup stays declarative:
 *   <span data-count-to="86" data-count-suffix="%"></span>
 */
export function countUp(el) {
  const target = Number(el.dataset.countTo);
  if (!Number.isFinite(target)) return;

  const options = {
    decimals: Number(el.dataset.countDecimals) || 0,
    prefix: el.dataset.countPrefix || "",
    suffix: el.dataset.countSuffix || ""
  };
  const duration = Number(el.dataset.countDuration) || 1400;

  if (REDUCED) {
    el.textContent = formatNumber(target, options);
    return;
  }

  const start = performance.now();
  let settled = false;
  const tick = (now) => {
    const progress = Math.min(1, (now - start) / duration);
    if (settled) return;
    el.textContent = formatNumber(target * easeOut(progress), options);
    if (progress < 1) requestAnimationFrame(tick);
    else settled = true;
  };
  // Start from zero so the first painted frame is not the answer.
  el.textContent = formatNumber(0, options);
  requestAnimationFrame(tick);

  // Never leave a stalled counter showing zero.
  setTimeout(() => {
    if (settled) return;
    settled = true;
    el.textContent = formatNumber(target, options);
  }, duration + 400);
}

/**
 * Runs `onEnter` the first time each element scrolls into view.
 * Elements already on screen fire immediately.
 */
function whenVisible(elements, onEnter, failsafeMs = 1600) {
  const items = [...elements];
  if (!items.length) return;

  if (!("IntersectionObserver" in window)) {
    items.forEach(onEnter);
    return;
  }

  const pending = new Set(items);
  const run = (el) => {
    if (pending.delete(el)) onEnter(el);
  };

  // Wait for layout before observing. Observing in the same task as the DOM
  // write resolves every element as "not intersecting" against a page that has
  // no height yet, and with no scroll to follow, it would never fire again.
  requestAnimationFrame(() => requestAnimationFrame(() => {
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        observer.unobserve(entry.target);
        run(entry.target);
      }
    }, { threshold: 0.2, rootMargin: "0px 0px -40px 0px" });

    pending.forEach((el) => observer.observe(el));
  }));

  // If nothing has run by the deadline the observer never got a chance — an
  // unpainted tab starves rAF, for one. Show the content rather than hide it
  // behind an animation that is never coming.
  setTimeout(() => {
    if (pending.size === items.length) items.forEach(run);
  }, failsafeMs);
}

/** Fades and lifts `.reveal` elements into place, staggered within a group. */
export function bindReveals(root) {
  const items = root.querySelectorAll(".reveal");
  items.forEach((el, i) => {
    el.style.setProperty("--reveal-delay", `${Math.min(i % 5, 4) * 80}ms`);
  });
  whenVisible(items, (el) => el.classList.add("in"));
}

/** Starts every counter in `root` as it scrolls into view. */
export function bindCounters(root) {
  whenVisible(root.querySelectorAll("[data-count-to]"), countUp);
}

/** Adds `.scrolled` to the header once the page moves past the hero edge. */
export function bindStickyHeader(root, selector = ".site-header") {
  const header = root.querySelector(selector);
  if (!header) return () => {};

  const onScroll = () => header.classList.toggle("scrolled", window.scrollY > 12);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });
  return () => window.removeEventListener("scroll", onScroll);
}
