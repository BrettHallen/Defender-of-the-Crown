/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * ai.c: the computer lords. ai_turn (AB 2995), ai_reinforce_garrison (2C60),
 * ai_choose_order (2D84), ai_do_order (2D10), the search for a target
 * (2704 target_value, 2803 ai_find_target, 28B8 ai_search), buying (2A9E
 * ai_buy, 2A3C best_site_for_castle) and the Normans' raids (4428 ai_raid,
 * 43F6 choose_raid_victim). See Analysis/GAME_LOGIC.md, "The computer lords".
 *
 * Everything a lord decides, and why, goes to the log (--log; the values of
 * all the targets it looked at with --log=verbose).
 */
#include "ai.h"
#include "war.h"
#include "game.h"
#include "gamelog.h"
#include "month.h"

#define D_SEARCH_PATH   0x0069   /* 5 words: the way to the best target so far */
#define D_SEARCH_BEST   0x0073
#define D_SEARCH_SEEN   0x0075   /* 19 words */
#define D_SEARCH_TARGET 0x009B

static int16_t w16(int v) { return (int16_t)(v & 0xFFFF); }

/* ------------------------------------------------------------------ the target */

static int target_value(int side, int t, int steps)   /* 2704 */
{
    int owner = (int8_t)B(TERR(t) + T_OWNER);
    if (t == 0 || owner == side) return -1;
    if (owner == -1) return w16(1000 - steps);
    int enmity = W(ENMITY(side, owner));
    if (enmity == 0) return -1;
    int own = army_strength(ARMY(side));
    int defenders = army_strength(GARRISON(t));
    if (W(ARMY(owner) + A_AT) == t) defenders = w16(defenders + army_strength(ARMY(owner)));
    if (B(TERR(t) + T_CASTLE)) {
        if (W(ARMY(side) + A_CATAPULTS) == 0) return -1;
        return w16((defenders / 2 + w16(own - defenders) + enmity) * 3);
    }
    return w16(own - defenders + enmity);
}

/* 28B8: depth first from t through the side's own territories, up to 4 steps;
 * every other territory reached gets a value the first time. The values are
 * compared unsigned (AB 2957 jbe), so a negative value (an attack on a much
 * stronger enemy) beats every positive one: kept. */
static void ai_search(int side, int t, int depth, const int16_t *path)
{
    if ((unsigned)depth >= 4) return;
    int16_t here[5];
    SDL_memcpy(here, path, sizeof here);
    SW(D_SEARCH_SEEN + 2 * t, 1);
    for (int i = 0; i < 7; i++) {
        int nb = (int8_t)B(TERR(t) + T_NB + i);
        if (!nb || W(D_SEARCH_SEEN + 2 * nb)) continue;
        if ((int8_t)B(TERR(nb) + T_OWNER) == side) {
            here[depth + 1] = (int16_t)nb;
            ai_search(side, nb, depth + 1, here);
            continue;
        }
        SW(D_SEARCH_SEEN + 2 * nb, 1);
        int v = target_value(side, nb, depth);
        bool best = v != -1 && (uint16_t)v > UW(D_SEARCH_BEST);
        GLOG(GLOG_VERBOSE, "AI %s: looks at %s (%s%s), %d step%s away: value %d%s", glog_side(side), glog_terr(nb),
             (int8_t)B(TERR(nb) + T_OWNER) == -1 ? "nobody's" : glog_side((int8_t)B(TERR(nb) + T_OWNER)),
             B(TERR(nb) + T_CASTLE) ? ", castle" : "", depth, depth == 1 ? "" : "s",
             v, v == -1 ? " (never)" : best ? " (the best so far)" : "");
        if (best) {
            SW(D_SEARCH_BEST, v);
            SW(D_SEARCH_TARGET, nb);
            for (int k = 0; k < 5; k++) SW(D_SEARCH_PATH + 2 * k, here[k]);
        }
    }
}

static int ai_find_target(int side, int *target, int16_t *path)   /* 2803 */
{
    if (army_strength(ARMY(side)) == 0) {
        GLOG(GLOG_NORMAL, "AI %s: no target: its campaign army is empty", glog_side(side));
        return 0;
    }
    for (int t = 0; t < 19; t++) SW(D_SEARCH_SEEN + 2 * t, 0);
    int16_t start[5] = { 0 };
    for (int k = 0; k < 5; k++) path[k] = 0;
    start[0] = (int16_t)W(SIDE(side) + S_AT);
    SW(D_SEARCH_BEST, 0);
    SW(D_SEARCH_TARGET, 0);
    ai_search(side, W(SIDE(side) + S_AT), 0, start);
    if (UW(D_SEARCH_TARGET) == 0) {
        GLOG(GLOG_NORMAL, "AI %s: no target worth attacking from %s", glog_side(side), glog_terr(W(SIDE(side) + S_AT)));
        return 0;
    }
    *target = W(D_SEARCH_TARGET);
    for (int k = 0; k < 5; k++) path[k] = (int16_t)W(D_SEARCH_PATH + 2 * k);
    return 1;
}

/* ------------------------------------------------------------------ buying */

static int best_site_for_castle(int side)   /* 2A3C: its territory without a castle with the highest income */
{
    int di = 0;
    for (int si = 0; si < 19; si++) {
        if ((int8_t)B(TERR(si) + T_OWNER) != side || B(TERR(si) + T_CASTLE)) continue;
        if (!di) di = si;
        else if ((int8_t)B(TERR(si) + T_INCOME) > (int8_t)B(TERR(di) + T_INCOME)) di = si;
    }
    return di;
}

/* 2A9E. Whether it has a catapult is read from its campaign army and the
 * garrison of the territory with its side's number, not its home's (AB 2AD1):
 * kept. Without one and without 15 gold it buys nothing. */
static void ai_buy(int si)
{
    int home = W(SIDE(si) + S_HOME);
    if (w16(W(ARMY(si) + A_CATAPULTS) + W(GARRISON(si) + A_CATAPULTS)) <= 0) {
        if (W(SIDE(si) + S_GOLD) < 15) {
            GLOG(GLOG_NORMAL, "AI %s: buys nothing: no catapult and only %d gold for one", glog_side(si), W(SIDE(si) + S_GOLD));
            return;
        }
        SW(SIDE(si) + S_GOLD, W(SIDE(si) + S_GOLD) - 15);
        SW(GARRISON(home) + A_CATAPULTS, W(GARRISON(home) + A_CATAPULTS) + 1);
        GLOG(GLOG_NORMAL, "AI %s: buys a catapult (15 gold) for %s", glog_side(si), glog_terr(home));
    }
    int gold = W(SIDE(si) + S_GOLD);
    int spend = w16(w16(W(SIDE(si) + S_SPEND) * gold) / 10);
    SW(SIDE(si) + S_GOLD, W(SIDE(si) + S_GOLD) - spend);
    int knights = w16(spend / 2) / 8;
    SW(GARRISON(home) + A_KNIGHTS, W(GARRISON(home) + A_KNIGHTS) + knights);
    int soldiers = w16(spend - knights * 8);
    SW(GARRISON(home) + A_SOLDIERS, W(GARRISON(home) + A_SOLDIERS) + soldiers);
    GLOG(GLOG_NORMAL, "AI %s: spends %d of its %d gold (spending %d/10): %s and %s for %s", glog_side(si), spend, gold,
         W(SIDE(si) + S_SPEND), glog_count(knights, "knight"), glog_count(soldiers, "soldier"), glog_terr(home));
    while (W(SIDE(si) + S_GOLD) >= 20) {
        int t = best_site_for_castle(si);
        if (!t) break;
        SB(TERR(t) + T_CASTLE, 35);
        SW(GARRISON(t) + A_SOLDIERS, W(GARRISON(t) + A_SOLDIERS) + 10);
        SW(SIDE(si) + S_GOLD, W(SIDE(si) + S_GOLD) - 20);
        GLOG(GLOG_NORMAL, "AI %s: builds a castle (20 gold) in %s, with 10 soldiers", glog_side(si), glog_terr(t));
    }
    /* 80% of the men of the garrison where its army stands join the army, and all its catapults */
    int g = GARRISON(W(SIDE(si) + S_AT)), a = ARMY(si);
    int n = (int)(((int32_t)W(g + A_SOLDIERS) << 3) / 10);
    SW(a + A_SOLDIERS, W(a + A_SOLDIERS) + n);
    SW(g + A_SOLDIERS, W(g + A_SOLDIERS) - n);
    int k = (int)(((int32_t)W(g + A_KNIGHTS) << 3) / 10);
    SW(a + A_KNIGHTS, W(a + A_KNIGHTS) + k);
    SW(g + A_KNIGHTS, W(g + A_KNIGHTS) - k);
    int c = W(g + A_CATAPULTS);
    SW(a + A_CATAPULTS, W(a + A_CATAPULTS) + c);
    SW(g + A_CATAPULTS, 0);
    GLOG(GLOG_NORMAL, "AI %s: %s, %s and %s of the garrison of %s join its campaign army (now %d, %d, %d); %d gold left",
         glog_side(si), glog_count(n, "soldier"), glog_count(k, "knight"), glog_count(c, "catapult"), glog_terr(W(SIDE(si) + S_AT)),
         W(a + A_SOLDIERS), W(a + A_KNIGHTS), W(a + A_CATAPULTS), W(SIDE(si) + S_GOLD));
}

/* ------------------------------------------------------------------ raids */

static int choose_raid_victim(void)   /* 43F6: one of the three Saxons, if its home stands */
{
    int si = random_n(3) + 1;
    if ((int8_t)B(TERR(W(SIDE(si) + S_HOME)) + T_OWNER) != si) return -1;
    return si;
}

static void ai_raid(int side)   /* 4428 */
{
    int si = choose_raid_victim();
    if (si == -1) {
        GLOG(GLOG_NORMAL, "AI %s: raids nobody (the Saxon it picked has lost its home)", glog_side(side));
        return;
    }
    enmity_add(si, side, 1);
    int p = W(D_PLAYER);
    int lady = W(SIDE(si) + S_LADY);
    if (lady != -1 && W(SIDE(p) + S_LADY) == -1 && W(D_MONTH) > 10) {
        SW(D_KIDNAPPED, lady);
        SW(LADY(lady) + L_TERR, W(SIDE(side) + S_HOME));
        GLOG(GLOG_NORMAL, "AI %s: raids %s and kidnaps %s to %s", glog_side(side), glog_side(si), STR(W(LADY(lady) + L_NAME)),
             glog_terr(W(SIDE(side) + S_HOME)));
        return;
    }
    int di = W(SIDE(si) + S_GOLD) / 2;
    if (!di) {
        GLOG(GLOG_NORMAL, "AI %s: raids %s, who has no gold to take", glog_side(side), glog_side(si));
        return;
    }
    SW(SIDE(si) + S_GOLD, W(SIDE(si) + S_GOLD) - di);
    SW(SIDE(side) + S_GOLD, W(SIDE(side) + S_GOLD) + di);
    GLOG(GLOG_NORMAL, "AI %s: raids %s and takes %d gold (half)", glog_side(side), glog_side(si), di);
    if (si == p) {
        dialog(0x20BA);
        redraw_map();
    }
}

/* ------------------------------------------------------------------ the turn */

/* 2C60: men from the campaign army into the garrison where it is, when the
 * garrison has fewer than half (at home) or a fifth (elsewhere) of the army's
 * soldiers */
static void ai_reinforce_garrison(int si)
{
    int t = W(ARMY(si) + A_AT);
    int s = W(ARMY(si) + A_SOLDIERS);
    int want = t == W(SIDE(si) + S_HOME) ? s / 2 : s / 5;
    if (W(GARRISON(t) + A_SOLDIERS) >= want) return;
    int di = want > 2 ? want : s > 2 ? 2 : 0;
    SW(ARMY(si) + A_SOLDIERS, W(ARMY(si) + A_SOLDIERS) - di);
    SW(GARRISON(t) + A_SOLDIERS, W(GARRISON(t) + A_SOLDIERS) + di);
    if (di) GLOG(GLOG_NORMAL, "AI %s: %s of its campaign army join the garrison of %s (it had fewer than %d)", glog_side(si),
                 glog_count(di, "soldier"), glog_terr(t), want);
}

/* 2D84: from the random generator's last value (DS:005B) after each step */
static int ai_choose_order(int di, int *target, int16_t *path)
{
    int si;
    const char *why;
    if (W(SIDE(di) + S_AT) != W(SIDE(di) + S_HOME) && (random_next(), !(W(D_RANDOM) & 3))) {
        si = 9; why = "its army is away from home and the 1 in 4 to go home came up";
    } else if (W(D_LAST_ORDER + 2 * di) != 4 && (random_next(), !(W(D_RANDOM) & 3))) {
        si = 4; why = "it did not buy last time and the 1 in 4 to buy came up";
    } else if (random_next(), W(D_RANDOM) & 7) {
        if (ai_find_target(di, target, path)) { si = 2; why = "the 7 in 8 for conquest came up and it has a target"; }
        else if (random_next(), W(D_RANDOM) & 1) { si = 4; why = "the 7 in 8 for conquest came up, no target: buys (even chances)"; }
        else { si = 6; why = "the 7 in 8 for conquest came up, no target: passes (even chances)"; }
    } else if (di > 3) {
        si = 3; why = "the 1 in 8 came up: a Norman raids";
    } else if ((unsigned)W(D_YEAR) > 1149) {
        si = 1; why = "the 1 in 8 came up: a Saxon after 1149 holds a tournament";
    } else {
        si = 4; why = "the 1 in 8 came up: a Saxon in 1149 buys";
    }
    SW(D_LAST_ORDER + 2 * di, si);
    static const char *const ORDER[10] = { "", "Hold Tournament", "Seek Conquest", "Raid", "Buy", "", "Pass", "", "", "Go Home" };
    GLOG(GLOG_NORMAL, "AI %s: order %s, because %s", glog_side(di), ORDER[si], why);
    return si;
}

static void ai_do_order(int si, int order, int target, const int16_t *path)   /* 2D10 */
{
    switch (order) {
    case 1:
        tournament(si);
        break;
    case 2: {
        char way[128] = "";
        for (int k = 0; k < 5 && path[k]; k++)
            SDL_snprintf(way + SDL_strlen(way), sizeof way - SDL_strlen(way), "%s%d", k ? " > " : "", path[k]);
        int owner = (int8_t)B(TERR(target) + T_OWNER);
        GLOG(GLOG_NORMAL, "AI %s: marches its campaign army (%s, %s, %s) to %s of %s, value %d (way: %s > %d)",
             glog_side(si), glog_count(W(ARMY(si) + A_SOLDIERS), "soldier"), glog_count(W(ARMY(si) + A_KNIGHTS), "knight"),
             glog_count(W(ARMY(si) + A_CATAPULTS), "catapult"), glog_terr(target),
             owner == -1 ? "nobody" : glog_side(owner), W(D_SEARCH_BEST), way, target);
        army_move_to(si, target);
        attack(si, owner, target);
        break;
    }
    case 3:
        ai_raid(si);
        break;
    case 4:
        ai_buy(si);
        break;
    case 9:
        army_go_home(si);
        GLOG(GLOG_NORMAL, "AI %s: its campaign army goes home to %s", glog_side(si), glog_terr(W(SIDE(si) + S_HOME)));
        break;
    default:
        break;
    }
}

void ai_turn(int si)
{
    int home = W(SIDE(si) + S_HOME);
    if (W(D_QUIT)) return;
    if ((int8_t)B(TERR(home) + T_OWNER) != si) {
        GLOG(GLOG_VERBOSE, "AI %s: its home %s has fallen: it does nothing", glog_side(si), glog_terr(home));
        return;
    }
    SW(SIDE(si) + S_GOLD, W(SIDE(si) + S_GOLD) + W(SIDE(si) + S_INCOME));
    GLOG(GLOG_NORMAL, "AI %s: its turn: income %d, gold now %d; campaign army at %s: %s, %s, %s",
         glog_side(si), W(SIDE(si) + S_INCOME), W(SIDE(si) + S_GOLD), glog_terr(W(ARMY(si) + A_AT)), glog_count(W(ARMY(si) + A_SOLDIERS), "soldier"),
         glog_count(W(ARMY(si) + A_KNIGHTS), "knight"), glog_count(W(ARMY(si) + A_CATAPULTS), "catapult"));
    ai_reinforce_garrison(si);
    flash_territory(home, 7);
    get_key();
    flash_territory(home, 7);
    get_key();
    int target = 0;
    int16_t path[5] = { 0 };
    int order = ai_choose_order(si, &target, path);
    ai_do_order(si, order, target, path);
    SW(D_LAST_ORDER + 2 * si, order);
}
