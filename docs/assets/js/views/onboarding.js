import { escapeHtml, SPECIALTIES, CREDENTIALS } from "../brand.js";
import { appStore } from "../store.js";

const DOCTOR_STEPS = [
  { icon: "👤", title: "Who are you?", subtitle: "Enter your name and credential type." },
  { icon: "📄", title: "Verify Credentials", subtitle: "We check NPI, DEA#, license, and malpractice with federal registries." },
  { icon: "✉", title: "Confirm Email", subtitle: "Enter the 6-digit code we sent to your email." },
  { icon: "🏥", title: "Your Specialties", subtitle: "Select all specialties you're qualified to cover." }
];

const HOSPITAL_STEPS = [
  { icon: "🏥", title: "Hospital Details", subtitle: "Enter your facility name and NPI." },
  { icon: "✉", title: "Confirm Email", subtitle: "Enter the 6-digit code we sent to your email." },
  { icon: "📋", title: "Scheduling Policy", subtitle: "Set default on-call granularity and rules." }
];

export function renderOnboarding(role, state) {
  const steps = role === "Doctor" ? DOCTOR_STEPS : HOSPITAL_STEPS;
  const step = steps[state.step] || steps[0];
  const progress = ((state.step + 1) / steps.length) * 100;

  return `
    <div class="onboarding-screen">
      <div class="progress-bar"><div style="width:${progress}%"></div></div>
      <div class="onboarding-body">
        <div class="onboarding-icon">${step.icon}</div>
        <h2 class="page-title" style="text-align:center;margin-bottom:8px">${escapeHtml(step.title)}</h2>
        <p class="subtitle" style="text-align:center;margin-bottom:24px">${escapeHtml(step.subtitle)}</p>
        ${role === "Doctor" ? doctorStepBody(state) : hospitalStepBody(state)}
        ${state.error ? `<p class="error-text" style="margin-top:12px">${escapeHtml(state.error)}</p>` : ""}
      </div>
      <div class="onboarding-actions">
        ${state.step > 0 ? `<button type="button" class="btn-bordered" data-onb-back>Back</button>` : "<span></span>"}
        <button type="button" class="btn-primary" data-onb-next ${state.loading ? "disabled" : ""}>
          ${state.loading ? `<span class="spinner"></span>` : (state.step >= steps.length - 1 ? "Get Started" : "Continue")}
        </button>
      </div>
    </div>`;
}

function doctorStepBody(state) {
  switch (state.step) {
    case 0:
      return `
        <div class="form-stack">
          <div class="form-field"><label>First name</label><input data-field="firstName" value="${escapeHtml(state.firstName || "")}" /></div>
          <div class="form-field"><label>Last name</label><input data-field="lastName" value="${escapeHtml(state.lastName || "")}" /></div>
          <div class="form-field"><label>Credential</label>
            <select data-field="credential">${CREDENTIALS.map((c) => `<option ${state.credential === c ? "selected" : ""}>${c}</option>`).join("")}</select>
          </div>
        </div>`;
    case 1:
      return `
        <div class="form-stack">
          <div class="form-field"><label>NPI (10 digits)</label><input data-field="npi" maxlength="10" value="${escapeHtml(state.npi || "")}" /></div>
          <div class="form-field"><label>License #</label><input data-field="licenseNumber" value="${escapeHtml(state.licenseNumber || "")}" /></div>
          <div class="form-field"><label>License state</label><input data-field="licenseState" maxlength="2" value="${escapeHtml(state.licenseState || "")}" /></div>
          <div class="form-field"><label>Email</label><input data-field="email" type="email" value="${escapeHtml(state.email || appStore.session?.email || "")}" /></div>
          <button type="button" class="btn-secondary" data-verify-npi ${state.verified ? "disabled" : ""}>
            ${state.verified ? "✓ Credentials verified" : "Verify with NPI Registry"}
          </button>
        </div>`;
    case 2:
      return `
        <div class="form-stack" style="text-align:center">
          <p class="subtitle">Demo mode: use code <strong>123456</strong></p>
          <div class="form-field"><label>6-digit code</label><input data-field="code" maxlength="6" inputmode="numeric" placeholder="123456" /></div>
        </div>`;
    default:
      return `
        <div class="chip-grid">
          ${SPECIALTIES.map((sp) => `
            <button type="button" class="chip ${state.specialties?.includes(sp) ? "active" : ""}" data-specialty="${escapeHtml(sp)}">${escapeHtml(sp)}</button>
          `).join("")}
        </div>`;
  }
}

function hospitalStepBody(state) {
  switch (state.step) {
    case 0:
      return `
        <div class="form-stack">
          <div class="form-field"><label>Hospital name</label><input data-field="name" value="${escapeHtml(state.name || "")}" /></div>
          <div class="form-field"><label>NPI</label><input data-field="npi" maxlength="10" value="${escapeHtml(state.npi || "")}" /></div>
          <div class="form-field"><label>Email</label><input data-field="email" type="email" value="${escapeHtml(state.email || appStore.session?.email || "")}" /></div>
        </div>`;
    case 1:
      return `
        <div class="form-stack" style="text-align:center">
          <p class="subtitle">Demo mode: use code <strong>123456</strong></p>
          <div class="form-field"><label>6-digit code</label><input data-field="code" maxlength="6" inputmode="numeric" /></div>
        </div>`;
    default:
      return `
        <div class="form-stack">
          <div class="form-field"><label>Granularity</label>
            <select data-field="granularity"><option value="day">Per day</option><option value="hour">Per hour</option></select>
          </div>
          <p class="subtitle">Default scheduling policy will apply to newly generated shifts.</p>
        </div>`;
  }
}

export function readOnboardingFields(root) {
  const data = {};
  root.querySelectorAll("[data-field]").forEach((el) => {
    data[el.dataset.field] = el.value;
  });
  return data;
}

export function bindOnboarding(root, handlers) {
  root.querySelector("[data-onb-back]")?.addEventListener("click", handlers.onBack);
  root.querySelector("[data-onb-next]")?.addEventListener("click", handlers.onNext);
  root.querySelector("[data-verify-npi]")?.addEventListener("click", handlers.onVerify);
  root.querySelectorAll("[data-specialty]").forEach((btn) => {
    btn.addEventListener("click", () => handlers.onToggleSpecialty(btn.dataset.specialty));
  });
}

export function finishDoctorOnboarding(state) {
  const profile = {
    id: crypto.randomUUID(),
    userID: appStore.session?.userID,
    firstName: state.firstName.trim(),
    lastName: state.lastName.trim(),
    credential: state.credential,
    npi: state.npi,
    deaNumber: "",
    licenseNumber: state.licenseNumber,
    licenseState: state.licenseState.toUpperCase(),
    specialties: state.specialties || [],
    email: state.email,
    verificationStatus: "pending",
    verificationFlags: []
  };
  appStore.saveDoctorProfile(profile);
}

export function finishHospitalOnboarding(state) {
  const profile = {
    id: crypto.randomUUID(),
    userID: appStore.session?.userID,
    name: state.name.trim(),
    npi: state.npi,
    email: state.email,
    verificationStatus: "pending",
    verificationFlags: [],
    schedulingPolicy: { granularity: state.granularity || "day" }
  };
  appStore.saveHospitalProfile(profile);
}
