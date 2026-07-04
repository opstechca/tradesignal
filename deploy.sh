#!/usr/bin/env bash
# One-shot non-interactive deploy of the Supabase Edge Functions.
# Fill .env (see .env.example), then: ./deploy.sh
# Requires the supabase CLI installed. Auth is via SUPABASE_ACCESS_TOKEN in .env
# (a Personal Access Token, sbp_..., from Dashboard -> Account -> Access Tokens),
# so no interactive `supabase login` is needed.
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "Missing .env - copy .env.example to .env and fill it."; exit 1; }
set -a; . ./.env; set +a

: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN in .env (sbp_... personal access token)}"
: "${SUPABASE_PROJECT_REF:?set SUPABASE_PROJECT_REF in .env}"
export SUPABASE_ACCESS_TOKEN

command -v supabase >/dev/null || { echo "supabase CLI not found. Install: brew install supabase/tap/supabase"; exit 1; }

echo "==> Linking project $SUPABASE_PROJECT_REF"
supabase link --project-ref "$SUPABASE_PROJECT_REF"

# Telegram: only if a bot token is present
if [ -n "${TELEGRAM_TOKEN:-}" ]; then
  echo "==> Deploying telegram-broadcast"
  supabase secrets set \
    TELEGRAM_TOKEN="$TELEGRAM_TOKEN" \
    TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:?set TELEGRAM_CHAT_ID}" \
    WEBHOOK_SECRET="${WEBHOOK_SECRET:?set WEBHOOK_SECRET}"
  supabase functions deploy telegram-broadcast --no-verify-jwt
else
  echo "-- Skipping telegram-broadcast (TELEGRAM_TOKEN blank)"
fi

# Stripe: only if a secret key is present. SUPABASE_* are auto-injected, never set here.
if [ -n "${STRIPE_SECRET_KEY:-}" ]; then
  echo "==> Deploying stripe-webhook"
  supabase secrets set \
    STRIPE_SECRET_KEY="$STRIPE_SECRET_KEY" \
    STRIPE_WEBHOOK_SECRET="${STRIPE_WEBHOOK_SECRET:?set STRIPE_WEBHOOK_SECRET}"
  supabase functions deploy stripe-webhook --no-verify-jwt
else
  echo "-- Skipping stripe-webhook (STRIPE_SECRET_KEY blank)"
fi

echo "==> Done. Function URLs:"
echo "   https://$SUPABASE_PROJECT_REF.functions.supabase.co/telegram-broadcast"
echo "   https://$SUPABASE_PROJECT_REF.functions.supabase.co/stripe-webhook"
echo "Next (dashboard, one-time): add the Database Webhook (signals insert -> telegram-broadcast,"
echo "header x-webhook-secret) and the Stripe webhook endpoint. See README."
