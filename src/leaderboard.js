// leaderboard.js — top scores by net worth. Reads a SECURITY DEFINER function that
// exposes only display_name / net worth / level, so no emails or ids leak.
import * as api from "./api.js";
import { store } from "./store.js";
import { $, fmtMoney } from "./ui.js";
import { LEADERBOARD_LIMIT, LEADERBOARD_REFRESH_MS } from "./config.js";

let loading = false;

export function initLeaderboard() {
  $("#lbRefresh").addEventListener("click", refreshLeaderboard);
  refreshLeaderboard();

  // Auto-refresh on an interval, but skip the request while the tab is hidden
  // (no point updating a leaderboard nobody's looking at).
  setInterval(() => {
    if (!document.hidden) refreshLeaderboard();
  }, LEADERBOARD_REFRESH_MS);

  // And refresh right away when the player comes back to the tab.
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) refreshLeaderboard();
  });
}

export async function refreshLeaderboard() {
  if (loading) return;            // don't stack requests if one is in flight
  loading = true;
  const btn = $("#lbRefresh");
  if (btn) btn.classList.add("loading");   // spin the icon while fetching
  const host = $("#lbList");
  const empty = $("#lbEmpty");
  try {
    const rows = await api.getLeaderboard(LEADERBOARD_LIMIT);
    host.innerHTML = "";
    empty.style.display = rows.length ? "none" : "block";
    const me = store.profile?.display_name;
    for (const row of rows) {
      const li = document.createElement("li");
      if (row.display_name === me) li.classList.add("me");

      const info = document.createElement("div");
      info.className = "who-wrap";
      const who = document.createElement("span");
      who.className = "who";
      who.textContent = row.display_name;
      const rk = document.createElement("span");
      rk.className = "who-rank";
      rk.textContent = row.rank_name || "Rakyat";
      info.append(who, rk);

      const pts = document.createElement("span");
      pts.className = "pts";
      pts.textContent = fmtMoney(row.net_worth);

      li.append(info, pts);
      host.appendChild(li);
    }
  } catch (e) {
    console.error("leaderboard failed:", e);
  } finally {
    loading = false;
    if (btn) btn.classList.remove("loading");
  }
}
