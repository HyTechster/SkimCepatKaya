-- ============================================================================
-- 03_rls.sql — Row Level Security
-- ----------------------------------------------------------------------------
-- The whole security model in one idea:
--   * Config tables (methods/upgrades/boosters): anyone may READ (to draw the
--     shop). No one may write.
--   * Player tables (player_state/profiles/owned_methods/player_boosters): a
--     user may READ ONLY THEIR OWN rows, and may NOT write them directly.
--
-- Notice there are NO insert/update/delete policies on the player tables. That
-- is deliberate: with RLS on and no write policy, the anon/authenticated roles
-- CANNOT change score, money, or upgrades no matter what they send. The only
-- way those rows change is through the SECURITY DEFINER functions in
-- 04_functions.sql, which run as the table owner (bypassing RLS) and validate
-- everything first. This is what closes the "set score = 999999" attack.
-- ============================================================================

-- ---- config tables: public read, no write --------------------------------
alter table methods   enable row level security;
alter table upgrades enable row level security;
alter table boosters enable row level security;
alter table ranks    enable row level security;

drop policy if exists "methods read"   on methods;
drop policy if exists "upgrades read" on upgrades;
drop policy if exists "boosters read" on boosters;
drop policy if exists "ranks read"    on ranks;

create policy "methods read"   on methods   for select using (true);
create policy "upgrades read" on upgrades for select using (true);
create policy "boosters read" on boosters for select using (true);
create policy "ranks read"    on ranks    for select using (true);

-- ---- player tables: read own rows only, never write ----------------------
alter table profiles        enable row level security;
alter table player_state    enable row level security;
alter table owned_methods    enable row level security;
alter table player_boosters enable row level security;

drop policy if exists "own profile"  on profiles;
drop policy if exists "own state"    on player_state;
drop policy if exists "own methods"   on owned_methods;
drop policy if exists "own boosters" on player_boosters;

create policy "own profile"  on profiles        for select using (auth.uid() = user_id);
create policy "own state"    on player_state     for select using (auth.uid() = user_id);
create policy "own methods"   on owned_methods     for select using (auth.uid() = user_id);
create policy "own boosters" on player_boosters  for select using (auth.uid() = user_id);
-- (No insert/update/delete policies anywhere above — writes go through functions.)
