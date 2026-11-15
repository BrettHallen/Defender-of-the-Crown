/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * gamelog.c: the debug log (see gamelog.h). It only reads the game.
 */
#include "gamelog.h"
#include "game.h"

static struct {
    GameLogLevel level;
    char dir[1024];
    char path[1280];
    SDL_IOStream *f;
    SDL_Mutex *lock;          /* the display lines come from the main thread */
    char settings[4096];
    char mode[32];
    bool aspect_43;
} G;

static const char *const MONTHS[12] = { "January", "February", "March", "April", "May", "June", "July",
                                        "August", "September", "October", "November", "December" };

static char *buf(void)
{
    static char b[16][200];
    static int n;
    n = (n + 1) % 16;
    return b[n];
}

static const char *name_at(int ptr) { return ptr ? STR(ptr) : "?"; }

const char *glog_side(int s)
{
    char *b = buf();
    if (s < 1 || s > 6) SDL_snprintf(b, 200, "side %d", s);
    else SDL_snprintf(b, 200, "side %d (%s%s)", s, name_at(W(SIDE(s) + S_NAME)),
                      s == W(D_PLAYER) ? ", you" : s <= 3 ? ", Saxon" : ", Norman");
    return b;
}

const char *glog_terr(int t)
{
    char *b = buf();
    if (t < 0 || t > 18) SDL_snprintf(b, 200, "territory %d", t);
    else SDL_snprintf(b, 200, "%s (%d)", name_at(W(TERR(t) + T_NAME)), t);
    return b;
}

const char *glog_count(int n, const char *noun)
{
    char *b = buf();
    SDL_snprintf(b, 200, "%d %s%s", n, noun, n == 1 ? "" : "s");
    return b;
}

static const char *owner_name(int t)
{
    int o = (int8_t)B(TERR(t) + T_OWNER);
    if (o < 1 || o > 6) return "nobody";
    return glog_side(o);
}

void gamelog_setup(GameLogLevel level, const char *dir)
{
    G.level = level;
    SDL_strlcpy(G.dir, dir ? dir : "", sizeof G.dir);
    if (!G.lock) G.lock = SDL_CreateMutex();
}

void gamelog_settings(const char *text) { SDL_strlcpy(G.settings, text ? text : "", sizeof G.settings); }

bool gamelog_on(GameLogLevel level) { return G.f && G.level >= level; }
const char *gamelog_path(void) { return G.f ? G.path : ""; }

static void out(const char *s) { if (G.f) SDL_WriteIO(G.f, s, SDL_strlen(s)); }

static void outf(SDL_PRINTF_FORMAT_STRING const char *fmt, ...) SDL_PRINTF_VARARG_FUNC(1);
static void outf(const char *fmt, ...)
{
    char line[2048];
    va_list ap;
    va_start(ap, fmt);
    SDL_vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    out(line);
}

static void dated(const char *line)
{
    int mo = W(D_MONTH_NO);
    outf("[%-9s %4d, month %2d] %s\n", mo >= 0 && mo < 12 ? MONTHS[mo] : "?", W(D_YEAR), W(D_MONTH), line);
    SDL_FlushIO(G.f);
}

void gamelog_printf(const char *fmt, ...)
{
    if (!G.f) return;
    char line[2048];
    va_list ap;
    va_start(ap, fmt);
    SDL_vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    SDL_LockMutex(G.lock);
    if (G.f) dated(line);
    SDL_UnlockMutex(G.lock);
}

void gamelog_display(const char *mode, bool aspect_43)
{
    SDL_LockMutex(G.lock);
    bool first = !G.mode[0];
    if (G.f && !first && SDL_strcmp(G.mode, mode) != 0) {
        char line[200];
        SDL_snprintf(line, sizeof line, "SETTING the video mode is now %s (Tab)", mode);
        dated(line);
    }
    if (G.f && !first && G.aspect_43 != aspect_43) dated(aspect_43 ? "SETTING the pixels are now 4:3 (F2)" : "SETTING the pixels are now square (F2)");
    SDL_strlcpy(G.mode, mode, sizeof G.mode);
    G.aspect_43 = aspect_43;
    SDL_UnlockMutex(G.lock);
}

static void state(const char *title);

void gamelog_state(const char *title)
{
    SDL_LockMutex(G.lock);
    state(title);
    SDL_UnlockMutex(G.lock);
}

static void state(const char *title)
{
    if (!G.f) return;
    outf("\n== %s ==\n", title);
    int mo = W(D_MONTH_NO);
    outf("Date: %s %d (months played %d). Morale %d. The next event in %d months. Kidnapped lady: %d. "
         "Robin's help: DS:004B %d, DS:004D %d.\n",
         mo >= 0 && mo < 12 ? MONTHS[mo] : "?", W(D_YEAR), W(D_MONTH), W(D_MORALE), W(D_EVENT_IN), W(D_KIDNAPPED), W(0x4B), W(0x4D));
    outf("Random generator: DS:005B = %04Xh, %u calls until it reseeds.\n", UW(D_RANDOM), UW(D_RANDOM_N));
    out("\nSides (leadership, jousting, swordplay are 0-10):\n");
    for (int s = 1; s <= 6; s++) {
        int lady = W(SIDE(s) + S_LADY);
        outf("  %-46s home %-20s army at %-20s gold %3d income %2d  lead %2d joust %2d sword %2d  spend %2d  lady %s\n",
             glog_side(s), glog_terr(W(SIDE(s) + S_HOME)), glog_terr(W(SIDE(s) + S_AT)), W(SIDE(s) + S_GOLD),
             W(SIDE(s) + S_INCOME), W(SIDE(s) + S_LEAD), W(SIDE(s) + S_JOUST), W(SIDE(s) + S_SWORD), W(SIDE(s) + S_SPEND),
             lady >= 0 && lady < 4 ? name_at(W(LADY(lady) + L_NAME)) : "none");
    }
    out("\nCampaign armies (soldiers, knights, catapults):\n");
    for (int s = 1; s <= 6; s++)
        outf("  %-46s at %-20s %4d %4d %3d\n", glog_side(s), glog_terr(W(ARMY(s) + A_AT)),
             W(ARMY(s) + A_SOLDIERS), W(ARMY(s) + A_KNIGHTS), W(ARMY(s) + A_CATAPULTS));
    out("\nTerritories (owner, castle, vassals, income, neighbours; garrison soldiers, knights, catapults):\n");
    for (int t = 1; t <= 18; t++) {
        char nb[64] = "";
        for (int k = 0; k < 7; k++) {
            int n = B(TERR(t) + T_NB + k);
            if (!n) break;
            SDL_snprintf(nb + SDL_strlen(nb), sizeof nb - SDL_strlen(nb), "%s%d", k ? "," : "", n);
        }
        outf("  %-20s %-46s castle %2d vassals %2d income %d  nb %-16s garrison %4d %4d %3d\n", glog_terr(t), owner_name(t),
             B(TERR(t) + T_CASTLE), B(TERR(t) + T_VASSALS), B(TERR(t) + T_INCOME), nb,
             W(ARMY(t + 7) + A_SOLDIERS), W(ARMY(t + 7) + A_KNIGHTS), W(ARMY(t + 7) + A_CATAPULTS));
    }
    out("\nLadies:\n");
    for (int l = 0; l < 4; l++) {
        int s = W(LADY(l) + L_SIDE);
        outf("  %-26s %s, at %s, flag %d\n", name_at(W(LADY(l) + L_NAME)), s >= 1 && s <= 6 ? glog_side(s) : "no side",
             glog_terr(W(LADY(l) + L_TERR)), W(LADY(l) + L_FLAG));
    }
    out("\nEnmity (row: how hostile that side is to each column; a computer side never attacks one it has 0 with):\n       ");
    for (int b = 1; b <= 6; b++) outf("%5d", b);
    out("\n");
    for (int a = 1; a <= 6; a++) {
        outf("  %d    ", a);
        for (int b = 1; b <= 6; b++) outf("%5d", W(ENMITY(a, b)));
        out("\n");
    }
    out("\n");
    SDL_FlushIO(G.f);
}

static void begin(int character);

void gamelog_begin(int character)
{
    if (G.level == GLOG_OFF) return;
    SDL_LockMutex(G.lock);   /* reentrant */
    begin(character);
    SDL_UnlockMutex(G.lock);
}

static void begin(int character)
{
    if (G.f) gamelog_end("A new game was started");
    SDL_CreateDirectory(G.dir);
    SDL_Time now;
    SDL_DateTime dt;
    SDL_zero(dt);
    if (SDL_GetCurrentTime(&now)) SDL_TimeToDateTime(now, &dt, true);
    char lord[64];
    SDL_strlcpy(lord, name_at(W(SIDE(1) + S_NAME)), sizeof lord);
    SDL_snprintf(G.path, sizeof G.path, "%s%04d-%02d-%02d %02d-%02d-%02d %s.log", G.dir, dt.year, dt.month, dt.day,
                 dt.hour, dt.minute, dt.second, lord);
    G.f = SDL_IOFromFile(G.path, "w");
    if (!G.f) { SDL_Log("Could not open the log %s", G.path); return; }
    outf("Defender of the Crown (remake) - game log (%s)\n", G.level == GLOG_VERBOSE ? "verbose" : "normal");
    outf("Started %04d-%02d-%02d %02d:%02d:%02d. You chose character %d: %s.\n", dt.year, dt.month, dt.day, dt.hour,
         dt.minute, dt.second, character, lord);
    char fx[256] = "";
    for (int i = 0; i < FIX_COUNT; i++)
        if (fixed((Fix)i)) SDL_snprintf(fx + SDL_strlen(fx), sizeof fx - SDL_strlen(fx), "%s%s", *fx ? ", " : "", FIX_NAMES[i]);
    if (G.settings[0]) out(G.settings);
    else outf("The original's flaws fixed (--fix): %s.\n", *fx ? fx : "none, the game as it was");
    if (G.mode[0]) outf("Video mode at the start of the game: %s, %s pixels.\n", G.mode, G.aspect_43 ? "4:3" : "square");
    gamelog_state("The game as it was set up");
    SDL_Log("Game log: %s", G.path);
}

void gamelog_end(const char *how)
{
    SDL_LockMutex(G.lock);
    if (G.f) {
        gamelog_printf("The end of the log: %s", how ? how : "");
        if (G.level == GLOG_VERBOSE) gamelog_state("The game at the end");
        SDL_CloseIO(G.f);
        G.f = NULL;
    }
    SDL_UnlockMutex(G.lock);
}
