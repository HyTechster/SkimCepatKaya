// store.js — a tiny reactive store. Holds the last server snapshot + config,
// and lets UI modules subscribe so they re-render whenever state changes.
const listeners = new Set();

export const store = {
  state: null,    // latest server snapshot (from state_json)
  config: null,   // { methods, upgrades, boosters }
  profile: null,  // { display_name }
};

export function subscribe(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

function emit() {
  for (const fn of listeners) fn(store);
}

export function setState(snapshot) {
  if (!snapshot) return;
  store.state = snapshot;
  emit();
}

export function setConfig(cfg) { store.config = cfg; }
export function setProfile(p)  { store.profile = p; }

// Re-notify subscribers without changing state (used by 1s tickers for booster
// countdowns, etc.).
export function refresh() { emit(); }

// --- shared cost/level helpers (mirror the server formula for DISPLAY only) --
export function upgradeLevel(up, state) {
  return up.kind === "tap" ? state.tap_level : state.drone_level;
}
export function upgradeCost(up, state) {
  return Number(up.base_cost) * Math.pow(Number(up.growth), upgradeLevel(up, state));
}
export function isMaxed(up, state) {
  return upgradeLevel(up, state) >= up.max_level;
}
