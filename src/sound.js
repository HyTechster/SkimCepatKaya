// sound.js — tiny Web Audio "cash" blip played on each tap. No asset file: the
// sound is synthesized so there's nothing extra to download. The AudioContext is
// created lazily and resumed on the first user gesture (browsers block audio
// before that), and playback is throttled so rapid tapping stays pleasant.

let ctx = null;
let last = 0;
const MIN_GAP = 45; // ms between blips, so fast clicking doesn't turn into noise

function ensureCtx() {
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return null;
  if (!ctx) ctx = new AC();
  if (ctx.state === "suspended") ctx.resume();
  return ctx;
}

// A short two-tone coin "ching": a bright blip that quickly rises in pitch,
// with a fast decay so it feels like a small register/coin tap.
export function playCash() {
  const now = performance.now();
  if (now - last < MIN_GAP) return;
  last = now;

  const ac = ensureCtx();
  if (!ac) return;

  const t = ac.currentTime;
  const gain = ac.createGain();
  gain.gain.setValueAtTime(0.0001, t);
  gain.gain.exponentialRampToValueAtTime(0.16, t + 0.008);
  gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.14);
  gain.connect(ac.destination);

  const osc = ac.createOscillator();
  osc.type = "triangle";
  osc.frequency.setValueAtTime(880, t);
  osc.frequency.exponentialRampToValueAtTime(1320, t + 0.06);
  osc.connect(gain);
  osc.start(t);
  osc.stop(t + 0.15);
}
