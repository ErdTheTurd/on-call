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

/**
 * Antigravity-style spotlight on the landing dot grid.
 * Canvas draws a quiet grid; a soft radius of brighter dots trails the
 * pointer (lerp) instead of locking onto it. Desktop mouse only.
 */
export function bindDotField(root, siteSelector = ".site") {
  const site = root.querySelector(siteSelector);
  const host = site?.querySelector(".site-dotfield");
  const canvas = host?.querySelector("canvas");
  if (!site || !host || !canvas) return () => {};
  if (REDUCED) return () => {};

  const ctx = canvas.getContext("2d", { alpha: true });
  if (!ctx) return () => {};

  const GAP = 24;
  const RADIUS = 190;
  const FOLLOW = 0.1;
  const FIELD_H = 760;

  let targetX = null;
  let targetY = null;
  let currX = null;
  let currY = null;
  let glow = 0;
  let targetGlow = 0;
  let raf = 0;
  let active = false;
  let width = 0;
  let height = 0;
  let dpr = 1;

  const resize = () => {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    width = Math.max(1, Math.floor(host.clientWidth));
    height = Math.max(1, Math.floor(host.clientHeight || FIELD_H));
    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    paint();
  };

  const paint = () => {
    ctx.clearRect(0, 0, width, height);

    const hx = currX;
    const hy = currY;
    const lit = glow > 0.02 && hx != null && hy != null;

    const cols = Math.ceil(width / GAP) + 1;
    const rows = Math.ceil(height / GAP) + 1;
    const r2 = RADIUS * RADIUS;

    for (let row = 0; row < rows; row += 1) {
      const y = row * GAP + 4;
      for (let col = 0; col < cols; col += 1) {
        const x = col * GAP + 4;
        // Quiet base grid — only the dots themselves brighten near the pointer.
        let alpha = 0.09;
        let radius = 1;
        let r = 226;
        let g = 232;
        let b = 240;

        if (lit) {
          const dx = x - hx;
          const dy = y - hy;
          const dist2 = dx * dx + dy * dy;
          if (dist2 < r2) {
            const t = 1 - Math.sqrt(dist2) / RADIUS;
            const boost = t * t * glow;
            alpha = Math.min(0.72, 0.09 + boost * 0.55);
            radius = 1 + boost * 0.55;
            r = Math.round(226 + boost * 20);
            g = Math.round(232 + boost * 16);
            b = Math.round(240 + boost * 10);
          }
        }

        ctx.beginPath();
        ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha})`;
        ctx.arc(x, y, radius, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  };

  const tick = () => {
    raf = 0;

    if (targetX == null || targetY == null) {
      glow += (0 - glow) * 0.06;
      if (glow < 0.01) {
        glow = 0;
        active = false;
        paint();
        return;
      }
    } else {
      if (currX == null) {
        currX = targetX;
        currY = targetY;
      } else {
        currX += (targetX - currX) * FOLLOW;
        currY += (targetY - currY) * FOLLOW;
      }
      glow += (targetGlow - glow) * 0.18;
    }

    paint();

    const chasing = targetX != null && (
      Math.abs(targetX - (currX || 0)) > 0.4
      || Math.abs(targetY - (currY || 0)) > 0.4
      || Math.abs(targetGlow - glow) > 0.01
      || glow > 0.01
    );
    if (chasing || glow > 0.01) {
      raf = requestAnimationFrame(tick);
    } else {
      active = false;
    }
  };

  const kick = () => {
    if (active) return;
    active = true;
    raf = requestAnimationFrame(tick);
  };

  const onMove = (event) => {
    // Touch/pen skip — mouse and unspecified (some browsers) get the trail.
    if (event.pointerType === "touch" || event.pointerType === "pen") return;
    const rect = host.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    if (y < -40 || y > FIELD_H + 40 || x < -40 || x > rect.width + 40) {
      targetGlow = 0;
      targetX = null;
      targetY = null;
      kick();
      return;
    }
    targetX = x;
    targetY = y;
    targetGlow = 1;
    kick();
  };

  const onLeaveWindow = (event) => {
    if (event.relatedTarget) return;
    targetGlow = 0;
    targetX = null;
    targetY = null;
    kick();
  };

  resize();
  // Window capture so interactive hero controls cannot eat the trail.
  window.addEventListener("pointermove", onMove, { passive: true });
  document.addEventListener("pointerleave", onLeaveWindow);
  window.addEventListener("resize", resize, { passive: true });

  return () => {
    window.removeEventListener("pointermove", onMove);
    document.removeEventListener("pointerleave", onLeaveWindow);
    window.removeEventListener("resize", resize);
    if (raf) cancelAnimationFrame(raf);
  };
}
