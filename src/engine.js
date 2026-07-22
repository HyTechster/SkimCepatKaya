// engine.js — bridges the C++/WASM visual engine to the canvas and input, and
// handles the optimistic-click / server-reconcile loop.
//
// Flow: a tap plays instantly (WASM animates + bumps the local number), and is
// counted in `pending`. Every CLICK_BATCH_MS we flush the pending count to the
// server via do_click(n); the server credits at most a human-plausible number
// and returns the authoritative snapshot, which we reconcile back into the WASM
// engine and the store.
import { CLICK_BATCH_MS, METHOD_VISUALS, DEFAULT_VISUAL } from "./config.js";
import { store, setState } from "./store.js";
import * as api from "./api.js";
import { fmtMoney } from "./ui.js";
import { playCash } from "./sound.js";

const CENTER = 240;
const BASE_R = 92;
const METHOD_IMG_SIZE = 340;   // longest side of the tapped object, in logical px
// per-method size nudge for art whose subject doesn't fill the frame (1 = normal)
const METHOD_SCALE = { qr: 1.25, card: 1.5 };

// Preload the art. The tapped object is the current method's sprite; coins fly
// off on each tap.
const methodImgs = {};
for (const id of ["piggy_bank", "wallet", "qr", "card", "bank", "vault"]) {
  const img = new Image();
  img.src = `assets/method-${id}.png`;
  methodImgs[id] = img;
}
const coinImg = new Image();
coinImg.src = "assets/coin.png";

let cw = {};
let canvas, ctx, balanceEl, gainHost;
let pending = 0;
let flushing = false;
let running = false;
let lastFlush = 0;
let lastT = 0;
let lastGainAt = 0;

export async function initEngine(canvasEl, balanceElem) {
  // window.createGame is defined by the Emscripten glue loaded in index.html.
  const Module = await window.createGame();
  cw = {
    init:      Module.cwrap("engine_init", null, []),
    reconcile: Module.cwrap("engine_reconcile", null, ["number", "number", "number"]),
    tap:       Module.cwrap("engine_tap", null, []),
    tick:      Module.cwrap("engine_tick", null, ["number"]),
    cash:      Module.cwrap("engine_display_cash", "number", []),
    pulse:     Module.cwrap("engine_pulse", "number", []),
    coins:     Module.cwrap("engine_coin_count", "number", []),
    cx:        Module.cwrap("engine_coin_x", "number", ["number"]),
    cy:        Module.cwrap("engine_coin_y", "number", ["number"]),
    clife:     Module.cwrap("engine_coin_life", "number", ["number"]),
  };
  cw.init();

  canvas = canvasEl;
  balanceEl = balanceElem;
  gainHost = canvas.parentElement;   // the .stage, for floating "+$" text
  ctx = canvas.getContext("2d");
  const DPR = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = 480 * DPR;
  canvas.height = 480 * DPR;
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);

  canvas.addEventListener("pointerdown", onTap);
  running = true;
  requestAnimationFrame(loop);
}

// Push the latest server snapshot into the WASM engine so its optimistic number
// snaps to truth and per-tap/method visuals stay correct.
export function reconcileFromState(state) {
  if (!state || !cw.reconcile) return;
  // the big optimistic number is your BALANCE (spendable cash), so it drops when
  // you buy and rises as you tap
  cw.reconcile(Number(state.balance), Number(state.per_tap), methodIndex(state.current_method_id));
}

function methodIndex(id) {
  const methods = store.config?.methods || [];
  const i = methods.findIndex((m) => m.id === id);
  return i < 0 ? 0 : i;
}

function currentVisual() {
  const id = store.state?.current_method_id;
  return (id && METHOD_VISUALS[id]) || DEFAULT_VISUAL;
}

function onTap() {
  if (!store.state) return;
  cw.tap();
  pending++;
  spawnGain();
  playCash();
}

// A floating "+$X" (the per-tap money) that rises from the object, NOT from the
// cursor. Slightly jittered and throttled so fast clicking doesn't flood the DOM.
function spawnGain() {
  const now = performance.now();
  if (now - lastGainAt < 80) return;
  lastGainAt = now;
  const amt = Number(store.state?.per_tap || 0);
  if (!gainHost || amt <= 0) return;
  const el = document.createElement("div");
  el.className = "gain-text";
  el.textContent = "+" + fmtMoney(amt);
  el.style.left = (50 + (Math.random() - 0.5) * 28) + "%";
  el.style.top = (42 + (Math.random() - 0.5) * 12) + "%";
  gainHost.appendChild(el);
  setTimeout(() => el.remove(), 850);
}

async function flush() {
  if (flushing || pending <= 0) return;
  const n = Math.min(pending, 200);
  pending -= n;
  flushing = true;
  try {
    const snap = await api.doClick(n);
    setState(snap);              // updates HUD/shop subscribers
    reconcileFromState(snap);    // corrects the optimistic number
  } catch (e) {
    console.error("click flush failed:", e);
  } finally {
    flushing = false;
  }
}

function loop(now) {
  if (!running) return;
  const dt = lastT ? Math.min((now - lastT) / 1000, 0.1) : 0;
  lastT = now;

  cw.tick(dt);
  if (now - lastFlush >= CLICK_BATCH_MS) { lastFlush = now; flush(); }

  draw();
  if (balanceEl) balanceEl.textContent = fmtMoney(cw.cash());
  requestAnimationFrame(loop);
}

function draw() {
  const vis = currentVisual();
  // Transparent canvas so the room background shows through around the object.
  ctx.clearRect(0, 0, 480, 480);

  const pulse = cw.pulse();               // 0..1

  // the method image (piggy bank / wallet / ...), scaled slightly by the pulse.
  // Keep the art's aspect ratio, fitting the longest side to `size`.
  const id = store.state?.current_method_id || "piggy_bank";
  const img = methodImgs[id];
  const size = METHOD_IMG_SIZE * (METHOD_SCALE[id] || 1) * (1 + 0.05 * pulse);
  if (img && img.complete && img.naturalWidth) {
    const scale = size / Math.max(img.naturalWidth, img.naturalHeight);
    const w = img.naturalWidth * scale;
    const h = img.naturalHeight * scale;
    ctx.drawImage(img, CENTER - w / 2, CENTER - h / 2, w, h);
  } else {
    // fallback disc until the image finishes loading
    ctx.fillStyle = vis.core;
    ctx.beginPath();
    ctx.arc(CENTER, CENTER, BASE_R, 0, Math.PI * 2);
    ctx.fill();
  }

  // coins flying off each tap (coin sprite, falling back to a gold dot)
  const n = cw.coins();
  const coinReady = coinImg.complete && coinImg.naturalWidth;
  for (let i = 0; i < n; i++) {
    const life = cw.clife(i);
    if (life <= 0) continue;
    const x = cw.cx(i), y = cw.cy(i);
    ctx.globalAlpha = life;
    if (coinReady) {
      const s = 12 + 16 * life;
      ctx.drawImage(coinImg, x - s / 2, y - s / 2, s, s);
    } else {
      ctx.fillStyle = "#FFD24A";
      ctx.beginPath();
      ctx.arc(x, y, 3.2 * life + 1, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  ctx.globalAlpha = 1;
}
