/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * raid.c: Go Raiding (AB 45AC) with choose_raid_target (4538), raid (45EC),
 * The Attack and The Defense (5449 raid_attack, 5571 raid_defense), the
 * sword fight (4F24, with sword_pose 4CAC/4DE8 and bar_shorten 4C5C), and
 * the offer to rescue a kidnapped lady (4316). See Analysis/GAME_LOGIC.md,
 * "Raids".
 *
 * The fight keeps its state where the original did, in the data segment:
 * the player's fighter at DS:0B08 (x, y, legs, body, strength), the enemy at
 * DS:0B12, the two fighters behind them in The Attack at DS:0B1C and 0B26
 * (x, y, legs, body). Bodies are BN items 160 (sword raised), 161 (middle),
 * 162 (thrust), 163 (parry), the enemy's 170-173; legs 164 (standing) and
 * 165-166 (a step), the enemy's 174-176. Positions are in 4-pixel units.
 */
#include "raid.h"
#include "conquest.h"
#include "war.h"
#include "game.h"
#include "gamelog.h"
#include "month.h"

#define D_RAIDED      0x0AFA   /* the side whose castle is raided */
#define D_BAR_YOU     0x0AF2   /* x of the end of the player's strength bar */
#define D_BAR_ENEMY   0x0B04
#define D_LIMIT_BACK  0x0B02   /* the player retreats past this x */
#define D_LIMIT_ENEMY 0x0B30   /* the enemy steps back no further */
#define F_X     0x0B08
#define F_Y     0x0B0A
#define F_LEGS  0x0B0C
#define F_BODY  0x0B0E
#define F_STR   0x0B10
#define E_X     0x0B12
#define E_LEGS  0x0B16
#define E_BODY  0x0B18
#define E_STR   0x0B1A
#define D_ROBIN_ASKED 0x004D

void leadership_add(int side, int d)
{
    int v = W(SIDE(side) + S_LEAD) + d;
    SW(SIDE(side) + S_LEAD, v > 10 ? 10 : v < 0 ? 0 : v);
}

/* The strength bars. The booter programs XOR theirs in (BO 7 "You" and 8
 * "Enemy" on line 192, filled); the 1987 DOS version's raid pictures (RAID.LIB)
 * have them drawn in already, filled to its own ends: the player's to x 153,
 * the guards' to 242 (20 points), the lord's to 282 (DOC.EXE 050E:10E9,
 * 11F0). So in the CGA (1987) mode the bars' ends are DOC.EXE's (dos_x). */
static int dos_x[2];   /* 0 the player's bar, 1 the enemy's */

static void shorten(unsigned modes, int *x)   /* 2 pixels off the end (lines 195-196), as bar_shorten */
{
    for (int i = 0; i < 2; i++) {
        gfx_put_pixel_m(modes, PAGE_BACK, *x, 195, 0);
        gfx_put_pixel_m(modes, PAGE_BACK, *x, 196, 0);
        (*x)--;
    }
}

/* 4C5C (DOC.EXE 050E:08F7): a point off a bar, in every mode */
static void bar_shorten(int ptr)
{
    int x = W(ptr);
    shorten(MODES_BOOTER, &x);
    SW(ptr, x);
    shorten(MODES_DOS, &dos_x[ptr == D_BAR_ENEMY]);
}

/* the bars at the start of a fight, from full down to the strengths: the booter
 * programs take a point off for each below 49 (39 for the enemy), DOC.EXE for each
 * below 50 (40), from their own ends */
static void bars_start(int you, int enemy_from, int enemy, int dos_enemy_from)
{
    int x = 154;
    for (int si = 49; si > you; si--) shorten(MODES_BOOTER, &x);
    SW(D_BAR_YOU, x);
    dos_x[0] = 153;
    for (int si = 50; si > you; si--) shorten(MODES_DOS, &dos_x[0]);
    x = 0x118;
    for (int si = enemy_from; si > enemy; si--) shorten(MODES_BOOTER, &x);
    SW(D_BAR_ENEMY, x);
    dos_x[1] = dos_enemy_from;
    for (int si = 40; dos_enemy_from == 282 && si > enemy; si--) shorten(MODES_DOS, &dos_x[1]);
}

/* 4DE8 / 4CAC: a pair of fighters (the record at DS:0B08 + 2 x rec) into four
 * sprite slots: bodies at (x, y), legs at (x, y + 24), the right one's legs
 * 8 units further on */
static struct { int x, y, ex, ey, legs, body, elegs, ebody; } P;

static void sword_pose(int rec, int slot0)
{
    int r = 0xB08 + 2 * rec;
    P.x = W(r); P.y = W(r + 2); P.ex = W(r + 10); P.ey = W(r + 12);
    P.legs = W(r + 4); P.body = W(r + 6); P.elegs = W(r + 14); P.ebody = W(r + 16);
    Slot *s = gfx_video()->slot;
    s[slot0 + 3] = (Slot){ true, P.x * 4, P.y + 24, F_SWORD, P.legs, 0, 0 };
    s[slot0 + 1] = (Slot){ true, P.x * 4, P.y, F_SWORD, P.body, 0, 0 };
    s[slot0 + 2] = (Slot){ true, (P.ex + 8) * 4, P.ey + 24, F_SWORD, P.elegs, 0, 0 };
    s[slot0 + 0] = (Slot){ true, P.ex * 4, P.ey, F_SWORD, P.ebody, 0, 0 };
}

/* the two fighters behind (The Attack): a step now and then, and a new stance */
static void background_fighters(void)
{
    if (W(0xB20) > 164) {
        SW(0xB20, W(0xB20) + 1);
        if (W(0xB20) > 166) SW(0xB20, 164);
        SW(0xB2A, W(0xB20) + 10);
    } else {
        int si = random_n(9);
        if (!si && W(0xB22) != 162 && W(0xB2C) != 172) {
            SW(0xB20, 165);
            SW(0xB2A, 175);
            if (random_n(2)) {
                SW(0xB1C, W(0xB1C) + 1);
                if (W(0xB1C) > 10) SW(0xB1C, 9);
            } else {
                SW(0xB1C, W(0xB1C) - 1);
                if (W(0xB1C) < 4) SW(0xB1C, 5);
            }
            SW(0xB26, W(0xB1C) + 6);
        }
        if (si > 4) SW(0xB22, si + 155);
        else if (si) SW(0xB2C, si + 169);
    }
    sword_pose(10, 4);
}

static void spark(int x, int y, int item, int bar)
{
    gfx_xor_sprite(x, y, F_END, item);
    present();
    bar_shorten(bar);
    gfx_xor_sprite(x, y, F_END, item);
}

/* 4F24: one frame a screen refresh. The keypad (or the arrows): Enter thrusts,
 * 8 raises the sword, 2 parries, 7/4/1 step back and 9/6/3 forward (forward only
 * while more than 5 apart) with the sword raised, in the middle or parrying.
 * Returns 1 if the enemy falls, 0 if the player retreats past the left limit or
 * is captured. */
static int sword_fight(int attack)
{
    int p = W(D_PLAYER), di = -1, result;
    for (;;) {
        if (attack) background_fighters();
        sword_pose(0, 0);
        gfx_sprites_draw();
        present();
        if (W(F_X) < W(D_LIMIT_BACK)) {
            leadership_add(p, -10);
            morale_add(-2);
            GLOG(GLOG_NORMAL, "RAID you retreat: leadership 0, morale -2");
            dialog(0x253A);
            result = 0;
            break;
        }
        if (W(E_STR) <= 0) {
            gfx_sprites_erase();
            Slot *s = gfx_video()->slot;
            for (int k = 3; k < 8; k++) s[k].active = false;
            s[2] = (Slot){ true, P.x * 4, P.y + 24, F_SWORD, P.legs, 0, 0 };
            s[1] = (Slot){ true, P.x * 4, P.y, F_SWORD, P.body, 0, 0 };
            s[0] = (Slot){ true, P.ex * 4, P.ey, F_SWORD, 178, 0, 0 };
            gfx_sprites_draw();
            present();
            gfx_sprites_erase();
            flush_keys();
            wait_ticks(2);
            s[0] = (Slot){ true, P.ex * 4, P.ey + 32, F_SWORD, 179, 0, 0 };
            gfx_sprites_draw();   /* left on the picture */
            present();
            flush_keys();
            result = 1;
            break;
        }
        if (W(F_STR) <= 0) {
            leadership_add(p, -1);
            morale_add(-1);
            int g = W(SIDE(p) + S_GOLD) / 2;
            if (g) {
                SW(SIDE(p) + S_GOLD, W(SIDE(p) + S_GOLD) - g);
                SW(SIDE(W(D_RAIDED)) + S_GOLD, W(SIDE(W(D_RAIDED)) + S_GOLD) + g);
            }
            GLOG(GLOG_NORMAL, "RAID you are captured: %d gold ransom to %s, leadership -1, morale -1", g, glog_side(W(D_RAIDED)));
            dialog(0x240E);
            result = 0;
            break;
        }
        /* the player */
        if (W(F_LEGS) > 164) {
            SW(F_LEGS, W(F_LEGS) + 1);
            if (W(F_LEGS) > 166) SW(F_LEGS, 164);
        } else {
            int si = W(E_X) - W(F_X);
            if (W(F_BODY) == 162) {
                SW(F_BODY, 161);
                if (si < 7 && W(E_BODY) != 173) {
                    SW(E_STR, W(E_STR) - 1);
                    spark(P.x + 7, P.y + 17, 9, D_BAR_ENEMY);
                    GLOG(GLOG_VERBOSE, "RAID you hit: the enemy's strength %d", W(E_STR));
                }
            } else {
                int fwd = si > 5;
                switch ((int8_t)get_key()) {
                case 0x1C: SW(F_BODY, 162); break;
                case 0x47: SW(F_X, W(F_X) - 1); SW(F_LEGS, 165); SW(F_BODY, 160); break;
                case 0x48: SW(F_BODY, 160); break;
                case 0x49: if (fwd) { SW(F_X, W(F_X) + 1); SW(F_LEGS, 165); } SW(F_BODY, 160); break;
                case 0x4B: SW(F_X, W(F_X) - 1); SW(F_LEGS, 165); SW(F_BODY, 161); break;
                case 0x4D: if (fwd) { SW(F_X, W(F_X) + 1); SW(F_LEGS, 165); } SW(F_BODY, 161); break;
                case 0x4F: SW(F_X, W(F_X) - 1); SW(F_LEGS, 165); SW(F_BODY, 163); break;
                case 0x50: SW(F_BODY, 163); break;
                case 0x51: if (fwd) { SW(F_X, W(F_X) + 1); SW(F_LEGS, 165); } SW(F_BODY, 163); break;
                default: break;
                }
                flush_keys();
            }
        }
        /* the enemy: a step goes on; otherwise he acts every other frame */
        if (W(E_LEGS) > 174) {
            SW(E_LEGS, W(E_LEGS) + 1);
            if (W(E_LEGS) > 176) SW(E_LEGS, 174);
        } else if ((di = -di) > 0) {
            int si = W(E_X) - W(F_X);
            if (W(E_BODY) == 170) {
                SW(E_BODY, 172);
            } else {
                if (W(E_BODY) == 172 && si < 7 && W(F_BODY) != 163) {
                    SW(F_STR, W(F_STR) - 1);
                    spark(P.ex - 1, P.y + 16, 10, D_BAR_YOU);
                    GLOG(GLOG_VERBOSE, "RAID you are hit: your strength %d", W(F_STR));
                }
                if (si > 6) {
                    SW(E_BODY, 171);
                    if (random_n(2)) { SW(E_LEGS, 175); SW(E_X, W(E_X) - 1); }
                } else if (si < 6 && W(E_X) < W(D_LIMIT_ENEMY)) {
                    SW(E_LEGS, 175);
                    SW(E_BODY, 173);
                    SW(E_X, W(E_X) + 1);
                } else {
                    SW(E_BODY, random_n(2) ? 170 : 173);
                }
            }
        }
        gfx_sprites_erase();
    }
    for (int k = 0; k < 8; k++) gfx_video()->slot[k].active = false;
    return result;
}

/* the strength bars: "You" (BO 7) and "Enemy" (8) on line 192 (not in the DOS pictures' mode: they have them) */
static void bars(void)
{
    gfx_xor_sprite_m(MODES_BOOTER, 8, 192, F_END, 7);
    gfx_xor_sprite_m(MODES_BOOTER, 43, 192, F_END, 8);
}

/* 5449: against the guards (strength 20), two more fighters behind */
static int raid_attack(void)
{
    gfx_show_picture(PIC_NIGHT);
    bars();
    present();
    gfx_set_palette();
    play_tune(0x9B, W(D_TUNE_LOOP));
    bars_start(W(F_STR), 40, 20, 242);   /* the booter shortens the guards' bar 20 times; DOC.EXE's picture has it at 20 */
    SW(D_LIMIT_BACK, 30); SW(D_LIMIT_ENEMY, 51);
    SW(F_X, 32); SW(F_Y, 141); SW(F_LEGS, 164); SW(F_BODY, 161);
    SW(E_X, 54); SW(0xB14, 141); SW(E_LEGS, 174); SW(E_BODY, 171);
    SW(E_STR, 20);
    SW(0xB1C, 7); SW(0xB1E, 139); SW(0xB20, 164); SW(0xB22, 161);
    SW(0xB26, 13); SW(0xB28, 139); SW(0xB2A, 174); SW(0xB2C, 171);
    GLOG(GLOG_NORMAL, "RAID The Attack: your strength %d against the guards' 20", W(F_STR));
    return sword_fight(1);
}

/* 5571: against the lord (his swordplay x 4). The hall is put up after 39
 * back-to-back wait_ticks(1) (about two seconds: each of them waits for the
 * tick the one before ended on). */
static int raid_defense(void)
{
    gfx_show_picture(PIC_HALL);
    bars();
    wait_ticks(39);
    present();
    gfx_set_palette();
    SW(E_STR, W(SIDE(W(D_RAIDED)) + S_SWORD) * 4);
    bars_start(W(F_STR), 39, W(E_STR), 282);
    SW(D_LIMIT_BACK, 4); SW(D_LIMIT_ENEMY, 20);
    SW(F_X, 6); SW(F_Y, 141); SW(F_LEGS, 164); SW(F_BODY, 161);
    SW(E_X, 23); SW(0xB14, 141); SW(E_LEGS, 174); SW(E_BODY, 171);
    GLOG(GLOG_NORMAL, "RAID The Defense: your strength %d against %s's %d", W(F_STR), glog_side(W(D_RAIDED)), W(E_STR));
    return sword_fight(0);
}

/* 48EB: the romance, not ported yet (its scenes differ between the three
 * programs): its first and last words over the hall, and what it does (morale
 * 50; the lady and her ward's land then go to the player in raid) */
static void romance(int lady)
{
    GLOG(GLOG_NORMAL, "REMAKE the romance with %s (48EB) is not ported yet: only its words", STR(W(LADY(lady) + L_NAME)));
    dialog(0x267F);
    dialog(0x27CA);
    SW(D_MORALE, 50);
}

/* 45EC */
static void raid(int t)
{
    int p = W(D_PLAYER);
    SW(D_RAIDED, (int8_t)B(TERR(t) + T_OWNER));
    enmity_add(W(D_RAIDED), p, 1);
    SW(F_STR, W(SIDE(p) + S_SWORD) * 4);
    if (W(D_ROBIN_ASKED)) {
        SW(F_STR, 50);
        SW(D_ROBIN_ASKED, 0);
    }
    GLOG(GLOG_NORMAL, "RAID you raid %s of %s; your sword strength %d%s", glog_terr(t), glog_side(W(D_RAIDED)), W(F_STR),
         W(F_STR) == 50 ? " (Robin's help)" : "");
    SW(0x8C7, 2);
    if (raid_attack() && raid_defense()) {
        play_tune(0x9B, W(D_TUNE_STOP));
        int k = W(D_KIDNAPPED);
        if (k != -1) {
            gfx_show_picture(PIC_HALL);   /* the last picture loaded, put up again without the fighters */
            present();
            gfx_set_palette();
            int ward = W(LADY(k) + L_SIDE);
            GLOG(GLOG_NORMAL, "RAID success: you rescue %s; she is yours, and the land of %s", STR(W(LADY(k) + L_NAME)), glog_side(ward));
            romance(k);
            lady_to_side(k, p, 2);
            side_falls(ward, p);
        } else {
            int r = W(D_RAIDED), g = W(SIDE(r) + S_GOLD) / 2;
            SW(SIDE(r) + S_GOLD, W(SIDE(r) + S_GOLD) - g);
            SW(SIDE(p) + S_GOLD, W(SIDE(p) + S_GOLD) + g);
            morale_add(1);
            leadership_add(p, 1);
            GLOG(GLOG_NORMAL, "RAID success: you take %d gold (half) from %s; morale +1, leadership +1", g, glog_side(r));
            dialog(0x22C0);
        }
    }
    play_tune(0x9B, W(D_TUNE_STOP));
    SW(0x8C7, 3);
}

/* 4538: another side's home castle that it still holds (your own cancels the
 * order; Sherwood Forest asks Robin) */
static int choose_raid_target(void)
{
    for (;;) {
        int di = choose_territory(W(SIDE(W(D_PLAYER)) + S_AT));
        if (!di) { see_robin(); continue; }
        for (int si = 1; si < 7; si++)
            if (W(SIDE(si) + S_HOME) == di && (int8_t)B(TERR(di) + T_OWNER) == si) return di;
        dialog(0x207B);   /* "Territory must have a home castle." */
    }
}

int go_raiding(void)
{
    int t = choose_raid_target();
    if (t == W(SIDE(W(D_PLAYER)) + S_HOME)) return 0;
    redraw_map();
    dialog(0x2143);
    raid(t);
    return 1;
}

/* 4316: at the start of the player's month, if a Norman has kidnapped a lady */
int rescue_offer(void)
{
    int p = W(D_PLAYER), k = W(D_KIDNAPPED), si = 0;
    if (k == -1) return 0;
    redraw_map();
    str_append(W(LADY(k) + L_NAME), str_append(0x4315, W(0x287C)));
    str_append(W(TERR(W(LADY(k) + L_TERR)) + T_NAME), str_append(0x4321, W(0x2880)));
    dialog(0x2871);
    dialog(0x2920);
    if (dialog(0x2948) == 1) {
        GLOG(GLOG_NORMAL, "YOU set out to rescue %s from %s", STR(W(LADY(k) + L_NAME)), glog_terr(W(LADY(k) + L_TERR)));
        raid(W(LADY(k) + L_TERR));
        leadership_add(p, 2);
        si = 1;
    } else {
        GLOG(GLOG_NORMAL, "YOU leave %s where she is: leadership -2", STR(W(LADY(k) + L_NAME)));
        leadership_add(p, -2);
    }
    SW(D_KIDNAPPED, -1);
    return si;
}
