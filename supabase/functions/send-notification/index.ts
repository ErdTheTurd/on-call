import { serve } from "https://deno.land/std@0.177.0/http/server.ts"

serve(async (req) => {
  const { to, subject, html } = await req.json()
  const apiKey = Deno.env.get("SENDGRID_API_KEY")
  if (!apiKey) return new Response(JSON.stringify({ error: "Missing SendGrid key" }), { status: 500 })

  const res = await fetch("https://api.sendgrid.com/v3/mail/send", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      personalizations: [{ to: [{ email: to }] }],
      from: { email: Deno.env.get("SENDGRID_FROM") ?? "noreply@oncallwizard.com" },
      subject,
      content: [{ type: "text/html", value: html }]
    })
  })

  return new Response(JSON.stringify({ ok: res.ok }), { status: res.status })
})
