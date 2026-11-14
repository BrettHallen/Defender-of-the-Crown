/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * conquest.c: the player's Seek Conquest (AB 35E0) with choose_destination
 * (3585), send_army (3135), Robin (2E37 see_robin, 2E84 robin_men),
 * Transfer Forces (3721), and Read Map (4084, territory_info 3DB4). The
 * battles and sieges themselves are in war.c. See Analysis/GAME_LOGIC.md.
 */
#include "conquest.h"
#include "war.h"
#include "game.h"
#include "gamelog.h"
#include "month.h"

#define D_ROBIN_ASKED 0x004D   /* Robin's men join the next attack */
#define D_ROBIN_TIMES 0x004B   /* pledges asked for (3 in a game) */
#define D_SEEK_OPEN   0x0990   /* the Seek Conquest menu stays up */
#define D_CUR_TERR    0x0B54   /* Read Map's territory */

static int16_t w16(int v) { return (int16_t)(v & 0xFFFF); }

/* ------------------------------------------------------------------ Robin */

void see_robin(void)   /* 2E37 */
{
    redraw_map();
    if (!W(D_ROBIN_ASKED) && W(D_ROBIN_TIMES) >= 3) {
        dialog(0x1ACE);   /* "--- Sherwood Again ---": no more */
        GLOG(GLOG_NORMAL, "ROBIN you have had his three pledges");
        return;
    }
    if (!W(D_ROBIN_ASKED)) {
        SW(D_ROBIN_ASKED, 1);
        SW(D_ROBIN_TIMES, W(D_ROBIN_TIMES) + 1);
        GLOG(GLOG_NORMAL, "ROBIN pledges his men for your next attack (pledge %d of 3)", W(D_ROBIN_TIMES));
    }
    dialog(0x19F8);
}

/* 2E84: 1.5 x the defenders' soldiers less yours, 2 to 50 */
static int robin_men(int owner, int t)
{
    int si = W(GARRISON(t) + A_SOLDIERS);
    if (W(ARMY(owner) + A_AT) == t) si = w16(si + W(ARMY(owner) + A_SOLDIERS));
    si = w16(si / 2 + si - W(ARMY(W(D_PLAYER)) + A_SOLDIERS));
    if (si > 50) si = 50;
    else if (si < 2) si = 2;
    return si;
}

/* ------------------------------------------------------------------ marching */

static int is_neighbour(int a, int b)   /* 3D82 */
{
    for (int i = 0; i < 7; i++)
        if ((int8_t)B(TERR(a) + T_NB + i) == b) return 1;
    return 0;
}

/* 3585: a neighbour of where the army is (or that territory itself); Sherwood
 * Forest asks Robin and the choice goes on */
static int choose_destination(void)
{
    int si = W(SIDE(W(D_PLAYER)) + S_AT);
    for (;;) {
        int di = choose_territory(si);
        if (!di) { see_robin(); continue; }
        if (si == di || is_neighbour(si, di)) return di;
        dialog(0x2B88);
    }
}

/* 3135: the army moves in and attacks; Robin's men join for it, and half of them
 * go again afterwards (an army left with fewer than 5 soldiers gets 5) */
static int send_army(int t)
{
    int p = W(D_PLAYER), extra = 0;
    army_move_to(p, t);
    int owner = (int8_t)B(TERR(t) + T_OWNER);
    GLOG(GLOG_NORMAL, "YOU march your campaign army to %s (%s)", glog_terr(t), owner == -1 ? "nobody's" : glog_side(owner));
    if (W(D_ROBIN_ASKED)) {
        extra = robin_men(owner, t);
        SW(ARMY(p) + A_SOLDIERS, W(ARMY(p) + A_SOLDIERS) + extra);
        GLOG(GLOG_NORMAL, "ROBIN %s join your army", glog_count(extra, "of his men"));
    }
    int r = attack(p, owner, t);
    if (W(D_ROBIN_ASKED)) {
        SW(ARMY(p) + A_SOLDIERS, W(ARMY(p) + A_SOLDIERS) - extra / 2);
        if (W(ARMY(p) + A_SOLDIERS) < 5) SW(ARMY(p) + A_SOLDIERS, 5);
        GLOG(GLOG_NORMAL, "ROBIN %d of his men go back to Sherwood: you have %d soldiers", extra / 2, W(ARMY(p) + A_SOLDIERS));
    }
    SW(D_ROBIN_ASKED, 0);
    return r;
}

/* ------------------------------------------------------------------ Transfer Forces (3721) */

/* Right moves one from the garrison to the campaign army, Left back; no limits
 * but what there is. The table's spaces are the font's '>' (as Buy Home Army). */
static void transfer_forces(void)
{
    int p = W(D_PLAYER), di = W(ARMY(p) + A_AT);
    int gar[4] = { 0, W(GARRISON(di) + A_SOLDIERS), W(GARRISON(di) + A_KNIGHTS), W(GARRISON(di) + A_CATAPULTS) };
    int arm[4] = { 0, W(ARMY(p) + A_SOLDIERS), W(ARMY(p) + A_KNIGHTS), W(ARMY(p) + A_CATAPULTS) };
    if (W(SIDE(p) + S_HOME) == di) SW(0x3972, W(0x3914));        /* " Home           Campaign" */
    else if (B(TERR(di) + T_CASTLE)) SW(0x3972, W(0x392F));     /* "Garrison         Campaign" */
    else SW(0x3972, W(0x394B));                                 /* "Territory        Campaign" */
    gfx_glyph_alias(0x20, 0x3E);
    SB(0x396B, 0);
    int si = 1;
    SW(D_LEFTRIGHT, 0);
    static const int LINE[4] = { 0, 0x3974, 0x3976, 0x3978 }, TEXT[4] = { 0, 0x40EC, 0x40FB, 0x410A };
    while (si != 4) {
        if (W(D_LEFTRIGHT) > 0) {
            if (gar[si] > 0) { gar[si]--; arm[si]++; }
            else snd_speaker_click(250, 2);
        } else if (W(D_LEFTRIGHT) < 0) {
            if (arm[si] > 0) { arm[si]--; gar[si]++; }
            else snd_speaker_click(250, 2);
        }
        for (int i = 1; i < 4; i++) {
            int e = num_append((unsigned)gar[i], str_append(0x432C, W(LINE[i])));
            e = str_append(TEXT[i], str_append(0x432A, e));
            num_append((unsigned)arm[i], e);
        }
        SB(0x396E, si);
        snd_speaker_off();
        si = dialog(0x3967);
    }
    SW(GARRISON(di) + A_SOLDIERS, gar[1]);
    SW(GARRISON(di) + A_KNIGHTS, gar[2]);
    SW(GARRISON(di) + A_CATAPULTS, gar[3]);
    SW(ARMY(p) + A_SOLDIERS, arm[1]);
    SW(ARMY(p) + A_KNIGHTS, arm[2]);
    SW(ARMY(p) + A_CATAPULTS, arm[3]);
    gfx_glyph_alias(0x20, -1);
    GLOG(GLOG_NORMAL, "YOU transfer forces at %s: garrison %d soldiers, %d knights, %d catapults; campaign army %d, %d, %d", glog_terr(di),
         gar[1], gar[2], gar[3], arm[1], arm[2], arm[3]);
}

/* ------------------------------------------------------------------ Read Map (4084) */

/* 3DB4: a territory's name, income and vassals, and its owner's ratings (with his
 * portrait when it is his home) */
static void territory_info(void)
{
    int t = choose_territory(W(D_CUR_TERR));
    SW(D_CUR_TERR, t);
    int si = (int8_t)B(TERR(t) + T_OWNER);
    str_append(W(TERR(t) + T_NAME), W(0x1FF6));
    str_append(0x4074, num_append((unsigned)B(TERR(t) + T_INCOME), W(0x1FF8)));
    str_append(0x4082, num_append((unsigned)B(TERR(t) + T_VASSALS), W(0x1FFA)));
    SB(0x1FEE, t ? 23 : 25);
    if (si == -1) {
        SW(0x1FFC, 0x408B);   /* "Not Owned" */
    } else {
        SW(0x200A, W(SIDE(si) + S_NAME));
        str_append(W(0x37B1 + 2 * W(SIDE(si) + S_LEAD)), str_append(0x3FEF, W(0x200C)));
        str_append(W(0x37B1 + 2 * W(SIDE(si) + S_JOUST)), str_append(0x3FFD, W(0x200E)));
        str_append(W(0x37B1 + 2 * W(SIDE(si) + S_SWORD)), str_append(0x400B, W(0x2010)));
        if (W(SIDE(si) + S_HOME) == t) {
            SW(0x1FFC, 0x4095);   /* "Home" */
            show_portrait(W(SIDE(si) + S_PORTRAIT), 25, 3);
            SB(0x1FFF, 45);
        } else {
            SW(0x1FFC, 0x409A);   /* "Owned" */
            SB(0x1FFF, 25);
        }
        dialog(0x1FFF);
    }
    dialog(0x1FEB);
}

int read_map(void)
{
    int si = 1;
    SW(D_CUR_TERR, W(SIDE(W(D_PLAYER)) + S_HOME));
    redraw_map();
    while (si == 1) {
        si = dialog(0x202B);   /* Read Territory / Continue */
        if (si == 1) territory_info();
    }
    return 0;
}

/* ------------------------------------------------------------------ Seek Conquest (35E0) */

/* The menu stays up until a move ends the order (and the month). Moving into a
 * territory of your own (1), a siege refused for want of a catapult (3) and safe
 * passage (8) keep it up: the army can go on. Continue leaves without ending the
 * month. */
int seek_conquest(void)
{
    int p = W(D_PLAYER), di = 0;
    SW(D_SEEK_OPEN, 1);
    while (!di && W(D_SEEK_OPEN)) {
        redraw_map();
        int c = dialog(0x3852);
        static const char *const N[6] = { "", "Send forth Campaign Army", "Transfer Forces", "Read Map", "See Robin", "Continue" };
        if (c >= 1 && c <= 5) GLOG(GLOG_VERBOSE, "YOU Seek Conquest: %s", N[c]);
        switch (c) {
        case 1: {
            if (W(ARMY(p) + A_SOLDIERS) + W(ARMY(p) + A_KNIGHTS) == 0) {
                dialog(0x38AC);   /* "You must transfer forces to campaign army." */
                break;
            }
            int t = choose_destination();
            if (!t) { see_robin(); break; }
            if (!is_neighbour(W(SIDE(p) + S_AT), t)) break;   /* where it already is */
            int r = send_army(t);
            if (r == 1 || r == 8 || r == 3) break;
            di = 1;
            if (r == 6) army_settle(p);
            break;
        }
        case 2:
            if ((int8_t)B(TERR(W(SIDE(p) + S_AT)) + T_OWNER) != p) dialog(0x38E4);   /* "You must be in your own territory." */
            else transfer_forces();
            break;
        case 3:
            read_map();
            break;
        case 4:
            see_robin();
            break;
        case 5:
            SW(D_SEEK_OPEN, 0);
            break;
        default:
            break;
        }
    }
    return di;
}
