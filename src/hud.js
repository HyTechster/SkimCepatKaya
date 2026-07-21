// hud.js — the top status bar. Subscribes to the store and re-renders the
// authoritative numbers (net worth, level, method, rates). The balance is driven
// separately by engine.js because it animates optimistically every frame.
import { subscribe, store } from "./store.js";
import { $, fmtMoney } from "./ui.js";
import { RANK_ICON, DEFAULT_RANK_ICON } from "./config.js";

export function initHud() {
  render(store);
  subscribe(render);
}

function render({ state, profile, config }) {
  if (!state) return;

  const nameEl = $("#playerName");
  if (nameEl && profile) nameEl.textContent = profile.display_name;

  // topbar shows NET WORTH (total earned); the big center number is your balance
  $("#netWorthVal").textContent = fmtMoney(state.net_worth);
  $("#levelVal").textContent    = state.level;
  $("#perTapVal").textContent   = fmtMoney(state.per_tap);
  $("#idleRateVal").textContent = fmtMoney(state.idle_rate) + " /30s";

  const method = config?.methods?.find((m) => m.id === state.current_method_id);
  $("#methodName").textContent = method ? method.name : state.current_method_id;

  // current prestige rank (emoji + title)
  const rank = config?.ranks?.find((r) => r.id === state.rank_id);
  const rankEmoji = RANK_ICON[state.rank_id] || DEFAULT_RANK_ICON;
  $("#rankVal").textContent = `${rankEmoji} ${rank ? rank.name : state.rank_id || "Rakyat"}`;

  renderLevelBar(state);

  // swap the page background to the current method's scene. Set background-image
  // inline (not via a CSS var) so the url resolves relative to the page, not the
  // stylesheet. The overlay gradient is kept so text stays readable.
  const bgId = state.current_method_id || "piggy_bank";
  document.body.style.backgroundImage =
    `linear-gradient(180deg, rgba(12,9,3,0.30), rgba(12,9,3,0.55)), url("assets/bg-${bgId}.png")`;
}

// Level comes from net worth: level = 1 + floor(sqrt(net_worth) / 3), so the net
// worth to be at level L is (3*(L-1))^2. Show progress through the current level
// and how much net worth is still needed for the next one.
function renderLevelBar(state) {
  const level = Number(state.level) || 1;
  const nw = Number(state.net_worth) || 0;
  const nwCur = Math.pow(3 * (level - 1), 2);   // net worth at the start of this level
  const nwNext = Math.pow(3 * level, 2);        // net worth needed for the next level
  const span = nwNext - nwCur;
  const prog = span > 0 ? Math.min(1, Math.max(0, (nw - nwCur) / span)) : 0;

  $("#levelFill").style.width = (prog * 100).toFixed(1) + "%";
  $("#levelCur").textContent = "Lv " + level;
  $("#levelNext").textContent = "Lv " + (level + 1);
  $("#levelNeed").textContent = fmtMoney(Math.max(0, nwNext - nw)) + " more to Lv " + (level + 1);
}
