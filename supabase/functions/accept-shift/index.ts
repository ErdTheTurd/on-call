// Supabase Edge Function: accept-shift
// Deno.serve(async (req) => { ... verify token, create assignment atomically })

import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )
  const { shift_id, doctor_id, hospital_id, shift_date } = await req.json()

  const { data: token } = await supabase
    .from("token_requests")
    .select("*")
    .eq("doctor_id", doctor_id)
    .eq("hospital_id", hospital_id)
    .eq("shift_date", shift_date)
    .in("status", ["approved", "auto_approved"])
    .maybeSingle()

  if (!token) {
    return new Response(JSON.stringify({ error: "Token not approved" }), { status: 403 })
  }

  const { data: assignment, error } = await supabase
    .from("assignments")
    .insert({ shift_id, doctor_id, status: "scheduled" })
    .select()
    .single()

  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  return new Response(JSON.stringify(assignment), { status: 200 })
})
