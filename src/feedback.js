// feedback.js — the "Feedback & ideas" form. Sends a note to the server-side
// submit_feedback() RPC, which validates, caps length, and rate-limits. The name
// field is pre-filled with the player's display name but stays editable.
import * as api from "./api.js";
import { $, toast, errText } from "./ui.js";

const COOLDOWN_MS = 45000;   // must match FEEDBACK_COOLDOWN in db/06_feedback.sql
let cooling = false;

export function initFeedback() {
  const form = $("#feedbackForm");
  if (!form) return;

  form.addEventListener("submit", onSubmit);

  // Desktop modal open/close. On mobile the button and X are hidden and the
  // panel is always inline, so these listeners simply never do anything visible.
  const wrap = $("#feedbackWrap");
  const openBtn = $("#feedbackOpen");
  const closeBtn = $("#feedbackClose");
  if (openBtn && wrap) openBtn.addEventListener("click", () => wrap.classList.add("open"));
  if (closeBtn && wrap) closeBtn.addEventListener("click", () => wrap.classList.remove("open"));
  if (wrap) wrap.addEventListener("click", (e) => { if (e.target === wrap) wrap.classList.remove("open"); });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && wrap) wrap.classList.remove("open");
  });
}

async function onSubmit(e) {
  e.preventDefault();
  if (cooling) return;

  const name = $("#fbName").value.trim();
  const category = $("#fbCategory").value;
  const message = $("#fbMessage").value.trim();
  if (name.length < 1) { toast("Please enter your name."); return; }
  if (message.length < 1) { toast("Please write a message."); return; }

  const btn = $("#fbSubmit");
  btn.disabled = true;
  try {
    await api.submitFeedback(name, category, message);
    $("#fbMessage").value = "";
    $("#feedbackWrap")?.classList.remove("open");   // close the desktop modal
    toast("Thanks! Your feedback was sent.");
    startCooldown(btn);
  } catch (err) {
    btn.disabled = false;
    toast(errText(err));
  }
}

// After a successful send, count the button down so people can't spam it (and so
// the UI matches the server's 45s rate limit).
function startCooldown(btn) {
  cooling = true;
  let left = Math.ceil(COOLDOWN_MS / 1000);
  btn.disabled = true;
  btn.textContent = `Wait ${left}s`;
  const timer = setInterval(() => {
    left -= 1;
    if (left <= 0) {
      clearInterval(timer);
      cooling = false;
      btn.disabled = false;
      btn.textContent = "Send feedback";
    } else {
      btn.textContent = `Wait ${left}s`;
    }
  }, 1000);
}
