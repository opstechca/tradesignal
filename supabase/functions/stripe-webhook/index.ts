// Stripe webhook: flips a follower to tier='paid' when they pay.
// Uses Stripe Payment Links (no checkout code) - the payment link is built in
// the frontend with ?client_reference_id=<supabase user id>, so we know who paid.
//
// Secrets you set (Project Settings -> Edge Functions -> Secrets, or CLI):
//   STRIPE_SECRET_KEY          -> sk_live_... (or sk_test_...)
//   STRIPE_WEBHOOK_SECRET      -> whsec_... from the Stripe webhook endpoint
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected into every Edge
// Function by Supabase. Do NOT set them: the SUPABASE_ prefix is reserved and
// `supabase secrets set` rejects it.
//
// Point a Stripe webhook (Developers -> Webhooks) at this function's URL,
// events: checkout.session.completed, customer.subscription.deleted.

import Stripe from "https://esm.sh/stripe@14?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, { apiVersion: "2024-06-20" });
const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, // bypasses RLS - never expose to client
);

Deno.serve(async (req) => {
  const sig = req.headers.get("stripe-signature");
  const raw = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      raw, sig!, Deno.env.get("STRIPE_WEBHOOK_SECRET")!,
    );
  } catch (e) {
    return new Response(`bad signature: ${e.message}`, { status: 400 });
  }

  if (event.type === "checkout.session.completed") {
    const s = event.data.object as Stripe.Checkout.Session;
    const userId = s.client_reference_id;
    if (userId) {
      // subscription -> use its period end; one-off -> 30 days
      let paidUntil = new Date(Date.now() + 30 * 864e5);
      if (s.subscription) {
        const sub = await stripe.subscriptions.retrieve(s.subscription as string);
        paidUntil = new Date(sub.current_period_end * 1000);
      }
      await admin.from("profiles")
        .update({ tier: "paid", paid_until: paidUntil.toISOString() })
        .eq("id", userId);
    }
  }

  if (event.type === "customer.subscription.deleted") {
    // subscription ended -> downgrade. Match by stored customer id if you track it;
    // simplest: let paid_until lapse naturally. Left as a no-op safety hook.
  }

  return new Response("ok", { status: 200 });
});
