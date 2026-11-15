/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * game.c: the program's own helpers (AB 7A80 dialog, the tunes, the random
 * numbers), main (1014) and new_game (10B2): the opening, the choice of
 * character, Sherwood and the setup. See game.h.
 */
#include "game.h"
#include "gamelog.h"
#include "month.h"

/* initialised, so it is not a common symbol: Apple's linker aligns those by their size and warns
 * ("reducing alignment of section __DATA,__common") */
uint8_t ds[65536] = { 0 };

const char *const FIX_NAMES[FIX_COUNT] = { "viking", "hostility", "targets", "catapult", "siege-merge",
                                           "joust-opponent", "joust-margin", "battle-text", "siege-sprite" };
unsigned g_fixes;
bool g_dos_rules;
int g_catapult_pull = 2;
int g_sword_pace = 3;
int g_joust_pace = 4;

bool fixes_parse(const char *list, char *err, size_t errlen)
{
    unsigned f = 0;
    const char *p = list;
    while (*p) {
        const char *e = SDL_strchr(p, ',');
        size_t n = e ? (size_t)(e - p) : SDL_strlen(p);
        bool known = false;
        if (n == 3 && SDL_strncmp(p, "all", 3) == 0) { f = (1u << FIX_COUNT) - 1; known = true; }
        for (int i = 0; i < FIX_COUNT && !known; i++)
            if (SDL_strlen(FIX_NAMES[i]) == n && SDL_strncmp(p, FIX_NAMES[i], n) == 0) { f |= 1u << i; known = true; }
        if (!known && n) {
            SDL_snprintf(err, errlen, "unknown fix '%.*s'", (int)n, p);
            return false;
        }
        p += n;
        if (*p == ',') p++;
    }
    g_fixes = f;
    return true;
}

/* ------------------------------------------------------------------ helpers */

/* DOC.EXE unpacks a picture off screen and shows it (070A:01B3) in 4 passes, two
 * ticks each: lines 2p + 8k after a tick, then lines 2p + 8k + 1 after another
 * (its CGA's two banks): the first present after a picture, in the CGA (1987)
 * mode under the DOS rules (the other modes show it at once, then wait as well) */
static void dos_wipe(void)
{
    gfx_present_rows_m(BOOT_MODES, 0, 1);
    sys_frame_done();
    for (int p = 0; p < 4; p++) {
        wait_ticks(1);
        gfx_present_rows_m(DOS_MODES, 2 * p, 8);
        sys_frame_done();
        wait_ticks(1);
        gfx_present_rows_m(DOS_MODES, 2 * p + 1, 8);
        sys_frame_done();
    }
}

void present(void)                                                                     /* 9902 */
{
    sys_retrace();
    if (gfx_take_wipe() && g_dos_rules) dos_wipe();
    else gfx_present();
    sys_frame_done();
}
void present_bottom(void) { sys_retrace(); gfx_present_bottom(); sys_frame_done(); }   /* 994A */

/* 9DDB */
static void lfsr_step(void)
{
    unsigned v = UW(D_RANDOM);
    unsigned c = v & 1;
    v >>= 1;
    if (c) v ^= 0xB400;
    SW(D_RANDOM, (int)v);
}

/* 9DB3: the BIOS tick count's low word (never 0), then that many more steps */
static void seed_random(void)
{
    uint32_t t;
    while (!((t = sys_ticks()) & 0xFFFF)) sys_check();
    SW(0x5D, (int)(t >> 16));
    SW(D_RANDOM, (int)(t & 0xFFFF));
    unsigned si;
    while (!(si = sys_ticks() & 0xFFFF)) sys_check();
    do { lfsr_step(); } while (--si & 0xFFFF);
    SW(D_RANDOM_N, 0xFFFF);
}

/* DOC.EXE's random numbers: Aztec C's ran() (0AFF:0009), seed = seed x 125 mod
 * 2796203 from 100001 (DS:40D2), as a double in 0..1 */
static uint32_t dos_seed = 100001;

static double dos_ran(void)
{
    dos_seed = (uint32_t)(((uint64_t)dos_seed * 125u) % 2796203u);
    return dos_seed / 2796203.0;
}

void set_dos_rules(bool on)
{
    g_dos_rules = on;
    sys_dos_ticks(on);
}

/* DOC 021C:0002, the first game only: ran() (BIOS ticks & 1FFh) + 1 times */
static void dos_seed_random(void)
{
    static bool seeded;
    if (seeded) return;
    seeded = true;
    for (int si = (int)(sys_ticks() & 0x1FF); si >= 0; si--) dos_ran();
}

/* 9D96 */
unsigned random_next(void)
{
    unsigned v = UW(D_RANDOM);
    unsigned c = v & 1;
    v >>= 1;
    if (c) v ^= 0xB400;
    SW(D_RANDOM, (int)v);
    SW(D_RANDOM_N, W(D_RANDOM_N) - 1);
    if (!UW(D_RANDOM_N)) { seed_random(); return 0; }
    return v;
}

/* 9CFC: 0 .. n-1 */
int random_n(int n)
{
    if (!n) return 0;
    if (g_dos_rules) {   /* DOC 070A:000D */
        unsigned d = (unsigned)(int)(dos_ran() * 32767.0) & 0xFFFF;
        if (n < 0x100) d >>= 8;
        return (int)(d % (unsigned)n);
    }
    unsigned v = (random_next() * 0x7FFFu) & 0xFFFF;
    if ((unsigned)n < 0x100) v >>= 8;
    return (int)(v % (unsigned)n);
}

/* 9D33: a[0..n-1] = 0..n-1 shuffled */
static void shuffle(int *a, int n)
{
    for (int i = 0; i < n; i++) a[i] = i;
    for (int i = 0; i < n; i++) {
        int j = g_dos_rules ? (int)(dos_ran() * 32767.0) % n   /* DOC 070A:005C */
                            : (int)(((random_next() * 0x7FFFu) & 0xFFFF) % (unsigned)n);
        int t = a[j]; a[j] = a[i]; a[i] = t;
    }
}

void play_tune(int tune, int flags) { snd_play_tune(tune, flags & 0xFFFF); }   /* 9559 */

void wait_tune(int tune)            /* 958E */
{
    (void)tune;
    snd_tune_clear_loop();
    while (!(snd_tune_flags() & 1)) get_key();
}

int tune_playing(int tune, int n)   /* 95BE */
{
    (void)tune;
    get_key();
    if (n && snd_tune_index() >= n) return 0;
    return (snd_tune_flags() & 1) ? 0 : 1;
}

void beep(int divisor, int ticks)   /* 9520 */
{
    snd_speaker_tone(divisor);
    delay_ticks(ticks);
    snd_speaker_off();
}

/* ------------------------------------------------------------------ dialog (7A80) */

/* The 12 bytes at DS:box: x (4-pixel units), y, lines, width, icon (-2: the text
 * only; -3: a box without its frame; -1: the box but no text), the first and last
 * line to choose from (the first < 0: not a menu), the line chosen at first
 * (also lets Left and Right end it), the ticks to wait at the end, then a word:
 * the table of the lines' pointers. A menu returns the line chosen (1 = the
 * first one it can choose); Left/Right set DS:0A9C to -1 or 1. */
static const char *dos_text[16];   /* dialog_dos_text: lines the DOS version wrote its own way */

void dialog_dos_text(int line, const char *s) { if (line >= 0 && line < 16) dos_text[line] = s; }

/* a line of the next dialog (box), at the line pointer line_ptr, as DOC.EXE's
 * sprintf wrote it (its "%d" has no space before numbers under 10, as the booter's
 * 94B5 has, and its labels end in a space more where the booter's add one) */
void dialog_dos_fmt(int box, int line_ptr, const char *fmt, ...)
{
    if (!DOS_MODES) return;
    static char buf[16][100];
    static int next;
    char *b = buf[next];
    next = (next + 1) % 16;
    va_list ap;
    va_start(ap, fmt);
    SDL_vsnprintf(b, sizeof buf[0], fmt, ap);
    va_end(ap);
    dialog_dos_text((line_ptr - UW(box + 9)) / 2, b);
}

/* the lines of DOC.EXE's own box (13 bytes in its data segment: as the booter's, with
 * a far pointer to a table of far pointers), for the next dialog in its mode */
void dialog_dos_box(int doc_box)
{
    if (!DOS_MODES) return;
    int n = (int8_t)DB(doc_box + 2), tab = (uint16_t)DW(doc_box + 9);
    for (int i = 0; i < n && i < 16; i++) dos_text[i] = (const char *)&gfx_assets()->doc_ds[(uint16_t)DW(tab + 4 * i)];
}

int dialog(int box)
{
    int x0 = (int8_t)B(box), y0 = B(box + 1), n = (int8_t)B(box + 2), wd = (int8_t)B(box + 3);
    int icon = (int8_t)B(box + 4), first = (int8_t)B(box + 5), last = (int8_t)B(box + 6), start = (int8_t)B(box + 7);
    int wait = B(box + 8), lines = UW(box + 9);
    if (icon != -2) {
        int x1 = x0 + wd - 4, y1 = (n + 1) * 11 + y0;
        /* the corners, then the top and bottom (14h-19h), then the sides (1Ah-1Dh) */
        struct { int x, y, piece; } p[200];
        int k = 0;
        p[k++] = (typeof(p[0])){ x0, y0, 0x7B };
        p[k++] = (typeof(p[0])){ x0, y1, 0x7C };
        p[k++] = (typeof(p[0])){ x1, y0, 0x7D };
        p[k++] = (typeof(p[0])){ x1, y1, 0x7E };
        int di = 0x14;
        for (int x = x0 + 4; x < x1 && k < 198; x += 2) {
            p[k++] = (typeof(p[0])){ x, y0, di };
            p[k++] = (typeof(p[0])){ x, y1, di + 1 };
            di += 2;
            if (di > 0x19) di = 0x14;
        }
        di = 0x1A;
        for (int y = y0 + 11; y < y1 && k < 198; y += 11) {
            p[k++] = (typeof(p[0])){ x0, y, di };
            p[k++] = (typeof(p[0])){ x1, y, di + 1 };
            di += 2;
            if (di > 0x1D) di = 0x1A;
        }
        gfx_fill_rect(x0 + 4, y0 + 11, wd - 8, (y1 - y0) - 11, 0xDDFF);
        if (icon != -3)
            for (int i = 0; i < k; i++) gfx_slot_sprite(p[i].x * 4, p[i].y, F_FONT, p[i].piece);
    }
    if (icon != -1) {
        int x = x0 * 4 + 20, y = y0 + 13;
        for (int i = 0; i < n; i++) {
            const uint8_t *s = &ds[UW(lines + 2 * i)];
            const char *d = i < 16 && DOS_MODES ? dos_text[i] : NULL;
            for (; *s; s++) {
                gfx_glyph_m(d ? BOOT_MODES : MODES_ALL, x, y, *s);
                x += gfx_glyph_advance(*s);
            }
            for (x = x0 * 4 + 20; d && *d; d++) {   /* in the DOS version's mode, its own line in its own font */
                gfx_glyph_m(DOS_MODES, x, y, (uint8_t)*d);
                x += gfx_glyph_advance_m(MODE_CGA1, (uint8_t)*d);
            }
            x = x0 * 4 + 20;
            y += 11;
        }
    }
    SDL_zeroa(dos_text);
    present();
    int si = first;
    if (si < 0) { wait_ticks(wait); return si; }
    flush_keys();
    if (start >= 0) si = start;
    int di = -1, key = -1;
    int hx = x0 + 4, hw = wd - 8, hy = 0;
    SW(0x0A9C, 0);
    for (;;) {
        switch (key) {
        case KEY_UP:    if (--si < first) si = last; break;
        case KEY_LEFT:  if (start >= 0 && icon != 1) SW(0x0A9C, -1); break;
        case KEY_RIGHT: if (start >= 0 && icon != 1) SW(0x0A9C, 1); break;
        case KEY_DOWN:  if (++si > last) si = first; break;
        default: break;
        }
        if (si != di) {
            if (di >= 0) { hy = (di + 1) * 11 + y0; gfx_xor_rect3(hx, hy, hw, 11, 0xFFFF, 0xF0F, 0xFFFF); }
            di = si;
            hy = (di + 1) * 11 + y0;
            gfx_xor_rect3(hx, hy, hw, 11, 0xFFFF, 0xF0F, 0xFFFF);
        }
        present();
        if (W(0x0A9C)) break;
        key = wait_key();
        if (key == KEY_ENTER) break;
    }
    gfx_xor_rect3(hx, hy, hw, 11, 0xFFFF, 0xF0F, 0xFFFF);
    present();
    si = si - first + 1;
    wait_ticks(wait);
    return si;
}

/* ------------------------------------------------------------------ the opening */

/* 179A: a sparkle around (x, y): 11 rounds of 4 pixels (offsets DS:0936) turn
 * white, a pause of 2 ticks, the same 11 rounds put back, the centre put back,
 * then d ticks. Each round waits a busy loop of DS:0005 x 1500 (about 7 ms
 * on the machines the speed classes were made for). */
static void twinkle_pixel(int x, int y)
{
    gfx_put_pixel_m(BOOT_MODES, PAGE_SCREEN, x, y, 0xF);
    gfx_put_pixel_m(DOS_MODES, PAGE_SCREEN, x, y, 1);   /* DOC 021C:086F: colour 1 (green), put whole (093C:000F) */
}

static int title_twinkle(int x, int y, int d)
{
    int saved[MODE_COUNT][45];
    int k = 0;
    for (int m = 0; m < MODE_COUNT; m++) saved[m][0] = gfx_get_pixel((Mode)m, PAGE_SCREEN, x, y);
    twinkle_pixel(x, y);
    for (int r = 0; r < 11; r++) {
        for (int i = 0; i < 4; i++) {
            k++;
            int px = x + (int8_t)B(0x936 + 2 * k), py = y + (int8_t)B(0x937 + 2 * k);
            for (int m = 0; m < MODE_COUNT; m++) saved[m][k] = gfx_get_pixel((Mode)m, PAGE_SCREEN, px, py);
            twinkle_pixel(px, py);
        }
        sys_frame_done();
        SDL_DelayNS(7000000);
        sys_check();
    }
    delay_ticks(2);
    for (int r = 0; r < 11; r++) {
        for (int i = 0; i < 4; i++) {
            int px = x + (int8_t)B(0x936 + 2 * k), py = y + (int8_t)B(0x937 + 2 * k);
            for (int m = 0; m < MODE_COUNT; m++) {   /* each mode puts back its own pixel */
                gfx_lock();
                gfx_video()->px[m][PAGE_SCREEN][py * SCREEN_W + px] = (uint8_t)saved[m][k];
                gfx_unlock();
            }
            k--;
        }
        sys_frame_done();
        SDL_DelayNS(7000000);
        sys_check();
    }
    for (int m = 0; m < MODE_COUNT; m++) {
        gfx_lock();
        gfx_video()->px[m][PAGE_SCREEN][y * SCREEN_W + x] = (uint8_t)saved[m][0];
        gfx_unlock();
    }
    sys_frame_done();
    delay_ticks(d);
    return get_key();
}

/* 18C9: the campfire (frames: off, flame 1, flame 2), each shown with present_bottom */
static int fire_phase;

static void fire_flicker(int frames)
{
    static uint32_t rnd = 12345;   /* the CGA program's random place for its flame (not the game's random numbers) */
    for (int i = 0; i < frames; i++) {
        get_key();
        rnd = rnd * 1103515245u + 12345u;
        int pos = g_dos_rules ? random_n(4) : (int)((rnd >> 16) & 3);   /* DOC 021C:0996: the game's random(4) */
        gfx_fire_draw(fire_phase, 144, 121, B(0x92E + 2 * pos), B(0x92F + 2 * pos));
        present_bottom();
        gfx_fire_erase();
        if (++fire_phase >= 3) fire_phase = 0;
    }
}

/* 9898 asked "Please insert reel two and press any key to continue..." after the
 * opening: the remake has both reels at once and leaves it out (a deliberate
 * difference). */

/* after S has skipped part of the opening: what was left half done */
static void skipped(int tune)
{
    play_tune(tune, W(D_TUNE_STOP));
    gfx_fire_erase();
    for (int k = 0; k < NUM_SLOTS; k++) gfx_video()->slot[k].active = false;
    flush_keys();
}

/* ------------------------------------------------------------------ the setup */

static void copy_lord(int from, int to)   /* 236D: a lord's record into a side's */
{
    SW(to + 0, W(from + 0));
    SW(to + 2, W(from + 2));
    SW(to + 4, W(from + 4));
    SW(to + 0x10, W(from + 6));    /* leadership */
    SW(to + 0x0E, W(from + 8));    /* jousting */
    SW(to + 0x12, W(from + 0xA));  /* swordplay */
    SW(to + 0x0C, W(from + 0xC));
    SW(to + 0x16, W(from + 0xE));  /* gold */
}

static void setup_sides(void)   /* 21CC */
{
    int a[6];
    shuffle(a, 3);
    SW(SIDE(a[0] + 1) + S_HOME, 1);
    SW(SIDE(a[1] + 1) + S_HOME, 5);
    SW(SIDE(a[2] + 1) + S_HOME, 8);
    SW(SIDE(4) + S_HOME, 11);
    SW(SIDE(5) + S_HOME, 13);
    SW(SIDE(6) + S_HOME, 15);
    SW(0x9D, 0);
    copy_lord(((W(D_PLAYER) - 1) << 4) + 0x4E7, 0xB7);   /* the character chosen becomes side 1 */
    SW(D_PLAYER, 1);
    SW(0x1C0D, W(SIDE(W(D_PLAYER)) + S_NAME));
    shuffle(a, 4);
    for (int di = 2, i = 0; di <= 3; i++) {   /* two of the other three Saxons */
        if (W(LORD(a[i]) + 0) == W(SIDE(W(D_PLAYER)) + S_NAME)) continue;
        copy_lord(LORD(a[i]), SIDE(di));
        di++;
    }
    shuffle(a, 5);
    for (int si = 0; si < 3; si++) copy_lord((a[si] << 4) + 0x537, SIDE(si + 4));   /* three of the five Normans */
    for (int si = 1; si < 7; si++) {
        SW(SIDE(si) + S_LADY, -1);
        SW(SIDE(si) + S_AT, W(SIDE(si) + S_HOME));
        SW(SIDE(si) + S_INCOME, (int8_t)B(TERR(W(SIDE(si) + S_HOME)) + T_INCOME));
    }
}

static void place_castles(void)   /* 3CAF */
{
    SB(TERR(W(SIDE(1) + S_HOME)) + T_OWNER, 1);
    SB(0x6A9, 30);                         /* terr 1's castle, whoever's home it is */
    SB(0x6B7, 0xFF); SB(0x6B8, 0);
    SB(0x6C6, 0xFF); SB(0x6C7, 0);
    SB(0x6D5, 0xFF); SB(0x6D6, 0);
    SB(TERR(W(SIDE(2) + S_HOME)) + T_OWNER, 2);
    SB(0x6E5, 30);
    SB(0x6F3, 0xFF); SB(0x6F4, 0);
    SB(0x702, 0xFF); SB(0x703, 0);
    SB(TERR(W(SIDE(3) + S_HOME)) + T_OWNER, 3);
    SB(0x712, 30);
    SB(0x720, 0xFF); SB(0x721, 0);
    SB(0x72F, 0xFF); SB(0x730, 0);
    SB(0x73E, 4); SB(0x73F, 30);
    SB(0x74D, 0xFF); SB(0x74E, 0);
    SB(0x75C, 5); SB(0x75D, 30);
    SB(0x76B, 0xFF); SB(0x76C, 0);
    SB(0x77A, 6); SB(0x77B, 30);
    SB(0x789, 0xFF); SB(0x78A, 0);
    SB(0x798, 0xFF); SB(0x799, 0);
    SB(0x7A7, 0xFF); SB(0x7A8, 0);
}

void lady_to_side(int lady, int side, int flag)   /* 24B1 */
{
    if (W(LADY(lady) + L_SIDE) != -1) SW(SIDE(W(LADY(lady) + L_SIDE)) + S_LADY, -1);
    SW(SIDE(side) + S_LADY, lady);
    SW(LADY(lady) + L_SIDE, side);
    SW(LADY(lady) + L_TERR, W(SIDE(side) + S_HOME));
    SW(LADY(lady) + L_FLAG, flag);
}

static void setup_ladies(void)   /* 243B */
{
    int a[4];
    SW(D_KIDNAPPED, -1);
    shuffle(a, 4);
    for (int si = 0; si < 4; si++) {
        SW(LADY(si) + L_SIDE, -1);
        SW(LADY(si) + L_TERR, 0);
        SW(LADY(si) + L_FLAG, 0);
    }
    lady_to_side(a[0], 2, 1);
    lady_to_side(a[1], 3, 1);
}

static void setup_garrisons(void)   /* 1FB3 */
{
    for (int si = 1; si < 19; si++) {
        SW(ARMY(si + 7) + A_AT, si);
        SW(ARMY(si + 7) + A_BASE, si);
        SW(ARMY(si + 7) + A_SOLDIERS, (int8_t)B(TERR(si) + T_VASSALS));
        SW(ARMY(si + 7) + A_KNIGHTS, 0);
        SW(ARMY(si + 7) + A_CATAPULTS, 0);
    }
}

static void setup_armies(void)   /* 1F11 */
{
    for (int si = 1; si < 7; si++) {
        SW(ARMY(si) + A_AT, W(SIDE(si) + S_HOME));
        SW(ARMY(si) + A_BASE, W(SIDE(si) + S_HOME));
        SW(ARMY(si) + A_SOLDIERS, 15);
        SW(ARMY(si) + A_KNIGHTS, 0);
        SW(ARMY(si) + A_CATAPULTS, 0);
        int di = 5;
        if (si == 1) { di = 10; SW(ARMY(1) + A_SOLDIERS, 0); }
        SW(ARMY(W(ARMY(si) + A_AT) + 7) + A_SOLDIERS, di);
    }
}

void next_event_in(void) { SW(D_EVENT_IN, random_n(8) + 5); }   /* 2EEC */

void enmity_add(int a, int b, int d)   /* 25E5: both ways, kept within -10..10 */
{
    if (a < 1 || a > 6 || b < 1 || b > 6 || a == b) return;
    int v = W(ENMITY(a, b)) + d;
    SW(ENMITY(a, b), v < -10 ? -10 : v > 10 ? 10 : v);
    v = W(ENMITY(b, a)) + d;
    SW(ENMITY(b, a), v < -10 ? -10 : v > 10 ? 10 : v);
}

static void setup_enmity(void)   /* 2556 */
{
    for (int si = 6; si; si--)
        for (int di = 6; di; di--)
            SW(ENMITY(si, di), ((si < 4 && di > 3) || (si > 3 && di < 4)) ? 2 : 0);
    enmity_add(4, 1, 3);
    enmity_add(5, 1, 3);
    enmity_add(6, 1, 3);
}

/* the owners' colours on the map, each program its own table: CGA DS:0C62 (patterns XORed
 * in), Tandy DS:0C70 (two nibbles), EGA DS:0C7E (set/reset planes and values) */
void set_region_colour(int t, int owner)   /* 9719 */
{
    int c[MODE_COUNT];
    c[MODE_CGA1] = c[MODE_CGA2] = UW(0x0C62 + 2 * owner);
    c[MODE_TANDY] = UW(0x0C70 + 2 * owner);
    c[MODE_EGA] = UW(0x0C7E + 2 * owner);
    gfx_set_region_colour(t + 1, c);
}

/* ------------------------------------------------------------------ new_game (10B2) */

static void character_choice(void)
{
    int di = -1, si = -1;
    for (;;) {
        int ofs = -1;
        switch (si) {
        case 0x48: ofs = 0; break;   /* 8 */
        case 0x49: ofs = 1; break;   /* 9 */
        case 0x4D: ofs = 2; break;   /* 6 */
        case 0x51: ofs = 3; break;   /* 3 */
        case 0x50: ofs = 4; break;   /* 2 */
        case 0x4F: ofs = 5; break;   /* 1 */
        case 0x4B: ofs = 6; break;   /* 4 */
        case 0x47: ofs = 7; break;   /* 7 */
        default: break;
        }
        if (ofs >= 0) {
            int nb = (int8_t)B(0x906 + 8 * W(D_PLAYER) + ofs);
            if (nb) SW(D_PLAYER, nb);
        }
        if (W(D_PLAYER) != di) {
            if (di >= 0) {
                gfx_xor_sprite_m(BOOT_MODES, W(0x8F2 + 2 * di), W(0x8FC + 2 * di), F_CHARS, di + 7);
                gfx_xor_sprite_m(DOS_MODES, DW(0x3214 + 2 * di), DW(0x321E + 2 * di), F_CHARS, di + 7);   /* DOC 021C:061F */
            }
            di = W(D_PLAYER);
            gfx_xor_sprite_m(BOOT_MODES, W(0x8F2 + 2 * di), W(0x8FC + 2 * di), F_CHARS, di + 7);
            gfx_xor_sprite_m(DOS_MODES, DW(0x3214 + 2 * di), DW(0x321E + 2 * di), F_CHARS, di + 7);
        }
        present();
        si = wait_key();
        if (si == KEY_ENTER) break;
    }
}

static void new_game(void)
{
    if (g_dos_rules) dos_seed_random();
    else seed_random();
    SW(0x67, 0);
    SW(D_PLAYER, 1);
    play_tune(0x97, W(D_TUNE_STOP));
    jmp_buf skip;
    if (W(D_FIRST_GAME) && setjmp(skip)) {
        skipped(0x97);
    } else if (W(D_FIRST_GAME)) {
        /* the remake's own: S skips the rest of the opening, to the choice of character */
        sys_skip_arm(&skip);
        gfx_show_picture(PIC_SCROLL);
        gfx_set_palette();
        dialog_dos_box(0x239);   /* DOC 021C:01BE, and its own texts below ("Master Designer Software"; two credits left blank) */
        dialog(0x12D4);
        play_tune(0x97, W(D_TUNE_ONCE));
        if (g_dos_rules) { gfx_show_picture(PIC_SCROLL); gfx_no_wipe(); }   /* DOC 021C:01E3: the scroll again, at once */
        dialog_dos_box(0x310);
        dialog(0x1351);
        gfx_show_picture(PIC_TITLE);
        present();
        gfx_set_palette();
        delay_ticks(36);
        bool skip = (get_key() & 0xFF) != 0;
        static const int TW[6][3] = { { 55, 67, 9 }, { 0x112, 41, 18 }, { 117, 98, 9 }, { 223, 97, 18 }, { 122, 156, 9 }, { 247, 141, 9 } };
        for (int i = 0; i < 6 && !skip; i++) skip = (title_twinkle(TW[i][0], TW[i][1], TW[i][2]) & 0xFF) != 0;
        if (!skip) {
            gfx_show_picture(PIC_SCROLL);
            gfx_put_sprite_m(DOS_MODES, 0x1C, 10, F_CHARS, 12);   /* DOC 021C:0341: the crown (TITLE item 12) */
            dialog_dos_box(0x3C3);
            dialog(0x1405);
            gfx_fill_rect(20, 61, 42, 78, 0xDDFF);
            dialog_dos_box(0x426);
            dialog(0x14A9);
            dialog_dos_box(0x483);
            dialog(0x1505);
            dialog_dos_box(0x52E);
            dialog(0x155B);
            gfx_fill_rect(20, 61, 42, 78, 0xDDFF);
            dialog_dos_box(0x579);
            dialog(0x15F7);
            dialog_dos_box(0x5CC);
            dialog(0x163D);
            dialog_dos_box(0x627);
            dialog(0x1689);
            gfx_show_picture(PIC_CAST);
            gfx_no_wipe();   /* DOC 021C:032D-04FA: the cast and the introduction at once */
            present();
            gfx_set_palette();
            wait_ticks(108);
            gfx_show_picture(PIC_INTRO);
            gfx_no_wipe();
            present();
            gfx_set_palette();
            wait_ticks(180);
        } else {
            play_tune(0x97, W(D_TUNE_STOP));
        }
        sys_skip_disarm();
    }
    /* the map: its palette kept as slot 0, its planes at A000:6000 (redraw_map takes them from there) */
    gfx_keep_palette(PIC_MAP, 0);
    gfx_picture_to(PIC_MAP, PAGE_MAP);
    wait_tune(0x97);
    gfx_show_picture(PIC_CHOOSE);
    present();
    gfx_set_palette();
    character_choice();
    int chosen = W(D_PLAYER);
    if (setjmp(skip)) {
        skipped(0x98);
        goto setup;
    }
    sys_skip_arm(&skip);   /* the remake's own: S skips Sherwood */
    gfx_show_picture(PIC_SHERWOOD);
    present();
    gfx_set_palette();
    play_tune(0x98, W(D_TUNE_ONCE));
    dialog(0x16DD);
    while (tune_playing(0x98, 0)) fire_flicker(4);
    play_tune(0x98, W(D_TUNE_ONCE));
    gfx_show_picture(PIC_SHERWOOD);
    gfx_set_palette();
    dialog_dos_box(0x96A);   /* DOC's own text ("Killing the King") */
    dialog(0x1865);
    while (tune_playing(0x98, 0)) fire_flicker(4);
    fire_flicker(125);
    sys_skip_disarm();
setup:
    SB(0x2BC9, 1);
    SW(0x3B, 0); SW(0x3D, 0); SW(0x3F, 0);
    SW(0x41, -1);
    SW(D_MONTH, 0);
    SW(D_MONTH_NO, 8);
    SW(D_YEAR, 1149);
    SW(D_MORALE, 30);
    SW(0x4B, 0); SW(0x4D, 0); SW(0x4F, 0);
    setup_sides();
    place_castles();
    setup_ladies();
    setup_garrisons();
    setup_armies();
    next_event_in();
    setup_enmity();
    for (int si = 0; si < 7; si++) SW(0x24B + 2 * si, -1);
    for (int si = 1; si < 19; si++) {
        int di = (int8_t)B(TERR(si) + T_OWNER);
        if (di != -1) set_region_colour(si, di);
    }
    play_tune(0x98, W(D_TUNE_STOP));
    gamelog_begin(chosen);
}

/* ------------------------------------------------------------------ main (1014) */

void game_main(void)
{
    const Assets *a = gfx_assets();
    SDL_memcpy(ds, a->bh, a->bh_len);
    SB(D_MEMORY, 10);      /* int 2Ch: memory enough to keep every file */
    SB(D_SPEED, 1);
    SW(0x0006, 1);         /* video type: EGA */
    for (;;) {
        if (W(D_QUIT)) break;
        play_tune(0, 0);
        new_game();
        SW(0x2B, 0);
        SW(D_GAME_OVER, 0);
        SW(D_FIRST_GAME, 0);
        while (!W(D_GAME_OVER)) month();
        gamelog_end(W(D_QUIT) ? "The player quit" : "The game is over");
    }
}
