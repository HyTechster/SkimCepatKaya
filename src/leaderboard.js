// leaderboard.js — top scores by net worth. Reads a SECURITY DEFINER function that
// exposes only display_name / net worth / level, so no emails or ids leak.
import * as api from "./api.js";
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

// Build one leaderboard row. `isMe` highlights it; `pos` (when set) marks it as
// the "you are #N" row that sits below the top 10 and shows its real position.
function makeRow(data, { isMe = false, pos = null } = {}) {
  const li = document.createElement("li");
  if (isMe) li.classList.add("me");
  if (pos != null) { li.classList.add("lb-you"); li.dataset.pos = String(pos); }

  const info = document.createElement("div");
  info.className = "who-wrap";
  const who = document.createElement("span");
  who.className = "who";
  who.textContent = data.display_name;
  const rk = document.createElement("span");
  rk.className = "who-rank";
  rk.textContent = data.rank_name || "Rakyat";
  info.append(who, rk);

  const lvl = document.createElement("span");
  lvl.className = "lvl";
  lvl.textContent = "Lv " + (data.level ?? 1);

  const pts = document.createElement("span");
  pts.className = "pts";
  pts.textContent = fmtMoney(data.net_worth);

  li.append(info, lvl, pts);
  return li;
}

export async function refreshLeaderboard() {
  if (loading) return;            // don't stack requests if one is in flight
  loading = true;
  const btn = $("#lbRefresh");
  if (btn) btn.classList.add("loading");   // spin the icon while fetching
  const host = $("#lbList");
  const empty = $("#lbEmpty");
  try {
    // top slice + my own standing, fetched together so their numbering lines up
    const [rows, mineRows] = await Promise.all([
      api.getLeaderboard(LEADERBOARD_LIMIT),
      api.getMyRank(),
    ]);
    const mine = (mineRows && mineRows[0]) || null;

    host.innerHTML = "";
    empty.style.display = rows.length ? "none" : "block";
    for (const row of rows) host.appendChild(makeRow(row, { isMe: !!row.is_me }));

    // If I'm not in the visible top slice, add a divider + my own row so I can
    // always see where I stand (e.g. "26"), using the same highlighted box.
    const inTop = rows.some((r) => r.is_me);
    if (mine && !inTop) {
      const gap = document.createElement("li");
      gap.className = "lb-gap";
      gap.textContent = "⋯";   // horizontal ellipsis
      gap.setAttribute("aria-hidden", "true");
      host.appendChild(gap);
      host.appendChild(makeRow(mine, { isMe: true, pos: mine.rank_pos }));
    }
  } catch (e) {
    console.error("leaderboard failed:", e);
  } finally {
    loading = false;
    if (btn) btn.classList.remove("loading");
  }
}
