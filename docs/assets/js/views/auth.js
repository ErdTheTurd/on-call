import { escapeHtml, BRAND, brandMark } from "../brand.js";
import { icon } from "../components.js";
import { isConfigured } from "../supabase-client.js";

function googleMark() {
  return `<svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
    <path fill="#EA4335" d="M9 7.2v3.5h4.9c-.2 1.1-.8 2-1.7 2.6l2.7 2.1c1.6-1.5 2.5-3.7 2.5-6.3 0-.6-.1-1.2-.2-1.8H9z"/>
    <path fill="#34A853" d="M4.1 10.7l-.7.5-2.3 1.8C2.6 15.7 5.6 17.5 9 17.5c2.4 0 4.4-.8 5.9-2.2l-2.7-2.1c-.8.5-1.8.9-3.2.9-2.4 0-4.5-1.6-5.2-3.9z"/>
    <path fill="#4A90E2" d="M1.1 5.1C.4 6.4 0 7.7 0 9.2c0 1.5.4 2.8 1.1 4l3-2.3c-.2-.5-.3-1.1-.3-1.7 0-.6.1-1.2.3-1.7L1.1 5.1z"/>
    <path fill="#FBBC05" d="M9 3.6c1.3 0 2.5.5 3.4 1.3l2.5-2.5C13.4.9 11.4 0 9 0 5.6 0 2.6 1.8 1.1 4.5l3 2.3C4.5 5.2 6.6 3.6 9 3.6z"/>
  </svg>`;
}

function appleMark() {
  return `<svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true" fill="currentColor">
    <path d="M13.6 9.4c0-2 1.6-3 1.7-3.1-1-1.4-2.4-1.6-2.9-1.6-1.2-.1-2.4.7-3 .7-.6 0-1.6-.7-2.7-.7-1.4 0-2.7.8-3.4 2.1-1.5 2.5-.4 6.3 1 8.3.7 1 1.5 2.1 2.6 2 .1 0 .2 0 .3-.1.9-.2 1.3-.7 2.4-.7 1.1 0 1.4.5 2.4.7.1 0 .2 0 .3.1 1.1-.1 1.9-1 2.6-2 .8-1.1 1.1-2.2 1.1-2.3-.1 0-2.1-.8-2.1-3.4zM11.5 3.3c.5-.6.9-1.5.8-2.3-.8 0-1.7.5-2.3 1.2-.5.6-.9 1.5-.8 2.3.9.1 1.7-.4 2.3-1.2z"/>
  </svg>`;
}

function otpInputs(value = "") {
  const digits = String(value || "").replace(/\D/g, "").slice(0, 6).padEnd(6, " ");
  return Array.from({ length: 6 }, (_, i) => {
    const d = digits[i] === " " ? "" : digits[i];
    return `<input class="otp-digit" type="text" inputmode="numeric" maxlength="1" autocomplete="${i === 0 ? "one-time-code" : "off"}" data-otp-index="${i}" value="${escapeHtml(d)}" aria-label="Digit ${i + 1}" />`;
  }).join("");
}

export function renderAuthView(state, handlers) {
  const mode = state.authMode || "signin";
  const verifyEmail = state.verifyEmail;

  if (verifyEmail) {
    return `
    <div class="auth-screen auth-bg">
      <div class="mesh-blob"></div><div class="mesh-blob"></div><div class="mesh-blob"></div>
      <button type="button" class="auth-back" data-back-to-landing>‹ Back</button>
      <div class="auth-brand">
        <div class="auth-brand-row">
          <span class="auth-brand-icon">${brandMark({ size: 32 })}</span>
          <span>${BRAND.name}</span>
        </div>
        <p class="auth-tagline">${BRAND.tagline}</p>
      </div>
      <div class="auth-card-shell" style="padding:28px 24px">
        <h2 style="margin:0 0 8px;font-size:1.35rem">Enter verification code</h2>
        <p class="subtitle" style="margin:0 0 18px;line-height:1.5">
          We sent a 6-digit code to <strong>${escapeHtml(verifyEmail)}</strong>.
          Enter it here — no link to click.
        </p>
        <form id="otp-form" class="otp-form">
          <div class="otp-row" role="group" aria-label="6-digit verification code">
            ${otpInputs(state.otpCode)}
          </div>
          <input type="hidden" name="otp" id="otp-value" value="${escapeHtml(state.otpCode || "")}" />
        </form>
        ${state.verifyNotice ? `<p class="subtitle" style="color:var(--success);margin:12px 0 0">${escapeHtml(state.verifyNotice)}</p>` : ""}
        ${state.error ? `<p class="error-text" style="padding:12px 0 0">${escapeHtml(state.error)}</p>` : ""}
        <div class="auth-actions" style="padding:20px 0 0">
          <button type="submit" form="otp-form" class="btn-primary" ${state.loading ? "disabled" : ""}>
            ${state.loading ? `<span class="spinner"></span>` : "Verify and continue"}
          </button>
          <button type="button" class="btn-ghost" data-resend-verify ${state.loading ? "disabled" : ""} style="margin-top:12px;width:100%">
            Resend code
          </button>
          <button type="button" class="btn-secondary" data-auth-mode="signin" style="margin-top:10px">Back to sign in</button>
        </div>
      </div>
    </div>`;
  }

  return `
    <div class="auth-screen auth-bg">
      <div class="mesh-blob"></div><div class="mesh-blob"></div><div class="mesh-blob"></div>
      <button type="button" class="auth-back" data-back-to-landing>‹ Back</button>
      <div class="auth-brand">
        <div class="auth-brand-row">
          <span class="auth-brand-icon">${brandMark({ size: 32 })}</span>
          <span>${BRAND.name}</span>
        </div>
        <p class="auth-tagline">${BRAND.tagline}</p>
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
        <div class="oauth-row">
          <button type="button" class="btn-oauth" data-oauth="google" ${state.loading || !isConfigured() ? "disabled" : ""}>
            ${googleMark()} Continue with Google
          </button>
          <button type="button" class="btn-oauth" data-oauth="apple" ${state.loading || !isConfigured() ? "disabled" : ""}>
            ${appleMark()} Continue with Apple
          </button>
        </div>
        <div class="auth-divider">OR USE EMAIL</div>
        <form class="auth-fields" id="auth-form">
          <label class="auth-field">
            <span class="field-icon">${icon("envelope")}</span>
            <input name="email" type="text" inputmode="email" placeholder="Email or erdunn" autocomplete="username" required value="${escapeHtml(state.email || "")}" />
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
        <div class="auth-actions">
          <button type="submit" form="auth-form" class="btn-primary" ${state.loading ? "disabled" : ""}>
            ${state.loading ? `<span class="spinner"></span>` : (mode === "signin" ? "Sign in" : "Create account")}
          </button>
        </div>
        <div class="auth-divider">OR LOOK AROUND FIRST</div>
        <div class="demo-entry">
          <button type="button" class="btn-secondary" data-demo="Doctor">
            ${icon("stethoscope")} Explore as a doctor
          </button>
          <button type="button" class="btn-secondary" data-demo="Hospital">
            ${icon("hospital")} Explore as a hospital
          </button>
          <p class="demo-note">Sample data, no account needed.</p>
        </div>
      </div>
      <p class="auth-footer">By continuing you agree to our Terms of Service and Privacy Policy.</p>
    </div>`;
}

function readOtp(root) {
  return Array.from(root.querySelectorAll(".otp-digit"))
    .map((el) => el.value.replace(/\D/g, "").slice(0, 1))
    .join("")
    .slice(0, 6);
}

export function bindAuth(root, { onSubmit, onMode, onRole, onDemo, onBack, onResend, onOAuth, onVerifyOtp }) {
  root.querySelectorAll("[data-demo]").forEach((btn) => {
    btn.addEventListener("click", () => onDemo?.(btn.dataset.demo));
  });
  root.querySelector("[data-back-to-landing]")?.addEventListener("click", () => onBack?.());
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
  root.querySelectorAll("[data-resend-verify]").forEach((btn) => {
    btn.addEventListener("click", () => onResend?.());
  });
  root.querySelectorAll("[data-oauth]").forEach((btn) => {
    btn.addEventListener("click", () => onOAuth?.(btn.dataset.oauth));
  });

  const otpForm = root.querySelector("#otp-form");
  if (otpForm) {
    const digits = Array.from(root.querySelectorAll(".otp-digit"));
    digits.forEach((input, i) => {
      input.addEventListener("input", () => {
        const v = input.value.replace(/\D/g, "").slice(-1);
        input.value = v;
        if (v && i < digits.length - 1) digits[i + 1].focus();
        const code = readOtp(root);
        const hidden = root.querySelector("#otp-value");
        if (hidden) hidden.value = code;
        if (code.length === 6) onVerifyOtp?.(code);
      });
      input.addEventListener("keydown", (e) => {
        if (e.key === "Backspace" && !input.value && i > 0) digits[i - 1].focus();
      });
      input.addEventListener("paste", (e) => {
        e.preventDefault();
        const pasted = (e.clipboardData?.getData("text") || "").replace(/\D/g, "").slice(0, 6);
        pasted.split("").forEach((ch, idx) => {
          if (digits[idx]) digits[idx].value = ch;
        });
        const focusIdx = Math.min(pasted.length, digits.length - 1);
        digits[focusIdx]?.focus();
        if (pasted.length === 6) onVerifyOtp?.(pasted);
      });
    });
    otpForm.addEventListener("submit", (e) => {
      e.preventDefault();
      onVerifyOtp?.(readOtp(root));
    });
    digits[0]?.focus();
  }
}
