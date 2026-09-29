import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

function bearerJwt(req: Request): string {
  const header = req.headers.get("authorization") || ""
  return header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : ""
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only." }), { status: 405 })
  }

  const url = Deno.env.get("SUPABASE_URL")
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")
  if (!url || !serviceKey || !anonKey) {
    return new Response(JSON.stringify({ error: "Trade requests are not configured." }), { status: 500 })
  }

  const jwt = bearerJwt(req)
  if (!jwt || jwt === anonKey) {
    return new Response(JSON.stringify({ error: "Sign in before requesting a trade." }), { status: 401 })
  }

  const admin = createClient(url, serviceKey)
  const { data: userData, error: userError } = await admin.auth.getUser(jwt)
  if (userError || !userData?.user?.id) {
    return new Response(JSON.stringify({ error: "Sign in before requesting a trade." }), { status: 401 })
  }

  const body = await req.json().catch(() => ({}))
  const actorId = userData.user.id
  const claimedFrom = String(body?.from_doctor_id || "")
  if (claimedFrom && claimedFrom !== actorId) {
    return new Response(JSON.stringify({ error: "You can only request a trade as yourself." }), { status: 403 })
  }

  const shiftId = String(body?.shift_id || "")
  const toDoctorId = String(body?.to_doctor_id || "")
  if (!shiftId || !toDoctorId) {
    return new Response(JSON.stringify({ error: "Choose a shift and a doctor." }), { status: 400 })
  }
  if (toDoctorId === actorId) {
    return new Response(JSON.stringify({ error: "You cannot trade a shift to yourself." }), { status: 403 })
  }

  const { data: assignment } = await admin
    .from("assignments")
    .select("doctor_id, status")
    .eq("shift_id", shiftId)
    .neq("status", "canceled")
    .maybeSingle()
  if (!assignment || assignment.doctor_id !== actorId) {
    return new Response(JSON.stringify({
      error: "Only the doctor assigned to this shift can request a trade.",
    }), { status: 403 })
  }

  const row: Record<string, unknown> = {
    shift_id: shiftId,
    from_doctor_id: actorId,
    to_doctor_id: toDoctorId,
    state: "pending",
  }
  if (body?.id) row.id = body.id

  const { data, error } = await admin.from("trade_requests").insert(row).select().single()
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  return new Response(JSON.stringify(data), { status: 200 })
})
