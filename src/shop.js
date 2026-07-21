// shop.js — a single tabbed shop (Upgrades / Boosters / Methods). Cards are
// compact rows: icon · name+meta · buy button. Everything renders from the
// store; after a purchase the returned snapshot flows back and re-renders.
import { store, subscribe, setState, upgradeCost, upgradeLevel, isMaxed } from "./store.js";
import { reconcileFromState } from "./engine.js";
import * as api from "./api.js";
import { $, fmtDec, fmtMoney, toast, errText } from "./ui.js";
import { RANK_ICON, DEFAULT_RANK_ICON } from "./config.js";

export function initShop() {
  initTabs();
  render(store);
  subscribe(render);
  // Booster timers count down live; nudge a re-render every second.
  setInterval(() => { if (store.state) render(store); }, 1000);
}

function initTabs() {
  const tabs = $("#shopTabs");
  tabs.addEventListener("click", (e) => {
    const btn = e.target.closest(".shop-tab");
    if (!btn) return;
    const which = btn.dataset.tab;
    for (const b of tabs.querySelectorAll(".shop-tab")) b.classList.toggle("on", b === btn);
    $("#upgradeList").classList.toggle("hidden", which !== "upgrades");
    $("#boosterList").classList.toggle("hidden", which !== "boosters");
    $("#methodList").classList.toggle("hidden", which !== "methods");
    $("#rankList").classList.toggle("hidden", which !== "ranks");
  });
}

function render({ state, config }) {
  if (!state || !config) return;
  $("#shopBalance").textContent = fmtMoney(state.balance);
  renderUpgrades(state, config.upgrades);
  renderBoosters(state, config.boosters);
  renderMethods(state, config.methods);
  renderRanks(state, config.ranks || []);

  // little dot on the Boosters tab while any booster is running
  const anyActive = (state.boosters || []).some((x) => x.active);
  $('#shopTabs [data-tab="boosters"]').classList.toggle("has-active", anyActive);
}

// generic buy handler: run the action, push the snapshot everywhere, toast errors
async function buy(fn, id, btn) {
  if (btn) btn.disabled = true;
  try {
    const snap = await fn(id);
    setState(snap);
    reconcileFromState(snap);
  } catch (e) {
    toast(errText(e));
  } finally {
    if (btn) btn.disabled = false;
  }
}

// Build one compact card row. Returns { el, btn } so callers can wire the click.
function row({ icon, iconEmoji, iconClass = "", name, chip, sub, btnLabel, affordable, disabled }) {
  const el = document.createElement("div");
  el.className = "card";
  const iconHtml = iconEmoji
    ? `<span class="card-icon emoji">${iconEmoji}</span>`
    : `<img class="card-icon ${iconClass}" src="${icon}" alt="" onerror="this.style.visibility='hidden'" />`;
  // Name gets its own full-width line (wraps if long, never truncates); the chip
  // sits on the meta line with the sub text.
  el.innerHTML = `
    ${iconHtml}
    <div class="card-body">
      <div class="card-name">${name}</div>
      <div class="card-sub">${chip ? `<span class="chip">${chip}</span>` : ""}<span>${sub}</span></div>
    </div>
    <button class="buy ${affordable && !disabled ? "" : "off"}">${btnLabel}</button>`;
  const btn = el.querySelector("button");
  btn.disabled = !!disabled;
  return { el, btn };
}

function renderRanks(state, ranks) {
  const host = $("#rankList");
  host.innerHTML = "";
  const current = ranks.find((r) => r.id === state.rank_id);
  const curSort = current ? current.sort : -1;

  for (const r of ranks) {
    const emoji = RANK_ICON[r.id] || DEFAULT_RANK_ICON;
    const isCurrent = r.id === state.rank_id;
    const isOwned = r.sort < curSort;                 // already surpassed
    const isNext = r.sort === curSort + 1;            // only the very next is buyable
    const levelOk = Number(state.level) >= r.min_level;
    const afford = Number(state.balance) >= Number(r.cost);
    const bonus = Number(r.tap_bonus) || 0;

    let btnLabel, action = null, disabled = true;
    let sub = bonus > 0 ? `+${fmtMoney(bonus)} / tap` : "starting rank";

    if (isCurrent) {
      btnLabel = "CURRENT";
    } else if (isOwned) {
      btnLabel = "PASSED";
    } else if (isNext) {
      if (!levelOk) {
        btnLabel = `🔒 Lv ${r.min_level}`;
      } else if (!afford) {
        btnLabel = fmtMoney(r.cost);
      } else {
        btnLabel = fmtMoney(r.cost); disabled = false; action = () => buy(api.buyRank, r.id);
      }
    } else {
      // further up the ladder — must claim the earlier ranks first
      btnLabel = "🔒";
      sub = "unlock the previous rank first";
    }

    const { el, btn } = row({
      iconEmoji: emoji,
      name: r.name,
      chip: `Lv ${r.min_level}`,
      sub,
      btnLabel,
      affordable: !disabled,
      disabled,
    });
    if (isCurrent) el.classList.add("active");
    if (action) btn.addEventListener("click", action);
    host.appendChild(el);
  }
}

function renderUpgrades(state, upgrades) {
  const host = $("#upgradeList");
  host.innerHTML = "";
  for (const up of upgrades) {
    const level = upgradeLevel(up, state);
    const maxed = isMaxed(up, state);
    const cost = upgradeCost(up, state);
    const afford = Number(state.balance) >= cost;
    const { el, btn } = row({
      icon: `assets/icon-${up.id}.png`,
      name: up.name,
      chip: maxed ? `Lv ${level} · MAX` : `Lv ${level}`,
      sub: `+${fmtMoney(up.effect)} ${up.kind === "tap" ? "/ tap" : "/ 30s"}`,
      btnLabel: maxed ? "MAX" : fmtMoney(cost),
      affordable: afford,
      disabled: maxed || !afford,
    });
    if (!maxed) btn.addEventListener("click", () => buy(api.buyUpgrade, up.id, btn));
    host.appendChild(el);
  }
}

function renderBoosters(state, boosters) {
  const host = $("#boosterList");
  host.innerHTML = "";
  const now = Date.now();
  const map = new Map((state.boosters || []).map((x) => [x.id, x]));

  // the multiplier of the booster currently running (for the takeover alert)
  let activeMult = null;
  for (const b of boosters) {
    const e = map.get(b.id);
    if (e && e.active) activeMult = Number(b.multiplier);
  }

  for (const b of boosters) {
    const cost = Number(b.cost);
    const afford = Number(state.balance) >= cost;
    const e = map.get(b.id);
    const isActive = e && e.active;
    const isPaused = e && !e.active && Number(e.remaining) > 0;

    let sub;
    if (isActive) {
      const remain = Math.max(0, Math.ceil((new Date(e.expires_at).getTime() - now) / 1000));
      sub = `running, ${remain}s left`;
    } else if (isPaused) {
      sub = `paused, ${Math.ceil(Number(e.remaining))}s held`;
    } else {
      sub = `${b.duration_seconds}s tap boost`;
    }

    const { el, btn } = row({
      icon: `assets/icon-${b.id}.png`,
      name: b.name,
      chip: `×${fmtDec(b.multiplier)}`,
      sub,
      btnLabel: fmtMoney(cost),
      affordable: afford,
      disabled: !afford,
    });
    if (isActive) el.classList.add("active");
    if (isPaused) el.classList.add("paused");
    btn.addEventListener("click", async () => {
      // buying a higher booster pauses the lower running one — tell the player
      if (activeMult != null && Number(b.multiplier) > activeMult) {
        toast(`×${fmtDec(b.multiplier)} runs now — your ×${fmtDec(activeMult)} is paused and resumes when it ends.`);
      }
      await buy(api.buyBooster, b.id, btn);
    });
    host.appendChild(el);
  }
}

function renderMethods(state, methods) {
  const host = $("#methodList");
  host.innerHTML = "";
  const owned = new Set(state.owned_methods || []);
  for (const m of methods) {
    const isOwned = owned.has(m.id);
    const isCurrent = state.current_method_id === m.id;
    const cost = Number(m.cost);
    const afford = Number(state.balance) >= cost;

    let btnLabel, action, disabled = false;
    if (isCurrent) {
      btnLabel = "IN USE"; disabled = true;
    } else if (isOwned) {
      btnLabel = "Switch"; action = () => buy(api.setMethod, m.id);
    } else {
      btnLabel = fmtMoney(cost); action = () => buy(api.unlockMethod, m.id); disabled = !afford;
    }
    const { el, btn } = row({
      icon: `assets/method-${m.id}.png`,
      iconClass: `method method-${m.id}`,
      name: m.name,
      chip: `×${fmtDec(m.multiplier)}`,
      sub: isCurrent ? "in use" : isOwned ? "unlocked" : "locked",
      btnLabel,
      affordable: afford || isOwned,
      disabled,
    });
    if (isCurrent) el.classList.add("active");
    if (action) btn.addEventListener("click", action);
    host.appendChild(el);
  }
}
