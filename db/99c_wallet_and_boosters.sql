-- ============================================================================
-- 99c_wallet_and_boosters.sql — schema changes for wallet drops + booster
-- pause/resume + per-30s idle. Run ONCE on a live database, then re-run
-- db/04_functions.sql. No data is lost.
-- ============================================================================

-- rare wallet drop needs its own cooldown clock
alter table player_state
  add column if not exists last_wallet_at timestamptz not null default now();

-- boosters can now be PAUSED (frozen remaining time) while a higher one runs
alter table player_boosters
  add column if not exists paused_seconds numeric;
alter table player_boosters
  alter column expires_at drop not null;

-- ============================================================================
-- Now re-run db/04_functions.sql to install settle_boosters(), the new
-- buy_booster(), claim_wallet(), and the per-30s claim_idle().
-- ============================================================================
