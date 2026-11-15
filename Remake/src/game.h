/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * game.h: the game, ported from the booter's EGA program AB routine by
 * routine (addresses and names as in Analysis/AB.ASM and GAME_LOGIC.md).
 *
 * The game's data lives where the original kept it: the data file BH is the
 * data segment (DS = 1200h), and the game reads and writes it at the same
 * offsets (side DS:009F, territories DS:0695 ...), with the original's
 * 16-bit words, signed or unsigned as each comparison was. That keeps its
 * quirks (Analysis/GAME_LOGIC.md lists them).
 */
#ifndef DOTC_GAME_H
#define DOTC_GAME_H

#include "assets.h"
#include "gfx.h"
#include "sys.h"
#include "sound.h"

#include <stdint.h>

extern uint8_t ds[65536];

static inline int  B(int o)          { return ds[o & 0xFFFF]; }
static inline void SB(int o, int v)  { ds[o & 0xFFFF] = (uint8_t)v; }
static inline int  W(int o)          { return (int16_t)(ds[o & 0xFFFF] | (ds[(o + 1) & 0xFFFF] << 8)); }   /* signed */
static inline unsigned UW(int o)     { return (uint16_t)(ds[o & 0xFFFF] | (ds[(o + 1) & 0xFFFF] << 8)); }
static inline void SW(int o, int v)  { ds[o & 0xFFFF] = (uint8_t)v; ds[(o + 1) & 0xFFFF] = (uint8_t)(v >> 8); }
static inline const char *STR(int o) { return (const char *)&ds[(uint16_t)o]; }

/* the records (Analysis/tools/ds_names.txt) */
#define SIDE(i)      (0x009F + 24 * (i))
#define  S_NAME      0
#define  S_PORTRAIT  4
#define  S_LADY      6
#define  S_HOME      8
#define  S_AT        10
#define  S_SPEND     12
#define  S_JOUST     14
#define  S_LEAD      16
#define  S_SWORD     18
#define  S_INCOME    20
#define  S_GOLD      22
#define TERR(t)      (0x0695 + 15 * (t))
#define  T_NAME      0
#define  T_OWNER     4      /* byte, FFh = none */
#define  T_CASTLE    5      /* byte */
#define  T_VASSALS   6      /* byte */
#define  T_INCOME    7      /* byte */
#define  T_NB        8      /* bytes: neighbours */
#define LORD(i)      (0x04E7 + 16 * (i))
#define LADY(i)      (0x0478 + 8 * (i))
#define  L_NAME      0
#define  L_SIDE      2
#define  L_TERR      4
#define  L_FLAG      6
#define ARMY(i)      (0x0147 + 10 * (i))   /* 0-6 campaign armies, 7 + t garrison of territory t */
#define  A_AT        0
#define  A_BASE      2
#define  A_SOLDIERS  4
#define  A_KNIGHTS   6
#define  A_CATAPULTS 8
#define ENMITY(a, b) (0x0416 + 14 * (a) + 2 * (b))

#define D_PLAYER     0x0051
#define D_GAME_OVER  0x002D
#define D_QUIT       0x0029
#define D_MONTH      0x0043     /* months played */
#define D_MONTH_NO   0x0045     /* 0 = January */
#define D_YEAR       0x0047
#define D_MORALE     0x0049
#define D_KIDNAPPED  0x0053
#define D_EVENT_IN   0x0055
#define D_RANDOM     0x005B
#define D_RANDOM_N   0x0025
#define D_SOUND_ON   0x0033
#define D_TUNE_ONCE  0x0035
#define D_TUNE_LOOP  0x0037
#define D_TUNE_STOP  0x0039
#define D_FIRST_GAME 0x002F
#define D_SIEGE_SHOWN 0x003F    /* the siege's messages are shown: the battle skips its own */
#define D_MAP_SHOWN  0x0067     /* redraw_map sets it; set_owner redraws the map while it is 0 */
#define D_INCOME_LOST 0x0D2E
#define D_LEFTRIGHT  0x0A9C     /* dialog: Left -1, Right 1 */
#define D_LAST_ORDER 0x024B     /* words by side: the computer lords' last orders */
#define D_PRICE      0x0A90     /* words by item 2-5: soldier 1, knight 8, catapult 15, castle 20 */
#define D_DMG_TO_ATT 0x0B4C     /* battle_round: the damage done to the attackers */
#define D_DMG_TO_DEF 0x0B4E     /* and to the defenders */
#define GARRISON(t)  ARMY(7 + (t))
#define D_MEMORY     0x0004     /* 64K blocks (int 2Ch AH) */
#define D_SPEED      0x0005     /* the CPU's speed class (int 2Ch AL, GameSYS 08BD) */

/* the game thread's entry: AB's main (1014) */
void game_main(void);

/* the original's helpers used everywhere */
void present(void);
void present_bottom(void);
unsigned random_next(void);          /* 9D96: steps the generator (DS:005B) and returns it (0 when it reseeds) */
int  random_n(int n);                /* 9CFC */

/* --fix: the original's flaws the player chose to have fixed (none by default;
 * each is described where it is fixed and in Remake/README.md) */
typedef enum {
    FIX_VIKING,            /* the Viking raid strikes your home's garrison */
    FIX_HOSTILITY,         /* the end check adds the three Norman homes' owners */
    FIX_TARGETS,           /* the computer lords compare their targets' values signed */
    FIX_CATAPULT,          /* a buying lord looks for a catapult in his home's garrison */
    FIX_SIEGE_MERGE,       /* the defending army joins the garrison only if the siege goes ahead */
    FIX_JOUST_OPPONENT,    /* the joust is judged by the opponent's jousting (and his army goes home) */
    FIX_JOUST_MARGIN,      /* the joust's margin is at least 1, as in the CGA and Tandy programs */
    FIX_BATTLE_TEXT,       /* "Saxon blood taints the green fields of" the territory attacked */
    FIX_SIEGE_SPRITE,      /* the catapult does not linger into the battle after a siege */
    FIX_COUNT
} Fix;
extern const char *const FIX_NAMES[FIX_COUNT];
extern unsigned g_fixes;
static inline bool fixed(Fix f) { return (g_fixes >> f) & 1; }
bool fixes_parse(const char *list, char *err, size_t errlen);   /* "viking,joust-margin" or "all" */
/* Screen refreshes per step of the catapult's pull (--catapult-pull=N, 1-8). The
 * original steps once a refresh, a full pull in 0.4 s, on a PC fast enough to copy
 * its picture every refresh (and in DOSBox); on the PCs of 1987 that copy took two
 * or three refreshes. The remake takes 2 unless told otherwise. */
extern int g_catapult_pull;

/* The rules (--rules=, the settings' rules): the booter's (false), or the 1987 DOS
 * version's (true): its random numbers, its computer lords' odds, its signed
 * comparisons, its waits that wait (../Analysis/DOC_vs_AB.md). One game runs under
 * either, whatever the video mode. */
extern bool g_dos_rules;
void set_dos_rules(bool on);

/* The CGA (1987) mode draws with DOC.EXE's own sprites and tables when DOC.EXE and its
 * .LIB files are there (assets.c): DOS_MODES is then that mode's mask (else 0), and
 * DB / DW read DOC.EXE's data segment (DGROUP 0BCE). The booter's modes are the rest. */
#define DOS_MODES   (gfx_assets()->have_doc ? MODES_DOS : 0u)
#define BOOT_MODES  (MODES_ALL & ~DOS_MODES)
#define DB(off)     (gfx_assets()->doc_ds[(off) & 0xFFFF])
#define DW(off)     ((int16_t)(DB(off) | (DB((off) + 1) << 8)))
void play_tune(int tune, int flags); /* 9559 */
void wait_tune(int tune);            /* 958E */
int  tune_playing(int tune, int n);  /* 95BE */
int  dialog(int box);                /* 7A80: the 12-byte description at DS:box */
void beep(int divisor, int ticks);   /* 9520 */

#endif
