// main.js — entry point. Wires the auth screen, watches the session, and boots
// the game once a user is signed in.
import * as auth from "./auth.js";
import * as api from "./api.js";
import { setState, setConfig, setProfile } from "./store.js";
import { initEngine, reconcileFromState } from "./engine.js";
import { initHud } from "./hud.js";
import { initShop } from "./shop.js";
import { initLeaderboard } from "./leaderboard.js";
import { claimIdleOnLoad } from "./idle.js";
import { initSky, enableCashDrops } from "./sky.js";
import { $, showScreen, toast, errText } from "./ui.js";

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
    enableCashDrops(true);       // cash drops pay out now that we're signed in
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

function wireAuth() {
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

async function boot() {
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
