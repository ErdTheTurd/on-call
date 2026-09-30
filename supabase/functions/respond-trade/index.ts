import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

function bearerJwt(req: Request): string {
  const header = req.headers.get("authorization") || ""
  return header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : ""
}

const DEMO_SCOPE_ERROR = "Demo accounts can only work with the demo hospital."

/** Null when the trade stays inside non-demo users, or inside demo doctors and demo hospitals. */
async function demoTradeScopeError(
  admin: { from: (table: string) => any },
  fromId: string,
  toId: string,
  shiftIds: string[],
): Promise<string | null> {
  const doctorIds = [fromId, toId].filter((id) => id)
  const { data: doctors, error } = await admin
    .from("doctor_profiles")
    .select("profile_id, is_demo")
    .in("profile_id", doctorIds)
  if (error || !doctors) return null
  const demoDoctors = new Set(
    doctors.filter((doctor: { is_demo?: boolean }) => doctor.is_demo).map((doctor: { profile_id: string }) => doctor.profile_id),
  )
  if (demoDoctors.size === 0) return null
  if (doctorIds.some((id) => !demoDoctors.has(id))) return DEMO_SCOPE_ERROR
  const ids = [...new Set(shiftIds.filter((id) => id))]
  if (ids.length === 0) return DEMO_SCOPE_ERROR
  const { data: shifts, error: shiftError } = await admin
    .from("shifts")
    .select("id, hospital_id")
    .in("id", ids)
  if (shiftError || !shifts || shifts.length !== ids.length) return DEMO_SCOPE_ERROR
  const hospitalIds = [...new Set(shifts.map((shift: { hospital_id: string }) => shift.hospital_id))]
  const { data: hospitals, error: hospitalError } = await admin
    .from("hospital_profiles")
    .select("id, is_demo")
    .in("id", hospitalIds)
  if (hospitalError || !hospitals || hospitals.some((hospital: { is_demo?: boolean }) => !hospital.is_demo)) {
    return DEMO_SCOPE_ERROR
  }
  return null
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only." }), { status: 405 })
  }

  const url = Deno.env.get("SUPABASE_URL")
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")
  if (!url || !serviceKey || !anonKey) {
    return new Response(JSON.stringify({ error: "Trade responses are not configured." }), { status: 500 })
  }

  const jwt = bearerJwt(req)
  if (!jwt || jwt === anonKey) {
    return new Response(JSON.stringify({ error: "Sign in before responding to a trade." }), { status: 401 })
  }

  const admin = createClient(url, serviceKey)
  const { data: userData, error: userError } = await admin.auth.getUser(jwt)
  if (userError || !userData?.user?.id) {
    return new Response(JSON.stringify({ error: "Sign in before responding to a trade." }), { status: 401 })
  }

  const body = await req.json().catch(() => ({}))
  const tradeId = String(body?.trade_id || "")
  if (!tradeId) return new Response(JSON.stringify({ error: "Trade not found." }), { status: 400 })

  const { data: trade } = await admin.from("trade_requests").select("*").eq("id", tradeId).maybeSingle()
  if (!trade) return new Response(JSON.stringify({ error: "Not found" }), { status: 404 })

  if (trade.from_doctor_id === trade.to_doctor_id) {
    return new Response(JSON.stringify({ error: "This trade is not valid." }), { status: 403 })
  }
  if (trade.state !== "pending") {
    return new Response(JSON.stringify({ error: "This trade is no longer pending." }), { status: 400 })
  }

  const actorId = userData.user.id
  const { data: shift } = await admin.from("shifts").select("hospital_id").eq("id", trade.shift_id).maybeSingle()
  const { data: hospital } = shift?.hospital_id
    ? await admin.from("hospital_profiles").select("profile_id").eq("id", shift.hospital_id).maybeSingle()
    : { data: null }
  const { data: profile } = await admin.from("profiles").select("is_admin").eq("id", actorId).maybeSingle()

  const isTarget = trade.to_doctor_id === actorId
  const isHospital = hospital?.profile_id === actorId
  const isAdmin = profile?.is_admin === true
  if (!isTarget && !isHospital && !isAdmin) {
    return new Response(JSON.stringify({
      error: "Only the doctor who was asked, or that hospital, can respond to this trade.",
    }), { status: 403 })
  }

  const scopeError = await demoTradeScopeError(
    admin,
    trade.from_doctor_id,
    trade.to_doctor_id,
    [trade.shift_id, trade.requested_shift_id || ""],
  )
  if (scopeError) return new Response(JSON.stringify({ error: scopeError }), { status: 403 })

  const state = body?.accept === true ? "accepted" : "rejected"
  if (state === "accepted") {
    const { data: assignment } = await admin
      .from("assignments")
      .select("id, doctor_id")
      .eq("shift_id", trade.shift_id)
      .neq("status", "canceled")
      .maybeSingle()
    if (!assignment || assignment.doctor_id !== trade.from_doctor_id) {
      return new Response(JSON.stringify({
        error: "The doctor who offered this shift no longer holds it.",
      }), { status: 403 })
    }
  }

  const { data: updated, error: updateError } = await admin
    .from("trade_requests")
    .update({ state })
    .eq("id", tradeId)
    .eq("state", "pending")
    .select("id")
    .maybeSingle()
  if (updateError) return new Response(JSON.stringify({ error: updateError.message }), { status: 400 })
  if (!updated) {
    return new Response(JSON.stringify({ error: "This trade is no longer pending." }), { status: 400 })
  }

  if (state === "accepted") {
    const { data: moved, error: assignError } = await admin
      .from("assignments")
      .update({ doctor_id: trade.to_doctor_id })
      .eq("shift_id", trade.shift_id)
      .eq("doctor_id", trade.from_doctor_id)
      .neq("status", "canceled")
      .select("id")
      .maybeSingle()
    if (assignError || !moved) {
      await admin.from("trade_requests").update({ state: "pending" }).eq("id", tradeId)
      return new Response(JSON.stringify({
        error: "The doctor who offered this shift no longer holds it.",
      }), { status: 403 })
    }
  }

  return new Response(JSON.stringify({ state }), { status: 200 })
})
