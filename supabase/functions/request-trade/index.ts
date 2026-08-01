import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )
  const { shift_id, from_doctor_id, to_doctor_id } = await req.json()

  const { data, error } = await supabase.from("trade_requests").insert({
    shift_id, from_doctor_id, to_doctor_id, state: "pending"
  }).select().single()

  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  return new Response(JSON.stringify(data), { status: 200 })
})
