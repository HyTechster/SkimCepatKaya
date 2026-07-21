// engine.cpp — money-clicker VISUAL engine (C++ -> WebAssembly)
// ---------------------------------------------------------------------------
// IMPORTANT: this file holds ZERO authority over the game economy. It cannot,
// and must not, be trusted for money — it runs in the browser where anyone can
// inspect and edit it. The real balance/net worth/upgrades live in Supabase and
// are computed server-side (see db/04_functions.sql).
//
// What this engine DOES do is make the clicker feel good:
//   * the tapped object (piggy bank / wallet / ...) pulses when you tap it
//   * little coins that fly off on each tap
//   * a smoothly-animated "displayed balance" that ticks up optimistically the
//     instant you click, then reconciles to the server's real value
//
// The JS side (src/engine.js) reads these values every frame and draws them on
// a 480x480 logical canvas, with the object centered at (240, 240).

#include <emscripten/emscripten.h>
#include <cstdlib>   // rand(), RAND_MAX
#include <cmath>     // sinf, cosf, sqrtf

// --- play field (matches the canvas logical size in JS) --------------------
static const float CENTER_X = 240.0f;
static const float CENTER_Y = 240.0f;

// A fixed coin pool: fixed memory, no heap growth, nothing to leak.
static const int MAX_COINS = 48;
struct Coin {
    float x, y;      // position
    float vx, vy;    // velocity (px/sec)
    float life;      // 1.0 -> 0.0, dead at 0
};
static Coin g_coins[MAX_COINS];
static int  g_next_coin = 0;   // ring-buffer cursor

// --- optimistic display state ----------------------------------------------
// g_target_cash: what we CURRENTLY BELIEVE the balance is. Taps add to it right
//   away (optimistic); a server reconcile snaps it to the authoritative value.
// g_display_cash: chases the target so the on-screen number animates smoothly
//   instead of jumping.
static double g_target_cash  = 0.0;
static double g_display_cash = 0.0;
static double g_per_tap      = 0.01;   // last per-tap value the server told us
static int    g_method_index = 0;      // which method (drives visuals in JS)

// object pulse: kicked to 1.0 on a tap, decays back to 0.0
static float g_pulse = 0.0f;

static float frand() { return (float)rand() / (float)RAND_MAX; }  // 0..1

static void spawnCoin() {
    Coin &c = g_coins[g_next_coin];
    g_next_coin = (g_next_coin + 1) % MAX_COINS;

    float angle = frand() * 6.2831853f;          // random direction
    float speed = 120.0f + frand() * 140.0f;     // px/sec
    c.x = CENTER_X;
    c.y = CENTER_Y;
    c.vx = cosf(angle) * speed;
    c.vy = sinf(angle) * speed;
    c.life = 1.0f;
}

// extern "C" + KEEPALIVE so JS can call these by their plain names.
extern "C" {

EMSCRIPTEN_KEEPALIVE
void engine_init() {
    g_target_cash = 0.0;
    g_display_cash = 0.0;
    g_per_tap = 0.01;
    g_method_index = 0;
    g_pulse = 0.0f;
    for (int i = 0; i < MAX_COINS; i++) g_coins[i].life = 0.0f;
    g_next_coin = 0;
}

// Server truth arrived: snap our belief to it. per_tap and method come from the
// same snapshot so optimistic taps between reconciles look right.
EMSCRIPTEN_KEEPALIVE
void engine_reconcile(double balance, double per_tap, int method_index) {
    g_target_cash = balance;
    g_per_tap = per_tap > 0.0 ? per_tap : 0.01;
    g_method_index = method_index;
}

// The player tapped the object. Optimistically bump the target, kick the pulse,
// and throw off a couple of coins. (The server may later correct the number via
// engine_reconcile; that's expected and fine.)
EMSCRIPTEN_KEEPALIVE
void engine_tap() {
    g_target_cash += g_per_tap;
    g_pulse = 1.0f;
    spawnCoin();
    spawnCoin();
}

// Advance animation by dt seconds.
EMSCRIPTEN_KEEPALIVE
void engine_tick(double dt) {
    float fdt = (float)dt;

    // pulse decays with a ~0.18s time constant
    g_pulse -= fdt / 0.18f;
    if (g_pulse < 0.0f) g_pulse = 0.0f;

    // coins drift out, slow down, and fade
    for (int i = 0; i < MAX_COINS; i++) {
        Coin &c = g_coins[i];
        if (c.life <= 0.0f) continue;
        c.x += c.vx * fdt;
        c.y += c.vy * fdt;
        c.vx *= 0.94f;   // gentle drag
        c.vy *= 0.94f;
        c.life -= fdt / 0.6f;   // ~0.6s lifetime
        if (c.life < 0.0f) c.life = 0.0f;
    }

    // ease the displayed number toward the target (exponential smoothing)
    double diff = g_target_cash - g_display_cash;
    if (diff < 0.0001 && diff > -0.0001) {
        g_display_cash = g_target_cash;
    } else {
        g_display_cash += diff * (1.0 - exp(-12.0 * dt));
    }
}

// --- getters for the JS render loop ----------------------------------------
EMSCRIPTEN_KEEPALIVE double engine_display_cash()   { return g_display_cash; }
EMSCRIPTEN_KEEPALIVE double engine_pulse()          { return (double)g_pulse; }
EMSCRIPTEN_KEEPALIVE int    engine_method_index()   { return g_method_index; }
EMSCRIPTEN_KEEPALIVE int    engine_coin_count()     { return MAX_COINS; }
EMSCRIPTEN_KEEPALIVE double engine_coin_x(int i)    { return (double)g_coins[i].x; }
EMSCRIPTEN_KEEPALIVE double engine_coin_y(int i)    { return (double)g_coins[i].y; }
EMSCRIPTEN_KEEPALIVE double engine_coin_life(int i) { return (double)g_coins[i].life; }

} // extern "C"
