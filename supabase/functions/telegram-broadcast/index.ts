// Telegram auto-broadcast. Fires when a new signal row is inserted.
// Triggered by a Supabase Database Webhook (Database -> Webhooks) on
// INSERT into public.signals, pointing at this function's URL.
//
// Secrets needed (Project Settings -> Edge Functions -> Secrets, or CLI):
//   TELEGRAM_TOKEN   -> from @BotFather
//   TELEGRAM_CHAT_ID -> your channel id, e.g. @yoursignals or -100123...
//   WEBHOOK_SECRET   -> any random string; also set as a webhook header (see README)

Deno.serve(async (req) => {
  // simple shared-secret check so only your webhook can call this
  const secret = Deno.env.get("WEBHOOK_SECRET");
  if (secret && req.headers.get("x-webhook-secret") !== secret) {
    return new Response("forbidden", { status: 403 });
  }

  const token = Deno.env.get("TELEGRAM_TOKEN");
  const chat = Deno.env.get("TELEGRAM_CHAT_ID");
  if (!token || !chat) return new Response("missing telegram config", { status: 500 });

  const body = await req.json().catch(() => ({}));
  const s = body.record ?? body; // Supabase webhook wraps the row in `record`
  if (!s?.symbol) return new Response("no signal", { status: 400 });

  const arrow = s.side === "BUY" ? "🟢" : "🔴";
  const line = (l: string, v: unknown) => (v != null ? `\n${l}: ${v}` : "");
  const text =
    `${arrow} *${s.side} ${escapeMd(s.symbol)}*` +
    line("Entry", s.entry) +
    line("Target", s.target) +
    line("Stop", s.stoploss) +
    (s.note ? `\n\n_${escapeMd(s.note)}_` : "") +
    `\n\n_Educational only. Not financial advice._`;

  const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ chat_id: chat, text, parse_mode: "Markdown" }),
  });

  return new Response(await res.text(), { status: res.ok ? 200 : 502 });
});

// Telegram Markdown v1 needs these escaped inside text
function escapeMd(s: string) {
  return String(s).replace(/([_*`\[])/g, "\\$1");
}
