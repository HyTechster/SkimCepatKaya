-- ============================================================================
-- 99b_rename_to_methods.sql — rename the old cosmic-ish names to money names
-- ----------------------------------------------------------------------------
-- Run this ONCE on a live database that already has the previous names
-- (places / energy / stardust / current_place_id / claim_comet / ...). It only
-- RENAMES, so no data is lost. Afterwards, re-run 03_rls.sql, 04_functions.sql,
-- and 05_leaderboard.sql to reinstall the policies and functions with the new
-- names.
--
-- A brand-new setup does NOT need this file: 01..05 already use the new names.
-- ============================================================================

-- tables
alter table if exists places       rename to methods;
alter table if exists owned_places rename to owned_methods;

-- columns
alter table owned_methods rename column place_id         to method_id;
alter table player_state  rename column energy           to net_worth;
alter table player_state  rename column stardust         to balance;
alter table player_state  rename column current_place_id to current_method_id;
alter table player_state  rename column last_comet_at    to last_cash_at;

-- index
alter index if exists player_state_energy_idx rename to player_state_net_worth_idx;

-- drop the old-named functions (replaced by set_method / unlock_method / claim_cash)
drop function if exists set_place(text);
drop function if exists unlock_place(text);
drop function if exists claim_comet();

-- drop the old-named RLS policies (re-created when you re-run 03_rls.sql)
drop policy if exists "places read" on methods;
drop policy if exists "own places"  on owned_methods;

-- ============================================================================
-- Now re-run, in order: 03_rls.sql  →  04_functions.sql  →  05_leaderboard.sql
-- ============================================================================
