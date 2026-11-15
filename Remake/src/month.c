/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * month.c: the month (AB 1B44), the map (4013), the status panel (90A3),
 * the orders (1A91), the options (1957), the events (2F4E) and Buy Home Army
 * (39C7). See Analysis/GAME_LOGIC.md.
 */
#include "month.h"
#include "game.h"
#include "gamelog.h"
#include "ai.h"
#include "war.h"
#include "conquest.h"
#include "raid.h"
#include "tourney.h"

/* ------------------------------------------------------------------ small helpers */

int str_append(int src, int dst)   /* 948D */
{
    for (;;) {
        int c = B(src++);
        SB(dst, c);
        if (!c) return dst;
        dst++;
    }
}

int num_append(unsigned n, int dst)   /* 94B5: a space before numbers under 10 */
{
    char d[8];
    int k = 0;
    unsigned v = n & 0xFFFF;
    do { d[k++] = (char)('0' + v % 10); v /= 10; } while (v);
    if ((n & 0xFFFF) < 10) d[k++] = ' ';
    while (k) SB(dst++, d[--k]);
    SB(dst, 0);
    return dst;
}

void side_income(int side)   /* 23AC: the sum of the incomes of the side's territories */
{
    int sum = 0;
    if (side != -1)
        for (int t = 1; t < 19; t++)
            if ((int8_t)B(TERR(t) + T_OWNER) == side) sum += (int8_t)B(TERR(t) + T_INCOME);
    SW(SIDE(side) + S_INCOME, sum);   /* side -1 writes DS:009B, as the original does */
}

void morale_add(int d)   /* 9464 */
{
    int v = W(D_MORALE) + d;
    SW(D_MORALE, v < 1 ? 1 : v > 50 ? 50 : v);
}

void show_portrait(int portrait, int x, int y)   /* 9407 */
{
    SB(0x1FE0, x);
    SB(0x1FE1, y);
    dialog(0x1FE0);
    gfx_put_sprite(x + 4, y + 7, F_PORTRAITS, portrait);
}

/* ------------------------------------------------------------------ the map */

/* 3F4F: the castles (BL item = the castle's strength, 30 or 35) at DS:0C14, and the
 * player's campaign army (item 127) at DS:0C3A, through sprite slot 0 */
static void draw_castles(void)
{
    for (int t = 1; t < 19; t++) {
        int c = (int8_t)B(TERR(t) + T_CASTLE);
        if (!B(TERR(t) + T_CASTLE)) continue;
        gfx_slot_sprite(B(0xC14 + 2 * t) * 4, B(0xC15 + 2 * t), F_PORTRAITS, c);
    }
    SW(0xC60, W(ARMY(W(D_PLAYER)) + A_AT));
    int at = W(0xC60);
    gfx_slot_sprite(B(0xC3A + 2 * at) * 4, B(0xC3B + 2 * at), F_PORTRAITS, 127);
    present();
}

void redraw_map(void)   /* 4013 */
{
    gfx_use_palette(0);
    gfx_copy_page(PAGE_BACK, PAGE_MAP);
    gfx_set_palette();
    SW(0x67, 1);
    for (int t = 1; t < 19; t++)
        if ((int8_t)B(TERR(t) + T_OWNER) != -1) gfx_xor_mask(B(0xBEE + 2 * t), B(0xBEF + 2 * t), F_PORTRAITS, t + 1);
    draw_castles();
}

void flash_territory(int t, int n)   /* 40C6: XORs its shape n times, a tick apart */
{
    for (int i = 0; i < n; i++) {
        uint32_t t0 = sys_ticks();
        while (sys_ticks() == t0) sys_check();
        gfx_xor_mask(B(0xBEE + 2 * t), B(0xBEF + 2 * t), F_PORTRAITS, t + 1);
        present();
    }
}

/* ------------------------------------------------------------------ the status panel (90A3) */

static void month_status(void)
{
    int p = W(D_PLAYER);
    int si = W(SIDE(p) + S_INCOME) - W(0xD2E);
    if (si < 0) si = 0;
    SW(0xD2E, 0);
    int e;
    e = str_append(0x3FEF, W(0x1C0F)); str_append(W(0x37B1 + 2 * W(SIDE(p) + S_LEAD)), e);
    e = str_append(0x3FFD, W(0x1C11)); str_append(W(0x37B1 + 2 * W(SIDE(p) + S_JOUST)), e);
    e = str_append(0x400B, W(0x1C13)); str_append(W(0x37B1 + 2 * W(SIDE(p) + S_SWORD)), e);
    e = str_append(0x4018, W(0x1C17)); str_append(W(TERR(W(ARMY(p) + A_AT)) + T_NAME), e);
    e = str_append(0x4021, W(0x1C19)); num_append((unsigned)W(ARMY(p) + A_SOLDIERS), e);
    e = str_append(0x4030, W(0x1C1B)); num_append((unsigned)W(ARMY(p) + A_KNIGHTS), e);
    e = str_append(0x403F, W(0x1C1D)); num_append((unsigned)W(ARMY(p) + A_CATAPULTS), e);
    e = str_append(0x404D, W(0x1C21)); num_append((unsigned)si, e);
    e = str_append(0x4061, W(0x1C23)); num_append((unsigned)W(SIDE(p) + S_GOLD), e);
    redraw_map();
    dialog(0x1C02);
    dialog(0x1C26);
    if (W(D_MORALE) > 29) {
        SW(0x9D, 0);
        if (W(D_MORALE) > 50) SW(D_MORALE, 50);
    } else if (W(D_MORALE) > 19) SW(0x9D, 1);
    else SW(0x9D, 2);
    show_portrait(W(SIDE(p) + S_PORTRAIT) + W(0x9D), 0x24, 3);
    int lady = W(SIDE(p) + S_LADY);
    if (lady != -1) {
        int home = W(SIDE(p) + S_HOME);
        SW(LADY(lady) + L_TERR, home);
        if (home) show_portrait(lady + 0x92, 0x38, 3);
    }
    wait_ticks(9);
    SW(D_MONTH_NO, W(D_MONTH_NO) + 1);
    if (W(D_MONTH_NO) > 11) { SW(D_MONTH_NO, 0); SW(D_YEAR, W(D_YEAR) + 1); }
    e = str_append(W(0x372B + 2 * W(D_MONTH_NO)), W(0x1C31));
    num_append((unsigned)W(D_YEAR), e);
    beep(1000, 2);
    dialog(0x1C26);
    wait_ticks(9);
    GLOG(GLOG_NORMAL, "STATUS your income %d (less any lost this month), treasure %d; morale %d; army at %s: %s, %s, %s",
         si, W(SIDE(p) + S_GOLD), W(D_MORALE), glog_terr(W(ARMY(p) + A_AT)), glog_count(W(ARMY(p) + A_SOLDIERS), "soldier"),
         glog_count(W(ARMY(p) + A_KNIGHTS), "knight"), glog_count(W(ARMY(p) + A_CATAPULTS), "catapult"));
    while (si) {   /* the treasure counts up, 5 at a time while more than 10 are left */
        int step;
        if ((unsigned)si > 10) { si -= 5; step = 5; }
        else { si--; step = 1; }
        e = str_append(0x404D, W(0x1C4F)); num_append((unsigned)si, e);
        beep(250, 2);
        dialog(0x1C44);
        e = str_append(0x4061, W(0x1C51));
        SW(SIDE(p) + S_GOLD, W(SIDE(p) + S_GOLD) + step);
        num_append((unsigned)W(SIDE(p) + S_GOLD), e);
        beep(250, 2);
        dialog(0x1C44);
    }
    wait_ticks(40);
}

/* ------------------------------------------------------------------ the events (2F4E) */

static void show_plotters_picture(void)   /* 2EFB */
{
    gfx_show_picture(PIC_PLOTTERS);
    present();
    gfx_set_palette();
    present();
}

static int side_last_territory(int side)   /* 2F14: its highest-numbered territory that is not its home */
{
    for (int si = 18; si; si--)
        if ((int8_t)B(TERR(si) + T_OWNER) == side && W(SIDE(side) + S_HOME) != si) return si;
    return 0;
}

static void monthly_event(void)
{
    SW(D_EVENT_IN, W(D_EVENT_IN) - 1);
    if (W(D_EVENT_IN)) return;
    int p = W(D_PLAYER), si, n = random_n(10) + 1;
    switch (n) {
    case 1: {   /* the garrison of the territory with the player's side number, not the player's home (AB 2F89; --fix=viking) */
        int g = fixed(FIX_VIKING) ? W(SIDE(p) + S_HOME) : p;
        si = W(GARRISON(g) + A_SOLDIERS) / 3;
        GLOG(GLOG_NORMAL, "EVENT 1 Viking raid: the garrison of %s loses %s", glog_terr(g), glog_count(si, "soldier"));
        if (si) {
            SW(GARRISON(g) + A_SOLDIERS, W(GARRISON(g) + A_SOLDIERS) - si);
            dialog(0x1C53);
        }
        break;
    }
    case 2:
    case 3:
        si = side_last_territory(p);
        GLOG(GLOG_NORMAL, "EVENT %d %s: you lose %s", n, n == 2 ? "Danes invade" : "Norman plotters", si ? glog_terr(si) : "nothing");
        if (si) {
            if (n == 3) show_plotters_picture();
            dialog(n == 2 ? 0x1CC1 : 0x1D2F);
            redraw_map();
            set_owner(-1, si);
            send_home_armies_at(si);
        }
        break;
    case 4:
        show_plotters_picture();
        SW(D_INCOME_LOST, W(D_INCOME_LOST) + W(SIDE(p) + S_INCOME) / 2);
        GLOG(GLOG_NORMAL, "EVENT 4 Sheriff ambushed: %d of this month's income is lost", W(SIDE(p) + S_INCOME) / 2);
        dialog(0x1DA3);
        break;
    case 5:
        GLOG(GLOG_NORMAL, "EVENT 5 catapult sabotaged: %s", W(ARMY(p) + A_CATAPULTS) ? "your campaign army loses one" : "you have none");
        if (W(ARMY(p) + A_CATAPULTS)) {
            SW(ARMY(p) + A_CATAPULTS, W(ARMY(p) + A_CATAPULTS) - 1);
            show_plotters_picture();
            dialog(0x1E1A);
        }
        break;
    case 6:
        for (int s = 1; s < 4; s++) SW(SIDE(s) + S_GOLD, W(SIDE(s) + S_GOLD) + 25);
        GLOG(GLOG_NORMAL, "EVENT 6 Robin raids a Norman stronghold: sides 1-3 get 25 gold");
        dialog(0x1E8C);
        break;
    case 7:
        SW(ARMY(p) + A_KNIGHTS, W(ARMY(p) + A_KNIGHTS) + 3);
        GLOG(GLOG_NORMAL, "EVENT 7 three knights from Germany join your campaign army");
        dialog(0x1EFA);
        break;
    case 8:
        for (si = 4; si < 7; si++) {
            int di = side_last_territory(si);
            if (!di) continue;
            GLOG(GLOG_NORMAL, "EVENT 8 Norman vassals revolt: %s of %s is yours", glog_terr(di), glog_side(si));
            dialog(0x1F56);
            redraw_map();
            set_owner(p, di);
            send_home_armies_at(di);
            break;
        }
        if (si == 7) GLOG(GLOG_NORMAL, "EVENT 8 Norman vassals revolt: no Norman has a territory besides its home");
        break;
    default:
        GLOG(GLOG_VERBOSE, "EVENT %d: nothing happens", n);
        break;
    }
    next_event_in();
    GLOG(GLOG_VERBOSE, "EVENT the next in %d months", W(D_EVENT_IN));
}

/* ------------------------------------------------------------------ choosing a territory (4142) */

/* a cursor on the map from territory t: it flashes; the keypad moves it through
 * the table DS:0B56 (8 a territory: up, down, right, left, up-right, down-left,
 * up-left, down-right); Enter chooses */
int choose_territory(int t)
{
    redraw_map();
    dialog(0x2B68);
    int di = t, si = t;
    for (;;) {
        flash_territory(si, 2);
        if (di) flush_keys();
        static const int8_t DIR[11] = { 6, 0, 4, -1, 3, -1, 2, -1, 5, 1, 7 };   /* scan codes 47h-51h */
        if (di >= 0x47 && di <= 0x51 && DIR[di - 0x47] >= 0) si = (int8_t)B(0xB56 + 8 * si + DIR[di - 0x47]);
        di = get_key();
        if (di == KEY_ENTER) return si;
    }
}

/* ------------------------------------------------------------------ Buy Home Army (39C7) */

/* Right (or Enter on Castles) buys, Left sells back what was bought this time
 * (not more); a refusal is a short click. Castles: choose a territory of yours
 * without one (castle 35, and 10 soldiers in its garrison). Returns 1 if
 * anything was bought (the month goes on). */
static int buy_army(void)
{
    int p = W(D_PLAYER), di = W(SIDE(p) + S_HOME), bought = 0;
    gfx_glyph_alias(0x20, 0x3E);
    int have[7] = { 0 }, had[7] = { 0 };   /* by item: 2 soldiers, 3 knights, 4 catapults, 5 castles */
    have[2] = had[2] = W(GARRISON(di) + A_SOLDIERS);
    have[3] = had[3] = W(GARRISON(di) + A_KNIGHTS);
    have[4] = had[4] = W(GARRISON(di) + A_CATAPULTS);
    redraw_map();
    int si = 2;
    SW(D_LEFTRIGHT, 0);
    static const char *const ITEM[7] = { "", "", "soldier", "knight", "catapult", "castle", "" };
    while (si != 6) {
        if (si == 5 && W(D_LEFTRIGHT) == 0) SW(D_LEFTRIGHT, 1);
        int price = W(D_PRICE + 2 * si);
        if (W(D_LEFTRIGHT) > 0) {
            if (price > W(SIDE(p) + S_GOLD)) {
                snd_speaker_click(250, 2);
            } else if (si == 5) {
                int t = choose_territory(W(SIDE(p) + S_AT));
                if ((int8_t)B(TERR(t) + T_OWNER) != p) {
                    dialog(0x2CF1);
                } else if (B(TERR(t) + T_CASTLE)) {
                    dialog(0x2D1D);
                } else {
                    SB(TERR(t) + T_CASTLE, 35);
                    SW(GARRISON(t) + A_SOLDIERS, W(GARRISON(t) + A_SOLDIERS) + 10);
                    SW(SIDE(p) + S_GOLD, W(SIDE(p) + S_GOLD) - price);
                    bought++;
                    GLOG(GLOG_NORMAL, "YOU buy a castle (%d gold) in %s, with 10 soldiers; %d gold left", price, glog_terr(t), W(SIDE(p) + S_GOLD));
                }
                redraw_map();
            } else {
                SW(SIDE(p) + S_GOLD, W(SIDE(p) + S_GOLD) - price);
                have[si]++;
                bought++;
                GLOG(GLOG_VERBOSE, "YOU buy a %s (%d gold); %d gold left", ITEM[si], price, W(SIDE(p) + S_GOLD));
            }
        } else if (W(D_LEFTRIGHT) < 0) {
            if (have[si] > had[si]) {
                have[si]--;
                bought--;
                SW(SIDE(p) + S_GOLD, W(SIDE(p) + S_GOLD) + price);
                GLOG(GLOG_VERBOSE, "YOU sell back a %s (%d gold); %d gold left", ITEM[si], price, W(SIDE(p) + S_GOLD));
            } else {
                snd_speaker_click(250, 2);
            }
        }
        int e = str_append(0x40A0, W(0x3816));
        e = num_append((unsigned)W(SIDE(p) + S_GOLD), e);
        str_append(0x40AA, e);
        num_append((unsigned)have[2], str_append(0x40B7, W(0x381A)));
        num_append((unsigned)have[3], str_append(0x40C9, W(0x381C)));
        num_append((unsigned)have[4], str_append(0x40DB, W(0x381E)));
        SB(0x3812, si);
        snd_speaker_off();
        si = dialog(0x380B) + 1;
    }
    SW(GARRISON(di) + A_SOLDIERS, have[2]);
    SW(GARRISON(di) + A_KNIGHTS, have[3]);
    SW(GARRISON(di) + A_CATAPULTS, have[4]);
    gfx_glyph_alias(0x20, -1);
    if (bought)
        GLOG(GLOG_NORMAL, "YOU Buy Home Army: %s now has %d soldiers, %d knights, %d catapults; %d gold left", glog_terr(di), have[2], have[3],
             have[4], W(SIDE(p) + S_GOLD));
    return bought != 0;
}

/* ------------------------------------------------------------------ the menus */

static int options_menu(void)   /* 1957 */
{
    int si = 1;
    SW(D_QUIT, 0);
    SB(0x3503, 0);
    for (;;) {
        SW(0x350A, W(W(0x8C5) ? 0x34CF : 0x34BD));
        SW(0x350C, W(W(D_SOUND_ON) ? 0x34F0 : 0x34E1));
        SB(0x3506, si - 1);
        si = dialog(0x34FF);
        switch (si) {
        case 1:   /* the joystick: the remake has none */
            SW(0x8C5, !W(0x8C5));
            break;
        case 2:   /* the music: with it off the tunes still run, silently */
            SW(D_SOUND_ON, !W(D_SOUND_ON));
            SW(D_TUNE_ONCE, W(D_SOUND_ON) ? 0x8000 : 0xA000);
            SW(D_TUNE_LOOP, W(D_SOUND_ON) ? 0xC000 : 0xE000);
            GLOG(GLOG_NORMAL, "YOU options: music %s", W(D_SOUND_ON) ? "on" : "off");
            break;
        case 3:
            SW(0x2B, 1); SW(D_GAME_OVER, 1);
            GLOG(GLOG_NORMAL, "YOU options: Start a New Game");
            return 1;
        case 4:
            SW(D_QUIT, 1); SW(D_GAME_OVER, 1);
            GLOG(GLOG_NORMAL, "YOU options: End Present Game");
            return 1;
        case 5:
            return 0;
        default:
            break;
        }
    }
}

static int orders_menu(void)   /* 1A91 */
{
    int si = 0;
    redraw_map();
    int c = dialog(0x2BC2);
    SB(0x2BC9, c);
    static const char *const N[] = { "", "Hold Tournament", "Seek Conquest", "Go Raiding", "Buy Home Army", "Read Map", "Pass", "Options" };
    if (c >= 1 && c <= 7) GLOG(GLOG_NORMAL, "YOU order: %s", N[c]);
    switch (c) {
    case 1: si = tournament(W(D_PLAYER)); break;
    case 2: si = seek_conquest(); break;
    case 3: si = go_raiding(); break;
    case 4: si = buy_army(); break;
    case 5: si = read_map(); break;
    case 6: {
        int e = str_append(0x3FE1, 0x38F);
        e = str_append(W(SIDE(W(D_PLAYER)) + S_NAME), e);
        str_append(0x3FE7, e);
        dialog(0x2C97);
        si = 1;
        break;
    }
    case 7: si = options_menu(); break;
    default: break;
    }
    return si;
}

/* ------------------------------------------------------------------ the month (1B44) */

static void the_end_sprite(int y)
{
    Video *v = gfx_video();
    v->slot[0] = (Slot){ true, 100, y, F_END, 6, 0, 0, 0 };
    gfx_sprites_draw();
    present();
    gfx_sprites_erase();
    v->slot[0].active = false;
}

void month(void)
{
    for (int si = 1; si < 7; si++) {
        side_income(si);
        if (si == W(D_PLAYER)) {
            SW(D_MONTH, W(D_MONTH) + 1);
            monthly_event();
            month_status();
            int di = rescue_offer();
            while (!di) di = orders_menu();
            if (!W(D_GAME_OVER)) {
                redraw_map();
                dialog(0x2C64);
                flash_territory(W(SIDE(W(D_PLAYER)) + S_HOME), 4);
            }
        } else {
            ai_turn(si);
        }
        side_income(si);
        /* the end: the three Norman castles held by one Saxon */
        int l2 = (int8_t)B(0x73E);
        if ((int8_t)B(0x75C) == l2 && (int8_t)B(0x77A) == l2 && l2 < 4) {
            SW(D_GAME_OVER, 1);
            if (l2 == W(D_PLAYER)) {
                GLOG(GLOG_NORMAL, "END you hold the three Norman castles: you win");
                gfx_clear_back(0);
                play_tune(0x9E, W(D_TUNE_ONCE));
                dialog(0x3986);
                dialog(0x3ACF);
                gfx_show_picture(PIC_LAND);
                gfx_set_palette();
                present();
                wait_ticks(0x36);
                the_end_sprite(30);
                wait_tune(0x9E);
            } else {
                GLOG(GLOG_NORMAL, "END %s holds the three Norman castles: you lose", glog_side(l2));
                gfx_clear_back(0);
                play_tune(0x9D, W(D_TUNE_ONCE));
                dialog(0x3E93);
                the_end_sprite(116);
                wait_tune(0x9D);
            }
        }
        /* the home castle */
        if ((int8_t)B(TERR(W(SIDE(W(D_PLAYER)) + S_HOME)) + T_OWNER) != W(D_PLAYER)) {
            SW(D_GAME_OVER, 1);
            GLOG(GLOG_NORMAL, "END your home castle %s has fallen: you lose", glog_terr(W(SIDE(W(D_PLAYER)) + S_HOME)));
            gfx_clear_back(0);
            play_tune(0x9D, W(D_TUNE_ONCE));
            dialog(0x3C14);
            gfx_clear_back(0);
            dialog(0x3D5A);
            the_end_sprite(127);
            wait_tune(0x9D);
        } else if (W(D_QUIT)) {
            SW(D_GAME_OVER, 1);
        } else {
            /* the code adds Buckingham's owner twice and never looks at Cornwall (1E6C; --fix=hostility) */
            int sum = (int8_t)B(0x73E) + (int8_t)B(0x75C) + (int8_t)B(fixed(FIX_HOSTILITY) ? 0x77A : 0x75C);
            if (sum < 12) {
                enmity_add(2, W(D_PLAYER), 2);
                enmity_add(3, W(D_PLAYER), 2);
                GLOG(GLOG_VERBOSE, "ENMITY Norfolk's owner + %s = %d < 12: sides 2 and 3 +2 against you (now %d, %d)",
                     fixed(FIX_HOSTILITY) ? "Buckingham's + Cornwall's" : "twice Buckingham's", sum, W(ENMITY(2, W(D_PLAYER))),
                     W(ENMITY(3, W(D_PLAYER))));
            }
        }
        if (W(D_GAME_OVER)) {
            if (!W(D_QUIT) && !W(0x2B)) {
                wait_ticks(0x24);
                gfx_clear_back(0);
                dialog(0x3541);
                if (dialog(0x356C) == 2) SW(D_QUIT, 1);
            }
            return;
        }
    }
}
