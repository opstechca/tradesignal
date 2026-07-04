# Stock Signals platform

Broadcast trading signals to followers, with accounts, a live feed, a public
track record, and referral links. Frontend on GitHub Pages, data on Supabase
(free). No server to run.

> Educational only. Not financial advice. Sending stock signals may be a
> regulated activity where you live (SEBI / SEC / CIRO). Get advice before
> charging money. A disclaimer is shown on every page - keep it.

## What it does
- Followers **sign up free**, see a **live signal feed** (updates in real time).
- Each follower taps **"I took this"** on signals they act on.
- **Public track record**: win rate auto-calculated from closed calls. Your growth engine.
- **Referral link** per follower to invite others (`?ref=CODE`).
- **Admin** (you) posts signals and marks Target/SL hit; P&L % is auto-computed.

## Setup (15 minutes)

### 1. Create the Supabase project
1. Go to [supabase.com](https://supabase.com) → new project (free). Pick a strong DB password.
2. Left menu → **SQL Editor** → New query → paste all of `schema.sql` → **Run**.
3. Left menu → **Project Settings → API**. Copy the **Project URL** and the **anon public** key.

### 2. Wire up the frontend
Edit `config.js`:
```js
window.SUPABASE_URL  = "https://xxxx.supabase.co";   // your Project URL
window.SUPABASE_ANON_KEY = "eyJhbGciOi...";           // anon public key (safe to expose)
window.BRAND = "Your Signals";
```
The anon key is meant to be public - Row Level Security in `schema.sql` protects the data.

### 3. Make yourself the admin
1. Open the app, **Sign up** with your email (this creates your account).
2. In Supabase → SQL Editor, run (your email):
   ```sql
   update profiles set role='admin'
   where id = (select id from auth.users where email='YOU@EMAIL.COM');
   ```
3. Reload the app - you now see the **Post a signal** panel.

Optional: Supabase → Authentication → Providers → Email → turn **"Confirm email"** off
for faster signups while testing.

## Deploy to GitHub Pages
```bash
cd signals-app
git init && git add . && git commit -m "Stock signals app"
git branch -M main
git remote add origin git@github.com:YOUR_USER/signals-app.git   # create the empty repo first
git push -u origin main
```
Then repo → **Settings → Pages → Source: main / root → Save**.
Live at `https://YOUR_USER.github.io/signals-app/`.

## Broadcasting to your existing followers (Telegram, free)
The web app is the database + track record. To also **push** each new signal to a
Telegram channel (easier + free vs WhatsApp Business API):
1. Telegram → message **@BotFather** → `/newbot` → get a bot token.
2. Create a channel, add the bot as admin.
3. Later: a small Supabase Edge Function on new-signal insert calls
   `https://api.telegram.org/bot<TOKEN>/sendMessage`. Ask and I'll add it.

Keep your WhatsApp group too - put the app link in its description so members sign up.

## Paid tier + auto-broadcast (v2)

Run `schema-v2.sql` in the Supabase SQL Editor (after `schema.sql`). This adds
paid tiers and gates the feed: **free followers see signals 30 min delayed**
(plus all closed calls for the track record); **paid + admin see them live**.
The gate is enforced by Row Level Security, so it can't be bypassed from the browser.

Both features run as **Supabase Edge Functions** (free). Install the CLI once:
`npm i -g supabase` then `supabase login` and `supabase link --project-ref YOUR_REF`.

### (a) Telegram auto-broadcast
1. Telegram → **@BotFather** → `/newbot` → copy the **token**.
2. Create a channel, add the bot as an **admin**. Get its id (e.g. `@yoursignals`).
3. Set secrets + deploy:
   ```bash
   supabase secrets set TELEGRAM_TOKEN=xxx TELEGRAM_CHAT_ID=@yoursignals WEBHOOK_SECRET=$(openssl rand -hex 16)
   supabase functions deploy telegram-broadcast --no-verify-jwt
   ```
4. Supabase → **Database → Webhooks** → Create:
   - Table `signals`, event **Insert**
   - Type **HTTP Request** → URL = your function URL
     (`https://YOUR_REF.functions.supabase.co/telegram-broadcast`)
   - Add HTTP header `x-webhook-secret: <the WEBHOOK_SECRET value>`
5. Post a signal in the app → it lands in your Telegram channel.

### (b) Stripe paid tier
1. Stripe → **Payment Links** → new link for your monthly plan. Copy the URL.
2. Put it in `config.js`:
   ```js
   window.STRIPE_PAYMENT_LINK = "https://buy.stripe.com/xxxx";
   ```
   The app appends `?client_reference_id=<user id>` so the webhook knows who paid.
3. Set secrets + deploy the webhook:
   ```bash
   supabase secrets set STRIPE_SECRET_KEY=sk_live_xxx STRIPE_WEBHOOK_SECRET=whsec_xxx \
     SUPABASE_URL=https://YOUR_REF.supabase.co SUPABASE_SERVICE_ROLE_KEY=eyJ...service_role
   supabase functions deploy stripe-webhook --no-verify-jwt
   ```
4. Stripe → **Developers → Webhooks** → add endpoint = your function URL
   (`https://YOUR_REF.functions.supabase.co/stripe-webhook`), events:
   `checkout.session.completed`, `customer.subscription.deleted`.
   Copy the signing secret (`whsec_...`) back into step 3 if you didn't already.
5. A free follower clicks **Upgrade → live signals**, pays, and the webhook flips
   them to `tier='paid'`. They see signals live immediately.

> The **service role key** goes ONLY into the edge function secret - never into
> `config.js` or the frontend. It bypasses all security rules.

## Roadmap (ask when you want these)
- Web-push notifications in the browser
- Per-follower P&L dashboard and leaderboard
- Live price feed to auto-close signals at target/SL (needs a market data API)

## Shortcuts taken (deliberate)
- Result % is computed from entry→target/SL at the moment admin closes a signal,
  not from a live price feed. Add a data API when you want auto-close.
- Single admin model via a `role` column. Fine for a small team.
