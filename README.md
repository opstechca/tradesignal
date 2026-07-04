# TradeSignal

Broadcast trading signals to followers, with free accounts, a realtime signal
feed, an auto-calculated public track record, and per-follower referral links.
Static frontend on GitHub Pages, data + auth on Supabase (free tier). No server
to run and nothing to deploy beyond a `git push`.

> Educational only. Not financial advice. Broadcasting stock signals may be a
> regulated activity where you live (SEBI / SEC / CIRO). Get advice before
> charging money. A disclaimer shows on every page: keep it.

---

## Design

### Stack
- **Frontend**: one file, `index.html`. Vanilla JS, no build step, no framework.
  Supabase JS client loaded from CDN. `config.js` holds the public keys + brand.
- **Backend**: Supabase (hosted Postgres). No custom server. Auth, database,
  Row Level Security, and realtime all come from Supabase.
- **Hosting**: GitHub Pages, plain static (`.nojekyll` forces raw serving).

### Data model (`schema.sql`)
| Table | Purpose |
|---|---|
| `profiles` | one row per user, mirrors `auth.users`. Holds `display_name`, `role` (`follower`/`admin`), `referral_code`, `referred_by`. `tier`/`paid_until` added by `schema-v2.sql`. |
| `signals` | what the admin broadcasts: `symbol`, `side` (BUY/SELL), `entry`, `target`, `stoploss`, `note`, `status` (open/hit_target/hit_sl/closed), `result_pct`. |
| `follows` | a follower marks "I took this" on a signal. Unique per (signal, user). |

### Security model (Row Level Security, enforced in Postgres)
Nothing is trusted from the browser. The anon key is public by design; RLS is
what actually protects data:
- **signals**: anyone (even logged out) can READ, which powers the public track
  record. Only an admin can insert or update.
- **profiles**: you read/update only your own row (admin can read all).
- **follows**: a follower manages only their own rows.
- `is_admin()` / `is_paid()` are `security definer` helpers with a pinned
  `search_path` so RLS checks can't be spoofed.

### Signup trigger
On every new `auth.users` row, a trigger (`handle_new_user`) auto-creates the
matching `profiles` row and generates a referral code. The internal
`supabase_auth_admin` role is granted rights on `profiles` so the trigger can
insert; this was the cause of the early "Database error saving new user"
failures, fixed in `schema-fix2.sql`.

---

## How it works

**Follower flow**
1. Signs up free (email + password). Profile + referral code created automatically.
2. Sees the **live feed**: newest signals first, updated in realtime.
3. Taps **"I took this"** on any open signal to log that they acted on it.
4. Gets a personal **referral link** (`?ref=CODE`) to invite others; new signups
   record who referred them.

**Admin flow (you)**
1. Post a signal: symbol, side, entry, optional target / stop loss / note.
2. When a call plays out, click **Target hit** or **SL hit** on that signal.
3. `result_pct` is computed at close from entry to exit, direction-aware
   (BUY vs SELL), and stored.

**Track record (always public)**
Win rate, total calls, winners, losers are computed live in the browser from
all closed signals. This is the growth engine: a logged-out visitor sees it.

**Realtime**
The frontend subscribes to a Supabase `postgres_changes` channel on `signals`.
Any insert/update reloads the feed for everyone currently viewing, no refresh.

---

## Done so far
- Static frontend live on GitHub Pages, wired to Supabase.
- Email/password auth: sign up, log in, forgot-password reset.
- Auto profile + referral code on signup (trigger fixed and verified).
- Realtime signal feed, newest first.
- Admin post-a-signal panel (admin-only, gated by RLS + UI).
- Admin close-a-signal (Target hit / SL hit) with auto `result_pct`.
- Public track record (win rate / totals) from closed calls.
- "I took this" follow/unfollow per signal.
- Per-follower referral links with `?ref=` capture.
- Account panel: change display name + password.
- RLS across all three tables; admin role set and confirmed working.
- Public **leaderboard** (`schema-v3.sql`): top followers by total return, win
  rate, calls taken. Your own row is highlighted.
- **Your P&L** summary for logged-in followers, from the signals you took.
- **Edge functions written**: Telegram auto-broadcast + Stripe paid-tier webhook.
- **`deploy.sh`**: one non-interactive command deploys both functions from `.env`.

## What's next
The remaining work needs credentials from your own accounts. Once you have them
it is one command; nothing else is left to code.
1. **First real signals** + share the leaderboard/track record. It needs data.
2. **Deploy the edge functions**: fill `.env` (copy `.env.example`), then
   `./deploy.sh`. Needs a Supabase Personal Access Token (`sbp_...`), and, per
   function, a Telegram bot token and/or Stripe keys. Then add the two webhooks
   in the dashboards (see below). Telegram + Stripe both go live from here.
3. **Web-push** browser notifications for new signals (needs VAPID keys).
4. **Live price feed** to auto-close signals at target/SL (needs a market data API).

---

## Setup (if starting fresh)
1. Create a Supabase project. In SQL Editor, run `schema.sql`, then
   `schema-fix2.sql` (the signup-trigger fix), then `schema-v3.sql` (leaderboard).
   Run `schema-v2.sql` only when you want the paid tier.
2. Put your Project URL + anon key in `config.js` (anon key is safe to expose).
3. Sign up in the app, then make yourself admin in SQL Editor:
   ```sql
   update profiles set role='admin'
   where id = (select id from auth.users where email='YOU@EMAIL.COM');
   ```
4. Push to GitHub, enable Pages (Settings -> Pages -> Source: main / root).

### Deploy the edge functions (`deploy.sh`)
Both functions are written (`supabase/functions/`). Install the CLI once
(`brew install supabase/tap/supabase`), copy `.env.example` to `.env`, fill it,
then run `./deploy.sh`. It links the project, sets secrets, and deploys whichever
functions have credentials present. `.env` is gitignored. Then wire the two
dashboard webhooks below.

### Telegram auto-broadcast
BotFather -> `/newbot` -> token. Create a channel, add the bot as admin, note its
chat id. Put both (plus `WEBHOOK_SECRET`) in `.env`, run `./deploy.sh`. Then
Supabase -> Database -> Webhooks -> Create: table `signals`, event Insert, HTTP
POST to `https://<ref>.functions.supabase.co/telegram-broadcast`, header
`x-webhook-secret` = your `WEBHOOK_SECRET`.

### Stripe paid tier
Run `schema-v2.sql` first (gates the feed). Stripe -> Payment Links -> put the URL
in `config.js` as `STRIPE_PAYMENT_LINK`; the app appends `client_reference_id=<user
id>`. Put `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET` in `.env`, run `./deploy.sh`.
Then Stripe -> Developers -> Webhooks -> add endpoint
`https://<ref>.functions.supabase.co/stripe-webhook`, events
`checkout.session.completed` + `customer.subscription.deleted`. The service role
key is auto-injected into the function, never in the frontend.

---

## Shortcuts taken (deliberate)
- `result_pct` is computed from entry to target/SL at the moment the admin
  closes a signal, not from a live price feed. Add a market data API for auto-close.
- Single admin model via a `role` column. Fine for a small team.
- Track record math runs client-side from the last 50 signals. Move to a SQL
  view if the history grows large.
