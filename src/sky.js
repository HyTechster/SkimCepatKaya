// sky.js — falling money drops. Coins fall often for a small reward; a wallet
// falls rarely for a much bigger one. Click one to catch it.
//
// Security: catching a drop just calls claim_cash() / claim_wallet(); the SERVER
// decides the reward and enforces a cooldown, so this file (fully visible in
// devtools) can't mint money, it only asks and the server answers.
import * as api from "./api.js";
import { setState } from "./store.js";
import { reconcileFromState } from "./engine.js";
import { fmtMoney, toast } from "./ui.js";

const COIN_MIN_GAP   = 12000;   // ms between coins
const COIN_MAX_GAP   = 24000;
const WALLET_MIN_GAP  = 70000;  // ms between wallets (rare)
const WALLET_MAX_GAP  = 160000;

let layer;
let drops = [];
let enabled = false;
let nextCoinAt = 0;
let nextWalletAt = 0;
let last = 0;
let W = 0, H = 0;

export function initSky() {
  layer = document.createElement("div");
  layer.id = "cashLayer";
  document.body.appendChild(layer);
  onResize();
  window.addEventListener("resize", onResize);
  const t = performance.now();
  nextCoinAt = t + rand(4000, 8000);
  nextWalletAt = t + rand(30000, 60000);   // first wallet not too soon
  requestAnimationFrame(loop);
}

// Drops only pay out while signed in and playing.
export function enableCashDrops(on) {
  enabled = on;
  if (!on) drops.slice().forEach(removeDrop);
}

function onResize() { W = window.innerWidth; H = window.innerHeight; }

function spawnDrop(type) {
  // rain straight down from above, within the visible width (mobile friendly)
  const startX = rand(24, Math.max(40, W - 24));
  const startY = -70;
  const vx = rand(-15, 15);                        // gentle sway
  const vy = type === "wallet" ? rand(120, 170) : rand(140, 220);  // wallets fall a bit slower
  const rot = rand(-15, 15);

  const el = document.createElement("button");
  el.className = type === "wallet" ? "walletdrop" : "cashdrop";
  el.type = "button";
  el.setAttribute("aria-label", type === "wallet" ? "Grab the wallet" : "Grab the cash");
  el.style.transform = `translate(${startX}px, ${startY}px) rotate(${rot}deg)`;

  const d = { el, type, x: startX, y: startY, vx, vy, rot, caught: false };
  el.addEventListener("click", () => onCatch(d));
  layer.appendChild(el);
  drops.push(d);
}

function count(type) { return drops.reduce((n, d) => n + (d.type === type ? 1 : 0), 0); }

function loop(now) {
  const dt = last ? Math.min(now - last, 100) : 16;
  last = now;

  if (enabled && count("coin") === 0 && now >= nextCoinAt) {
    spawnDrop("coin");
    nextCoinAt = now + rand(COIN_MIN_GAP, COIN_MAX_GAP);
  }
  if (enabled && count("wallet") === 0 && now >= nextWalletAt) {
    spawnDrop("wallet");
    nextWalletAt = now + rand(WALLET_MIN_GAP, WALLET_MAX_GAP);
  }
  for (let i = drops.length - 1; i >= 0; i--) {
    const d = drops[i];
    if (d.caught) continue;
    d.x += d.vx * dt / 1000;
    d.y += d.vy * dt / 1000;
    d.el.style.transform = `translate(${d.x}px, ${d.y}px) rotate(${d.rot}deg)`;
    if (d.y > H + 140) removeDrop(d);
  }
  requestAnimationFrame(loop);
}

async function onCatch(d) {
  if (d.caught) return;
  d.caught = true;
  d.el.classList.add("caught");
  try {
    const snap = d.type === "wallet" ? await api.claimWallet() : await api.claimCash();
    setState(snap);
    reconcileFromState(snap);
    const g = Number((d.type === "wallet" ? snap.wallet_gained : snap.cash_gained) || 0);
    if (g > 0) {
      toast(d.type === "wallet" ? `Wallet found!  +${fmtMoney(g)}` : `Cash grabbed!  +${fmtMoney(g)}`);
    } else {
      toast("Too slow, that one got away.");
    }
  } catch (e) {
    console.error("drop claim failed:", e);
  }
  setTimeout(() => removeDrop(d), 200);
}

function removeDrop(d) {
  const i = drops.indexOf(d);
  if (i >= 0) drops.splice(i, 1);
  if (d.el && d.el.parentNode) d.el.parentNode.removeChild(d.el);
}

function rand(a, b) { return a + Math.random() * (b - a); }
