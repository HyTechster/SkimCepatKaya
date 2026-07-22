// api.js — the ONLY place that talks to the server-authoritative functions.
// Every mutating call sends an ACTION, never a value. Each returns the full
// server snapshot (jsonb from state_json) which the caller feeds into the store.
import { supabase } from "./supabase.js";

async function rpc(name, args) {
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw error;
  return data;
}

// --- game actions ----------------------------------------------------------
export const getState    = ()   => rpc("get_state");
export const doClick     = (n)  => rpc("do_click",     { p_count: n });
export const buyUpgrade  = (id) => rpc("buy_upgrade",  { p_id: id });
export const buyBooster  = (id) => rpc("buy_booster",  { p_id: id });
export const unlockMethod = (id) => rpc("unlock_method", { p_id: id });
export const setMethod    = (id) => rpc("set_method",    { p_id: id });
export const buyRank      = (id) => rpc("buy_rank",      { p_id: id });
export const claimIdle    = ()   => rpc("claim_idle");
export const claimCash    = ()   => rpc("claim_cash");
export const claimWallet  = ()   => rpc("claim_wallet");
export const submitFeedback = (name, category, message) =>
  rpc("submit_feedback", { p_name: name, p_category: category, p_message: message });

// The signed-in user's public profile (display_name). RLS returns only the
// caller's own row, so we DON'T need — and must not call — supabase.auth.getUser()
// here: calling an auth method from inside the onAuthStateChange callback path
// deadlocks Supabase's auth lock (that was the "sign in needs multiple tries" bug).
export async function getProfile() {
  const { data, error } = await supabase
    .from("profiles")
    .select("display_name")
    .maybeSingle();
  if (error) throw error;
  return data;   // null is fine — the HUD guards against it
}

// --- public reads ----------------------------------------------------------
export const getLeaderboard = (limit = 10) => rpc("get_leaderboard", { p_limit: limit });
// the caller's own standing across all players (for the "you are #N" row)
export const getMyRank = () => rpc("get_my_rank");

// The shop's price lists. These tables are public-read; the server still
// recomputes every price on purchase, so reading them here is display-only.
export async function getConfig() {
  const [methods, upgrades, boosters, ranks] = await Promise.all([
    supabase.from("methods").select("*").order("sort"),
    supabase.from("upgrades").select("*").order("sort"),
    supabase.from("boosters").select("*").order("sort"),
    supabase.from("ranks").select("*").order("sort"),
  ]);
  for (const r of [methods, upgrades, boosters, ranks]) {
    if (r.error) throw r.error;
  }
  return {
    methods: methods.data, upgrades: upgrades.data,
    boosters: boosters.data, ranks: ranks.data,
  };
}
