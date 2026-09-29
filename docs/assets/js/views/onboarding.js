import { escapeHtml, SPECIALTIES, CREDENTIALS } from "../brand.js";
import { appStore, finishDoctorProfile, finishHospitalProfile, defaultPolicy } from "../store.js";
import { isConfigured } from "../supabase-client.js";
import { upsertHospitalProfile, upsertPolicy } from "../domain/sync.js";

function onboardingAddress(state) {
  const role = state.role || "Doctor";
  const raw = role === "Hospital" ? (state.email || "") : (state.email || appStore.session?.email || "");
  return String(raw).trim().toLowerCase();
}

function codeIsVerified(state) {
  const email = onboardingAddress(state);
  return !!state.codeVerified && String(state.codeVerifiedEmail || "").trim().toLowerCase() === email && email.includes("@");
}

function codeWasSent(state) {
  const email = onboardingAddress(state);
  return !!state.codeSent && String(state.codeSentEmail || "").trim().toLowerCase() === email;
}

const DOCTOR_STEPS = [
  { icon: "👤", title: "Who are you?", subtitle: "Enter your name and credential type." },
  { icon: "📄", title: "Verify Credentials", subtitle: "We verify your NPI against the national registry. License and DEA numbers are reviewed by our team." },
  { icon: "✉", title: "Confirm Email", subtitle: "Enter the 6-digit code we sent to your email." },
  { icon: "🏥", title: "Your Specialty", subtitle: "Choose the one specialty you cover on call." }
];

const HOSPITAL_STEPS = [
  { icon: "🏥", title: "Hospital Details", subtitle: "Enter your facility name and NPI." },
  { icon: "✉", title: "Confirm Email", subtitle: "Enter the 6-digit code we sent to your email." },
  { icon: "📋", title: "Scheduling Policy", subtitle: "Set default on-call granularity and rules." }
];

export function minOnboardingStep(state) {
  if ((state.role || "Doctor") === "Doctor") return state.skipNameStep ? 1 : 0;
  return 0;
}

export function nextOnboardingStep(state) {
  let step = (state.step || 0) + 1;
  const role = state.role || "Doctor";
  const skipConfirm = state.skipEmailConfirmStep || state.skipEmailStep;
  if (role === "Doctor" && step === 2 && skipConfirm) step = 3;
  // Hospitals always stop on email confirm (step 1).
  return step;
}

export function previousOnboardingStep(state) {
  let step = (state.step || 0) - 1;
  const role = state.role || "Doctor";
  const skipConfirm = state.skipEmailConfirmStep || state.skipEmailStep;
  if (role === "Doctor" && step === 2 && skipConfirm) step = 1;
  return Math.max(minOnboardingStep(state), step);
}

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
        ${state.step > minOnboardingStep(state) ? `<button type="button" class="btn-bordered" data-onb-back>Back</button>` : "<span></span>"}
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
          ${state.skipNameStep ? "" : `
          <div class="form-field"><label>First name</label><input data-field="firstName" value="${escapeHtml(state.firstName || "")}" /></div>
          <div class="form-field"><label>Last name</label><input data-field="lastName" value="${escapeHtml(state.lastName || "")}" /></div>
          `}
          <div class="form-field"><label>Credential</label>
            <select data-field="credential">${CREDENTIALS.map((c) => `<option ${state.credential === c ? "selected" : ""}>${c}</option>`).join("")}</select>
          </div>
        </div>`;
    case 1:
      return `
        <div class="form-stack">
          <div class="form-field"><label>NPI (10 digits)</label><input data-field="npi" maxlength="10" inputmode="numeric" value="${escapeHtml(state.npi || "")}" /></div>
          <div class="form-field"><label>DEA #</label><input data-field="deaNumber" value="${escapeHtml(state.deaNumber || "")}" placeholder="Optional" /></div>
          <div class="form-field"><label>License #</label><input data-field="licenseNumber" value="${escapeHtml(state.licenseNumber || "")}" /></div>
          <div class="form-field"><label>License state</label><input data-field="licenseState" maxlength="2" value="${escapeHtml(state.licenseState || "")}" /></div>
          ${state.skipEmailStep ? "" : `<div class="form-field"><label>Email</label><input data-field="email" type="email" value="${escapeHtml(state.email || appStore.session?.email || "")}" /></div>`}
          <button type="button" class="btn-secondary" data-verify-npi ${state.verified || state.loading ? "disabled" : ""}>
            ${state.loading ? `<span class="spinner"></span>` : (state.verified ? "✓ NPI checked" : "Check NPI registry")}
          </button>
          <p class="subtitle">Your NPI is checked automatically against the national NPI registry. License and DEA numbers are saved for our team to review. We do not upload credential documents.</p>
          ${state.verified && state.verificationFlags?.length ? `
            <div class="subtitle" style="font-size:12px">${state.verificationFlags.map(escapeHtml).join("<br>")}</div>` : ""}
          ${state.npiRecord && !state.npiRecord.offline ? `
            <div class="card" style="padding:12px">
              <div class="subtitle">Registry match</div>
              <div>${escapeHtml(state.npiRecord.firstName)} ${escapeHtml(state.npiRecord.lastName)} · ${escapeHtml(state.npiRecord.credential || "")}</div>
              <div class="tertiary" style="font-size:12px">${escapeHtml(state.npiRecord.taxonomyDescription || "")}</div>
            </div>` : ""}
        </div>`;
    case 2:
      return `
        <div class="form-stack" style="text-align:center">
          <p class="subtitle">We sent (or will send) a 6-digit code to <strong>${escapeHtml(state.email || appStore.session?.email || "")}</strong>.</p>
          ${codeIsVerified(state) ? `<p class="subtitle" style="color:var(--success,#34c759)">Email verified.</p>` : `
          <button type="button" class="btn-secondary" data-send-code ${state.loading ? "disabled" : ""}>
            ${state.loading ? `<span class="spinner"></span>` : (codeWasSent(state) ? "Resend code" : "Send verification code")}
          </button>
          <div class="form-field"><label>6-digit code</label><input data-field="code" maxlength="6" inputmode="numeric" value="${escapeHtml(state.code || "")}" /></div>
          `}
        </div>`;
    default:
      return `
        <p class="subtitle" style="text-align:center;margin-bottom:16px">You can change this later with support — one specialty keeps the marketplace focused.</p>
        <div class="chip-grid">
          ${SPECIALTIES.map((sp) => `
            <button type="button" class="chip ${state.specialties?.[0] === sp ? "active" : ""}" data-specialty="${escapeHtml(sp)}">${escapeHtml(sp)}</button>
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
          <div class="form-field"><label>NPI</label><input data-field="npi" maxlength="10" inputmode="numeric" value="${escapeHtml(state.npi || "")}" /></div>
          <div class="form-field"><label>Hospital work email</label><input data-field="email" type="email" placeholder="admin@yourhospital.org" value="${escapeHtml(state.email || "")}" /></div>
          <p class="subtitle" style="font-size:12px">Use an email on your hospital’s domain — not Gmail, iCloud, or Apple Hide My Email.</p>
          <button type="button" class="btn-secondary" data-verify-npi ${state.verified || state.loading ? "disabled" : ""}>
            ${state.loading ? `<span class="spinner"></span>` : (state.verified ? "✓ Facility verified" : "Verify facility NPI")}
          </button>
          ${state.verificationFlags?.length ? `
            <div class="subtitle" style="font-size:12px">${state.verificationFlags.map(escapeHtml).join("<br>")}</div>` : ""}
        </div>`;
    case 1:
      return `
        <div class="form-stack" style="text-align:center">
          <p class="subtitle">Confirm <strong>${escapeHtml(state.email || "")}</strong> with the 6-digit code from your inbox.</p>
          ${codeIsVerified(state) ? `<p class="subtitle" style="color:var(--success,#34c759)">Email verified.</p>` : `
          <button type="button" class="btn-secondary" data-send-code ${state.loading ? "disabled" : ""}>
            ${state.loading ? `<span class="spinner"></span>` : (codeWasSent(state) ? "Resend code" : "Send verification code")}
          </button>
          <div class="form-field"><label>6-digit code</label><input data-field="code" maxlength="6" inputmode="numeric" value="${escapeHtml(state.code || "")}" /></div>
          `}
        </div>`;
    default:
      return `
        <div class="form-stack">
          <div class="form-field"><label>Granularity</label>
            <select data-field="granularity">
              <option value="day" ${state.granularity === "day" ? "selected" : ""}>Per day</option>
              <option value="hour" ${state.granularity === "hour" ? "selected" : ""}>Per hour</option>
            </select>
          </div>
          <label class="toggle-row">
            <span>Require administrator approval for shifts</span>
            <input type="checkbox" data-field="adminApprove" ${state.adminApprove ? "checked" : ""} />
          </label>
          <p class="subtitle">Default scheduling policy applies to newly generated shifts.</p>
        </div>`;
  }
}

export function readOnboardingFields(root) {
  const data = {};
  root.querySelectorAll("[data-field]").forEach((el) => {
    if (el.type === "checkbox") data[el.dataset.field] = el.checked;
    else data[el.dataset.field] = el.value;
  });
  return data;
}

export function bindOnboarding(root, handlers) {
  root.querySelector("[data-onb-back]")?.addEventListener("click", handlers.onBack);
  root.querySelector("[data-onb-next]")?.addEventListener("click", handlers.onNext);
  root.querySelector("[data-verify-npi]")?.addEventListener("click", handlers.onVerify);
  root.querySelector("[data-send-code]")?.addEventListener("click", handlers.onSendCode);
  root.querySelectorAll("[data-specialty]").forEach((btn) => {
    btn.addEventListener("click", () => handlers.onToggleSpecialty(btn.dataset.specialty));
  });
}

export async function finishDoctorOnboarding(state) {
  const profile = {
    id: appStore.session?.userID || crypto.randomUUID(),
    userID: appStore.session?.userID,
    firstName: state.firstName.trim(),
    lastName: state.lastName.trim(),
    credential: state.credential,
    npi: state.npi,
    deaNumber: state.deaNumber || "",
    licenseNumber: state.licenseNumber,
    licenseState: (state.licenseState || "").toUpperCase(),
    specialties: state.specialties?.length ? [state.specialties[0]] : [],
    email: state.email || appStore.session?.email,
    verificationStatus: state.verificationStatus || (state.verified ? "pending" : "unverified"),
    verificationFlags: state.verificationFlags || [],
    documents: []
  };
  await finishDoctorProfile(profile);
}

export async function finishHospitalOnboarding(state) {
  const email = String(state.email || "").trim().toLowerCase();
  if (!state.codeVerified || String(state.codeVerifiedEmail || "").trim().toLowerCase() !== email || !email.includes("@")) {
    throw new Error("Verify your hospital work email before continuing.");
  }
  const policy = defaultPolicy();
  policy.granularity = state.granularity || "day";
  policy.administratorApproveShifts = !!state.adminApprove;

  const pendingKey = "mdshift_pending_hospital_id";
  const profile = {
    id: state.savedHospitalId || sessionStorage.getItem(pendingKey) || crypto.randomUUID(),
    userID: appStore.session?.userID,
    name: state.name.trim(),
    npi: state.npi,
    email: state.email || appStore.session?.email,
    verificationStatus: state.verificationStatus || (state.verified ? "pending" : "pending"),
    verificationFlags: state.verificationFlags || [],
    schedulingPolicy: policy,
    priorityPosting: false,
    autoPay: false
  };
  state.savedHospitalId = profile.id;
  try { sessionStorage.setItem(pendingKey, profile.id); } catch { /* private mode */ }

  if (isConfigured()) {
    let remoteSaved = false;
    try {
      await upsertHospitalProfile(profile);
      if (profile.schedulingPolicy) await upsertPolicy(profile.id, profile.schedulingPolicy);
      remoteSaved = true;
      const { notifyHospitalSignup } = await import("../domain/email.js");
      await notifyHospitalSignup({
        name: profile.name,
        email: profile.email,
        npi: profile.npi,
        flags: profile.verificationFlags
      });
    } catch (err) {
      const detail = err?.message || "Could not finish hospital signup.";
      if (remoteSaved) {
        throw new Error(`Your hospital profile was saved, but the signup email failed. ${detail}`);
      }
      throw new Error(detail);
    }
  }

  try { sessionStorage.removeItem(pendingKey); } catch { /* private mode */ }
  await finishHospitalProfile(profile);
}
