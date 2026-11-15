/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * war.c: the armies (AB 2016-21CC), set_owner (423D), side_falls (2406),
 * attack and apply_result (31D5, 33E5), the battles (5781 battle,
 * 57BB battle_shown, 600C battle_auto, 60EB battle_round) and the sieges
 * (74B5, 78A9). See Analysis/GAME_LOGIC.md, "Conquest".
 *
 * The numbers are the original's 16-bit words: the divisions are signed
 * (idiv), the products keep their low word.
 */
#include "war.h"
#include "game.h"
#include "gamelog.h"
#include "month.h"

static int16_t w16(int v) { return (int16_t)(v & 0xFFFF); }

static const char *army_text(int a)
{
    static char b[4][64];
    static int k;
    char *s = b[k++ & 3];
    SDL_snprintf(s, 64, "%s, %s, %s", glog_count(W(a + A_SOLDIERS), "soldier"), glog_count(W(a + A_KNIGHTS), "knight"),
                 glog_count(W(a + A_CATAPULTS), "catapult"));
    return s;
}

/* ------------------------------------------------------------------ the armies */

int army_strength(int a) { return w16(W(a + A_KNIGHTS) * 4 + W(a + A_SOLDIERS)); }
int army_empty(int a)    { return W(a + A_SOLDIERS) == 0 && W(a + A_KNIGHTS) == 0; }

void army_move_to(int si, int t)
{
    SW(SIDE(si) + S_AT, t);
    SW(ARMY(si) + A_BASE, W(ARMY(si) + A_AT));
    SW(ARMY(si) + A_AT, t);
}

void army_go_home(int si)
{
    int h = W(SIDE(si) + S_HOME);
    SW(ARMY(si) + A_AT, h);
    SW(ARMY(si) + A_BASE, h);
    SW(SIDE(si) + S_AT, h);
}

void send_others_home(int t, int except)
{
    for (int si = 1; si < 7; si++)
        if (W(ARMY(si) + A_AT) == t && si != except) army_go_home(si);
}

void send_home_armies_at(int t)
{
    for (int si = 1; si < 7; si++)
        if (W(ARMY(si) + A_AT) == t) army_go_home(si);
}

void army_settle(int si)
{
    if ((int8_t)B(TERR(W(ARMY(si) + A_BASE)) + T_OWNER) != si || w16(W(ARMY(si) + A_SOLDIERS) + W(ARMY(si) + A_KNIGHTS)) <= 0)
        SW(ARMY(si) + A_BASE, W(SIDE(si) + S_HOME));
    SW(ARMY(si) + A_AT, W(ARMY(si) + A_BASE));
    SW(SIDE(si) + S_AT, W(ARMY(si) + A_BASE));
}

void army_merge(int from, int to)
{
    SW(to + A_SOLDIERS, W(to + A_SOLDIERS) + W(from + A_SOLDIERS));
    SW(to + A_KNIGHTS, W(to + A_KNIGHTS) + W(from + A_KNIGHTS));
    SW(to + A_CATAPULTS, W(to + A_CATAPULTS) + W(from + A_CATAPULTS));
    SW(from + A_CATAPULTS, 0);
    SW(from + A_KNIGHTS, 0);
    SW(from + A_SOLDIERS, 0);
}

/* ------------------------------------------------------------------ owners */

/* 423D: the territory flashes, its old colour goes, the new one comes. The
 * CGA and Tandy programs redraw the map afterwards in any case (AA 32F4,
 * AC 335F); the EGA program only when the map is not up (DS:0067 = 0). */
void set_owner(int owner, int t)
{
    int old = (int8_t)B(TERR(t) + T_OWNER);
    GLOG(GLOG_NORMAL, "OWNER %s: %s -> %s", glog_terr(t), old == -1 ? "nobody" : glog_side(old), owner == -1 ? "nobody" : glog_side(owner));
    flash_territory(t, 4);
    if (old != -1) {
        flash_territory(t, 1);
        set_region_colour(t, old);
    }
    SB(TERR(t) + T_OWNER, owner);
    if (owner != -1) {
        set_region_colour(t, owner);
        flash_territory(t, 1);
    }
    flash_territory(t, 4);
    SW(0xC60, W(ARMY(W(D_PLAYER)) + A_AT));
    if (!W(D_MAP_SHOWN)) redraw_map();
}

void side_falls(int side, int winner)
{
    GLOG(GLOG_NORMAL, "FALLS %s: all its territories go to %s", glog_side(side), winner == -1 ? "nobody" : glog_side(winner));
    redraw_map();
    for (int t = 1; t < 19; t++)
        if ((int8_t)B(TERR(t) + T_OWNER) == side) set_owner(winner, t);
}

/* ------------------------------------------------------------------ battle rounds */

static int army_damage(int a, int tactic)   /* 6202 */
{
    int l2 = 32, si = 8;   /* si is not set for a tactic outside 1-5: never the case */
    switch (tactic) {
    case 1: si = 4; break;
    case 2: si = 8; break;
    case 3: si = 4; break;
    case 4: si = 8; break;
    case 5: l2 = 48; si = 16; break;
    default: break;
    }
    int di = w16(W(a + A_SOLDIERS) / l2 + W(a + A_KNIGHTS) / si);
    if (tactic == 3) di = w16(di + random_n(W(a + A_CATAPULTS) + 1));
    return di;
}

static int percent_of_lead(int a, int lead)   /* 627C: (a x lead + 5) / 10 */
{
    return w16((a * lead) + 5) / 10;
}

/* 60EB: the damage each side does in a round, to DS:0B4E (to the defenders) and
 * DS:0B4C (to the attackers). pct takes that much off the attackers' damage
 * (the castle's protection). With tactic 5 (Retreat) only the defenders' damage
 * is worked out: the attackers' is the last round's again (the battle ends before
 * such a round is ever fought). */
static void battle_round(int att, int def, int t, int pct, int tactic)
{
    if (tactic == 5) {
        SW(D_DMG_TO_ATT, army_damage(GARRISON(t), 5));
    } else {
        SW(D_DMG_TO_DEF, army_damage(ARMY(att), tactic));
        SW(D_DMG_TO_ATT, army_damage(GARRISON(t), tactic));
        if (tactic == 4) {
            SW(D_DMG_TO_DEF, W(D_DMG_TO_DEF) - percent_of_lead(W(D_DMG_TO_DEF), W(SIDE(def) + S_LEAD)));
            SW(D_DMG_TO_ATT, W(D_DMG_TO_ATT) - percent_of_lead(W(D_DMG_TO_ATT), W(SIDE(att) + S_LEAD)));
        } else {
            SW(D_DMG_TO_DEF, W(D_DMG_TO_DEF) + percent_of_lead(W(D_DMG_TO_DEF), W(SIDE(att) + S_LEAD)));
            SW(D_DMG_TO_ATT, W(D_DMG_TO_ATT) + percent_of_lead(W(D_DMG_TO_ATT), W(SIDE(def) + S_LEAD)));
        }
    }
    SW(D_DMG_TO_DEF, W(D_DMG_TO_DEF) + random_n(3));
    SW(D_DMG_TO_DEF, W(D_DMG_TO_DEF) - w16(pct * W(D_DMG_TO_DEF) + 50) / 100);
    if (W(D_DMG_TO_DEF) < 0) SW(D_DMG_TO_DEF, 0);
    SW(D_DMG_TO_ATT, W(D_DMG_TO_ATT) + random_n(3));
    if (W(D_DMG_TO_ATT) < 0) SW(D_DMG_TO_ATT, 0);
}

static void take_losses(int a, int n)   /* 6290: soldiers first, then knights */
{
    while (n-- > 0) {
        if (W(a + A_SOLDIERS) > 0) SW(a + A_SOLDIERS, W(a + A_SOLDIERS) - 1);
        else if (W(a + A_KNIGHTS) > 0) SW(a + A_KNIGHTS, W(a + A_KNIGHTS) - 1);
    }
}

static void round_and_losses(int att, int def, int t, int pct, int tactic, bool log)
{
    battle_round(att, def, t, pct, tactic);
    take_losses(GARRISON(t), W(D_DMG_TO_DEF));
    take_losses(ARMY(att), W(D_DMG_TO_ATT));
    if (log) GLOG(GLOG_VERBOSE, "ROUND tactic %d: the attackers lose %d, the defenders %d (protection %d%%); attackers now %s, defenders %s",
         tactic, W(D_DMG_TO_ATT), W(D_DMG_TO_DEF), pct, army_text(ARMY(att)), army_text(GARRISON(t)));
}

/* 600C: a battle the player is not in, fought out at once with Stand and Fight */
static int battle_auto(int att, int def, int t, int pct)
{
    if (W(ARMY(def) + A_AT) == t) army_merge(ARMY(def), GARRISON(t));
    for (;;) {
        round_and_losses(att, def, t, pct, 2, true);
        if (army_empty(GARRISON(t)) && army_empty(ARMY(att))) return 7;
        if (army_empty(GARRISON(t))) return 4;
        if (army_empty(ARMY(att))) return 5;
    }
}

/* ------------------------------------------------------------------ the battle shown (57BB) */

/* 5684: "Your Army / Enemy Army" with the numbers; the space is drawn as
 * the font's '>' while the lines are put (the table's columns) */
static void show_armies(int enemy, int yours)
{
    gfx_glyph_alias(0x20, 0x3E);
    static const int LINE[3] = { 0x35DF, 0x35E1, 0x35E3 }, TEXT[3] = { 0x4118, 0x412B, 0x413E }, FIELD[3] = { A_SOLDIERS, A_KNIGHTS, A_CATAPULTS };
    for (int i = 0; i < 3; i++) {
        int bx = W(LINE[i]);
        SB(bx, ' ');
        SB(bx + 1, ' ');
        int e = num_append((unsigned)W(yours + FIELD[i]), bx + 2);
        e = str_append(TEXT[i], e);
        e = num_append((unsigned)W(enemy + FIELD[i]), e);
        SB(e, '>');
        SB(e + 1, 0);
    }
    dialog(0x35D2);
    gfx_glyph_alias(0x20, -1);
}

static void cursor_rect(int x, int y, int w)  { gfx_xor_rect3(x, y, w, 11, 0xFFFF, 0x0F0F, 0xFFFF); }
static void chosen_rect(int x, int y, int w)  { gfx_xor_rect3(x, y, w, 11, 0x5555, 0x0F04, 0x8888); }

static void slot(int k, int xpx, int y, int item)
{
    gfx_video()->slot[k] = (Slot){ true, xpx, y, F_SWORD, item, 0, 0, 0 };
}

/* The player's battle: a1 attacks territory a3 of side a2, pct the castle's
 * protection. The tactic (Ferocious Attack, Stand and Fight, Bombard, Outflank,
 * Retreat!) is chosen with Up, Down and Enter; a round takes 28 ticks, in which
 * the men are animated (BN items 160-181) and the choice can change. */
static int battle_shown(int a1, int a2, int a3, int a4)
{
    int p = W(D_PLAYER);
    if (w16(W(GARRISON(a3) + A_SOLDIERS) + W(GARRISON(a3) + A_KNIGHTS)) <= 0) {
        redraw_map();
        if (a1 == p) dialog(0x3607);
        play_tune(0x9C, W(D_TUNE_STOP));
        GLOG(GLOG_NORMAL, "BATTLE no men defend %s", glog_terr(a3));
        return 4;
    }
    if (!W(D_SIEGE_SHOWN)) {
        redraw_map();
        if (a1 == p) {
            int e = str_append(W(ARMY(a2) + A_AT) == a3 ? 0x4150 : 0x4171, W(0x221F));
            str_append(W(SIDE(a2) + S_NAME), e);
            dialog(0x2212);
        } else {
            int e = str_append(0x4192, W(0x2294));
            str_append(W(SIDE(a1) + S_NAME), e);
            /* the territory's name is taken with the defender's side number (AB 58D1; --fix=battle-text) */
            e = str_append(0x41AC, W(0x2296));
            str_append(W(TERR(fixed(FIX_BATTLE_TEXT) ? a3 : a2) + T_NAME), e);
            dialog(0x2287);
        }
        play_tune(0x9C, W(D_TUNE_LOOP));
    }
    SW(D_MAP_SHOWN, 0);
    SW(D_SIEGE_SHOWN, 0);
    gfx_clear_back(0);
    dialog(0x3582);
    int last = 4;   /* the last tactic that can be chosen: Retreat */
    int l4 = GARRISON(a3), l2 = ARMY(a1);   /* l4 the enemy's army, l2 the player's */
    if (p == a2) {
        l4 = ARMY(a1);
        l2 = GARRISON(a3);
        if (W(ARMY(p) + A_AT) != a3 || W(SIDE(p) + S_HOME) == a3) last = 3;
    }
    GLOG(GLOG_NORMAL, "BATTLE (shown) %s attacks %s of %s: attackers %s, defenders %s%s", glog_side(a1), glog_terr(a3), glog_side(a2),
         army_text(ARMY(a1)), army_text(GARRISON(a3)), last == 4 ? "" : " (no retreat)");
    SW(0xB50, 1);
    show_armies(l4, l2);
    SB(0x35D6, 0xFE);
    int chosen = 1, shown = 1, sel = 1;
    SB(0x35D6, 0);
    flush_keys();
    int hx = (int8_t)B(0x3582) + 4, hw = (int8_t)B(0x3585) - 8, y0 = B(0x3583);
    int hy = y0 + 22;
    cursor_rect(hx, hy, hw);
    chosen_rect(hx, hy, hw);
    int group = 3, men = 75, knights = 30;
    int l34 = W(l4 + A_SOLDIERS), l32 = W(l2 + A_SOLDIERS), l30 = W(l4 + A_KNIGHTS), l28 = W(l2 + A_KNIGHTS);
    uint32_t tick = sys_ticks() - 1;   /* the original compares with locals not yet set: the first frame comes at once */
    static const char *const TACTIC[5] = { "Ferocious Attack", "Stand and Fight", "Bombard", "Outflank", "Retreat!" };
    for (;;) {
        round_and_losses(a1, a2, a3, a4, chosen + 1, false);
        GLOG(GLOG_NORMAL, "BATTLE round with %s: the attackers lose %d, the defenders %d; you have %s, the enemy %s",
             TACTIC[chosen], W(D_DMG_TO_ATT), W(D_DMG_TO_DEF), army_text(l2), army_text(l4));
        for (int frames = 28; frames; ) {
            int key = get_key() & 0xFF;
            if (key) {
                if (key == KEY_ENTER) {
                    if (chosen != sel) {
                        chosen_rect(hx, (chosen + 1) * 11 + y0, hw);
                        chosen = sel;
                        chosen_rect(hx, hy, hw);
                        GLOG(GLOG_NORMAL, "YOU tactic: %s", TACTIC[chosen]);
                    }
                } else if (key == KEY_UP) {
                    if (--sel < 0) sel = last;
                } else if (key == KEY_DOWN) {
                    if (++sel > last) sel = 0;
                }
                if (sel != shown) {
                    shown = sel;
                    cursor_rect(hx, hy, hw);
                    hy = (sel + 1) * 11 + y0;
                    cursor_rect(hx, hy, hw);
                }
            }
            uint32_t now = sys_ticks();
            if (now != tick) {
                tick = now;
                frames--;
                men -= 25;
                knights -= 10;
                if (--group < 0) { group = 2; men = 50; knights = 20; }
                int l22 = 160 + random_n(4), l20 = 170 + random_n(4);
                int g2 = 2 * group;
                if (group < 2) {
                    if (W(l2 + A_KNIGHTS) > knights) gfx_put_sprite(B(0xB34 + g2), B(0xB35 + g2), F_SWORD, 180);
                    else if (l28 > knights) { l28 = knights; gfx_xor_sprite(B(0xB34 + g2), B(0xB35 + g2), F_SWORD, 180); }
                    if (W(l4 + A_KNIGHTS) > knights) gfx_put_sprite(B(0xB3A + g2), B(0xB3B + g2), F_SWORD, 181);
                    else if (l30 > knights) { l30 = knights; gfx_xor_sprite(B(0xB3A + g2), B(0xB3B + g2), F_SWORD, 181); }
                }
                if (W(l2 + A_SOLDIERS) > men) {
                    slot(9 + group, B(0xB40 + g2) * 4, B(0xB41 + g2) + 24, 165);
                    slot(6 + group, B(0xB40 + g2) * 4, B(0xB41 + g2), l22);
                } else if (l32 > men) {
                    l32 = men;
                    slot(6 + group, B(0xB40 + g2) * 4, B(0xB41 + g2) + 32, 169);
                }
                if (W(l4 + A_SOLDIERS) > men) {
                    slot(3 + group, (B(0xB46 + g2) + 8) * 4, B(0xB47 + g2) + 24, 175);
                    slot(group, B(0xB46 + g2) * 4, B(0xB47 + g2), l20);
                } else if (l34 > men) {
                    l34 = men;
                    slot(group, B(0xB46 + g2) * 4, B(0xB47 + g2) + 32, 179);
                }
            }
            gfx_sprites_draw();
            present();
            gfx_sprites_erase();
        }
        for (int k = 0; k < NUM_SLOTS; k++) gfx_video()->slot[k].active = false;
        SW(0xB50, 0);
        if (W(l4 + A_SOLDIERS) + W(l4 + A_KNIGHTS) == 0) SW(l4 + A_CATAPULTS, 0);
        if (W(l2 + A_SOLDIERS) + W(l2 + A_KNIGHTS) == 0) SW(l2 + A_CATAPULTS, 0);
        show_armies(l4, l2);
        int morale, result;
        if (chosen == 4) {
            morale = -3;
            if ((int8_t)B(TERR(a3) + T_OWNER) == p) {
                army_merge(GARRISON(a3), ARMY(p));
                army_settle(p);
                result = 4;
            } else {
                result = 6;
            }
            GLOG(GLOG_NORMAL, "BATTLE you retreat");
        } else if (army_empty(GARRISON(a3)) && army_empty(ARMY(a1))) {
            morale = -1; result = 7;
        } else if (army_empty(GARRISON(a3))) {
            morale = p == a2 ? -3 : 3; result = 4;
        } else if (army_empty(ARMY(a1))) {
            morale = p == a2 ? 3 : -3; result = 5;
        } else {
            continue;
        }
        morale_add(morale);
        GLOG(GLOG_NORMAL, "BATTLE over: result %d, morale %+d (now %d)", result, morale, W(D_MORALE));
        wait_ticks(27);
        play_tune(0x9C, W(D_TUNE_STOP));
        return result;
    }
}

static int battle(int att, int def, int t, int pct, int shown)   /* 5781 */
{
    if (shown) {
        int r = battle_shown(att, def, t, pct);
        redraw_map();
        return r;
    }
    GLOG(GLOG_NORMAL, "BATTLE %s attacks %s of %s: attackers %s, defenders %s%s", glog_side(att), glog_terr(t), glog_side(def),
         army_text(ARMY(att)), army_text(GARRISON(t)), W(ARMY(def) + A_AT) == t ? " (and its campaign army)" : "");
    return battle_auto(att, def, t, pct);
}

/* ------------------------------------------------------------------ sieges (74B5) */

/* ------------------------------------------------------------------ the player's siege (763E) */

#define D_SIEGE_BOULDERS 0x0A82
#define D_SIEGE_AMMO     0x0A84   /* the ammunition chosen last (the menu starts on it) */
#define D_SIEGE_DISEASE  0x0A86
#define D_SIEGE_DAYS     0x0A88
#define D_SIEGE_WALL     0x0A8A   /* the wall's height (6 at first) */
#define D_SIEGE_FIRE     0x0A8C
#define D_SIEGE_HOLE     0x0A8E   /* the Bd item of the hole in the wall (3-7) */

/* The catapult and its shots are Bd sprites (F_SIEGE) at x 39 (the shot 41) in
 * 4-pixel units; the Tandy program puts them one unit to the left (AC 62D1). */
static void siege_slot(int k, int x, int y, int item)
{
    gfx_video()->slot[k] = (Slot){ true, x * 4, y, F_SIEGE, item, 0, -4, 0 };
}

/* 7505: "Load Ammunition": Greek Fire, Disease, Boulders (while there are any)
 * or Cease Fire (4) */
static int choose_ammo(int t)
{
    if (W(GARRISON(t) + A_SOLDIERS) <= 0) SW(GARRISON(t) + A_SOLDIERS, 1);
    for (;;) {
        num_append((unsigned)W(D_SIEGE_DAYS), str_append(0x41D4, W(0x3692)));
        num_append((unsigned)w16(W(GARRISON(t) + A_SOLDIERS) + W(GARRISON(t) + A_KNIGHTS)), str_append(0x41EE, W(0x3694)));
        num_append((unsigned)W(D_SIEGE_FIRE), str_append(0x41FF, W(0x3698)));
        num_append((unsigned)W(D_SIEGE_DISEASE), str_append(0x4212, W(0x369A)));
        num_append((unsigned)W(D_SIEGE_BOULDERS), str_append(0x4225, W(0x369C)));
        SB(0x368A, W(D_SIEGE_AMMO) + 4);
        int c = dialog(0x3683);
        SW(D_SIEGE_AMMO, c);
        static const int LEFT[4] = { D_SIEGE_FIRE, D_SIEGE_DISEASE, D_SIEGE_BOULDERS, 0 };
        if (c == 4) return c;
        if (c >= 1 && c <= 3 && W(LEFT[c - 1])) {
            SW(LEFT[c - 1], W(LEFT[c - 1]) - 1);
            return c;
        }
    }
}

/* 7168: Enter starts drawing the arm back, Enter again (or the arm at its
 * furthest) lets go; returns the shot's height 0-7 ((tension - 140) / 2). With
 * Greek Fire its flame (Bd 52) is XORed at the arm each step, so it flickers. The
 * steps go at the screen's pace: the delay_ticks(1) between them end at once (they
 * count the first tick change at once). */
static int catapult_aim(int ammo)
{
    Video *v = gfx_video();
    int si = 136;
    present();
    gfx_set_palette();
    siege_slot(0, 39, si, ammo * 14 - 4);
    gfx_sprites_draw();
    present();
    for (;;) {
        if (get_key() == KEY_ENTER) break;
        if (ammo == 1) { gfx_xor_sprite_t(39, 38, si, F_SIEGE, 52); present(); }
        delay_ticks(1);
    }
    SW(0x8C7, 1);
    for (;;) {
        if (get_key() == KEY_ENTER) break;
        if (++si > 159) break;
        gfx_sprites_erase();
        v->slot[0].y = si;
        gfx_sprites_draw();
        delay_ticks(1);
        if (ammo == 1) gfx_xor_sprite_t(39, 38, si, F_SIEGE, 52);
        present();
        delay_ticks(1);
    }
    SW(0x8C7, 3);
    int h = w16(si - 140) / 2;
    if (h < 0) h = 0;
    else if (h > 7) h = 7;
    GLOG(GLOG_NORMAL, "SIEGE you let go at tension %d: height %d", si, h);
    while (si > 136) {   /* the arm goes forward */
        gfx_sprites_erase();
        si -= 8;
        v->slot[0].y = si;
        gfx_sprites_draw();
        present();
    }
    static const struct { int item, y; } SWING[3] = { { -3, 132 }, { 8, 146 }, { 9, 125 } };
    for (int i = 0; i < 3; i++) {
        gfx_sprites_erase();
        v->slot[0].item = SWING[i].item < 0 ? ammo * 14 + SWING[i].item : SWING[i].item;
        v->slot[0].y = SWING[i].y;
        v->slot[0].x = 39 * 4;
        gfx_sprites_draw();
        present();
    }
    si = 125;
    int item = ammo * 14 - 2;   /* the shot leaves the arm */
    while (si > 112) {
        gfx_sprites_erase();
        si -= 3;
        siege_slot(1, 41, si, item);
        v->slot[1].tandy_dx = 0;   /* the Tandy program too has it at 41 here (AC 6449) */
        gfx_sprites_draw();
        present();
    }
    item = ammo * 14 - 1;
    while (si > 100) {
        gfx_sprites_erase();
        si -= 3;
        siege_slot(1, 41, si, item);
        v->slot[1].tandy_dx = 0;   /* the Tandy program too has it at 41 here (AC 6449) */
        gfx_sprites_draw();
        present();
    }
    gfx_sprites_erase();
    v->slot[1].active = false;   /* the catapult (slot 0) stays */
    return h;
}

/* 739D: the shot's flight, 30 frames: its height by the table DS:0992 (30 bytes
 * for each height 0-7), its picture one of 10 (ammo x 14 + 0..9), the next every
 * 3 frames. (The x would move on at frame 10, but the test is made only at frames
 * 2, 5, 8, 11 ...: it never does.) */
static void show_shot(int h, int ammo)
{
    Video *v = gfx_video();
    int di = 41, l2 = 0, l4 = ammo * 14;
    while ((unsigned)l2 < 29) {
        siege_slot(1, di, B(0x992 + h * 30 + l2), l4);
        gfx_sprites_draw(); present(); gfx_sprites_erase();
        l2++;
        wait_ticks(1);
        v->slot[1].y = B(0x992 + h * 30 + l2);
        gfx_sprites_draw(); present(); gfx_sprites_erase();
        l2++;
        wait_ticks(1);
        int y = B(0x992 + h * 30 + l2);
        if (l2 == 10) di++;
        v->slot[1].y = y;
        v->slot[1].x = di * 4;
        gfx_sprites_draw(); present(); gfx_sprites_erase();
        l2++;
        l4++;
        wait_ticks(1);
    }
    v->slot[1].active = false;
    gfx_sprites_draw(); present(); gfx_sprites_erase();
}

/* 763E: up to 6 days of bombardment, then the battle with the castle's
 * protection (90%, less 15 for each boulder that hit the wall) */
static int siege_by_player(int def, int t)
{
    int p = W(D_PLAYER), prot = 90;
    redraw_map();
    if (W(ARMY(p) + A_CATAPULTS) == 0) {
        dialog(0x295E);
        GLOG(GLOG_NORMAL, "SIEGE you have no catapult for the castle of %s: you retreat", glog_terr(t));
        return 3;
    }
    dialog(0x2AB7);
    /* with less than 8 blocks of memory Bd was loaded over BN here and DS:0067 cleared; the remake has all of them */
    play_tune(0x9C, W(D_TUNE_LOOP));
    gfx_show_picture((int8_t)B(TERR(t) + T_OWNER) >= 4 ? PIC_SIEGE1 : PIC_SIEGE2);
    gfx_copy_page(PAGE_SAVE, PAGE_BACK);
    SW(D_SIEGE_AMMO, 1);
    GLOG(GLOG_NORMAL, "SIEGE you besiege the castle of %s (%s): its garrison %s", glog_terr(t), glog_side(def), army_text(GARRISON(t)));
    static const char *const AMMO[5] = { "", "Greek Fire", "Disease", "Boulders", "Cease Fire" };
    while (W(D_SIEGE_DAYS)) {
        int ammo = choose_ammo(t);
        gfx_copy_page(PAGE_BACK, PAGE_SAVE);
        if (ammo >= 4) {
            SW(D_SIEGE_DAYS, 1);
            GLOG(GLOG_NORMAL, "SIEGE you cease fire");
        } else {
            int h = catapult_aim(ammo);
            show_shot(h, ammo);
            int g = GARRISON(t), before = W(g + A_SOLDIERS);
            if (h && h < 7) {
                switch (ammo) {
                case 1:
                    if (h > W(D_SIEGE_WALL)) {
                        int s = W(g + A_SOLDIERS);
                        SW(g + A_SOLDIERS, W(g + A_SOLDIERS) - w16(s / (random_n(25) + 6)));
                    }
                    break;
                case 2:
                    if (h > W(D_SIEGE_WALL))
                        SW(g + A_SOLDIERS, W(g + A_SOLDIERS) - w16(W(g + A_SOLDIERS) * W(D_SIEGE_DAYS)) / 15);
                    break;
                case 3:
                    if (h == W(D_SIEGE_WALL)) {
                        SW(D_SIEGE_WALL, W(D_SIEGE_WALL) - 1);
                        prot -= 15;
                        SW(D_SIEGE_HOLE, W(D_SIEGE_HOLE) + 1);
                        if (W(D_SIEGE_HOLE) > 7) SW(D_SIEGE_HOLE, 7);
                        Video *v = gfx_video();
                        siege_slot(1, 39, 75, W(D_SIEGE_HOLE));   /* stamped on the picture: drawn, then left out of the erase */
                        gfx_sprites_draw();
                        present();
                        v->slot[1].active = false;
                        gfx_sprites_erase();
                        v->slot[0].active = false;
                        GLOG(GLOG_NORMAL, "SIEGE the boulder breaks the wall: now %d high, the castle protects %d%%", W(D_SIEGE_WALL), prot);
                    }
                    break;
                default:
                    break;
                }
                if (W(g + A_SOLDIERS) <= 0) SW(g + A_SOLDIERS, 1);
            }
            GLOG(GLOG_NORMAL, "SIEGE day %d: %s at height %d (the wall is %d high): %s; the garrison has %s", 7 - W(D_SIEGE_DAYS),
                 AMMO[ammo], h, W(D_SIEGE_WALL), !h || h >= 7 ? "a miss" : before != W(g + A_SOLDIERS) ? "it kills" : "no harm",
                 army_text(g));
        }
        gfx_copy_page(PAGE_SAVE, PAGE_BACK);
        SW(D_SIEGE_DAYS, W(D_SIEGE_DAYS) - 1);
        delay_ticks(27);
    }
    SW(D_SIEGE_SHOWN, 1);
    /* only a boulder's hit clears the catapult's slot: otherwise it is drawn over the battle's first
     * frames (--fix=siege-sprite clears it) */
    if (fixed(FIX_SIEGE_SPRITE)) gfx_video()->slot[0].active = false;
    return battle(p, def, t, prot, 1);
}

/* 78A9: a computer lord besieges a castle (the player's or another's): the
 * castle protects 45, 30 or 15 percent, the garrison loses some men, then the
 * battle (shown when the player defends) */
static int siege_of_player(int att, int def, int t, int shown)
{
    int p = W(D_PLAYER);
    if (W(ARMY(att) + A_CATAPULTS) == 0) {
        GLOG(GLOG_NORMAL, "SIEGE %s has no catapult for the castle of %s", glog_side(att), glog_terr(t));
        return 6;
    }
    if (p == def) {
        SW(D_SIEGE_SHOWN, 1);
        play_tune(0x9C, W(D_TUNE_LOOP));
        if (W(SIDE(p) + S_HOME) == t) {
            int e = str_append(0x4238, W(0x29B6));
            str_append(W(SIDE(att) + S_NAME), e);
            dialog(0x29A9);
        } else {
            int e = str_append(0x4261, W(0x2A5E));
            str_append(W(TERR(t) + T_NAME), e);
            e = str_append(0x4290, W(0x2A60));
            str_append(W(SIDE(att) + S_NAME), e);
            dialog(0x2A51);
        }
    }
    int pct = w16(90 - (random_n(3) + 3) * 15);
    int soldiers = W(GARRISON(t) + A_SOLDIERS);
    int lost = w16(soldiers / (random_n(7) + 2));
    if (!lost) lost = 1;
    SW(GARRISON(t) + A_SOLDIERS, W(GARRISON(t) + A_SOLDIERS) - lost);
    if (W(GARRISON(t) + A_SOLDIERS) <= 0) SW(GARRISON(t) + A_SOLDIERS, 1);
    GLOG(GLOG_NORMAL, "SIEGE %s besieges the castle of %s (%s): protection %d%%, the garrison loses %s", glog_side(att),
         glog_terr(t), glog_side(def), pct, glog_count(lost, "soldier"));
    if (p == def) {
        redraw_map();
        int e = str_append(0x42AA, W(0x2A97));
        e = num_append((unsigned)pct, e);
        str_append(0x42C3, e);
        if (lost == 1) str_append(0x42CD, W(0x2A99));
        else str_append(0x42F2, num_append((unsigned)lost, W(0x2A99)));
        dialog(0x2A8A);
    }
    return battle(att, def, t, pct, shown);
}

static int siege(int att, int def, int t, int shown)
{
    SW(0xA82, 6);
    SW(0xA8C, 2);
    SW(0xA86, 1);
    SW(0xA88, 6);
    SW(0xA8E, 2);
    SW(0xA8A, 6);
    if (att == W(D_PLAYER)) return siege_by_player(def, t);
    return siege_of_player(att, def, t, shown);
}

/* ------------------------------------------------------------------ attack (31D5) */

/* 331C: entering the land of one of the other Saxons (2, 3) whose enmity to
 * the player is 0 or less: "Do you seek safe passage through my land?" Accept:
 * the army passes (1). Attack: both Saxons +5 against the player. */
static int ask_passage(int t)
{
    int p = W(D_PLAYER), si = (int8_t)B(TERR(t) + T_OWNER);
    if ((unsigned)si > 3 || si == p || W(ENMITY(si, p)) > 0) return 0;
    redraw_map();
    show_portrait(W(SIDE(si) + S_PORTRAIT), 9, 3);
    SW(0x2F64, W(SIDE(si) + S_NAME));
    SB(0x2F59, 1);
    dialog(0x2F59);
    if (dialog(0x36CC) == 1) {
        GLOG(GLOG_NORMAL, "PASSAGE %s offers safe passage through %s: you accept", glog_side(si), glog_terr(t));
        return 1;
    }
    enmity_add(2, p, 5);
    enmity_add(3, p, 5);
    GLOG(GLOG_NORMAL, "PASSAGE %s offers safe passage through %s: you attack (sides 2 and 3 +5 against you)", glog_side(si), glog_terr(t));
    return 0;
}

static void apply_result(int att, int def, int t, int r)   /* 33E5 */
{
    static const char *const R[9] = { "", "its own territory", "no defense", "no catapult: back", "the attackers win",
                                      "the defenders win", "no army: back", "both armies are lost", "safe passage" };
    GLOG(GLOG_NORMAL, "RESULT %d (%s): %s at %s", r, r >= 1 && r <= 8 ? R[r] : "?", glog_side(att), glog_terr(t));
    switch (r) {
    case 2:
        set_owner(att, t);
        break;
    case 3:
    case 6:
        army_settle(att);
        break;
    case 4:
        enmity_add(def, att, 6);
        if (W(SIDE(W(D_PLAYER)) + S_HOME) != t) set_owner(att, t);
        if (W(SIDE(def) + S_HOME) == t) {
            side_falls(def, att);
            SW(ARMY(def) + A_AT, -1);
            SW(SIDE(def) + S_AT, -1);
            SW(ARMY(def) + A_CATAPULTS, 0);
            SW(ARMY(def) + A_KNIGHTS, 0);
            SW(ARMY(def) + A_SOLDIERS, 0);
        }
        SW(GARRISON(t) + A_CATAPULTS, 0);
        send_others_home(t, att);
        break;
    case 5:
        enmity_add(def, att, 6);
        SW(ARMY(att) + A_CATAPULTS, 0);
        army_go_home(att);
        if (W(ARMY(def) + A_AT) == t) army_merge(GARRISON(t), ARMY(def));
        break;
    case 7:
        enmity_add(def, att, 6);
        SW(ARMY(att) + A_CATAPULTS, 0);
        SW(GARRISON(t) + A_CATAPULTS, 0);
        send_home_armies_at(t);
        if (W(SIDE(def) + S_HOME) != t) set_owner(-1, t);
        break;
    default:
        break;
    }
}

int attack(int att, int def, int t)
{
    int p = W(D_PLAYER);
    if (army_strength(ARMY(att)) == 0 && (int8_t)B(TERR(t) + T_OWNER) != att) return 6;
    int shown = 0;
    if (att == p) shown = 1;
    else if (def == p && (B(TERR(t) + T_CASTLE) || W(SIDE(p) + S_AT) == t)) shown = 1;
    int r;
    if (att == p && ask_passage(t)) r = 8;
    else if ((int8_t)B(TERR(t) + T_OWNER) == att) r = 1;
    else if ((int8_t)B(TERR(t) + T_OWNER) == -1) r = 2;
    else {
        /* the defending army joins the garrison before the siege looks for a catapult, and stays
         * joined if there is none (--fix=siege-merge: only when the siege goes ahead) */
        bool refused = B(TERR(t) + T_CASTLE) && !W(ARMY(att) + A_CATAPULTS);
        if (W(ARMY(def) + A_AT) == t && !(refused && fixed(FIX_SIEGE_MERGE))) army_merge(ARMY(def), GARRISON(t));
        if (B(TERR(t) + T_CASTLE)) r = siege(att, def, t, shown);
        else r = battle(att, def, t, 0, shown);
    }
    apply_result(att, def, t, r);
    return r;
}
