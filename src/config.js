// config.js — the only file you edit to connect your Supabase project.
// The anon key is meant to be public (see README). Row Level Security is what
// actually protects the data, so shipping this key in the page is expected.

export const SUPABASE_URL      = "https://gjeytpeoqjypbhhuqmly.supabase.co";
export const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdqZXl0cGVvcWp5cGJoaHVxbWx5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ1OTA3NjQsImV4cCI6MjEwMDE2Njc2NH0.-UqhU_YSL4D0bc0TfgugAYrhqtVmh3s1YXogXtkMbMM";

// How often taps are flushed to the server (ms). Taps feel instant locally and
// are reconciled to the authoritative count on each flush.
export const CLICK_BATCH_MS = 250;

// How many top scores to show.
export const LEADERBOARD_LIMIT = 20;

// Auto-refresh the leaderboard on this interval (ms). It also refreshes whenever
// you return to the tab. Kept modest so it isn't a constant load on the DB.
export const LEADERBOARD_REFRESH_MS = 10000;

// Per-method visuals for the tap glow / particles. Keys are method ids from
// db/02_config_data.sql. Warm, money-ish tones on a yellow theme.
export const METHOD_VISUALS = {
  piggy_bank: { core: "#FF9FB2", glow: "#B85C6E" },
  wallet:     { core: "#D6A15A", glow: "#7A5326" },
  qr:         { core: "#FFD24A", glow: "#9A6A10" },
  card:       { core: "#6FB0FF", glow: "#274F8C" },
  bank:       { core: "#7BD36A", glow: "#2E7A2A" },
  vault:      { core: "#FFD24A", glow: "#8A5E0E" },
};
export const DEFAULT_VISUAL = { core: "#FFD24A", glow: "#8A5E0E" };

// Emoji badge per rank id (from db/02_config_data.sql). Purely cosmetic.
export const RANK_ICON = {
  rakyat: "🧑",
  anak_dato: "🧒",
  anak_tan_sri: "👦",
  ceo: "💼",
  dato: "🎖️",
  tan_sri: "🏅",
  menteri: "🏛️",
  perdana_menteri: "🎩",
  jutawan: "💰",
  bilionair: "💎",
};
export const DEFAULT_RANK_ICON = "🎖️";
