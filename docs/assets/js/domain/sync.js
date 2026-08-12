import { getSupabase, isConfigured } from "../supabase-client.js";
import { normalizeShift } from "../shift-math.js";
import { defaultPolicy } from "./policy.js";

function toDateOnly(iso) {
  const d = new Date(iso);
  return d.toISOString().slice(0, 10);
}

function mapShiftRow(row) {
  const escalation = row.escalation || {};
  return normalizeShift({
    id: row.id,
    hospital_id: row.hospital_id,
    hospital_name: row.hospital_name,
    specialty: row.specialty,
    date: row.date,
    rate_floor: row.rate_floor,
    rate_unit: row.rate_unit,
    duration_hours: row.duration_hours,
    escalation,
    usesAlgorithmPricing: escalation.usesAlgorithmPricing ?? escalation.uses_algorithm_pricing
  });
}

function mapAssignmentRow(row, shift) {
  return {
    id: row.id,
    shiftID: row.shift_id,
    shift: shift || { id: row.shift_id },
    doctorID: row.doctor_id,
    doctorName: row.doctor_name || "",
    status: row.status,
    assignedAt: row.assigned_at
  };
}

function mapTokenRow(row) {
  return {
    id: row.id,
    doctorID: row.doctor_id,
    doctorName: row.doctor_name || "",
    credential: row.credential || "MD",
    hospitalID: row.hospital_id,
    hospitalName: row.hospital_name || "",
    date: row.shift_date,
    specialty: row.specialty,
    status: row.status,
    requestedAt: row.requested_at,
    approvedAt: row.approved_at || null,
    shiftRate: row.shift_rate ?? null
  };
}

export async function upsertDoctorProfile(profile) {
  if (!isConfigured()) return profile;
  const supabase = getSupabase();
  const profileId = profile.userID || profile.id;
  const row = {
    profile_id: profileId,
    first_name: profile.firstName,
    last_name: profile.lastName,
    credential: profile.credential,
    npi: profile.npi,
    specialties: profile.specialties || [],
    verification_status: profile.verificationStatus || "pending",
    dea_number: profile.deaNumber || "",
    license_number: profile.licenseNumber || "",
    license_state: profile.licenseState || "",
    email: profile.email,
    verification_flags: profile.verificationFlags || [],
    npi_registry_name: profile.npiRegistryName || null,
    npi_taxonomy: profile.npiTaxonomy || null
  };
  const { error } = await supabase.from("doctor_profiles").upsert(row);
  if (error) throw error;
  return { ...profile, id: profile.id || profileId, userID: profileId };
}

export async function upsertHospitalProfile(profile) {
  if (!isConfigured()) return profile;
  const supabase = getSupabase();
  const row = {
    id: profile.id,
    profile_id: profile.userID,
    name: profile.name,
    npi: profile.npi,
    email: profile.email,
    verification_status: profile.verificationStatus || "pending",
    verification_flags: profile.verificationFlags || [],
    npi_registry_name: profile.npiRegistryName || null
  };
  const { data, error } = await supabase.from("hospital_profiles").upsert(row).select().single();
  if (error) throw error;
  if (profile.schedulingPolicy) {
    await upsertPolicy(data.id, profile.schedulingPolicy);
  }
  return { ...profile, id: data.id };
}

/**
 * After a remote sign-in, pull the role profile into localStorage so the app
 * does not dump a returning user back into onboarding.
 */
export async function hydrateLocalProfiles({ userID, role, email }) {
  if (!isConfigured() || !userID) return null;
  const supabase = getSupabase();
  const kind = String(role || "").toLowerCase();

  if (kind === "hospital") {
    const { data, error } = await supabase
      .from("hospital_profiles")
      .select("*")
      .eq("profile_id", userID)
      .maybeSingle();
    if (error) throw error;
    if (!data) return null;
    return {
      kind: "hospital",
      profile: {
        id: data.id,
        userID: data.profile_id,
        name: data.name,
        npi: data.npi,
        email: data.email || email || "",
        verificationStatus: data.verification_status || "pending",
        verificationFlags: data.verification_flags || [],
        npiRegistryName: data.npi_registry_name || null,
        priorityPosting: false,
        autoPay: false
      }
    };
  }

  const { data, error } = await supabase
    .from("doctor_profiles")
    .select("*")
    .eq("profile_id", userID)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return {
    kind: "doctor",
    profile: {
      id: data.profile_id,
      userID: data.profile_id,
      firstName: data.first_name,
      lastName: data.last_name,
      credential: data.credential,
      npi: data.npi,
      specialties: data.specialties?.length ? [data.specialties[0]] : [],
      deaNumber: data.dea_number || "",
      licenseNumber: data.license_number || "",
      licenseState: data.license_state || "",
      email: data.email || email || "",
      verificationStatus: data.verification_status || "pending",
      verificationFlags: data.verification_flags || [],
      npiRegistryName: data.npi_registry_name || null,
      npiTaxonomy: data.npi_taxonomy || null,
      documents: []
    }
  };
}

export async function fetchAllShifts(hospitalID) {
  if (!isConfigured()) return [];
  const supabase = getSupabase();
  let q = supabase.from("shifts").select("*").gte("date", new Date().toISOString()).order("date").limit(500);
  if (hospitalID) q = q.eq("hospital_id", hospitalID);
  const { data, error } = await q;
  if (error) throw error;
  return (data || []).map(mapShiftRow);
}

/** A shift's natural identity: one hospital, one specialty, one calendar day. */
function slotKey(shift) {
  const day = new Date(shift.start);
  return [
    shift.hospitalID,
    shift.specialty,
    day.getFullYear(), day.getMonth(), day.getDate()
  ].join("|");
}

/** How far ahead a hospital's board is published. Matches what doctors can browse. */
const PUBLISH_HORIZON_DAYS = 60;

/**
 * A hospital's board lives on whichever device created it. Until it is pushed,
 * no doctor on any other device can see a single open day — so publish the
 * near-term board on every sync, skipping days the server already has.
 */
async function publishHospitalBoard(hospitalId, localShifts, remoteShifts) {
  const now = Date.now();
  const horizon = now + PUBLISH_HORIZON_DAYS * 86400000;
  const known = new Set(remoteShifts.map(slotKey));

  const pending = localShifts.filter((s) => {
    if (s.hospitalID !== hospitalId) return false;
    const at = new Date(s.start).getTime();
    if (!(at >= now - 86400000 && at <= horizon)) return false;
    return !known.has(slotKey(s));
  });
  if (!pending.length) return;

  // Sequential and bounded: a first-run board can be hundreds of days.
  for (const shift of pending.slice(0, 400)) {
    try { await upsertShift(shift); } catch { /* retried next sync */ }
  }
}

export async function upsertShift(shift) {
  if (!isConfigured()) return shift;
  const supabase = getSupabase();
  const escalation = {
    ...(shift.escalationMode ? { type: shift.escalationMode.type, rate: shift.escalationMode.rate } : {}),
    usesAlgorithmPricing: shift.usesAlgorithmPricing !== false
  };
  const row = {
    id: shift.id,
    hospital_id: shift.hospitalID,
    hospital_name: shift.hospital,
    specialty: shift.specialty,
    date: shift.start,
    rate_floor: shift.rateFloor,
    rate_unit: shift.rateUnit === "per hour" ? "per_hour" : "per_day",
    duration_hours: shift.durationHours ?? 24,
    escalation
  };
  const { error } = await supabase.from("shifts").upsert(row);
  if (error) throw error;
  return shift;
}

/**
 * @param doctorID  set for a doctor session
 * @param hospitalID set for a hospital session, which needs every doctor's
 *   assignment to know what is covered — but only at its own hospital.
 */
export async function fetchAssignments(doctorID, hospitalID = null) {
  if (!isConfigured()) return [];
  const supabase = getSupabase();
  const embed = hospitalID ? "*, shifts!inner(*)" : "*, shifts(*)";
  let q = supabase.from("assignments").select(embed).order("assigned_at", { ascending: false });
  if (doctorID) q = q.eq("doctor_id", doctorID);
  if (hospitalID) q = q.eq("shifts.hospital_id", hospitalID);
  const { data, error } = await q.limit(200);
  if (error) throw error;
  return (data || []).map((row) => mapAssignmentRow(row, row.shifts ? mapShiftRow(row.shifts) : null));
}

export async function createAssignment(shiftId, doctorId, meta = {}) {
  if (!isConfigured()) return null;
  const supabase = getSupabase();

  if (meta.hospitalID && meta.shiftDate) {
    try {
      const { data, error } = await supabase.functions.invoke("accept-shift", {
        body: {
          shift_id: shiftId,
          doctor_id: doctorId,
          hospital_id: meta.hospitalID,
          shift_date: toDateOnly(meta.shiftDate)
        }
      });
      if (!error && data?.id) {
        return mapAssignmentRow(data, meta.shift);
      }
    } catch {
      /* fall through to direct insert */
    }
  }

  const { data, error } = await supabase
    .from("assignments")
    .insert({ shift_id: shiftId, doctor_id: doctorId, status: "scheduled" })
    .select()
    .single();
  if (error) throw error;
  return mapAssignmentRow(data, meta.shift);
}

export async function fetchTokenRequests(hospitalID, doctorID) {
  if (!isConfigured()) return [];
  const supabase = getSupabase();
  let q = supabase.from("token_requests").select("*").order("requested_at", { ascending: false });
  if (hospitalID) q = q.eq("hospital_id", hospitalID);
  if (doctorID) q = q.eq("doctor_id", doctorID);
  const { data, error } = await q.limit(200);
  if (error) throw error;
  return (data || []).map(mapTokenRow);
}

export async function submitTokenRequest(req) {
  if (!isConfigured()) return req;
  const supabase = getSupabase();
  const row = {
    id: req.id,
    doctor_id: req.doctorID,
    hospital_id: req.hospitalID,
    shift_date: toDateOnly(req.date),
    specialty: req.specialty,
    status: req.status || "pending",
    requested_at: req.requestedAt || new Date().toISOString(),
    doctor_name: req.doctorName || null,
    credential: req.credential || null,
    hospital_name: req.hospitalName || null,
    shift_rate: req.shiftRate ?? null,
    approved_at: req.approvedAt || null
  };
  const { data, error } = await supabase.from("token_requests").upsert(row).select().single();
  if (error) {
    // Fall back to core columns if extended columns aren't migrated yet.
    const { data: d2, error: e2 } = await supabase.from("token_requests").upsert({
      id: row.id,
      doctor_id: row.doctor_id,
      hospital_id: row.hospital_id,
      shift_date: row.shift_date,
      specialty: row.specialty,
      status: row.status,
      requested_at: row.requested_at
    }).select().single();
    if (e2) throw e2;
    return mapTokenRow(d2);
  }
  return mapTokenRow(data);
}

export async function updateTokenStatus(id, status) {
  if (!isConfigured()) return;
  const supabase = getSupabase();
  if (status === "canceled") {
    const { error } = await supabase.from("token_requests").delete().eq("id", id);
    if (error) throw error;
    return;
  }
  const patch = { status };
  if (status === "approved" || status === "auto_approved") {
    patch.approved_at = new Date().toISOString();
  }
  const { error } = await supabase.from("token_requests").update(patch).eq("id", id);
  if (error) throw error;
}

export async function fetchRoster(hospitalId) {
  if (!isConfigured()) return [];
  const supabase = getSupabase();
  const { data, error } = await supabase
    .from("hospital_doctors")
    .select("auto_approve, doctor_profiles(*)")
    .eq("hospital_id", hospitalId);
  if (error) throw error;
  return (data || []).map((row) => {
    const d = row.doctor_profiles;
    if (!d) return null;
    return {
      id: d.profile_id,
      name: `${d.first_name} ${d.last_name}`,
      credential: d.credential,
      specialty: (d.specialties && d.specialties[0]) || "Internal Medicine",
      npi: d.npi,
      isAutoApproved: row.auto_approve,
      verificationStatus: d.verification_status
    };
  }).filter(Boolean);
}

export async function upsertRosterLink(hospitalId, doctorId, autoApprove) {
  if (!isConfigured()) return;
  const supabase = getSupabase();
  const { error } = await supabase.from("hospital_doctors").upsert({
    hospital_id: hospitalId,
    doctor_id: doctorId,
    auto_approve: autoApprove
  });
  if (error) throw error;
}

/** Adds a doctor to a hospital's roster without disturbing an existing auto-approve flag. */
export async function linkDoctorToHospital(hospitalId, doctorId) {
  if (!isConfigured() || !hospitalId || !doctorId) return;
  const supabase = getSupabase();
  const { error } = await supabase.from("hospital_doctors").upsert(
    { hospital_id: hospitalId, doctor_id: doctorId, auto_approve: false },
    { onConflict: "hospital_id,doctor_id", ignoreDuplicates: true }
  );
  if (error) throw error;
}

export async function fetchPolicy(hospitalId) {
  if (!isConfigured()) return defaultPolicy();
  const supabase = getSupabase();
  const { data, error } = await supabase
    .from("scheduling_policies")
    .select("policy")
    .eq("hospital_id", hospitalId)
    .maybeSingle();
  if (error) throw error;
  return { ...defaultPolicy(), ...(data?.policy || {}) };
}

export async function upsertPolicy(hospitalId, policy) {
  if (!isConfigured()) return policy;
  const supabase = getSupabase();
  const { error } = await supabase.from("scheduling_policies").upsert({
    hospital_id: hospitalId,
    policy
  });
  if (error) throw error;
  return policy;
}

export async function fetchUnavailable(hospitalId) {
  if (!isConfigured()) return [];
  const supabase = getSupabase();
  const { data, error } = await supabase
    .from("unavailable_days")
    .select("date")
    .eq("hospital_id", hospitalId);
  if (error) throw error;
  return (data || []).map((r) => r.date);
}

export async function setUnavailable(hospitalId, date, blocked) {
  if (!isConfigured()) return;
  const supabase = getSupabase();
  const dateStr = toDateOnly(date);
  if (blocked) {
    const { error } = await supabase.from("unavailable_days").upsert({
      hospital_id: hospitalId,
      date: dateStr
    });
    if (error) throw error;
  } else {
    const { error } = await supabase.from("unavailable_days").delete()
      .eq("hospital_id", hospitalId).eq("date", dateStr);
    if (error) throw error;
  }
}

export async function requestTrade(shiftId, fromDoctorId, toDoctorId, extras = {}) {
  if (!isConfigured()) return null;
  const supabase = getSupabase();
  const body = {
    shift_id: shiftId,
    from_doctor_id: fromDoctorId,
    to_doctor_id: toDoctorId
  };
  // The client owns the id so it can respond to its own trade later.
  if (extras.id) body.id = extras.id;
  if (extras.fromDoctorName) body.from_doctor_name = extras.fromDoctorName;
  if (extras.toDoctorName) body.to_doctor_name = extras.toDoctorName;
  if (extras.requestedShiftId) body.requested_shift_id = extras.requestedShiftId;
  if (extras.compensationAmount != null) body.compensation_amount = extras.compensationAmount;
  if (extras.offeredDate) body.offered_date = extras.offeredDate;
  if (extras.requestedDate) body.requested_date = extras.requestedDate;
  if (extras.specialty) body.specialty = extras.specialty;
  if (extras.counterOfTradeId) body.counter_of_trade_id = extras.counterOfTradeId;
  const { data, error } = await supabase.functions.invoke("request-trade", { body });
  if (error) throw error;
  return data;
}

/** Trades in either direction for this doctor, so a partner's request shows up here. */
export async function fetchTrades(doctorId) {
  if (!isConfigured() || !doctorId) return null;
  const supabase = getSupabase();
  const { data, error } = await supabase
    .from("trade_requests")
    .select("*")
    .or(`from_doctor_id.eq.${doctorId},to_doctor_id.eq.${doctorId}`)
    .order("created_at", { ascending: false })
    .limit(200);
  if (error) throw error;

  return (data || []).map((row) => ({
    id: row.id,
    shiftID: row.shift_id,
    fromDoctorID: row.from_doctor_id,
    toDoctorID: row.to_doctor_id,
    fromDoctorName: row.from_doctor_name || null,
    toDoctorName: row.to_doctor_name || null,
    requestedShiftID: row.requested_shift_id || null,
    offeredDate: row.offered_date || null,
    requestedDate: row.requested_date || null,
    specialty: row.specialty || null,
    compensationAmount: Number(row.compensation_amount) || 0,
    counterOfTradeId: row.counter_of_trade_id || null,
    state: row.state,
    createdAt: row.created_at
  }));
}

export async function respondTrade(tradeId, accept) {
  if (!isConfigured()) return null;
  const supabase = getSupabase();
  const { data, error } = await supabase.functions.invoke("respond-trade", {
    body: { trade_id: tradeId, accept }
  });
  if (error) throw error;
  return data;
}

export async function cancelAssignment(shiftId, doctorId) {
  if (!isConfigured()) return { penalty: 0 };
  const supabase = getSupabase();
  const { data, error } = await supabase.functions.invoke("cancel-shift", {
    body: { shift_id: shiftId, doctor_id: doctorId }
  });
  if (error) throw error;
  return data || { penalty: 0 };
}

/**
 * Pull remote data into localStorage via callbacks supplied by store.
 * @param {object} hooks - { readLocal, writeLocal, emit }
 */
export async function syncEverything(hooks) {
  if (!isConfigured()) return { ok: false, reason: "not_configured" };

  const doctor = hooks.readLocal("doctorProfile");
  const hospital = hooks.readLocal("hospitalProfile");
  const hospitalId = hospital?.id;

  try {
    const [shifts, assignments, tokens, roster, policy, unavailable, trades] = await Promise.all([
      fetchAllShifts(hospitalId),
      fetchAssignments(hospitalId ? null : doctor?.id, hospitalId || null),
      fetchTokenRequests(hospitalId, doctor?.id),
      hospitalId ? fetchRoster(hospitalId) : Promise.resolve(null),
      hospitalId ? fetchPolicy(hospitalId) : Promise.resolve(null),
      hospitalId ? fetchUnavailable(hospitalId) : Promise.resolve(null),
      doctor?.id ? fetchTrades(doctor.id) : Promise.resolve(null)
    ]);

    const localShifts = hooks.readLocal("shifts") || [];

    if (shifts.length) {
      const byId = new Map(localShifts.map((s) => [s.id, s]));
      const remoteMerged = shifts.map((remote) => {
        const prev = byId.get(remote.id);
        if (!prev) {
          return remote.usesAlgorithmPricing == null
            ? { ...remote, usesAlgorithmPricing: true }
            : remote;
        }
        if (remote.usesAlgorithmPricing == null && prev.usesAlgorithmPricing != null) {
          return { ...remote, usesAlgorithmPricing: prev.usesAlgorithmPricing };
        }
        return {
          ...remote,
          usesAlgorithmPricing: remote.usesAlgorithmPricing == null ? true : remote.usesAlgorithmPricing
        };
      });
      // Two devices posting the same day generate different shift ids. Let the
      // remote row win on its slot so the board does not show the day twice.
      const remoteSlots = new Set(shifts.map(slotKey));
      const merged = [
        ...localShifts.filter((s) => !shifts.some((r) => r.id === s.id) && !remoteSlots.has(slotKey(s))),
        ...remoteMerged
      ];
      hooks.writeLocal("shifts", merged);
    }

    if (hospitalId) {
      await publishHospitalBoard(hospitalId, localShifts, shifts);
    }

    if (assignments.length) {
      hooks.writeLocal("assignments", assignments);
    }

    if (tokens.length) {
      const tok = hooks.readLocal("tokens") || {};
      const localReqs = tok.requestedDays || [];
      // Merge by id so a just-submitted local request is not wiped before
      // the next remote round-trip returns it.
      const byId = new Map(localReqs.map((r) => [r.id, r]));
      for (const remote of tokens) byId.set(remote.id, remote);
      hooks.writeLocal("tokens", { ...tok, requestedDays: [...byId.values()] });
    }

    if (roster) {
      // Merge rather than replace: locally known doctors (and demo seeds) stay
      // until the hospital's remote roster actually contains them.
      const local = hooks.readLocal("roster") || [];
      const byId = new Map(local.map((d) => [d.id, d]));
      for (const remote of roster) byId.set(remote.id, { ...byId.get(remote.id), ...remote });
      hooks.writeLocal("roster", [...byId.values()]);
    }

    if (trades) {
      // Split by direction here so a partner's request lands in this doctor's inbox.
      const mine = doctor.id;
      const live = trades.filter((t) => t.state === "pending");
      hooks.writeLocal("trades", {
        incoming: live.filter((t) => t.toDoctorID === mine),
        outgoing: live.filter((t) => t.fromDoctorID === mine)
      });
    }

    if (policy && hospitalId) {
      const policies = hooks.readLocal("policies") || {};
      policies[hospitalId] = policy;
      hooks.writeLocal("policies", policies);
    }

    if (unavailable && hospitalId) {
      const unavail = hooks.readLocal("unavailable") || {};
      unavail[hospitalId] = unavailable;
      hooks.writeLocal("unavailable", unavail);
    }

    hooks.emit?.();
    return { ok: true };
  } catch (err) {
    return { ok: false, reason: err.message };
  }
}

export async function syncAfterMutation(fn) {
  if (!isConfigured()) return;
  try {
    await fn();
  } catch {
    /* offline — local state already updated */
  }
}
