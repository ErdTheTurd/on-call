import { isConfigured, getSupabase } from "./supabase-client.js";
import {
  authState, beginSession, registerAccount, signInLocal,
  signInRemote, signUpRemote, appStore, syncEverything, startPeriodicSync
} from "./store.js";
import { renderAuthView, bindAuth } from "./views/auth.js";
import {
  renderOnboarding, bindOnboarding, readOnboardingFields,
  finishDoctorOnboarding, finishHospitalOnboarding
} from "./views/onboarding.js";
import { renderDoctorApp, bindDoctor } from "./views/doctor.js";
import { renderHospitalApp, bindHospital } from "./views/hospital.js";
import { lookupNPI, verifyDoctorCredentials, validateInstitutionalEmail } from "./domain/verification.js";

const state = {
  route: "boot",
  authMode: "signin",
  role: "Doctor",
  email: "",
  error: null,
  loading: false,
  onb: { step: 0, role: "Doctor", specialties: [], verified: false, codeVerified: false },
  ui: { tab: "home", sheet: false, daySheet: null, calendarMonth: new Date().toISOString() }
};

function merge(path, patch) {
  if (path === "ui") Object.assign(state.ui, patch);
  else if (path === "onb") Object.assign(state.onb, patch);
  else Object.assign(state, patch);
}

function update(patch) {
  if (patch.route) state.route = patch.route;
  if (patch.ui) merge("ui", patch.ui);
  if (patch.onb) merge("onb", patch.onb);

  const uiKeys = [
    "tab", "sheet", "daySheet", "tradeSheet", "calendarMonth", "selectedDate",
    "alterDate", "alterSpecialty", "alterUseAlgo", "alterOverride",
    "alterCalendarMonth", "alterRateFloor", "alterUseFlat", "alterFlatRate", "alterSaved",
    "adminFilter", "adminSearch", "policyTab", "doctorFilter", "doctorAutoOnly",
    "doctorDetailId", "rateEditSpecialty"
  ];
  if (uiKeys.some((k) => k in patch)) {
    const uiPatch = {};
    for (const k of uiKeys) {
      if (k in patch) uiPatch[k] = patch[k];
    }
    merge("ui", uiPatch);
  }

  if ("authMode" in patch || "role" in patch || "email" in patch || "error" in patch || "loading" in patch) {
    Object.assign(state, patch);
  }
  render();
}

async function boot() {
  if (isConfigured()) {
    try {
      const supabase = getSupabase();
      const { data } = await supabase.auth.getSession();
      if (data.session?.user) {
        beginSession({
          userID: data.session.user.id,
          email: data.session.user.email,
          role: appStore.savedRole || "Doctor"
        });
      }
    } catch { /* local */ }
    await syncEverything();
  }

  const auth = authState();
  if (auth.kind === "loggedOut") state.route = "auth";
  else if (auth.kind === "needsOnboarding") {
    state.route = "onboarding";
    state.onb.role = auth.role;
    state.onb.step = 0;
  } else {
    state.route = auth.role === "Hospital" ? "hospital" : "doctor";
  }
  render();
  appStore.subscribe(() => render());
  startPeriodicSync(20000);
}

function render() {
  const root = document.getElementById("app");
  if (!root) return;

  if (state.route === "auth") {
    root.innerHTML = renderAuthView(state, {});
    bindAuth(root, {
      onMode: (mode) => update({ authMode: mode, error: null }),
      onRole: (role) => update({ role }),
      onSubmit: handleAuthSubmit
    });
    return;
  }

  if (state.route === "onboarding") {
    root.innerHTML = `<div class="bg-gradient"><div class="blob-bottom"></div></div>${renderOnboarding(state.onb.role, state.onb)}`;
    bindOnboarding(root, {
      onBack: () => update({ onb: { ...state.onb, step: Math.max(0, state.onb.step - 1) } }),
      onNext: handleOnboardingNext,
      onVerify: handleNpiVerify,
      onToggleSpecialty: (sp) => {
        const set = new Set(state.onb.specialties || []);
        set.has(sp) ? set.delete(sp) : set.add(sp);
        update({ onb: { ...state.onb, specialties: [...set] } });
      }
    });
    root.querySelectorAll("[data-field]").forEach((el) => {
      el.addEventListener("change", () => Object.assign(state.onb, readOnboardingFields(root)));
      el.addEventListener("input", () => Object.assign(state.onb, readOnboardingFields(root)));
    });
    return;
  }

  if (state.route === "doctor") {
    root.innerHTML = renderDoctorApp(state.ui);
    bindDoctor(root, state.ui, (p) => {
      if (p.route) state.route = p.route;
      update(p);
    });
    return;
  }

  if (state.route === "hospital") {
    root.innerHTML = renderHospitalApp(state.ui);
    bindHospital(root, state.ui, (p) => {
      if (p.route) state.route = p.route;
      update(p);
    });
  }
}

async function handleAuthSubmit({ email, password, confirm }) {
  state.error = null;
  if (!email) { update({ error: "Please enter your email." }); return; }
  if (password.length < 6) { update({ error: "Password must be at least 6 characters." }); return; }
  if (state.authMode === "signup" && password !== confirm) {
    update({ error: "Passwords don't match." }); return;
  }

  update({ loading: true, email });

  try {
    if (state.authMode === "signup") {
      if (isConfigured()) {
        const res = await signUpRemote(email, password, state.role);
        beginSession({ userID: res.userID, email: res.email, role: state.role });
      } else {
        if (signInLocal(email, password)) {
          update({ error: "Account already exists. Sign in instead.", loading: false });
          return;
        }
        const userID = registerAccount(email, password, state.role);
        beginSession({ userID, email, role: state.role });
      }
      state.route = "onboarding";
      state.onb = { step: 0, role: state.role, specialties: [], verified: false, codeVerified: false, email };
      update({ loading: false });
      return;
    }

    if (isConfigured()) {
      try {
        const res = await signInRemote(email, password);
        beginSession({ userID: res.userID, email: res.email, role: res.role });
        const auth = authState();
        state.route = auth.kind === "needsOnboarding" ? "onboarding" : (res.role === "Hospital" ? "hospital" : "doctor");
        if (auth.kind === "needsOnboarding") state.onb.role = res.role;
        update({ loading: false });
        return;
      } catch (net) {
        /* fall through to local */
      }
    }

    let acct = signInLocal(email, password);
    if (!acct) {
      const userID = registerAccount(email, password, "Doctor");
      beginSession({ userID, email, role: "Doctor" });
      state.route = "onboarding";
      state.onb = { step: 0, role: "Doctor", specialties: [], email };
      update({ loading: false });
      return;
    }
    beginSession({ userID: acct.id, email: acct.email, role: acct.role });
    const auth = authState();
    state.route = auth.kind === "needsOnboarding" ? "onboarding" : (acct.role === "Hospital" ? "hospital" : "doctor");
    if (auth.kind === "needsOnboarding") state.onb.role = acct.role;
    update({ loading: false });
  } catch (err) {
    update({ error: err.message || "Authentication failed.", loading: false });
  }
}

async function handleNpiVerify() {
  const root = document.getElementById("app");
  Object.assign(state.onb, readOnboardingFields(root));
  const role = state.onb.role;
  const npi = state.onb.npi;

  update({ onb: { ...state.onb, loading: true, error: null } });
  try {
    if (role === "Doctor") {
      const emailCheck = validateInstitutionalEmail(state.onb.email || appStore.session?.email);
      // Allow demo personal emails with a soft flag — still verify NPI.
      const record = await lookupNPI(npi, "NPI-1");
      const result = verifyDoctorCredentials({
        firstName: state.onb.firstName,
        lastName: state.onb.lastName,
        credential: state.onb.credential,
        npiRecord: record,
        email: state.onb.email || appStore.session?.email
      });
      // Soften email domain for demo accounts so onboarding isn't blocked.
      if (!emailCheck.ok) {
        result.flags = [...(result.flags || []).filter((f) => !f.includes("institutional")), "Using non-institutional email — queued for review."];
        if (result.finalStatus === "flagged" && result.nameMatches !== false) result.finalStatus = "pending";
      }
      update({
        onb: {
          ...state.onb,
          verified: true,
          verificationStatus: result.finalStatus,
          verificationFlags: result.flags,
          npiRecord: record,
          loading: false,
          error: null
        }
      });
    } else {
      const record = await lookupNPI(npi, "NPI-2");
      if (record.organizationName && !state.onb.name) state.onb.name = record.organizationName;
      update({
        onb: {
          ...state.onb,
          verified: true,
          name: state.onb.name || record.organizationName || state.onb.name,
          loading: false,
          error: null
        }
      });
    }
  } catch (err) {
    update({ onb: { ...state.onb, loading: false, error: err.message || "Verification failed." } });
  }
}

function handleOnboardingNext() {
  const root = document.getElementById("app");
  Object.assign(state.onb, readOnboardingFields(root));
  const role = state.onb.role;
  const steps = role === "Doctor" ? 4 : 3;

  if (role === "Doctor") {
    if (state.onb.step === 0 && (!state.onb.firstName?.trim() || !state.onb.lastName?.trim())) {
      update({ onb: { ...state.onb, error: "Enter your name." } }); return;
    }
    if (state.onb.step === 1 && !state.onb.verified) {
      update({ onb: { ...state.onb, error: "Verify credentials first." } }); return;
    }
    if (state.onb.step === 2 && state.onb.code !== "123456") {
      update({ onb: { ...state.onb, error: "Incorrect or expired code. Try 123456 in demo mode." } }); return;
    }
    if (state.onb.step === 3 && !(state.onb.specialties?.length)) {
      update({ onb: { ...state.onb, error: "Select at least one specialty." } }); return;
    }
  } else {
    if (state.onb.step === 0 && (!state.onb.name?.trim() || !state.onb.npi)) {
      update({ onb: { ...state.onb, error: "Enter hospital name and NPI." } }); return;
    }
    if (state.onb.step === 1 && state.onb.code !== "123456") {
      update({ onb: { ...state.onb, error: "Use demo code 123456." } }); return;
    }
  }

  if (state.onb.step >= steps - 1) {
    update({ loading: true });
    (async () => {
      try {
        if (role === "Doctor") await finishDoctorOnboarding(state.onb);
        else await finishHospitalOnboarding(state.onb);
        state.route = role === "Hospital" ? "hospital" : "doctor";
        update({ onb: { ...state.onb, error: null }, loading: false });
      } catch (err) {
        update({ onb: { ...state.onb, error: err.message || "Could not save profile." }, loading: false });
      }
    })();
    return;
  }

  update({ onb: { ...state.onb, step: state.onb.step + 1, error: null } });
}

boot();
