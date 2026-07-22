-- ============================================================================
-- 04_functions.sql — the server-authoritative game logic
-- ----------------------------------------------------------------------------
-- Every function here is SECURITY DEFINER: it runs as the table owner, so it
-- can write the player tables that RLS otherwise locks. Each one starts by
-- checking auth.uid() and only ever touches the caller's own row. `set
-- search_path = public` prevents search-path hijacking.
--
-- The client calls these via supabase.rpc(...). It sends ACTIONS, never values:
--   do_click(n)          -- "I tapped n times" (server caps n by real elapsed time)
--   buy_upgrade(id)      -- server looks up the price and checks you can afford it
--   buy_booster(id)
--   unlock_method(id)
--   set_method(id)
--   claim_idle()         -- pays passive income using the SERVER clock only
--   get_state()          -- read your full state (derived fields included)
-- All of them return the same jsonb snapshot so the client can just reconcile.
-- ============================================================================

-- ---- tunable server constants (change here, they are not client-visible) ---
--   MAX_CPS            = 20      clicks/sec ceiling (autoclicker cap)
--   BASE_TAP           = 0.01    dollars earned per click at tap level 0
--   HUSTLE_STEP        = 0.003   scaling: the Nth Side Hustle level adds $0.003 x N
--                                (total 0.003*L*(L+1)/2; gentle early, ~$15 at level 100)
--   LEVEL_DIVISOR      = 3       level = 1 + floor(sqrt(net_worth)/3)
--   IDLE_CAP_SECONDS   = 28800   never pay more than 8h of idle at once
--   CLICK_BURST_CAP    = 200     max clicks credited in a single do_click call
-- net_worth = net worth (total earned, score); balance = balance (spendable).
-- These live inline below (Postgres has no cheap global consts).

-- ---------------------------------------------------------------------------
-- settle_boosters(uid): bring booster state up to "now".
--   * a booster is ACTIVE if expires_at is set; PAUSED if paused_seconds is set.
--   * at most ONE booster is active (the highest multiplier); the rest are paused
--     with their remaining time FROZEN, so a lower booster loses no time while a
--     higher one runs.
-- This function: drops fully-spent active boosters, keeps only the highest active
-- (pausing any others), and if nothing is active, promotes the highest-multiplier
-- paused booster so it starts ticking from now.
-- ---------------------------------------------------------------------------
create or replace function settle_boosters(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_top text;
  v_id  text;
begin
  -- 1. remove active boosters whose time is fully used up
  delete from player_boosters
   where user_id = p_uid and expires_at is not null and expires_at <= v_now;

  -- 2. if more than one is somehow active, keep the highest-multiplier one active
  --    and pause the rest (freeze their remaining time)
  select pb.booster_id into v_top
    from player_boosters pb join boosters b on b.id = pb.booster_id
   where pb.user_id = p_uid and pb.expires_at is not null and pb.expires_at > v_now
   order by b.multiplier desc, pb.expires_at desc
   limit 1;

  if v_top is not null then
    update player_boosters
       set paused_seconds = extract(epoch from (expires_at - v_now)), expires_at = null
     where user_id = p_uid and expires_at is not null and expires_at > v_now
       and booster_id <> v_top;
  else
    -- 3. nothing active: promote the highest-multiplier paused booster with time left
    select pb.booster_id into v_id
      from player_boosters pb join boosters b on b.id = pb.booster_id
     where pb.user_id = p_uid and pb.expires_at is null and coalesce(pb.paused_seconds, 0) > 0
     order by b.multiplier desc
     limit 1;
    if v_id is not null then
      update player_boosters
         set expires_at = v_now + make_interval(secs => paused_seconds), paused_seconds = null
       where user_id = p_uid and booster_id = v_id;
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- state_json(uid): assemble the full snapshot the client renders from.
-- ---------------------------------------------------------------------------
create or replace function state_json(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v          player_state;
  v_method   methods;
  v_boost    numeric;
  v_rankbonus numeric;
  v_now      timestamptz := now();
begin
  select * into v from player_state where user_id = p_uid;
  if not found then
    return null;
  end if;

  select * into v_method from methods where id = v.current_method_id;

  perform settle_boosters(p_uid);   -- promote/pause boosters to the current moment

  -- the ONE active booster's multiplier (or 1 if none active)
  select coalesce(max(b.multiplier), 1) into v_boost
    from player_boosters pb
    join boosters b on b.id = pb.booster_id
   where pb.user_id = p_uid and pb.expires_at is not null and pb.expires_at > v_now;

  -- prestige: your rank adds a FLAT amount to every tap
  select coalesce(tap_bonus, 0) into v_rankbonus from ranks where id = v.rank_id;

  return jsonb_build_object(
    'net_worth',            v.net_worth,
    'balance',          v.balance,
    'level',             v.level,
    'tap_level',         v.tap_level,
    'drone_level',       v.drone_level,
    'rank_id',           v.rank_id,
    'current_method_id',  v.current_method_id,
    'method_multiplier',  coalesce(v_method.multiplier, 1),
    'booster_multiplier', v_boost,
    -- money per tap: rank bonus + hustle are summed FIRST, then the whole base is
    -- scaled by method x booster. Hustle SCALES gently: the Nth level adds $0.003 x N,
    -- so total = 0.003 * L*(L+1)/2 (e.g. L15 ~ $0.36, L50 ~ $3.83, L100 ~ $15.15).
    'per_tap',           (coalesce(v_rankbonus, 0) + 0.01 + 0.003 * v.tap_level * (v.tap_level + 1) / 2) * coalesce(v_method.multiplier, 1) * v_boost,
    -- passive income per 30s: $0.01 per drone level, times the method multiplier
    'idle_rate',         v.drone_level * 0.01 * coalesce(v_method.multiplier, 1),
    'server_now',        v_now,
    'last_idle_at',      v.last_idle_at,
    'owned_methods',      (select coalesce(jsonb_agg(method_id), '[]'::jsonb)
                            from owned_methods where user_id = p_uid),
    'boosters',          (select coalesce(
                              jsonb_agg(jsonb_build_object(
                                'id', booster_id,
                                'active', (expires_at is not null),
                                'expires_at', expires_at,
                                'remaining', case when expires_at is not null
                                                  then extract(epoch from (expires_at - v_now))
                                                  else coalesce(paused_seconds, 0) end)), '[]'::jsonb)
                            from player_boosters where user_id = p_uid)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- apply_earn(uid, amount): the player earned `amount` dollars. Money you earn
-- goes to BOTH totals 1:1:
--   net_worth   = NET WORTH (total ever earned) -> the leaderboard score, never drops
--   balance = BALANCE   (spendable cash)    -> what the shop deducts from
-- Level is derived from net worth. Shared by do_click, claim_idle, claim_cash.
--   LEVEL_DIVISOR = 3   (level = 1 + floor(sqrt(net_worth) / 3))
-- ---------------------------------------------------------------------------
create or replace function apply_earn(p_uid uuid, p_add numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_add <= 0 then
    return;
  end if;
  update player_state
     set net_worth   = net_worth + p_add,
         balance = balance + p_add,
         level    = 1 + floor(sqrt(net_worth + p_add) / 3)::int,
         updated_at = now()
   where user_id = p_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- get_state(): read-only snapshot for the caller.
-- ---------------------------------------------------------------------------
create or replace function get_state()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  return state_json(v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- do_click(n): the anti-cheat heart. n is what the client CLAIMS it clicked;
-- the server credits at most (seconds since last click * 20). So no matter what
-- number the client sends, throughput is capped to ~20 clicks/sec of real,
-- server-measured time. This neutralizes both the "claim a big number" cheat
-- and fast autoclickers in one stroke.
-- ---------------------------------------------------------------------------
create or replace function do_click(p_count int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v         player_state;
  v_method   methods;
  v_boost   numeric;
  v_rankbonus numeric;
  v_now     timestamptz := now();
  v_elapsed numeric;
  v_allowed int;
  v_granted int;
  v_pertap  numeric;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  if p_count is null or p_count <= 0 then
    return state_json(v_uid);   -- nothing to do
  end if;
  if p_count > 200 then p_count := 200; end if;  -- CLICK_BURST_CAP

  select * into v from player_state where user_id = v_uid for update;
  if not found then raise exception 'no player state'; end if;

  -- how many clicks has enough real time passed to justify?
  v_elapsed := extract(epoch from (v_now - v.last_click_at));
  if v_elapsed < 0 then v_elapsed := 0; end if;
  v_allowed := floor(v_elapsed * 20)::int;        -- MAX_CPS = 20
  if v_allowed > 200 then v_allowed := 200; end if;

  v_granted := least(p_count, v_allowed);
  if v_granted <= 0 then
    return state_json(v_uid);   -- clicking faster than a human; credit nothing
  end if;

  select * into v_method from methods where id = v.current_method_id;
  perform settle_boosters(v_uid);
  select coalesce(max(b.multiplier), 1) into v_boost
    from player_boosters pb
    join boosters b on b.id = pb.booster_id
   where pb.user_id = v_uid and pb.expires_at is not null and pb.expires_at > v_now;

  select coalesce(tap_bonus, 0) into v_rankbonus from ranks where id = v.rank_id;

  -- rank bonus + hustle summed first, then scaled by method x booster.
  -- Hustle scales gently: Nth level adds $0.003 x N, total = 0.003 * L*(L+1)/2.
  v_pertap := (coalesce(v_rankbonus, 0) + 0.01 + 0.003 * v.tap_level * (v.tap_level + 1) / 2) * coalesce(v_method.multiplier, 1) * v_boost;

  update player_state set last_click_at = v_now where user_id = v_uid;
  perform apply_earn(v_uid, v_granted * v_pertap);

  return state_json(v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- buy_upgrade(id): atomic. Locks the row, recomputes cost from the config
-- table + current level, checks funds, deducts, bumps the right level column.
-- Because it all happens in one transaction under a row lock, firing 20 buys at
-- once can't double-spend.
-- ---------------------------------------------------------------------------
create or replace function buy_upgrade(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v       player_state;
  v_up    upgrades;
  v_level int;
  v_cost  numeric;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_up from upgrades where id = p_id;
  if not found then raise exception 'unknown upgrade %', p_id; end if;

  select * into v from player_state where user_id = v_uid for update;

  v_level := case v_up.kind when 'tap' then v.tap_level else v.drone_level end;
  if v_level >= v_up.max_level then
    raise exception 'upgrade % is maxed', p_id;
  end if;

  v_cost := v_up.base_cost * power(v_up.growth, v_level);
  if v.balance < v_cost then
    raise exception 'not enough balance';
  end if;

  if v_up.kind = 'tap' then
    update player_state
       set balance = balance - v_cost, tap_level = tap_level + 1, updated_at = now()
     where user_id = v_uid;
  else
    update player_state
       set balance = balance - v_cost, drone_level = drone_level + 1, updated_at = now()
     where user_id = v_uid;
  end if;

  return state_json(v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- buy_booster(id): buy time on a booster. The highest-multiplier booster is the
-- one that runs; a lower one is PAUSED (its time frozen) until the higher one
-- ends, then it resumes automatically. Buying the same booster adds to its time.
--   * buy a HIGHER booster than the one running -> it takes over now, the running
--     one is paused.
--   * buy a LOWER/equal booster -> it waits (paused) while the current one runs.
-- ---------------------------------------------------------------------------
create or replace function buy_booster(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v           player_state;
  v_b         boosters;
  v_now       timestamptz := now();
  v_remaining numeric := 0;
  v_total     numeric;
  v_cost      numeric;
  v_active_id text;
  v_active_mult numeric;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_b from boosters where id = p_id;
  if not found then raise exception 'unknown booster %', p_id; end if;

  select * into v from player_state where user_id = v_uid for update;

  -- dynamic price: the floor, or a slice of net worth once you're wealthy enough.
  -- Recomputed here on the server, so a tampered client can't buy it cheaper.
  v_cost := greatest(v_b.cost, v.net_worth * coalesce(v_b.cost_rate, 0));
  if v.balance < v_cost then raise exception 'not enough balance'; end if;

  perform settle_boosters(v_uid);

  -- how much time this booster already has banked (active remaining or paused)
  select coalesce(case when expires_at is not null
                       then extract(epoch from (expires_at - v_now))
                       else coalesce(paused_seconds, 0) end, 0)
    into v_remaining
    from player_boosters where user_id = v_uid and booster_id = p_id;
  v_total := coalesce(v_remaining, 0) + v_b.duration_seconds;

  update player_state set balance = balance - v_cost, updated_at = v_now
   where user_id = v_uid;

  -- rebuild this booster's row from scratch
  delete from player_boosters where user_id = v_uid and booster_id = p_id;

  -- what is running right now (after removing this booster's old row)?
  select pb.booster_id, b.multiplier into v_active_id, v_active_mult
    from player_boosters pb join boosters b on b.id = pb.booster_id
   where pb.user_id = v_uid and pb.expires_at is not null and pb.expires_at > v_now
   limit 1;

  if v_active_id is null then
    -- nothing running: this booster runs now
    insert into player_boosters (user_id, booster_id, expires_at)
      values (v_uid, p_id, v_now + make_interval(secs => v_total));
  elsif v_b.multiplier > v_active_mult then
    -- higher multiplier: take over, pause the currently-running one
    update player_boosters
       set paused_seconds = extract(epoch from (expires_at - v_now)), expires_at = null
     where user_id = v_uid and booster_id = v_active_id;
    insert into player_boosters (user_id, booster_id, expires_at)
      values (v_uid, p_id, v_now + make_interval(secs => v_total));
  else
    -- lower/equal multiplier: wait paused while the current one runs
    insert into player_boosters (user_id, booster_id, paused_seconds)
      values (v_uid, p_id, v_total);
  end if;

  return state_json(v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- buy_rank(id): buy a prestige title. Requires level >= the rank's min_level,
-- the rank must be higher than your current one, and you pay its cost. Atomic.
-- ---------------------------------------------------------------------------
create or replace function buy_rank(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v          player_state;
  v_r        ranks;
  v_cur_sort int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_r from ranks where id = p_id;
  if not found then raise exception 'unknown rank %', p_id; end if;

  select * into v from player_state where user_id = v_uid for update;

  select sort into v_cur_sort from ranks where id = v.rank_id;
  v_cur_sort := coalesce(v_cur_sort, -1);
  if v_r.sort <= v_cur_sort then
    raise exception 'rank not higher than current';
  elsif v_r.sort > v_cur_sort + 1 then
    raise exception 'unlock the previous rank first';   -- ranks must be bought in order
  end if;
  if v.level < v_r.min_level then
    raise exception 'level too low';
  end if;
  if v.balance < v_r.cost then
    raise exception 'not enough balance';
  end if;

  update player_state
     set balance = balance - v_r.cost, rank_id = p_id, updated_at = now()
   where user_id = v_uid;

  return state_json(v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- unlock_method(id): buy a new location (once), atomically.
-- ---------------------------------------------------------------------------
create or replace function unlock_method(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v     player_state;
  v_pl  methods;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_pl from methods where id = p_id;
  if not found then raise exception 'unknown method %', p_id; end if;

  select * into v from player_state where user_id = v_uid for update;

  if exists (select 1 from owned_methods where user_id = v_uid and method_id = p_id) then
    raise exception 'already unlocked';
  end if;
  -- methods unlock in ladder order: you must own the one directly below (sort-1)
  -- before you can buy this one. piggy_bank (sort 0) is granted at signup.
  if v_pl.sort > 0 and not exists (
       select 1 from owned_methods om join methods m on m.id = om.method_id
        where om.user_id = v_uid and m.sort = v_pl.sort - 1
     ) then
    raise exception 'unlock the previous method first';
  end if;
  if v.balance < v_pl.cost then raise exception 'not enough balance'; end if;

  update player_state set balance = balance - v_pl.cost, updated_at = now()
   where user_id = v_uid;
  insert into owned_methods (user_id, method_id) values (v_uid, p_id);

  return state_json(v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- set_method(id): switch active location — must already own it.
-- ---------------------------------------------------------------------------
create or replace function set_method(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from owned_methods where user_id = v_uid and method_id = p_id) then
    raise exception 'method not unlocked';
  end if;
  update player_state set current_method_id = p_id, updated_at = now()
   where user_id = v_uid;
  return state_json(v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- claim_idle(): pay passive income earned since last_idle_at. Time comes ONLY
-- from the server clock (now() - last_idle_at), capped at 8h, so a client that
-- lies about how long it was away gets nothing extra. Returns the snapshot plus
-- 'idle_gained' so the UI can show "you earned X while away".
-- ---------------------------------------------------------------------------
create or replace function claim_idle()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v         player_state;
  v_method   methods;
  v_now     timestamptz := now();
  v_elapsed numeric;
  v_rate    numeric;
  v_gained  numeric;
  v_json    jsonb;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v from player_state where user_id = v_uid for update;
  if not found then raise exception 'no player state'; end if;

  v_elapsed := extract(epoch from (v_now - v.last_idle_at));
  if v_elapsed < 0 then v_elapsed := 0; end if;
  if v_elapsed > 28800 then v_elapsed := 28800; end if;   -- IDLE_CAP_SECONDS = 8h

  select * into v_method from methods where id = v.current_method_id;
  -- drone effect is per 30 seconds, so divide the per-30s amount by 30 to get $/sec
  v_rate   := v.drone_level * 0.01 * coalesce(v_method.multiplier, 1) / 30.0;   -- $/sec
  v_gained := v_elapsed * v_rate;

  update player_state set last_idle_at = v_now where user_id = v_uid;
  perform apply_earn(v_uid, v_gained);

  v_json := state_json(v_uid);
  return v_json || jsonb_build_object('idle_gained', v_gained);
end;
$$;

-- ---------------------------------------------------------------------------
-- claim_cash(): reward for clicking a floating cash drop. The client decides
-- when a drop appears/gets clicked, but the SERVER decides whether to pay:
-- allowed at most once per cooldown (server clock). So a script hammering this
-- only gets one reward per cooldown, same as an honest player. The reward is a
-- fixed number of TAPS' worth of income, so it scales with your hustle level,
-- method, and rank and stays proportionate at every stage (no flat base that is
-- huge early). Booster is excluded so drops can't be farmed during a boost.
-- Returns the snapshot plus 'cash_gained' (0 if still on cooldown).
--   reward = base_per_tap * CASH_TAPS
--   CASH_TAPS     = 15   a coin is worth ~15 taps of income
--   CASH_COOLDOWN = 10   seconds between rewards
-- ---------------------------------------------------------------------------
create or replace function claim_cash()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v        player_state;
  v_method methods;
  v_rankbonus numeric;
  v_pertap numeric;
  v_now    timestamptz := now();
  v_reward numeric;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v from player_state where user_id = v_uid for update;
  if not found then raise exception 'no player state'; end if;

  -- still cooling down? pay nothing, report 0.
  if extract(epoch from (v_now - v.last_cash_at)) < 10 then   -- CASH_COOLDOWN
    return state_json(v_uid) || jsonb_build_object('cash_gained', 0);
  end if;

  -- base per-tap (no booster) = same earning as a normal tap, so the drop scales
  -- with hustle level / method / rank.
  select * into v_method from methods where id = v.current_method_id;
  select coalesce(tap_bonus, 0) into v_rankbonus from ranks where id = v.rank_id;
  v_pertap := (coalesce(v_rankbonus, 0) + 0.01 + 0.003 * v.tap_level * (v.tap_level + 1) / 2)
              * coalesce(v_method.multiplier, 1);
  v_reward := v_pertap * 15;   -- CASH_TAPS = 15

  update player_state set last_cash_at = v_now where user_id = v_uid;
  perform apply_earn(v_uid, v_reward);    -- adds to both net worth and balance

  return state_json(v_uid) || jsonb_build_object('cash_gained', v_reward);
end;
$$;

-- ---------------------------------------------------------------------------
-- claim_wallet(): the RARE, bigger drop. Same server-authoritative design as
-- claim_cash but worth many more taps and a longer cooldown, so it can't be farmed.
--   reward = base_per_tap * WALLET_TAPS
--   WALLET_TAPS     = 100   a wallet is worth ~100 taps (about 7x a coin)
--   WALLET_COOLDOWN = 120   seconds between wallet rewards (rarer than coins)
-- ---------------------------------------------------------------------------
create or replace function claim_wallet()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v        player_state;
  v_method methods;
  v_rankbonus numeric;
  v_pertap numeric;
  v_now    timestamptz := now();
  v_reward numeric;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v from player_state where user_id = v_uid for update;
  if not found then raise exception 'no player state'; end if;

  if extract(epoch from (v_now - v.last_wallet_at)) < 120 then   -- WALLET_COOLDOWN
    return state_json(v_uid) || jsonb_build_object('wallet_gained', 0);
  end if;

  -- base per-tap (no booster), same scaling as claim_cash but worth more taps
  select * into v_method from methods where id = v.current_method_id;
  select coalesce(tap_bonus, 0) into v_rankbonus from ranks where id = v.rank_id;
  v_pertap := (coalesce(v_rankbonus, 0) + 0.01 + 0.003 * v.tap_level * (v.tap_level + 1) / 2)
              * coalesce(v_method.multiplier, 1);
  v_reward := v_pertap * 100;   -- WALLET_TAPS = 100

  update player_state set last_wallet_at = v_now where user_id = v_uid;
  perform apply_earn(v_uid, v_reward);

  return state_json(v_uid) || jsonb_build_object('wallet_gained', v_reward);
end;
$$;

-- ---------------------------------------------------------------------------
-- New-user bootstrap: when someone signs up, create their profile + player row
-- and grant the starting location. Runs as definer so RLS never blocks it.
-- ---------------------------------------------------------------------------
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id, display_name)
    values (
      new.id,
      left(coalesce(nullif(new.raw_user_meta_data->>'display_name', ''),
                    split_part(new.email, '@', 1)), 24)
    );
  -- start the drop cooldown clocks in the past so the FIRST cash/wallet drop is
  -- claimable right away (otherwise the initial 10s/60s cooldown blocks it).
  insert into public.player_state (user_id, last_cash_at, last_wallet_at)
    values (new.id, now() - interval '1 day', now() - interval '1 day');
  insert into public.owned_methods (user_id, method_id) values (new.id, 'piggy_bank');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---- allow logged-in users to call the game functions ---------------------
grant execute on function get_state()            to authenticated;
grant execute on function do_click(int)          to authenticated;
grant execute on function buy_upgrade(text)      to authenticated;
grant execute on function buy_booster(text)      to authenticated;
grant execute on function unlock_method(text)     to authenticated;
grant execute on function buy_rank(text)          to authenticated;
grant execute on function set_method(text)        to authenticated;
grant execute on function claim_idle()           to authenticated;
grant execute on function claim_cash()          to authenticated;
grant execute on function claim_wallet()         to authenticated;
-- state_json / apply_net_worth / handle_new_user are internal — not granted.
