-- ============================================================================
-- 99_migrate_to_money.sql — one-time migration from the cosmic theme to Tabung
-- ----------------------------------------------------------------------------
-- WHY A RESET: the currency changed meaning (energy is now NET WORTH in dollars,
-- stardust is now BALANCE) and the place ids changed (earth_orbit -> piggy_bank,
-- etc.). Old saves don't translate, so this wipes player PROGRESS (not accounts)
-- and reseeds the new economy. Accounts / logins in auth.users are kept.
--
-- RUN THIS ONCE, then run db/04_functions.sql to load the new game logic.
-- ============================================================================

-- 1) clear player progress (these reference the old place ids)
delete from player_boosters;
delete from owned_methods;
delete from player_state;

-- 2) reseed the config with the money economy (same content as 02_config_data)
delete from boosters;
delete from upgrades;
delete from methods;

insert into methods (id, name, cost, multiplier, sort) values
  ('piggy_bank', 'Piggy Bank',       0,      1.0,  0),
  ('wallet',     'Wallet',           5,      1.5,  1),
  ('qr',         'QR DuitSekarang',  50,     2.5,  2),
  ('card',       'Debit Card',       250,    4.0,  3),
  ('bank',       'Bank Account',     1500,   6.0,  4),
  ('vault',      'Vault',            12000,  12.0, 5);

insert into upgrades (id, kind, name, base_cost, growth, effect, max_level, sort) values
  ('hustle', 'tap',   'Side Hustle',     0.50, 1.15, 0.01, 100, 0),
  ('invest', 'drone', 'Auto Investment', 2.00, 1.18, 0.01, 100, 1);

insert into boosters (id, name, cost, multiplier, duration_seconds, sort) values
  ('payday',   'Payday',            3,  2.0, 30, 0),
  ('compound', 'Compound Interest', 15, 3.0, 60, 1);

-- 3) new players start at the piggy bank
alter table player_state alter column current_method_id set default 'piggy_bank';

-- add the cash cooldown column if this DB predates it
alter table player_state
  add column if not exists last_cash_at timestamptz not null default now();

-- 4) re-bootstrap every existing account with a fresh money-theme save
insert into player_state (user_id)
  select id from auth.users
on conflict (user_id) do nothing;

insert into owned_methods (user_id, method_id)
  select id, 'piggy_bank' from auth.users
on conflict do nothing;

-- ============================================================================
-- Now run db/04_functions.sql to install apply_earn() and the updated
-- do_click / claim_idle / claim_cash / state_json logic.
-- ============================================================================
