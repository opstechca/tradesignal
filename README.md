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

## What's next
Roughly in priority order. Ask when you want one.
1. **First real signals** + share the track record. The product is live; it needs data.
2. **Telegram auto-broadcast**: Supabase Edge Function on new-signal insert
   pushes to a Telegram channel (setup notes below). Reaches existing followers.
3. **Paid tier (Stripe)**: `schema-v2.sql` gates the feed so free followers see
   signals 30 min delayed and paid/admin see them live, enforced by RLS. Stripe
   Payment Link + a webhook Edge Function flips a user to `tier='paid'`.
   `STRIPE_PAYMENT_LINK` in `config.js` is empty until this is wired.
4. **Web-push** browser notifications for new signals.
5. **Per-follower P&L dashboard** + leaderboard (uses the `follows` data).
6. **Live price feed** to auto-close signals at target/SL (needs a market data API).

---

## Setup (if starting fresh)
1. Create a Supabase project. In SQL Editor, run `schema.sql`, then
   `schema-fix2.sql` (the signup-trigger fix). Run `schema-v2.sql` only when you
   want the paid tier.
2. Put your Project URL + anon key in `config.js` (anon key is safe to expose).
3. Sign up in the app, then make yourself admin in SQL Editor:
   ```sql
   update profiles set role='admin'
   where id = (select id from auth.users where email='YOU@EMAIL.COM');
   ```
4. Push to GitHub, enable Pages (Settings -> Pages -> Source: main / root).

### Telegram auto-broadcast (when ready)
BotFather -> `/newbot` -> token. Create a channel, add the bot as admin. Deploy a
Supabase Edge Function, add a Database Webhook on `signals` insert pointing at it,
guarded by an `x-webhook-secret` header. Ask and I'll write the function.

### Stripe paid tier (when ready)
Stripe Payment Link -> put URL in `config.js`. The app appends
`client_reference_id=<user id>`. A webhook Edge Function (holding the service
role key as a secret, never in the frontend) flips the payer to `tier='paid'`.

---

## Shortcuts taken (deliberate)
- `result_pct` is computed from entry to target/SL at the moment the admin
  closes a signal, not from a live price feed. Add a market data API for auto-close.
- Single admin model via a `role` column. Fine for a small team.
- Track record math runs client-side from the last 50 signals. Move to a SQL
  view if the history grows large.
