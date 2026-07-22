-- ============================================================================
-- 02_config_data.sql — seed the price lists (methods, upgrades, boosters)
-- ----------------------------------------------------------------------------
-- MONEY THEME (Tabung). All costs are in dollars (the spendable balance).
-- Tweak freely and re-run: `on conflict` makes this idempotent.
-- The client mirrors these to draw the shop; the server recomputes every cost
-- on purchase, so editing here changes the real economy.
-- ============================================================================

-- METHODS: the thing you tap changes to match your current place. cost is in
-- dollars; multiplier scales both tap value and idle income.
-- cost climbs steeply: each method is a real savings goal, and (server-enforced)
-- you must own the one below it before you can buy the next.
insert into methods (id, name, cost, multiplier, sort) values
  ('piggy_bank', 'Piggy Bank',       0,       1.0,  0),   -- owned by default
  ('wallet',     'Wallet',           35,      1.5,  1),
  ('qr',         'QR DuitSekarang',  300,     2.5,  2),
  ('card',       'Debit Card',       2000,    4.0,  3),
  ('bank',       'Bank Account',     15000,   6.0,  4),
  ('vault',      'Vault',            120000,  12.0, 5)
on conflict (id) do update set
  name = excluded.name, cost = excluded.cost,
  multiplier = excluded.multiplier, sort = excluded.sort;

-- UPGRADES:
--   tap   -> dollars per click  = ($0.01 base + hustle) * place_mult * booster
--             where hustle SCALES gently: the Nth level adds $0.003 x N, so total
--             after L levels = 0.003 * L*(L+1)/2 (L15 ~ $0.36, L50 ~ $3.83, L100 ~ $15).
--             `effect` holds the per-level step (0.003); the client multiplies it by
--             the next level to show its real gain.
--   drone -> passive $/sec      = (drone_level * $0.01) * place_mult  (flat effect)
-- Cost of the NEXT level = base_cost * growth ^ current_level.
-- Side Hustle is the main grind. Its cost climbs FASTER (growth 1.20) than its
-- per-tap payoff, so each level takes real taps to afford (~18-50 early-mid, into
-- the hundreds later) instead of being buyable every 2-3 taps.
insert into upgrades (id, kind, name, base_cost, growth, effect, max_level, sort) values
  ('hustle', 'tap',   'Side Hustle',     0.50, 1.20, 0.003, 100, 0),
  ('invest', 'drone', 'Auto Investment', 2.00, 1.18, 0.01,  100, 1)
on conflict (id) do update set
  kind = excluded.kind, name = excluded.name, base_cost = excluded.base_cost,
  growth = excluded.growth, effect = excluded.effect,
  max_level = excluded.max_level, sort = excluded.sort;

-- BOOSTERS: temporary flat multipliers on tap value. Best active one applies.
-- Price is dynamic: max(cost, base_per_tap * cost_taps). `cost` is the early-game
-- floor; `cost_taps` prices the booster at that many taps' worth of your current
-- income, so it scales with per-tap power (hustle/method/rank) but stays STEADY
-- between upgrades (net worth would creep the price up on every tap). Stronger
-- boosters cost more taps. Tune cost_taps up for a longer grind.
-- (Migrate the old net-worth `cost_rate` column to `cost_taps` if it exists.)
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_name = 'boosters' and column_name = 'cost_rate') then
    alter table boosters rename column cost_rate to cost_taps;
  end if;
end $$;
alter table boosters add column if not exists cost_taps numeric not null default 0;
insert into boosters (id, name, cost, cost_taps, multiplier, duration_seconds, sort) values
  ('payday',   'Payday',            3,  90,  2.0, 30, 0),
  ('compound', 'Compound Interest', 15, 150, 3.0, 20, 1)
on conflict (id) do update set
  name = excluded.name, cost = excluded.cost, cost_taps = excluded.cost_taps,
  multiplier = excluded.multiplier,
  duration_seconds = excluded.duration_seconds, sort = excluded.sort;

-- RANKS: Malaysian traditional / honorific titles, commoner (Rakyat) up to the
-- King (Yang di-Pertuan Agong). A rank is BUYABLE once you hit min_level; buying
-- it spends balance and sets it as your title. cost/min_level climb up the ladder.
-- tap_bonus = flat dollars added to EACH tap while you hold the rank (prestige).
-- Since per_tap = (rank_bonus + hustle) x method x booster, this bonus gets
-- multiplied by your method (up to 12x) and booster (up to 3x). So it is kept
-- SMALL on purpose: a few cents through mid game, only a few dollars at the very
-- top. Rank is a steady prestige perk; Side Hustle is the real per-tap driver.
insert into ranks (id, name, cost, min_level, tap_bonus, sort) values
  ('rakyat',          'Rakyat',           0,          1,     0,      0),
  ('anak_dato',       'Anak Dato',        15,         3,     0.02,   1),
  ('anak_tan_sri',    'Anak Tan Sri',     100,        6,     0.05,   2),
  ('ceo',             'CEO',              500,        12,    0.10,   3),
  ('dato',            'Dato',             1800,       22,    0.20,   4),
  ('tan_sri',         'Tan Sri',          4500,       35,    0.40,   5),
  ('menteri',         'Menteri',          12000,      55,    0.70,   6),
  ('perdana_menteri', 'Perdana Menteri',  25000,      80,    1.20,   7),
  -- Jutawan unlocks at $1,000,000 net worth (level 334),
  -- Bilionair at $1,000,000,000 net worth (level 10541).
  ('jutawan',         'Jutawan',          250000,     334,   2.50,   8),
  ('bilionair',       'Bilionair',        250000000,  10541, 5.00,   9)
on conflict (id) do update set
  name = excluded.name, cost = excluded.cost, min_level = excluded.min_level,
  tap_bonus = excluded.tap_bonus, sort = excluded.sort;
