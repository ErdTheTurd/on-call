import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )
  const { trade_id, accept } = await req.json()

  const { data: trade } = await supabase.from("trade_requests").select("*").eq("id", trade_id).single()
  if (!trade) return new Response(JSON.stringify({ error: "Not found" }), { status: 404 })

  const state = accept ? "accepted" : "rejected"
  await supabase.from("trade_requests").update({ state }).eq("id", trade_id)

  if (accept) {
    await supabase.from("assignments").update({ doctor_id: trade.to_doctor_id }).eq("shift_id", trade.shift_id)
  }

  return new Response(JSON.stringify({ state }), { status: 200 })
})
