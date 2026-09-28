# Fantasy Cardroom

A poker-room themed fantasy-football web app built for **Supabase + Netlify**.

## What is implemented

- Email/password accounts with a unique username.
- One administrator role plus normal players.
- Multiple weekly contests created by the administrator.
- **5 credits per hand** and **10 hands max per user per contest**.
- Mystery-card draft: every deal contains 3 server-generated cards that reveal **only position + NFL division** until one is selected.
- Starter-only player pool for QB/RB/WR/TE.
- Seven-card fantasy hand: **QB, RB, RB, WR, WR, TE, FLEX (RB/WR/TE)**.
- Once roster capacity for a position is full, that position is removed from future deals.
- No duplicate player can appear in the same hand.
- Player reveal card supports licensed headshot URL + current-season stats.
- Three one-use wildcards, each on a different player:
  - NFL: random same-position starter anywhere in the NFL.
  - Conference: random same-position starter in the same AFC/NFC conference.
  - Division: random same-position starter in the same NFL division.
- Half-PPR live scoring.
- Live leaderboard and overview of all of a user's hands.
- Credit-pot payouts: **60% first / 30% second / 10% third**.
- Fair ties: tied hands split the prize percentages represented by the tied finishing slots.
- Supabase Realtime support for score updates.
- Admin controls for contests, user credits, starter sync, scoring sync, lock/live/finalize.
- Responsive dark-green felt / brass / backroom poker design.

## Architecture

**Netlify** only hosts the built React/Vite site. The sensitive game logic lives in **Supabase PostgreSQL RPC functions**, so users cannot inspect the browser to discover mystery-card identities or manipulate random draws.

**Supabase Edge Functions** handle third-party NFL data. `sync-live-stats` can be invoked by Supabase Cron during games, keeping recurring live-scoring work off Netlify Functions.

### NFL data source

The included adapter is written for SportsDataIO because it provides NFL depth-chart data, real-time player stats, fantasy data, and licensed headshot products. It is deliberately isolated in two Edge Functions so you can replace it with another licensed feed later without changing game logic.

Your rule says the eligible pool must match **NFL official depth charts**. NFL.com does not expose a documented public depth-chart API in this project. For strict production compliance with that wording, use an authorized/licensed feed whose starter designation you accept as the source of truth, or replace `sync-players` with your authorized NFL data source. Do not rely on fragile scraping for a paid contest product.

Player photographs also require appropriate image rights. SportsDataIO offers licensed NFL headshot products; if your subscription does not include them, the UI falls back to a silhouette.

## Half-PPR scoring used

- Passing: 1 point / 25 yards, 4 per passing TD, -2 per interception.
- Rushing: 1 point / 10 yards, 6 per rushing TD.
- Receiving: 0.5 per reception, 1 point / 10 yards, 6 per receiving TD.
- Two-point conversions: 2 points.
- Fumbles lost: -2 points.

Edit `halfPpr()` in `supabase/functions/sync-live-stats/index.ts` if your contest rules differ.

---

# 1. Create the Supabase project

1. Create a Supabase project.
2. Open **SQL Editor**.
3. Run `supabase/schema.sql`.
4. In Authentication, enable Email/Password.
5. For quickest private testing you may disable email confirmation. For public use, leave confirmation enabled and configure your Site URL / redirect URLs.

The schema gives newly registered accounts **50 demo credits** so you can test ten hands. If credits should only be issued manually, change the default in `profiles` and `handle_new_user()` before launch.

## Make yourself administrator

Create your account through the app first, then run:

```sql
update public.profiles
set is_admin = true
where email = 'YOUR_EMAIL@example.com';
```

## Optional demo deck

Before connecting a sports-data API, run `supabase/seed_demo.sql`. It inserts fictional 2026 starters so you can test deals and wildcards. Do not use that seed for a real contest.

---

# 2. Configure the React app

Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

Set:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```

The publishable/anon key is expected in a browser app. **Never put the service-role key in Vite or any `VITE_` variable.**

Install and run:

```bash
npm install
npm run dev
```

---

# 3. Deploy the Supabase Edge Functions

Install and log into the Supabase CLI, link the project, then set secrets:

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set SPORTSDATA_API_KEY=YOUR_KEY
supabase secrets set CRON_SECRET=A_LONG_RANDOM_SECRET
```

Optional endpoint overrides are supported if your SportsDataIO plan uses different feed paths:

```bash
supabase secrets set SPORTSDATA_DEPTH_URL='https://api.sportsdata.io/v3/nfl/scores/json/DepthCharts'
supabase secrets set SPORTSDATA_PLAYERS_URL='https://api.sportsdata.io/v3/nfl/scores/json/Players'
supabase secrets set SPORTSDATA_SEASON_STATS_URL='https://api.sportsdata.io/v3/nfl/stats/json/PlayerSeasonStats/{season}'
supabase secrets set SPORTSDATA_WEEK_STATS_URL='https://api.sportsdata.io/v3/nfl/stats/json/PlayerGameStatsByWeek/{season}/{week}'
```

If you license the headshot endpoint, also set `SPORTSDATA_HEADSHOTS_URL` to the endpoint supplied for your account.

Deploy:

```bash
supabase functions deploy sync-players
supabase functions deploy sync-live-stats
```

The Admin Room can invoke both functions manually while you test.

> SportsDataIO endpoint access varies by subscription. The adapter surfaces provider HTTP errors directly so it is obvious if a feed/path is not enabled. Confirm your exact feed URLs in your SportsDataIO developer portal.

---

# 4. Schedule live scoring in Supabase

Use Supabase Cron to call `sync-live-stats` during the season. The function skips API work if no contest has `live` status.

A simple production option is every minute. In the Supabase Cron UI, create an HTTP/Edge Function job for `sync-live-stats` and send the same `x-cron-secret` value stored in the function secrets.

If configuring in SQL with Vault/pg_net, follow Supabase's current **Scheduling Edge Functions** guide and store the URL/key/secret in Vault rather than hardcoding secrets in SQL.

For lower API usage, run every 2–5 minutes outside your most important live windows, or create schedules only for Thursday/Sunday/Monday game windows.

---

# 5. Deploy to Netlify

Push this folder to GitHub and import the repository into Netlify.

`netlify.toml` is already configured:

- Build command: `npm run build`
- Publish directory: `dist`
- SPA redirect: all routes -> `index.html`

Add these Netlify environment variables:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```

Deploy. No Netlify Function is required by this version.

---

# Contest workflow

1. Admin creates a contest for season/week.
2. Admin runs **Sync starters & season stats** before opening play.
3. Users buy up to ten 5-credit hands and complete their card draws.
4. Users may use each wildcard once, on three different player cards.
5. At the roster/game deadline, admin **Locks** the contest. Locked contests reject further card selections/wildcards.
6. Admin sets the contest **Live** when scoring should begin.
7. Supabase Cron refreshes player-week stats; triggers propagate those points into every relevant hand, and Realtime updates the leaderboard.
8. After all games are final, admin clicks **Finalize + Pay**. The pot is credited automatically to the top three finishing positions (with tied finishing slots split fairly).

## Important launch decisions still worth making

The MVP intentionally leaves these as business-rule choices rather than guessing:

- Whether an unfinished purchased hand at contest lock is forfeited, refunded, or auto-completed.
- Whether wildcards may be used immediately after a hand is built or only in a separate pre-lock window.
- Whether credits are strictly play-money, admin-granted, promotional, or bought/redeemed for money. If credits have real monetary value, get jurisdiction-specific legal/compliance advice before launch.
- Whether starter eligibility freezes when a contest opens, when a hand is purchased, or at contest lock. The current deck uses the latest `players.is_starter` state at each deal.
- Whether injuries/inactives affect eligibility after a hand is created.

## Recommended next production upgrade

Create a `contest_player_pool` snapshot table when the admin opens/locks each contest. That freezes which players are eligible for that contest and creates an auditable record even if the external depth chart changes later. The current MVP deliberately keeps the data model simpler and always deals from the current starter pool.
