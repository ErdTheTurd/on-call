import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )
  const { shift_id, doctor_id } = await req.json()

  const { data: assignment } = await supabase
    .from("assignments")
    .select("*, shifts(*, scheduling_policies(policy))")
    .eq("shift_id", shift_id)
    .eq("doctor_id", doctor_id)
    .single()

  if (!assignment) {
    return new Response(JSON.stringify({ error: "Not found" }), { status: 404 })
  }

  const policy = assignment.shifts?.scheduling_policies?.policy ?? {}
  const penalty = computeCancelPenalty(assignment, policy)

  await supabase.from("assignments").update({ status: "canceled" }).eq("shift_id", shift_id)
  await supabase.from("penalty_ledger").insert({
    doctor_id,
    hospital_id: assignment.shifts.hospital_id,
    shift_id,
    type: "cancel",
    amount: penalty
  })

  return new Response(JSON.stringify({ penalty }), { status: 200 })
})

function computeCancelPenalty(_assignment: unknown, _policy: unknown): number {
  return 0
}
