// main.js — entry point. Wires the auth screen, watches the session, and boots
// the game once a user is signed in.
import * as auth from "./auth.js";
import * as api from "./api.js";
import { setState, setConfig, setProfile } from "./store.js";
import { initEngine, reconcileFromState } from "./engine.js";
import { initHud } from "./hud.js";
import { initShop } from "./shop.js";
import { initLeaderboard } from "./leaderboard.js";
import { initFeedback } from "./feedback.js";
import { claimIdleOnLoad } from "./idle.js";
import { initSky, enableCashDrops } from "./sky.js";
import { $, $$, showScreen, toast, errText } from "./ui.js";

let gameStarted = false;

async function startGame() {
  if (gameStarted) return;
  gameStarted = true;
  showScreen("game");
  try {
    const [config, profile, state] = await Promise.all([
      api.getConfig(),
      api.getProfile(),
      api.getState(),
    ]);
    setConfig(config);
    setProfile(profile);
    setState(state);

    await initEngine($("#clicker"), $("#balanceVal"));
    reconcileFromState(state);

    initHud();
    initShop();
    initLeaderboard();
    initFeedback();
    enableCashDrops(true);       // cash drops pay out now that we're signed in
    $("#helpModal").classList.remove("hidden");  // show the tutorial on each login
    await claimIdleOnLoad();
  } catch (e) {
    console.error(e);
    toast("Couldn't load your game: " + errText(e));
  }
}

function switchTab(which) {
  $("#tabIn").classList.toggle("on", which === "in");
  $("#tabUp").classList.toggle("on", which === "up");
  $("#formIn").classList.toggle("hidden", which !== "in");
  $("#formUp").classList.toggle("hidden", which !== "up");
}

// Wrap every password input in a .pw-field and drop a show/hide eye button in.
// Building it here keeps the markup for three fields out of the HTML.
const EYE_SVG =
  '<svg class="eye" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7-11-7-11-7z"/><circle cx="12" cy="12" r="3"/></svg>' +
  '<svg class="eye-off" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>';

function wireEyeToggles() {
  $$('input[type="password"]').forEach((input) => {
    const wrap = document.createElement("div");
    wrap.className = "pw-field";
    input.parentNode.insertBefore(wrap, input);
    wrap.appendChild(input);

    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "pw-toggle";
    btn.setAttribute("aria-label", "Show password");
    btn.innerHTML = EYE_SVG;
    wrap.appendChild(btn);

    btn.addEventListener("click", () => {
      const show = input.type === "password";
      input.type = show ? "text" : "password";
      btn.classList.toggle("showing", show);
      btn.setAttribute("aria-label", show ? "Hide password" : "Show password");
    });
  });
}

function wireAuth() {
  wireEyeToggles();
  $("#tabIn").addEventListener("click", () => switchTab("in"));
  $("#tabUp").addEventListener("click", () => switchTab("up"));

  $("#formIn").addEventListener("submit", async (e) => {
    e.preventDefault();
    const btn = $("#inSubmit");
    btn.disabled = true;
    const { data, error } = await auth.signIn($("#inEmail").value.trim(), $("#inPass").value);
    btn.disabled = false;
    if (error) { toast(errText(error)); return; }
    if (data?.session) startGame();   // start immediately; onAuthChange is a backup
  });

  $("#formUp").addEventListener("submit", async (e) => {
    e.preventDefault();
    const name = $("#upName").value.trim();
    if (name.length < 1) { toast("Pick a display name."); return; }
    const pass = $("#upPass").value;
    if (pass.length < 6) { toast("Password must be at least 6 characters."); return; }
    if (pass !== $("#upPass2").value) { toast("Passwords don't match."); return; }
    const btn = $("#upSubmit");
    btn.disabled = true;
    const { data, error } = await auth.signUp(
      $("#upEmail").value.trim(), $("#upPass").value, name
    );
    btn.disabled = false;
    if (error) { toast(errText(error)); return; }
    if (data?.session) {
      startGame();   // email confirmation off -> we're already in
    } else {
      toast("Account created. Check your email to confirm, then sign in.");
      switchTab("in");
    }
  });

  $("#signOutBtn").addEventListener("click", async () => {
    await auth.signOut();
    location.reload();   // cleanest full reset
  });
}

function wireHelp() {
  const modal = $("#helpModal");
  const open = () => modal.classList.remove("hidden");
  const close = () => modal.classList.add("hidden");
  $("#helpBtn").addEventListener("click", open);
  $("#helpClose").addEventListener("click", close);
  modal.addEventListener("click", (e) => { if (e.target === modal) close(); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") close(); });
}

// iOS Safari ignores `user-scalable=no`, so a tapping game gets zoomed by
// double-taps and pinches. touch-action (CSS) handles most double-tap zoom;
// these listeners stop the rest: pinch (gesture* events) and the stray
// double-tap. Taps are counted on pointerdown, so blocking the synthetic
// double-tap click never loses a tap.
function blockZoomGestures() {
  ["gesturestart", "gesturechange", "gestureend"].forEach((ev) =>
    document.addEventListener(ev, (e) => e.preventDefault(), { passive: false })
  );
  let lastTouch = 0;
  document.addEventListener("touchend", (e) => {
    const now = Date.now();
    if (now - lastTouch <= 300) e.preventDefault();
    lastTouch = now;
  }, { passive: false });
}

async function boot() {
  blockZoomGestures();
  initSky();                     // twinkling starfield runs on every screen
  wireAuth();
  wireHelp();
  auth.onAuthChange((session) => {
    // Defer out of the auth callback: doing async Supabase work synchronously
    // inside onAuthStateChange can deadlock the auth lock.
    if (session) setTimeout(startGame, 0);
    else { enableCashDrops(false); showScreen("auth"); }
  });
  const session = await auth.getSession();
  if (session) startGame();
  else showScreen("auth");
}

boot();
