-- ============================================================================
-- reset_players.sql — wipe EVERY player's progress back to a fresh start.
-- ----------------------------------------------------------------------------
-- Keeps accounts (auth.users) and display names (profiles). After this, every
-- player is back to: $0 net worth, $0 balance, level 1, Piggy Bank, Rakyat rank,
-- no upgrades, no boosters.
--
-- DESTRUCTIVE — there is no undo. Run in Supabase SQL Editor.
-- ============================================================================

-- 1. drop everyone's boosters and method ownership
delete from player_boosters;
delete from owned_methods;

-- 2. reset the core economy for every player
update player_state set
  net_worth         = 0,
  balance           = 0,
  level             = 1,
  tap_level         = 0,
  drone_level       = 0,
  current_method_id = 'piggy_bank',
  rank_id           = 'rakyat',
  last_click_at     = now(),
  last_idle_at      = now(),
  last_cash_at      = now(),
  last_wallet_at    = now(),
  updated_at        = now();

-- 3. give everyone back the starting method
insert into owned_methods (user_id, method_id)
  select user_id, 'piggy_bank' from player_state
on conflict do nothing;
