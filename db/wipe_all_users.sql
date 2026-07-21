-- ============================================================================
-- wipe_all_users.sql — delete EVERY user account and ALL of their data.
-- ----------------------------------------------------------------------------
-- Deleting from auth.users cascades to:
--   * your app tables: profiles, player_state, owned_methods, player_boosters
--     (all reference auth.users(id) ON DELETE CASCADE)
--   * Supabase's own auth tables: identities, sessions, refresh_tokens, ...
-- Everyone is removed and must sign up again from scratch. The game config
-- (methods / upgrades / boosters / ranks) is kept.
--
-- DESTRUCTIVE — there is NO undo. Run in the Supabase SQL Editor.
-- ============================================================================

delete from auth.users;
