import { serve } from "https://deno.land/std@0.177.0/http/server.ts"

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors })
  }

  try {
    const { to, subject, html } = await req.json()
    if (!to || !subject || !html) {
      return new Response(JSON.stringify({ error: "to, subject, and html are required" }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      })
    }

    const resendKey = Deno.env.get("RESEND_API_KEY")
    const sendgridKey = Deno.env.get("SENDGRID_API_KEY")
    const from =
      Deno.env.get("RESEND_FROM_EMAIL") ??
      Deno.env.get("SENDGRID_FROM") ??
      "noreply@mdshift.net"

    if (resendKey) {
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: `MD Shift <${from}>`,
          to: [to],
          subject,
          html,
        }),
      })
      const body = await res.text()
      return new Response(JSON.stringify({ ok: res.ok, provider: "resend", body }), {
        status: res.ok ? 200 : res.status,
        headers: { ...cors, "Content-Type": "application/json" },
      })
    }

    if (sendgridKey) {
      const res = await fetch("https://api.sendgrid.com/v3/mail/send", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${sendgridKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          personalizations: [{ to: [{ email: to }] }],
          from: { email: from, name: "MD Shift" },
          subject,
          content: [{ type: "text/html", value: html }],
        }),
      })
      return new Response(JSON.stringify({ ok: res.ok, provider: "sendgrid" }), {
        status: res.ok ? 200 : res.status,
        headers: { ...cors, "Content-Type": "application/json" },
      })
    }

    return new Response(JSON.stringify({ error: "No RESEND_API_KEY or SENDGRID_API_KEY configured" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    })
  }
})
