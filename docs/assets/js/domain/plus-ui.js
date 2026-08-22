/** Shared Plus upgrade sheet markup for doctor + hospital dashboards. */
import { escapeHtml } from "../brand.js";
import { icon, sectionHeader } from "../components.js";
import {
  PLUS_FEATURES, PLUS_PRICE_LABEL, isPlusActive, getPlusMembership
} from "./plus.js";

export function renderPlusSheet(role = "doctor") {
  const active = isPlusActive();
  const membership = getPlusMembership();
  const roleKey = role === "hospital" ? "hospital" : "doctor";
  const features = [...PLUS_FEATURES.shared, ...PLUS_FEATURES[roleKey]];

  const body = `
    <main class="main-scroll stack" style="padding:16px">
      <section class="card stack plus-hero">
        <div class="plus-kicker">${icon("sparkles", { size: 16 })} MD Shift+</div>
        <h2 class="plus-title">${active ? "You're on MD Shift+" : "Upgrade to MD Shift+"}</h2>
        <p class="subtitle">${active
          ? (membership.until
            ? `Active through ${new Date(membership.until).toLocaleDateString()}. Ad-free and perks stay on for this account.`
            : "Ad-free and Plus perks are active on this account.")
          : `Unlock a calmer, ad-free control room — for doctors and hospitals — at ${PLUS_PRICE_LABEL}.`}</p>
        ${active
          ? `<div class="success-banner" style="margin:0">${icon("checkCircle", { size: 20 })}
              <div><div class="success-title">Plus active</div>
              <div class="subtitle">Same subscription unlocks web and iOS.</div></div></div>`
          : `<button type="button" class="btn-primary" data-plus-checkout>Get MD Shift+ · ${PLUS_PRICE_LABEL}</button>
             <p class="tertiary" style="font-size:12px;margin:0">Billed monthly via Stripe. Cancel anytime. One Plus covers this signed-in account on web and iOS.</p>`}
      </section>
      <section class="card stack">
        ${sectionHeader("Included", "sparkles")}
        ${features.map((f) => `
          <div class="plus-feature">
            <div class="plus-feature-title">${escapeHtml(f.title)}</div>
            <div class="subtitle">${escapeHtml(f.detail)}</div>
          </div>`).join("")}
      </section>
      ${!active ? `
        <section class="card stack">
          <p class="subtitle" style="margin:0">Prefer the App Store later? Subscribe on the web today — your Plus status syncs to iOS automatically.</p>
        </section>` : ""}
    </main>`;

  return body;
}
