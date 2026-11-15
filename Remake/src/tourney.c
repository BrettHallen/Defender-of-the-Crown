/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * tourney.c: the tournament (AB 62BC, tournament_goodwill 26AA), a round
 * of it (joust_round 6475, choose_opponent 7094), the knights riding in
 * (joust_approach 6850), the joust down the lane (joust 6EC2, lance_step
 * 6B09) and its outcome over the stands (joust_outcome 6C59). See
 * Analysis/GAME_LOGIC.md, "Tournaments".
 *
 * Checked in DOSBox (EGA): the 51 steps of the lance take 51 frames (60 a
 * second) and the outcome's 41 frames as many, their one-tick waits ending at
 * once; the approach's frames come 2 ticks apart, then 1.
 *
 * The CGA program (AA) also moves the CRT controller's display start a line
 * with the gallop (crtc_write 8457), but only on GameSYS's configuration 2: left
 * out. The CGA and Tandy programs compare the joust's numbers signed where the
 * EGA one compares them unsigned (see joust); the remake goes by the EGA one.
 */
#include "tourney.h"
#include "raid.h"
#include "conquest.h"
#include "war.h"
#include "game.h"
#include "gamelog.h"
#include "month.h"

#define D_BANNED     0x003D   /* disgraced: no more tournaments */
#define D_LAST_TOURN 0x0041   /* year x 12 + month of the last tournament */
#define D_IN_TOURN   0x0D16   /* words by side: still in the tournament */
#define D_OPPONENT   0x0D10   /* the opponent shown (and who takes or loses the land) */
#define D_LANCE_X    0x0D0C   /* the lance's point, 20-50 (4-pixel units) */
#define D_LANCE_Y    0x0D14   /* 120-180 */
#define D_GALLOP     0x005F   /* the lance's step: the speaker's divisor */
#define D_BOB_LEFT   0x0061   /* steps until the bob turns */
#define D_BOB        0x0063   /* the bob: +-2 lines a step */
#define D_HOOVES     0x0065   /* the outcome's beat */

static int16_t w16(int v) { return (int16_t)(v & 0xFFFF); }

static int lance_item;   /* DS:0D0E: the lance (BK item 20) */

static void slot_set(int k, int xpx, int y, FileId f, int item, int rows)
{
    gfx_video()->slot[k] = (Slot){ true, xpx, y, f, item, 0, 0, rows, 0 };
}

/* the same in the booter's modes, and in the CGA (1987) mode the DOS version's sprite
 * at its own place (slot k + 2) */
static void slot_set2(int k, int xpx, int y, FileId f, int item, int dos_xpx, int dos_y, int dos_item)
{
    Slot *s = gfx_video()->slot;
    s[k] = (Slot){ true, xpx, y, f, item, 0, 0, 0, BOOT_MODES };
    s[k + 2] = (Slot){ DOS_MODES != 0, dos_xpx, dos_y, f, dos_item, 0, 0, 0, DOS_MODES };
}

static void slots_off(void)
{
    for (int k = 0; k < 4; k++) { gfx_video()->slot[k].active = false; gfx_video()->slot[k].modes = 0; }
}

static void next_beat(int addr)   /* the gallop's pitch falls by 500 a step, from 30000 to 28500 and round again */
{
    SW(addr, W(addr) - 500);
    if (W(addr) < 0x6F54) SW(addr, 0x7530);
}

/* ------------------------------------------------------------------ the knights ride in (6850) */

/* over the tournament from above (CH): the first knight rides in (BJ 2-22, x 41
 * to 61), turns (23, 24) and rides back (25-29) while the other comes in
 * (30-35, x 15 on); then the two portraits and names, and "An expectant hush..." */
static void joust_approach(void)
{
    int p = W(D_PLAYER);
    gfx_show_picture(PIC_TOURNAMENT);
    /* the DOS version (02D3:0737) puts the same items 2 units further on and 2 lines
     * higher (x 43-63, y 74), turns with 24 and 25 (at 62 and 61), and so rides back
     * with the next item each time; its other knight starts a unit on (16, y 86) */
    int di = 41, si;
    for (si = 2; si < 23; si++) {
        slot_set2(0, di * 4, 76, F_TOURN, si, (di + 2) * 4, 74, si);
        di++;
        gfx_sprites_draw(); present(); gfx_sprites_erase();
        wait_ticks(3);
        get_key();
    }
    for (int k = 0; k < 2; k++) {
        slot_set2(0, 60 * 4, 76, F_TOURN, si, (62 - k) * 4, 74, si + 1);
        si++;
        gfx_sprites_draw(); present(); gfx_sprites_erase();
        wait_ticks(3);
    }
    di = 60;
    int x2 = 15;
    while (si < 30) {
        slot_set2(0, di * 4, 76, F_TOURN, si, di * 4, 74, si + 1);
        di--;
        si++;
        gfx_sprites_draw(); present(); gfx_sprites_erase();
        wait_ticks(1);
        slot_set2(1, x2 * 4, 88, F_TOURN, si + 4, (x2 + 1) * 4, 86, si + 4);
        x2++;
        gfx_sprites_draw(); present(); gfx_sprites_erase();
        wait_ticks(2);
        get_key();
    }
    slot_set2(1, x2 * 4, 88, F_TOURN, si + 5, x2 * 4, 86, si + 5);
    gfx_sprites_draw(); present(); gfx_sprites_erase();
    slots_off();
    wait_ticks(g_dos_rules ? 9 : 4);   /* DOC 02D3:0737: 9 */
    int o = W(D_OPPONENT);
    show_portrait(W(SIDE(o) + S_PORTRAIT), 9, 3);
    SW(0x2F64, W(SIDE(o) + S_NAME));
    SB(0x2F59, 1);
    dialog(0x2F59);
    show_portrait(W(SIDE(p) + S_PORTRAIT) + W(0x9D), 53, 3);
    SW(0x2F64, W(SIDE(p) + S_NAME));
    SB(0x2F59, 45);
    dialog(0x2F59);
    dialog(0x2E9E);
    lance_item = 20;
}

/* ------------------------------------------------------------------ the joust (6EC2) */

/* 6B09: a step of the charge, one a screen refresh: the keypad moves the
 * lance's point by the table DS:0CDC (7/8/9 up, 1/2/3 down, 4/6 and the
 * diagonals sideways; x only moves on a step that also shows the opponent, or
 * when the key moves it), the gallop bobs it up and down (DS:0063, turned every
 * 6 steps and at the ends); `item` is the opponent's next picture (BK 3-19 at
 * DS:0C8C) or 0 */
static void lance_step(int item)
{
    snd_speaker_tone(W(D_GALLOP));
    int si = get_key() - 0x47;
    if (si < 0 || si > 10) si = 3;
    if (item) {
        int x = W(0xC8C + 4 * item) * 4, y = W(0xC8E + 4 * item) + 1;
        slot_set(1, x, y, F_LANE, item, 0);
        gfx_video()->slot[1].modes = BOOT_MODES;
        /* DOC 02D3:0AAE: put whole and left on the picture (each picture covers the last
         * and the distant knight the lane picture starts with); its own y (oy -1) */
        gfx_put_sprite_m(DOS_MODES, x / 4, y, F_LANE, item);
    }
    int dx = W(0xCDC + 4 * si);
    if (dx || item) {
        SW(D_LANCE_X, W(D_LANCE_X) + dx);
        if (W(D_LANCE_X) < 20) SW(D_LANCE_X, 20);
        else if (W(D_LANCE_X) > 50) SW(D_LANCE_X, 50);
    }
    SW(D_LANCE_Y, W(D_LANCE_Y) + W(0xCDE + 4 * si) + W(D_BOB));
    if (W(D_LANCE_Y) > 180) { SW(D_LANCE_Y, 180); SW(D_BOB_LEFT, 1); }
    else if (W(D_LANCE_Y) < 120) { SW(D_LANCE_Y, 120); SW(D_BOB_LEFT, 1); }
    slot_set(0, W(D_LANCE_X) * 4, W(D_LANCE_Y), F_LANE, lance_item, 0);
    gfx_sprites_draw();
    present_bottom();
    gfx_sprites_erase();
    SW(D_BOB_LEFT, W(D_BOB_LEFT) - 1);
    if (!W(D_BOB_LEFT)) { SW(D_BOB_LEFT, 6); SW(D_BOB, -W(D_BOB)); }
    beep(W(D_GALLOP), 1);
    next_beat(D_GALLOP);
}

/* 6C59: over the stands (CJ), the script BJ item 37 + result (0 a near miss,
 * 1 the opponent unhorsed, 2 the player, 3 the horse hit): a frame is 4 bytes a
 * knight, the BJ item - 20, the rows drawn (the rest is behind the barrier), x
 * and y; a y of 0 takes the knight away, an x over 80 ends it. Two beats of the
 * hooves a frame. */
static void joust_outcome(int r)
{
    flush_keys();
    gfx_show_picture(PIC_STANDS);
    gfx_no_wipe();   /* DOC 02D3:0BC8: at once */
    present();
    gfx_set_palette();
    const SpriteFile *f = &gfx_assets()->set[MODE_EGA].file[F_TOURN];   /* the three programs' scripts are the same */
    size_t pos = f->off[37 + r];
    int y1 = -1, y2 = -1, it1 = 0, it2 = 0, rows1 = 0, rows2 = 0, x1 = 0, x2 = 0;
    for (;;) {
        get_key();
        if (pos + 8 > f->len) return;
        if (y1) {
            it1 = f->raw[pos] + 20; rows1 = f->raw[pos + 1]; x1 = f->raw[pos + 2];
            pos += 3;
            if (x1 > 80) return;
            y1 = f->raw[pos++];
        }
        if (y2) {
            it2 = f->raw[pos] + 20; rows2 = f->raw[pos + 1]; x2 = f->raw[pos + 2];
            pos += 3;
            if (x2 > 80) return;
            y2 = f->raw[pos++];
        }
        beep(W(D_HOOVES), 1);
        next_beat(D_HOOVES);
        snd_speaker_tone(W(D_HOOVES));
        if (y1) slot_set(1, x1 * 4, y1, F_TOURN, it1, rows1);
        if (y2) slot_set(0, x2 * 4, y2, F_TOURN, it2, rows2);
        gfx_sprites_draw();
        present_bottom();
        gfx_sprites_erase();
        slots_off();
        beep(W(D_HOOVES), 1);
        next_beat(D_HOOVES);
    }
}

/* 6EC2: a pass down the lane (CI) after a key: 17 pictures of the opponent coming
 * closer, three lance steps each. Then the point (x 20-50, y 120-180) is judged:
 * within x 26 +- (1 if the player jousts better, else 0) and y 138 +- (the
 * player's jousting + 2 - the opponent's, at least 1) the opponent falls (1); x
 * below 30 with y over 170 is the horse (3); otherwise random(opponent's jousting)
 * of 2 or more unhorses the player (2), else a near miss and another pass (the
 * fourth pass is always lost). The EGA program compares these unsigned: against
 * an opponent jousting 3 or more better, (player + 2 - opponent) is negative and
 * stays so, and no point can hit (138 - n > y and 138 + n < y for every y). The
 * CGA and Tandy programs (signed) make it 1. Kept as the EGA one (--fix=joust-margin:
 * as the CGA and Tandy ones). */
static int joust(int opp)
{
    int p = W(D_PLAYER), passes = 0, r;
    for (;;) {
        wait_key();
        gfx_show_picture(PIC_LANE);
        present();
        gfx_set_palette();
        SW(D_LANCE_X, 40);
        SW(D_LANCE_Y, 125);
        for (int si = 3; si < 20; si++) {
            lance_step(si);
            lance_step(0);
            lance_step(0);
        }
        slots_off();
        int pj = W(SIDE(p) + S_JOUST), oj = W(SIDE(opp) + S_JOUST);
        int l4 = w16(pj + 2 - oj);
        if (fixed(FIX_JOUST_MARGIN) || g_dos_rules ? l4 < 1 : (uint16_t)l4 < 1) l4 = 1;
        int l6 = (uint16_t)pj > (uint16_t)oj ? 1 : 0;
        uint16_t x = (uint16_t)W(D_LANCE_X), y = (uint16_t)W(D_LANCE_Y);
        if (!((uint16_t)(26 - l6) > x) && !((uint16_t)(26 + l6) < x) && !((uint16_t)(138 - l4) > y) && !((uint16_t)(138 + l4) < y))
            r = 1;
        else if ((uint16_t)(26 + 4) > x && (uint16_t)170 < y)
            r = 3;
        else
            r = (uint16_t)random_n(oj) >= 2 ? 2 : 0;
        if (++passes > 3) r = 2;
        static const char *const R[4] = { "a near miss", "you unhorse him", "you are unhorsed", "you hit his horse" };
        GLOG(GLOG_NORMAL, "JOUST pass %d: your lance at x %d, y %d; the target x %d-%d, y %d-%d (jousting %d against %d): %s", passes, x, y,
             26 - l6, 26 + l6, w16(138 - l4), w16(138 + l4), pj, oj, R[r]);
        joust_outcome(r);
        if (r) return r;
        dialog(0x3372);   /* "--- A Near Miss ---" */
        dialog(0x2E9E);   /* "An expectant hush..." */
    }
}

/* ------------------------------------------------------------------ a round (6475) */

static int choose_opponent(void)   /* 7094: a menu of the lords still in the tournament */
{
    int k = 0, side[8] = { 0 };
    for (int si = 1; si < 7; si++)
        if (W(D_IN_TOURN + 2 * si)) {
            k++;
            SW(0x2C43 + 2 * k, W(SIDE(si) + S_NAME));
            side[k] = si;
        }
    SB(0x2C3E, k);
    SB(0x2C3A, k + 1);
    int c = dialog(0x2C38);
    return side[c >= 1 && c <= k ? c : 0];
}

/* The stakes: Land only if a lord still in the tournament owns a territory
 * without a castle and so does the player (his highest-numbered one is at
 * stake); the player then chooses the territory to win, whose owner is the
 * opponent. Otherwise, or for Fame, the player chooses the opponent.
 *
 * The opponent's jousting the joust is judged by is not the opponent's but that
 * of the owner of the territory the first search stopped at (the highest-numbered
 * territory without a castle of a lord still in it, else territory 1's owner),
 * and a land won sends that lord's army home if it is in the territory won, not
 * the opponent's (AB 64C6 di): kept (--fix=joust-opponent: the opponent's). Returns
 * 1 won, 2 lost, 3 disgraced. */
static int joust_round(void)
{
    int p = W(D_PLAYER), fame = 1, l2 = 0;
    gfx_show_picture(PIC_TOURNAMENT);
    present();
    gfx_set_palette();
    play_tune(0x9A, W(D_TUNE_ONCE));
    wait_ticks(27);
    int si, di = -1;
    for (si = 18; si; si--) {
        di = (int8_t)B(TERR(si) + T_OWNER);
        if (di != -1 && W(D_IN_TOURN + 2 * di) && !B(TERR(si) + T_CASTLE)) break;
    }
    if (si)
        for (si = 18; si; si--)
            if ((int8_t)B(TERR(si) + T_OWNER) == p && !B(TERR(si) + T_CASTLE)) break;
    if (si) {
        int c;
        while ((c = dialog(0x2FB1)) == 3) read_map();   /* Choose the Stakes: Fame / Land / Read Map */
        if (c == 1) {
            SW(D_OPPONENT, choose_opponent());
        } else {
            redraw_map();
            while (fame) {
                l2 = choose_territory(W(SIDE(p) + S_HOME));
                int o = (int8_t)B(TERR(l2) + T_OWNER);
                if (o == -1) dialog(0x2D4F);                 /* not owned by a lord in the tournament */
                else if (o == p) dialog(0x2DE8);             /* "You may not choose your own territory" */
                else if (B(TERR(l2) + T_CASTLE)) dialog(0x2DAB);   /* "... with a castle." */
                else {
                    SW(D_OPPONENT, o);
                    if (!W(D_IN_TOURN + 2 * o)) dialog(0x2D4F);
                    else fame = 0;
                }
            }
            redraw_map();
            dialog(0x3453);   /* "Your opponent chooses:" */
            flash_territory(si, 36);
        }
    } else {
        dialog(0x2F67);   /* "There is no land to joust for, so you must joust for fame." */
        SW(D_OPPONENT, choose_opponent());
    }
    int o = W(D_OPPONENT);
    if (fixed(FIX_JOUST_OPPONENT)) di = o;
    if (fame) GLOG(GLOG_NORMAL, "JOUST for fame against %s (judged by the jousting of %s)", glog_side(o), glog_side(di));
    else GLOG(GLOG_NORMAL, "JOUST for land: %s against your %s, with %s (judged by the jousting of %s)", glog_terr(l2), glog_terr(si),
              glog_side(o), glog_side(di));
    gfx_show_picture(PIC_TOURNAMENT);
    slot_set(0, 41 * 4, 76, F_TOURN, 2, 0);
    slot_set(1, 15 * 4, 88, F_TOURN, 30, 0);
    gfx_sprites_draw(); present(); gfx_sprites_erase();
    gfx_video()->slot[0].active = false;   /* the other knight (slot 1) waits on */
    SW(D_IN_TOURN + 2 * o, 0);
    wait_tune(0x9A);
    joust_approach();
    gfx_show_picture(PIC_LANE);
    int r = joust(di);
    if (r == 1) {
        dialog(0x2E6A);   /* "Congratulations, you won that round." */
        morale_add(1);
        if (fame) leadership_add(p, 1);
        else {
            redraw_map();
            set_owner(p, l2);
            if (W(SIDE(di) + S_AT) == l2) army_go_home(di);
        }
        GLOG(GLOG_NORMAL, "JOUST you win the round: morale +1, %s", fame ? "leadership +1" : glog_terr(l2));
    } else if (r == 2) {
        morale_add(-1);
        dialog(0x328E);   /* "--- A Long Day ---" */
        if (fame) leadership_add(p, -1);
        else {
            redraw_map();
            set_owner(o, si);
            if (W(SIDE(p) + S_AT) == si) army_go_home(p);
        }
        GLOG(GLOG_NORMAL, "JOUST you lose the round: morale -1, %s", fame ? "leadership -1" : glog_terr(si));
    } else {
        SW(D_BANNED, 1);
        SW(D_MORALE, 19);
        dialog(0x3066);   /* "--- Disgrace ---" */
        redraw_map();
        for (si = 18; si; si--)
            if ((int8_t)B(TERR(si) + T_OWNER) == p && W(SIDE(p) + S_HOME) != si) set_owner(-1, si);
        army_go_home(p);
        GLOG(GLOG_NORMAL, "JOUST disgrace: banned from tournaments, morale 19, all your land but your home lost");
    }
    return r;
}

/* ------------------------------------------------------------------ the tournament (62BC) */

int tournament(int di)
{
    int p = W(D_PLAYER);
    if (W(D_BANNED)) {
        if (di == p) dialog(0x2E1B);   /* "You may not call a tournament, you have been banned from Ashby." */
        GLOG(GLOG_NORMAL, "TOURNAMENT %s: none, the player is banned", glog_side(di));
        return 0;
    }
    int now = w16(W(D_YEAR) * 12 + W(D_MONTH_NO));
    if (W(D_LAST_TOURN) == now || w16(now - 1) == W(D_LAST_TOURN)) {
        if (di == p) dialog(0x3477);   /* "The Lords have just returned from the last tournament!" */
        GLOG(GLOG_NORMAL, "TOURNAMENT %s: none, the last was this month or the one before", glog_side(di));
        return 0;
    }
    if (W(SIDE(di) + S_GOLD) < 5) {
        if (di == p) dialog(0x2CA4);   /* "You must have at least 5 pieces of gold to hold a Tournament." */
        GLOG(GLOG_NORMAL, "TOURNAMENT %s: none, less than 5 gold", glog_side(di));
        return 0;
    }
    SW(SIDE(di) + S_GOLD, W(SIDE(di) + S_GOLD) - 5);
    for (int si = 1; si < 7; si++) enmity_add(si, di, -1);   /* 26AA */
    for (int si = 1; si < 7; si++) SW(D_IN_TOURN + 2 * si, 1);
    SW(D_IN_TOURN + 2 * p, 0);
    GLOG(GLOG_NORMAL, "TOURNAMENT held by %s (5 gold; every lord's enmity towards him -1)", glog_side(di));
    redraw_map();
    str_append(W(SIDE(di) + S_NAME), W(0x2FF5));
    dialog(0x2FEA);   /* "... bids all knights to attend the games of Chivalry." */
    gfx_show_picture(PIC_TRUMPETERS);
    present();
    gfx_set_palette();
    play_tune(0x9A, W(D_TUNE_ONCE));
    wait_tune(0x9A);
    int r = 0;
    for (int si = 0; si < 3; si++)
        if ((r = joust_round()) != 1) break;
    if (r == 1) {
        dialog(0x319C);   /* "--- The Champion ---" */
        GLOG(GLOG_NORMAL, "TOURNAMENT you are the champion");
    }
    SW(D_LAST_TOURN, w16(W(D_YEAR) * 12 + W(D_MONTH_NO)));
    redraw_map();
    return 1;
}
