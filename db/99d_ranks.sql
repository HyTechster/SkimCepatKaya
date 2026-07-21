-- ============================================================================
-- 99d_ranks.sql — add / update the prestige rank system on a live database.
-- Run ONCE, then re-run db/04_functions.sql and db/05_leaderboard.sql.
-- Safe to run again: it also cleans up an earlier (16-rank) version if present.
-- (A brand-new setup does not need this — 01..05 already include ranks.)
-- ============================================================================

-- 1. ranks config table (+ tap_bonus column if upgrading from an older version)
create table if not exists ranks (
  id         text primary key,
  name       text    not null,
  cost       numeric not null check (cost >= 0),
  min_level  int     not null check (min_level >= 1),
  tap_bonus  numeric not null default 0,
  sort       int     not null default 0
);
alter table ranks add column if not exists tap_bonus numeric not null default 0;

-- 2. seed the 10-rank ladder (same as db/02_config_data.sql)
insert into ranks (id, name, cost, min_level, tap_bonus, sort) values
  ('rakyat',          'Rakyat',           0,          1,     0,       0),
  ('anak_dato',       'Anak Dato',        15,         3,     0.05,    1),
  ('anak_tan_sri',    'Anak Tan Sri',     100,        6,     0.25,    2),
  ('ceo',             'CEO',              500,        12,    1.5,     3),
  ('dato',            'Dato',             1800,       22,    8,       4),
  ('tan_sri',         'Tan Sri',          4500,       35,    40,      5),
  ('menteri',         'Menteri',          12000,      55,    150,     6),
  ('perdana_menteri', 'Perdana Menteri',  25000,      80,    600,     7),
  ('jutawan',         'Jutawan',          250000,     334,   3000,    8),
  ('bilionair',       'Bilionair',        250000000,  10541, 250000,  9)
on conflict (id) do update set
  name = excluded.name, cost = excluded.cost, min_level = excluded.min_level,
  tap_bonus = excluded.tap_bonus, sort = excluded.sort;

-- 3. every player gets a rank (starts at Rakyat)
alter table player_state
  add column if not exists rank_id text not null default 'rakyat' references ranks (id);

-- 4. drop any leftover ranks from an older ladder (reset affected players first
--    so the foreign key stays valid)
update player_state set rank_id = 'rakyat'
 where rank_id not in ('rakyat','anak_dato','anak_tan_sri','ceo','dato',
                       'tan_sri','menteri','perdana_menteri','jutawan','bilionair');
delete from ranks
 where id not in ('rakyat','anak_dato','anak_tan_sri','ceo','dato',
                  'tan_sri','menteri','perdana_menteri','jutawan','bilionair');

-- 5. ranks are public-read like the other config tables
alter table ranks enable row level security;
drop policy if exists "ranks read" on ranks;
create policy "ranks read" on ranks for select using (true);

-- ============================================================================
-- Now re-run db/04_functions.sql and db/05_leaderboard.sql.
-- ============================================================================
