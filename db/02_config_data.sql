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
insert into methods (id, name, cost, multiplier, sort) values
  ('piggy_bank', 'Piggy Bank',       0,      1.0,  0),   -- owned by default
  ('wallet',     'Wallet',           5,      1.5,  1),
  ('qr',         'QR DuitSekarang',  50,     2.5,  2),
  ('card',       'Debit Card',       250,    4.0,  3),
  ('bank',       'Bank Account',     1500,   6.0,  4),
  ('vault',      'Vault',            12000,  12.0, 5)
on conflict (id) do update set
  name = excluded.name, cost = excluded.cost,
  multiplier = excluded.multiplier, sort = excluded.sort;

-- UPGRADES:
--   tap   -> dollars per click  = (1 + tap_level) * $0.01 * place_mult * booster
--   drone -> passive $/sec      = (drone_level * $0.01) * place_mult
-- Cost of the NEXT level = base_cost * growth ^ current_level.
insert into upgrades (id, kind, name, base_cost, growth, effect, max_level, sort) values
  ('hustle', 'tap',   'Side Hustle',     0.50, 1.15, 0.01, 100, 0),
  ('invest', 'drone', 'Auto Investment', 2.00, 1.18, 0.01, 100, 1)
on conflict (id) do update set
  kind = excluded.kind, name = excluded.name, base_cost = excluded.base_cost,
  growth = excluded.growth, effect = excluded.effect,
  max_level = excluded.max_level, sort = excluded.sort;

-- BOOSTERS: temporary flat multipliers on tap value. Best active one applies.
insert into boosters (id, name, cost, multiplier, duration_seconds, sort) values
  ('payday',   'Payday',            3,  2.0, 30, 0),
  ('compound', 'Compound Interest', 15, 3.0, 60, 1)
on conflict (id) do update set
  name = excluded.name, cost = excluded.cost, multiplier = excluded.multiplier,
  duration_seconds = excluded.duration_seconds, sort = excluded.sort;

-- RANKS: Malaysian traditional / honorific titles, commoner (Rakyat) up to the
-- King (Yang di-Pertuan Agong). A rank is BUYABLE once you hit min_level; buying
-- it spends balance and sets it as your title. cost/min_level climb up the ladder.
-- tap_bonus = flat dollars added to EACH tap while you hold the rank (prestige).
-- It ramps hard on the top ranks so the late game snowballs toward Bilionair.
insert into ranks (id, name, cost, min_level, tap_bonus, sort) values
  ('rakyat',          'Rakyat',           0,          1,     0,       0),
  ('anak_dato',       'Anak Dato',        15,         3,     0.05,    1),
  ('anak_tan_sri',    'Anak Tan Sri',     100,        6,     0.25,    2),
  ('ceo',             'CEO',              500,        12,    1.5,     3),
  ('dato',            'Dato',             1800,       22,    8,       4),
  ('tan_sri',         'Tan Sri',          4500,       35,    40,      5),
  ('menteri',         'Menteri',          12000,      55,    150,     6),
  ('perdana_menteri', 'Perdana Menteri',  25000,      80,    600,     7),
  -- Jutawan unlocks at $1,000,000 net worth (level 334),
  -- Bilionair at $1,000,000,000 net worth (level 10541).
  ('jutawan',         'Jutawan',          250000,     334,   3000,    8),
  ('bilionair',       'Bilionair',        250000000,  10541, 250000,  9)
on conflict (id) do update set
  name = excluded.name, cost = excluded.cost, min_level = excluded.min_level,
  tap_bonus = excluded.tap_bonus, sort = excluded.sort;
