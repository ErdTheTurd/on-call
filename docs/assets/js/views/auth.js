import { escapeHtml } from "../brand.js";
import { icon } from "../components.js";
import { isConfigured } from "../supabase-client.js";

export function renderAuthView(state, handlers) {
  const mode = state.authMode || "signin";
  return `
    <div class="auth-screen auth-bg">
      <div class="mesh-blob"></div><div class="mesh-blob"></div><div class="mesh-blob"></div>
      <div class="auth-brand">
        <div class="auth-brand-row">
          <span class="auth-brand-icon">${icon("wand")}</span>
          <span>On Call</span>
        </div>
        <p class="auth-tagline">Smarter on-call scheduling</p>
      </div>
      <div class="auth-card-shell">
        <div class="tab-switcher" role="tablist">
          <button type="button" class="${mode === "signin" ? "active" : ""}" data-auth-mode="signin">Sign in</button>
          <button type="button" class="${mode === "signup" ? "active" : ""}" data-auth-mode="signup">Create account</button>
        </div>
        ${mode === "signup" ? `
          <div class="eyebrow" style="padding:0 24px 8px">I AM A</div>
          <div class="role-pills">
            <button type="button" class="role-pill ${state.role === "Doctor" ? "active" : ""}" data-role="Doctor">${icon("stethoscope")} Doctor</button>
            <button type="button" class="role-pill ${state.role === "Hospital" ? "active" : ""}" data-role="Hospital">${icon("hospital")} Hospital</button>
          </div>` : ""}
        <form class="auth-fields" id="auth-form">
          <label class="auth-field">
            <span class="field-icon">${icon("envelope")}</span>
            <input name="email" type="email" placeholder="Email address" autocomplete="email" required value="${escapeHtml(state.email || "")}" />
          </label>
          <label class="auth-field">
            <span class="field-icon">${icon("lock")}</span>
            <input name="password" type="password" placeholder="Password" autocomplete="${mode === "signup" ? "new-password" : "current-password"}" required />
          </label>
          ${mode === "signup" ? `
            <label class="auth-field">
              <span class="field-icon">${icon("lock")}</span>
              <input name="confirm" type="password" placeholder="Confirm password" autocomplete="new-password" required />
            </label>` : ""}
        </form>
        ${state.error ? `<p class="error-text" style="padding:12px 24px 0">${escapeHtml(state.error)}</p>` : ""}
        ${!isConfigured() ? `<p class="error-text" style="padding:8px 24px 0;font-size:12px">Supabase not configured — using local offline auth.</p>` : ""}
        ${mode === "signin" ? `<div style="padding:8px 24px 0;text-align:right"><button type="button" class="btn-ghost">Forgot password?</button></div>` : ""}
        <div class="auth-actions">
          <button type="submit" form="auth-form" class="btn-primary" ${state.loading ? "disabled" : ""}>
            ${state.loading ? `<span class="spinner"></span>` : (mode === "signin" ? "Sign in" : "Create account")}
          </button>
        </div>
        <div class="auth-divider">OR</div>
        <div style="padding:0 24px 32px">
          <button type="button" class="btn-secondary" disabled>${icon("globe")} Continue with Google</button>
        </div>
      </div>
      <p class="auth-footer">By continuing you agree to our Terms of Service and Privacy Policy.</p>
    </div>`;
}

export function bindAuth(root, { onSubmit, onMode, onRole }) {
  root.querySelector("#auth-form")?.addEventListener("submit", (e) => {
    e.preventDefault();
    const fd = new FormData(e.target);
    onSubmit({
      email: String(fd.get("email") || "").trim(),
      password: String(fd.get("password") || ""),
      confirm: String(fd.get("confirm") || "")
    });
  });
  root.querySelectorAll("[data-auth-mode]").forEach((btn) => {
    btn.addEventListener("click", () => onMode(btn.dataset.authMode));
  });
  root.querySelectorAll("[data-role]").forEach((btn) => {
    btn.addEventListener("click", () => onRole(btn.dataset.role));
  });
}
