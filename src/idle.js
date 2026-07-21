// idle.js — claims passive income earned while away. The amount is computed
// entirely from the SERVER clock (see claim_idle in db/04_functions.sql), so a
// tampered client can't inflate it. Call once right after the game loads.
import * as api from "./api.js";
import { setState } from "./store.js";
import { reconcileFromState } from "./engine.js";
import { fmtMoney, toast } from "./ui.js";

export async function claimIdleOnLoad() {
  try {
    const snap = await api.claimIdle();
    setState(snap);
    reconcileFromState(snap);
    const gained = Number(snap.idle_gained || 0);
    if (gained >= 0.01) {
      toast(`Welcome back. Your investments earned +${fmtMoney(gained)} while you were away.`);
    }
  } catch (e) {
    console.error("idle claim failed:", e);
  }
}
