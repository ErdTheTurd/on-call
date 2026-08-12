import { isConfigured, getSupabase } from "./supabase-client.js";
import {
  authState, beginSession, registerAccount, signInLocal,
  signInRemote, signUpRemote, resendSignupEmail, verifySignupOtp,
  signInWithOAuth, completeOAuthSession, completeMfaSession, signOut, appStore, syncEverything, startPeriodicSync,
  normalizeEmail, syncStatus
} from "./store.js";
import { enrollTotp, verifyTotp, challengeAndVerifyFirstTotp } from "./domain/mfa.js";
import { hydrateLocalProfiles } from "./domain/sync.js";
import { renderAuthView, bindAuth } from "./views/auth.js";
import { renderAdminApp, bindAdmin } from "./views/admin.js";
import { isAdminUser, fetchApplications, setApplicationStatus } from "./domain/approvals.js";
import { fetchSavingsEvents, groupSavingsByHospital } from "./domain/savings.js";
import { startDemo, isDemoSession, clearDemoFlag } from "./domain/demo.js";
import { renderLanding, bindLanding } from "./views/landing.js";
import {
  renderOnboarding, bindOnboarding, readOnboardingFields,
  finishDoctorOnboarding, finishHospitalOnboarding
} from "./views/onboarding.js";
import { renderDoctorApp, bindDoctor } from "./views/doctor.js";
import { renderHospitalApp, bindHospital } from "./views/hospital.js";
import { lookupNPI, verifyDoctorCredentials, validateInstitutionalEmail } from "./domain/verification.js";
import { refreshPlusMembership, setPlusMembership } from "./domain/plus.js";

const state = {
  route: "boot",
  authMode: "signin",
  role: "Doctor",
  email: "",
  error: null,
  loading: false,
  verifyEmail: null,
  verifyNotice: null,
  otpCode: "",
  mfaChallenge: false,
  mfaEnroll: null,
  mfaCode: "",
  pendingAuth: null,
  onb: { step: 0, role: "Doctor", specialties: [], verified: false, codeVerified: false },
  ui: { tab: "home", sheet: false, daySheet: null, calendarMonth: new Date().toISOString() },
  admin: emptyAdminState()
};

function emptyAdminState() {
  return {
    loading: true, error: null, items: [], email: "",
    section: "approvals", filter: "review", kind: "all", search: "",
    busyKey: null, confirmKey: null, toast: null, menuOpen: false,
    savings: { loading: false, error: null, rows: [], loadedAt: null }
  };
}

function merge(path, patch) {
  if (path === "ui") Object.assign(state.ui, patch);
  else if (path === "onb") Object.assign(state.onb, patch);
  else if (path === "admin") Object.assign(state.admin, patch);
  else Object.assign(state, patch);
}

function update(patch) {
  if (patch.route === "auth" || patch.route === "landing") clearDemoFlag();
  if (patch.route) state.route = patch.route;
  if (patch.ui) merge("ui", patch.ui);
  if (patch.onb) merge("onb", patch.onb);
  if (patch.admin) merge("admin", patch.admin);

  const uiKeys = [
    "tab", "sheet", "daySheet", "tradeSheet", "calendarMonth", "selectedDate",
    "alterDate", "alterSpecialty", "alterUseAlgo", "alterOverride",
    "alterCalendarMonth", "alterRateFloor", "alterUseFlat", "alterFlatRate", "alterSaved",
    "alterDrafts",
    "adminFilter", "adminSearch", "policyTab", "doctorFilter", "doctorAutoOnly",
    "doctorDetailId", "rateEditSpecialty", "focusOpenDays",
    "counterTradeId", "counterComp", "counterAltShiftId",
    "tradePartnerId", "tradeComp"
  ];
  if (uiKeys.some((k) => k in patch)) {
    const uiPatch = {};
    for (const k of uiKeys) {
      if (k in patch) uiPatch[k] = patch[k];
    }
    merge("ui", uiPatch);
  }

  if ("authMode" in patch || "role" in patch || "email" in patch || "error" in patch || "loading" in patch
      || "verifyEmail" in patch || "verifyNotice" in patch || "otpCode" in patch
      || "mfaChallenge" in patch || "mfaEnroll" in patch || "mfaCode" in patch || "pendingAuth" in patch) {
    Object.assign(state, patch);
  }
  render();
}

// Re-rendering on every keystroke drops focus, so put the caret back.
let restoreSearchCaret = false;

/** Loads a fully populated sample account so the product can be seen at a glance. */
function enterDemo(role) {
  startDemo(role);
  const hospital = role === "Hospital";
  state.ui = {
    tab: hospital ? "dashboard" : "home",
    sheet: false,
    daySheet: null,
    calendarMonth: new Date().toISOString()
  };
  state.route = hospital ? "hospital" : "doctor";
  update({ error: null, loading: false });
}

/** Routes admins straight to the approvals queue. Returns false for everyone else. */
async function enterAdminIfPermitted(userId, email) {
  if (!userId || !(await isAdminUser(userId))) return false;
  state.route = "admin";
  state.loading = false;
  state.admin = { ...emptyAdminState(), email: email || "" };
  render();
  await loadApplications();
  return true;
}

async function loadApplications() {
  update({ admin: { loading: true, error: null, toast: null } });
  try {
    const items = await fetchApplications();
    update({ admin: { items, loading: false, error: null } });
  } catch (err) {
    update({ admin: { loading: false, error: err.message || "Could not reach Supabase." } });
  }
}

async function loadHospitalSavings() {
  update({ admin: { savings: { ...state.admin.savings, loading: true, error: null } } });
  try {
    const events = await fetchSavingsEvents();
    update({
      admin: {
        savings: {
          loading: false,
          error: null,
          rows: groupSavingsByHospital(events),
          loadedAt: new Date().toISOString()
        }
      }
    });
  } catch (err) {
    update({
      admin: {
        savings: {
          ...state.admin.savings,
          loading: false,
          error: err.message || "Could not reach Supabase."
        }
      }
    });
  }
}

function decisionLabel(status) {
  return {
    verified: "approved",
    waitlisted: "moved to the waitlist",
    rejected: "rejected",
    pending: "moved back to review"
  }[status] || "updated";
}

async function decideApplication(key, status) {
  const application = state.admin.items.find((a) => a.key === key);
  if (!application) return;

  update({ admin: { busyKey: key, confirmKey: null, toast: null, error: null } });
  try {
    await setApplicationStatus(application, status);
    const reviewedAt = new Date().toISOString();
    const items = state.admin.items.map((a) => (
      a.key === key ? { ...a, status, reviewedAt } : a
    ));
    update({
      admin: { items, busyKey: null, toast: `${application.name} ${decisionLabel(status)}.` }
    });
  } catch (err) {
    update({ admin: { busyKey: null, error: err.message || "Could not save that decision." } });
  }
}

async function boot() {
  const bootParams = new URLSearchParams(location.search);
  const plusParam = bootParams.get("plus");
  if (plusParam === "success") {
    try {
      const membership = await refreshPlusMembership();
      // Optimistic if webhook is still catching up
      if (!membership.active) setPlusMembership({ active: true, until: null });
    } catch { /* ignore */ }
    history.replaceState({}, "", location.pathname);
  } else if (plusParam === "cancel") {
    history.replaceState({}, "", location.pathname);
  }
  if (bootParams.get("open") === "plus") {
    state.sheet = "plus";
  }

  // A demo runs entirely on local sample data — never sync it to the real project.
  if (isConfigured() && !isDemoSession()) {
    let sessionUser = null;
    let sessionRole = appStore.savedRole || "Doctor";
    try {
      // OAuth callback.html may have just established a session — apply role stash.
      const oauth = await completeOAuthSession();
      if (oauth?.needsMfa) {
        state.route = "auth";
        state.mfaChallenge = true;
        state.pendingAuth = { userID: oauth.userID, email: oauth.email };
        update({ loading: false, error: null, mfaCode: "" });
        return;
      }
      if (oauth) {
        beginSession({ userID: oauth.userID, email: oauth.email, role: oauth.role });
        sessionUser = { id: oauth.userID, email: oauth.email };
        sessionRole = oauth.role;
        if (oauth.suggestMfaEnroll) {
          await enterAuthedRoute(
            { userID: oauth.userID, email: oauth.email, role: oauth.role, suggestMfaEnroll: true },
            { suggestMfa: true }
          );
          return;
        }
      }

      const supabase = getSupabase();
      const { data } = await supabase.auth.getSession();
      if (data.session?.user) {
        sessionUser = data.session.user;
        // Prefer the role stored on the server profile over a stale local savedRole.
        try {
          const { data: profile } = await supabase
            .from("profiles")
            .select("role")
            .eq("id", sessionUser.id)
            .maybeSingle();
          if (profile?.role) {
            sessionRole = profile.role.charAt(0).toUpperCase() + profile.role.slice(1);
          }
        } catch { /* keep savedRole */ }

        beginSession({
          userID: sessionUser.id,
          email: sessionUser.email,
          role: sessionRole
        });

        // Returning sessions need the same profile hydrate as a fresh sign-in.
        try {
          const hydrated = await hydrateLocalProfiles({
            userID: sessionUser.id,
            role: sessionRole,
            email: sessionUser.email
          });
          if (hydrated?.kind === "hospital") {
            appStore.saveHospitalProfile(hydrated.profile);
          } else if (hydrated?.kind === "doctor") {
            appStore.saveDoctorProfile(hydrated.profile);
          }
        } catch { /* offline / RLS */ }
      }
    } catch { /* local */ }

    // Admins never reach a doctor or hospital workspace, so skip the shift sync.
    if (await enterAdminIfPermitted(sessionUser?.id, sessionUser?.email)) return;

    await syncEverything();
  }

  const auth = authState();
  if (auth.kind === "loggedOut") state.route = "landing";
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

// The two workspaces name their tabs differently, so a role switch can leave a
// tab id the other side does not recognise — which renders an empty page.
const DOCTOR_TABS = ["home", "shifts", "credentials"];
const HOSPITAL_TABS = ["dashboard", "alter", "doctors"];

function render() {
  const root = document.getElementById("app");
  if (!root) return;

  if (state.route === "landing") {
    root.innerHTML = renderLanding();
    bindLanding(root, {
      onSignIn: () => {
        window.scrollTo(0, 0);
        update({ route: "auth", error: null });
      },
      onDemo: enterDemo
    });
    return;
  }

  if (state.route === "auth") {
    root.innerHTML = renderAuthView(state, {});
    bindAuth(root, {
      onMode: (mode) => update({
        authMode: mode, error: null, verifyEmail: null, verifyNotice: null, otpCode: "",
        mfaChallenge: false, mfaEnroll: null, mfaCode: "", pendingAuth: null
      }),
      onRole: (role) => update({ role }),
      onSubmit: handleAuthSubmit,
      onDemo: enterDemo,
      onBack: () => update({
        route: "landing", error: null, verifyEmail: null, verifyNotice: null, otpCode: "",
        mfaChallenge: false, mfaEnroll: null, mfaCode: "", pendingAuth: null
      }),
      onResend: async () => {
        if (!state.verifyEmail) return;
        update({ loading: true, error: null, verifyNotice: null });
        try {
          await resendSignupEmail(state.verifyEmail);
          update({ loading: false, verifyNotice: "New code sent. Check your inbox." });
        } catch (err) {
          update({ loading: false, error: err.message || "Could not resend code." });
        }
      },
      onOAuth: handleOAuth,
      onVerifyOtp: handleVerifyOtp,
      onVerifyMfa: handleVerifyMfa,
      onConfirmMfaEnroll: handleConfirmMfaEnroll,
      onSkipMfaEnroll: handleSkipMfaEnroll
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
        const current = state.onb.specialties?.[0];
        update({ onb: { ...state.onb, specialties: current === sp ? [] : [sp] } });
      }
    });
    root.querySelectorAll("[data-field]").forEach((el) => {
      el.addEventListener("change", () => Object.assign(state.onb, readOnboardingFields(root)));
      el.addEventListener("input", () => Object.assign(state.onb, readOnboardingFields(root)));
    });
    return;
  }

  if (state.route === "admin") {
    root.innerHTML = renderAdminApp(state.admin);
    bindAdmin(root, state.admin, {
      onPatch: (patch) => {
        const { keepFocus, ...rest } = patch;
        if (keepFocus) restoreSearchCaret = true;
        update({ admin: rest });
      },
      onDecide: decideApplication,
      onRefresh: loadApplications,
      onSection: (section) => {
        update({ admin: { section, confirmKey: null, toast: null } });
        if (section === "savings" && !state.admin.savings.loadedAt) loadHospitalSavings();
      },
      onSavingsRefresh: loadHospitalSavings,
      onSignOut: () => {
        signOut();
        state.route = "auth";
        state.admin = emptyAdminState();
        update({ email: "", error: null });
      }
    });
    if (restoreSearchCaret) {
      const input = root.querySelector("[data-approvals-search]");
      if (input) {
        input.focus();
        input.setSelectionRange(input.value.length, input.value.length);
      }
      restoreSearchCaret = false;
    }
    return;
  }

  if (state.route === "doctor") {
    if (!DOCTOR_TABS.includes(state.ui.tab)) state.ui.tab = "home";
    root.innerHTML = demoRibbon() + syncBanner() + renderDoctorApp(state.ui);
    bindDemoRibbon(root);
    bindDoctor(root, state.ui, (p) => {
      if (p.route) state.route = p.route;
      update(p);
    });
    return;
  }

  if (state.route === "hospital") {
    if (!HOSPITAL_TABS.includes(state.ui.tab)) state.ui.tab = "dashboard";
    root.innerHTML = demoRibbon() + syncBanner() + renderHospitalApp(state.ui);
    bindDemoRibbon(root);
    bindHospital(root, state.ui, (p) => {
      if (p.route) state.route = p.route;
      update(p);
    });
  }
}

function demoRibbon() {
  if (!isDemoSession()) return "";
  return `<div class="demo-ribbon">
    <span>Demo — sample data</span>
    <button type="button" data-exit-demo>Exit</button>
  </div>`;
}

/** A silent sync failure means two devices quietly disagree — say so. */
function syncBanner() {
  if (isDemoSession() || syncStatus.state !== "error") return "";
  return `<div class="sync-banner" role="status">
    <span>Changes are saved on this device only — we can't reach the server.</span>
    <button type="button" data-sync-retry>Retry</button>
  </div>`;
}

function bindDemoRibbon(root) {
  root.querySelector("[data-exit-demo]")?.addEventListener("click", () => {
    signOut();
    window.scrollTo(0, 0);
    update({ route: "landing" });
  });
  root.querySelector("[data-sync-retry]")?.addEventListener("click", () => {
    syncEverything().catch(() => {}).finally(() => update({}));
  });
}

async function handleOAuth(provider) {
  if (!isConfigured()) {
    update({ error: "Social sign-in requires Supabase to be configured." });
    return;
  }
  update({ loading: true, error: null });
  try {
    await signInWithOAuth(provider, state.role);
    // Browser navigates away to the provider.
  } catch (err) {
    update({
      loading: false,
      error: err.message || "Social sign-in is not enabled yet. Ask an admin to turn on Google/Apple in Supabase."
    });
  }
}

async function enterAuthedRoute(res, { suggestMfa = false } = {}) {
  beginSession({ userID: res.userID, email: res.email, role: res.role });
  if (await enterAdminIfPermitted(res.userID, res.email)) return;

  if (suggestMfa || res.suggestMfaEnroll) {
    try {
      const enroll = await enrollTotp();
      update({
        route: "auth",
        loading: false,
        verifyEmail: null,
        mfaChallenge: false,
        mfaEnroll: enroll,
        mfaCode: "",
        pendingAuth: { userID: res.userID, email: res.email, role: res.role },
        error: null
      });
      return;
    } catch {
      /* enrollment optional if API fails */
    }
  }

  const auth = authState();
  state.route = auth.kind === "needsOnboarding" ? "onboarding" : (res.role === "Hospital" ? "hospital" : "doctor");
  if (auth.kind === "needsOnboarding") {
    state.onb = { step: 0, role: res.role, specialties: [], verified: false, codeVerified: false, email: res.email };
  }
  update({
    loading: false,
    verifyEmail: null,
    verifyNotice: null,
    otpCode: "",
    mfaChallenge: false,
    mfaEnroll: null,
    mfaCode: "",
    pendingAuth: null
  });
}

async function handleVerifyMfa(code) {
  const otp = String(code || "").replace(/\D/g, "").slice(0, 6);
  update({ mfaCode: otp, error: null });
  if (otp.length !== 6) {
    update({ error: "Enter the 6-digit authenticator code." });
    return;
  }
  update({ loading: true });
  try {
    await challengeAndVerifyFirstTotp(otp);
    const res = await completeMfaSession();
    await enterAuthedRoute(res);
  } catch (err) {
    update({ loading: false, error: err.message || "Invalid authenticator code." });
  }
}

async function handleConfirmMfaEnroll(code) {
  if (!state.mfaEnroll?.factorId) return;
  const otp = String(code || "").replace(/\D/g, "").slice(0, 6);
  update({ mfaCode: otp, error: null });
  if (otp.length !== 6) {
    update({ error: "Enter the 6-digit authenticator code." });
    return;
  }
  update({ loading: true });
  try {
    await verifyTotp({ factorId: state.mfaEnroll.factorId, code: otp });
    const pending = state.pendingAuth;
    if (pending?.role) {
      await enterAuthedRoute({ ...pending, suggestMfaEnroll: false });
    } else {
      const res = await completeMfaSession();
      await enterAuthedRoute(res);
    }
  } catch (err) {
    update({ loading: false, error: err.message || "Could not confirm authenticator." });
  }
}

async function handleSkipMfaEnroll() {
  const pending = state.pendingAuth;
  if (!pending?.role) {
    update({ mfaEnroll: null, mfaChallenge: false, route: "auth", authMode: "signin" });
    return;
  }
  await enterAuthedRoute({ ...pending, suggestMfaEnroll: false });
}

async function handleVerifyOtp(code) {
  if (!state.verifyEmail) return;
  const otp = String(code || "").replace(/\D/g, "").slice(0, 6);
  update({ otpCode: otp, error: null });
  if (otp.length !== 6) {
    update({ error: "Enter the 6-digit code from your email." });
    return;
  }
  update({ loading: true });
  try {
    const res = await verifySignupOtp(state.verifyEmail, otp, state.role);
    await enterAuthedRoute(res, { suggestMfa: true });
  } catch (err) {
    update({ loading: false, error: err.message || "Invalid or expired code." });
  }
}

async function handleAuthSubmit({ email, password, confirm }) {
  state.error = null;
  state.verifyNotice = null;
  const normalizedEmail = normalizeEmail(email);
  if (!normalizedEmail) { update({ error: "Please enter your email." }); return; }
  if (password.length < 6) { update({ error: "Password must be at least 6 characters." }); return; }
  if (state.authMode === "signup" && password !== confirm) {
    update({ error: "Passwords don't match." }); return;
  }

  update({ loading: true, email: normalizedEmail });

  try {
    if (state.authMode === "signup") {
      if (isConfigured()) {
        const res = await signUpRemote(normalizedEmail, password, state.role);
        if (res.needsEmailVerification) {
          update({
            loading: true,
            verifyEmail: normalizedEmail,
            verifyNotice: null,
            otpCode: "",
            error: null
          });
          try {
            // signUp usually sends once; this makes the UI honest if SMTP is flaky.
            await resendSignupEmail(normalizedEmail);
            update({
              loading: false,
              verifyEmail: normalizedEmail,
              verifyNotice: "Code sent. Check your inbox (and spam)."
            });
          } catch {
            update({
              loading: false,
              verifyEmail: normalizedEmail,
              verifyNotice: null,
              error: "Account created, but email delivery failed. Tap Resend code."
            });
          }
          return;
        }
        beginSession({ userID: res.userID, email: res.email, role: state.role });
      } else {
        if (signInLocal(normalizedEmail, password)) {
          update({ error: "Account already exists. Sign in instead.", loading: false });
          return;
        }
        const userID = registerAccount(normalizedEmail, password, state.role);
        beginSession({ userID, email: normalizedEmail, role: state.role });
      }
      state.route = "onboarding";
      state.onb = { step: 0, role: state.role, specialties: [], verified: false, codeVerified: false, email: normalizedEmail };
      update({ loading: false, verifyEmail: null, otpCode: "" });
      return;
    }

    if (isConfigured()) {
      try {
        const res = await signInRemote(normalizedEmail, password);
        if (res.needsMfa) {
          update({
            loading: false,
            mfaChallenge: true,
            mfaEnroll: null,
            mfaCode: "",
            pendingAuth: { userID: res.userID, email: res.email },
            error: null
          });
          return;
        }
        await enterAuthedRoute(res);
        return;
      } catch (err) {
        const message = err?.message || "Could not sign in.";
        if (err?.code === "email_not_confirmed" || /email not confirmed/i.test(message)) {
          update({
            error: null,
            loading: true,
            verifyEmail: normalizedEmail,
            otpCode: "",
            verifyNotice: null
          });
          try {
            await resendSignupEmail(normalizedEmail);
            update({
              loading: false,
              verifyEmail: normalizedEmail,
              verifyNotice: "Code sent. Check your inbox (and spam)."
            });
          } catch (sendErr) {
            update({
              loading: false,
              verifyEmail: normalizedEmail,
              error: sendErr?.message || "Could not send a code. Tap Resend, or check Supabase email settings.",
              verifyNotice: null
            });
          }
          return;
        }
        const friendly = /invalid login credentials/i.test(message)
          ? "Wrong email or password. Try erdunn706@gmail.com, or create an account."
          : message;
        update({ error: friendly, loading: false });
        return;
      }
    }

    let acct = signInLocal(normalizedEmail, password);
    if (!acct) {
      update({ error: "Wrong email or password. Create an account if you are new.", loading: false });
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
      update({ onb: { ...state.onb, error: "Choose your specialty." } }); return;
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
