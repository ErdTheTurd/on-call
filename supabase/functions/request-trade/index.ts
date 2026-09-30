import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

/** ISO date or timestamp. Empty is allowed. Invalid or out of range is rejected. */
function tradeDate(value: unknown): { ok: true; iso?: string } | { ok: false } {
  if (value == null || value === "") return { ok: true }
  const text = String(value).trim()
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text)
  const dateTime = /^(\d{4})-(\d{2})-(\d{2})T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.exec(text)
  const match = dateOnly || dateTime
  if (!match) return { ok: false }
  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  const utc = new Date(Date.UTC(year, month - 1, day))
  if (utc.getUTCFullYear() !== year || utc.getUTCMonth() !== month - 1 || utc.getUTCDate() !== day) {
    return { ok: false }
  }
  const instant = dateOnly ? utc : new Date(text)
  if (Number.isNaN(instant.getTime())) return { ok: false }
  const now = new Date()
  const min = Date.UTC(now.getUTCFullYear() - 1, now.getUTCMonth(), now.getUTCDate())
  const max = Date.UTC(now.getUTCFullYear() + 2, now.getUTCMonth(), now.getUTCDate(), 23, 59, 59, 999)
  if (instant.getTime() < min || instant.getTime() > max) return { ok: false }
  return { ok: true, iso: dateOnly ? `${text}T12:00:00.000Z` : instant.toISOString() }
}

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
  const compensation = Number(body?.compensation_amount)
  if (Number.isFinite(compensation)) {
    row.compensation_amount = Math.min(1000, Math.max(0, compensation))
  }
  if (body?.requested_shift_id) row.requested_shift_id = String(body.requested_shift_id)
  if (body?.counter_of_trade_id) row.counter_of_trade_id = String(body.counter_of_trade_id)
  const clip = (value: unknown, max: number) => {
    const text = String(value ?? "").trim()
    return text ? text.slice(0, max) : ""
  }
  const fromName = clip(body?.from_doctor_name, 120)
  const toName = clip(body?.to_doctor_name, 120)
  const specialty = clip(body?.specialty, 80)
  if (fromName) row.from_doctor_name = fromName
  if (toName) row.to_doctor_name = toName
  if (specialty) row.specialty = specialty
  const offered = tradeDate(body?.offered_date)
  const requested = tradeDate(body?.requested_date)
  if (!offered.ok || !requested.ok) {
    return new Response(JSON.stringify({
      error: "Shift dates must be real calendar dates within the last year or the next two years.",
    }), { status: 400 })
  }
  if (offered.iso) row.offered_date = offered.iso
  if (requested.iso) row.requested_date = requested.iso

  const { data, error } = await admin.from("trade_requests").insert(row).select().single()
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  return new Response(JSON.stringify(data), { status: 200 })
})
