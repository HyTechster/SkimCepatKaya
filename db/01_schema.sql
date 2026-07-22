-- ============================================================================
-- 01_schema.sql — tables
-- ----------------------------------------------------------------------------
-- Run order: 01_schema → 02_config_data → 03_rls → 04_functions → 05_leaderboard
-- Paste each file into Supabase → SQL Editor → New query → Run.
--
-- Design in one sentence: the CLIENT never writes score/money. Everything the
-- player owns lives here and is only ever changed by the SECURITY DEFINER
-- functions in 04_functions.sql, which validate and rate-limit on the server.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- CONFIG TABLES (server-owned price lists). These are the ONLY source of truth
-- for costs and effects. The client reads them to draw the shop, but the buy
-- functions recompute every cost server-side, so a tampered client buys nothing.
-- ---------------------------------------------------------------------------

-- Unlockable locations. Each place has a score/idle multiplier.
create table if not exists methods (
  id          text primary key,
  name        text    not null,
  cost        numeric not null check (cost >= 0),   -- in balance (money)
  multiplier  numeric not null check (multiplier > 0),
  sort        int     not null default 0
);

-- Upgrades come in two kinds:
--   'tap'   -> more net_worth per click (active)
--   'drone' -> more passive net_worth per second (idle income)
create table if not exists upgrades (
  id          text primary key,
  kind        text    not null check (kind in ('tap', 'drone')),
  name        text    not null,
  base_cost   numeric not null check (base_cost >= 0),
  growth      numeric not null check (growth >= 1),  -- cost *= growth^level
  effect      numeric not null,                      -- per-level effect size
  max_level   int     not null check (max_level > 0),
  sort        int     not null default 0
);

-- Temporary multipliers you can buy. They stack by taking the highest active one.
-- Price is dynamic: max(cost, net_worth * cost_rate). `cost` is the early-game
-- floor; `cost_rate` scales the price with the player's net worth so a booster
-- always costs a meaningful chunk (roughly a fixed grind) instead of staying cheap.
create table if not exists boosters (
  id                text primary key,
  name              text    not null,
  cost              numeric not null check (cost >= 0),          -- price floor
  cost_rate         numeric not null default 0 check (cost_rate >= 0),  -- fraction of net worth
  multiplier        numeric not null check (multiplier > 1),
  duration_seconds  int     not null check (duration_seconds > 0),
  sort              int     not null default 0
);

-- Purchasable prestige titles (Malaysian traditional ranks). A rank is BUYABLE
-- once the player reaches min_level; buying it (spending balance) sets it as the
-- player's current rank. sort defines the ladder order (higher = grander).
create table if not exists ranks (
  id         text primary key,
  name       text    not null,
  cost       numeric not null check (cost >= 0),          -- in balance (money)
  min_level  int     not null check (min_level >= 1),
  tap_bonus  numeric not null default 0 check (tap_bonus >= 0),  -- flat $ added per tap while held
  sort       int     not null default 0
);

-- ---------------------------------------------------------------------------
-- PER-PLAYER TABLES. One row (or set of rows) per authenticated user.
-- ---------------------------------------------------------------------------

-- Public-facing identity. display_name is what shows on the leaderboard;
-- the email in auth.users is never exposed.
create table if not exists profiles (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 24),
  created_at  timestamptz not null default now()
);

-- The authoritative economy. net_worth is the SCORE (monotonic, never decreases —
-- spending uses balance, not net_worth — which keeps the leaderboard honest).
create table if not exists player_state (
  user_id          uuid primary key references auth.users (id) on delete cascade,
  net_worth           numeric not null default 0 check (net_worth   >= 0),  -- score
  balance         numeric not null default 0 check (balance >= 0),  -- money
  level            int     not null default 1,
  tap_level        int     not null default 0,   -- active upgrade level
  drone_level      int     not null default 0,   -- passive/idle upgrade level
  current_method_id text    not null default 'piggy_bank' references methods (id),
  rank_id          text    not null default 'rakyat' references ranks (id),  -- prestige title
  last_click_at    timestamptz not null default now(),  -- server clock: rate limit
  last_idle_at     timestamptz not null default now(),  -- server clock: idle payout
  last_cash_at    timestamptz not null default (now() - interval '1 day'),  -- past: first coin drop is claimable
  last_wallet_at   timestamptz not null default (now() - interval '1 day'),  -- past: first wallet drop is claimable
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- Which methods a user has unlocked.
create table if not exists owned_methods (
  user_id   uuid not null references auth.users (id) on delete cascade,
  method_id  text not null references methods (id),
  primary key (user_id, method_id)
);

-- Active temporary boosters and when they expire (server clock).
-- A booster is either ACTIVE (expires_at set, ticking down) or PAUSED
-- (paused_seconds set = frozen remaining time, because a higher-multiplier
-- booster is currently running). At most one booster is active at a time.
create table if not exists player_boosters (
  user_id         uuid not null references auth.users (id) on delete cascade,
  booster_id      text not null references boosters (id),
  expires_at      timestamptz,   -- set when this booster is the ACTIVE one
  paused_seconds  numeric,       -- set (frozen remaining) when PAUSED by a higher booster
  primary key (user_id, booster_id)
);

-- Fast leaderboard reads.
create index if not exists player_state_net_worth_idx on player_state (net_worth desc);
