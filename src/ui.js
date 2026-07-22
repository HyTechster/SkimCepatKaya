// ui.js — small DOM helpers shared across modules.

export const $  = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

// Abbreviate big COUNTS (net worth, balance, costs): 950 -> "950",
// 1_234 -> "1.23K", 5_600_000 -> "5.6M". Values under 1000 show as whole numbers.
export function fmt(n) {
  n = Number(n) || 0;
  const abs = Math.abs(n);
  if (abs < 1000) return Math.round(n).toLocaleString();
  const units = ["K", "M", "B", "T", "Qa", "Qi"];
  let u = -1;
  do { n /= 1000; u++; } while (Math.abs(n) >= 1000 && u < units.length - 1);
  return n.toFixed(n < 10 ? 2 : n < 100 ? 1 : 0) + units[u];
}

// For MULTIPLIERS that are meant to be fractional (x1.5, x2.5): keep up to 2
// decimals and trim trailing zeros, but still abbreviate once the value gets big.
export function fmtDec(n) {
  n = Number(n) || 0;
  if (Math.abs(n) >= 1000) return fmt(n);
  if (Number.isInteger(n)) return String(n);
  return String(Math.round(n * 100) / 100);   // e.g. 1.5, 2.5, 0.25
}

// MONEY: under $1000 show cents ($0.01, $12.50); above, abbreviate ($1.23K, $4.5M).
export function fmtMoney(n) {
  n = Number(n) || 0;
  if (Math.abs(n) < 1000) return "$" + n.toFixed(2);
  return "$" + fmt(n);
}

// Show one of the top-level screens ("auth" | "game").
export function showScreen(name) {
  $("#authScreen").classList.toggle("hidden", name !== "auth");
  $("#gameScreen").classList.toggle("hidden", name !== "game");
}

// Lightweight toast, auto-dismisses. Reuses a single container.
export function toast(msg, ms = 3200) {
  let host = $("#toastHost");
  if (!host) {
    host = document.createElement("div");
    host.id = "toastHost";
    document.body.appendChild(host);
  }
  const el = document.createElement("div");
  el.className = "toast";
  el.textContent = msg;
  host.appendChild(el);
  requestAnimationFrame(() => el.classList.add("show"));
  setTimeout(() => {
    el.classList.remove("show");
    setTimeout(() => el.remove(), 300);
  }, ms);
}

// Turn a thrown Supabase/RPC error into a short human message.
export function errText(e) {
  const m = (e && (e.message || e.error_description || e.msg)) || String(e);
  if (/not enough balance/i.test(m))  return "Not enough cash.";
  if (/maxed/i.test(m))               return "Already at max level.";
  if (/already unlocked/i.test(m))    return "You already own that.";
  if (/not unlocked/i.test(m))        return "Unlock it first.";
  if (/previous rank/i.test(m))       return "Unlock the previous rank first.";
  if (/previous method/i.test(m))     return "Unlock the previous method first.";
  if (/level too low/i.test(m))       return "Your level is too low for that.";
  if (/feedback cooldown/i.test(m))   return "Please wait a bit before sending more feedback.";
  if (/name required/i.test(m))       return "Please enter your name.";
  if (/message required/i.test(m))    return "Please write a message.";
  return m;
}
