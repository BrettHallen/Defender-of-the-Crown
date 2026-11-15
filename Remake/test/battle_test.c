/* battle_test GAME OUTDIR [siege t:key|t:shot:NAME ...]: a Norman besieges the
 * player's home with a big army, screenshots of the battle (all four modes)
 * every game second, Enter now and then. With "siege": the player besieges a
 * Saxon castle (Lancashire, 4) instead, driven by the key script (times in game
 * seconds, as run_script). With "raid": the player raids a Norman's home
 * (Yorkshire), the same way. */
#include "../src/assets.h"
#include "../src/gfx.h"
#include "../src/sys.h"
#include "../src/sound.h"
#include "../src/game.h"
#include "../src/month.h"
#include "../src/war.h"
#include "../src/raid.h"
#include "../src/gamelog.h"
#include <SDL3/SDL.h>
static Assets A;
static void shot(const char *dir, const char *name)
{
    static const char *M[] = { "cga1", "cga2", "ega", "tandy" };
    static uint32_t rgb[SCREEN_W * SCREEN_H];
    for (int m = 0; m < MODE_COUNT; m++) {
        gfx_to_rgb((Mode)m, rgb);
        SDL_Surface *s = SDL_CreateSurfaceFrom(SCREEN_W, SCREEN_H, SDL_PIXELFORMAT_XRGB8888, rgb, SCREEN_W * 4);
        char path[600];
        SDL_snprintf(path, sizeof path, "%s/%s_%s.bmp", dir, name, M[m]);
        SDL_SaveBMP(s, path);
        SDL_DestroySurface(s);
    }
}
static int siege_mode;
static void game(void)
{
    SDL_memcpy(ds, A.bh, A.bh_len);
    gfx_keep_palette(PIC_MAP, 0);
    gfx_picture_to(PIC_MAP, PAGE_MAP);
    SW(D_PLAYER, 1);
    for (int s = 1; s < 7; s++) {
        SW(SIDE(s) + S_NAME, W(LORD(s) + 0));
        SW(SIDE(s) + S_LEAD, 5);
        SW(SIDE(s) + S_HOME, s == 1 ? 1 : 15);
    }
    for (int t = 1; t < 19; t++) SB(TERR(t) + T_OWNER, 0xFF);
    SB(TERR(1) + T_OWNER, 1); SB(TERR(1) + T_CASTLE, 30);
    SB(TERR(15) + T_OWNER, 4);
    set_region_colour(1, 1);
    SW(ARMY(1) + A_AT, 1);
    SW(SIDE(1) + S_AT, 1);
    SW(ARMY(4) + A_AT, 1); SW(ARMY(4) + A_SOLDIERS, 80); SW(ARMY(4) + A_KNIGHTS, 25); SW(ARMY(4) + A_CATAPULTS, 2);
    SW(GARRISON(1) + A_SOLDIERS, 70); SW(GARRISON(1) + A_KNIGHTS, 22);
    SW(ENMITY(4, 1), 5);
    if (siege_mode == 2) {
        SW(SIDE(4) + S_HOME, 2); SB(TERR(2) + T_OWNER, 4); SB(TERR(2) + T_CASTLE, 30);
        set_region_colour(2, 4);
        SW(SIDE(1) + S_SWORD, 6); SW(SIDE(4) + S_SWORD, 5);
        SW(SIDE(1) + S_AT, 2); SW(SIDE(4) + S_GOLD, 40);
        gamelog_begin(1);
        if (SDL_getenv("ROMANCE")) {   /* the romance alone, over the hall, with lady ROMANCE (0-3) */
            gfx_show_picture(PIC_HALL);
            present();
            gfx_set_palette();
            romance(SDL_atoi(SDL_getenv("ROMANCE")));
        } else if (SDL_getenv("RESCUE")) {   /* a Saxon's lady held at the Norman's home: the offer, then the raid */
            SW(SIDE(2) + S_NAME, W(LORD(2) + 0));
            SW(SIDE(2) + S_HOME, 5); SB(TERR(5) + T_OWNER, 2); SB(TERR(6) + T_OWNER, 2);
            set_region_colour(5, 2); set_region_colour(6, 2);
            SW(SIDE(2) + S_LADY, 1); SW(LADY(1) + L_SIDE, 2); SW(LADY(1) + L_TERR, 2);
            SW(SIDE(1) + S_LADY, -1);
            SW(D_KIDNAPPED, 1);
            SW(0x4D, 1);   /* Robin's help: strength 50 */
            rescue_offer();
        } else go_raiding();
        gamelog_end("test over");
        return;
    }
    if (siege_mode) {
        SB(TERR(4) + T_OWNER, 2); SB(TERR(4) + T_CASTLE, 30);
        set_region_colour(4, 2);
        SW(ENMITY(2, 1), SDL_getenv("PASSAGE") ? 0 : 5);
        SW(ARMY(1) + A_SOLDIERS, 40); SW(ARMY(1) + A_KNIGHTS, 10); SW(ARMY(1) + A_CATAPULTS, 1);
        SW(GARRISON(4) + A_SOLDIERS, 30); SW(GARRISON(4) + A_KNIGHTS, 4);
        SW(ARMY(4) + A_AT, 15);
        gamelog_begin(1);
        attack(1, 2, 4);
        gamelog_end("test over");
        return;
    }
    if (SDL_getenv("FIELD")) {   /* FIELD=s,k,s,k: a field battle (no castle), your soldiers and knights against his */
        int n[4] = { 0 };
        SDL_sscanf(SDL_getenv("FIELD"), "%d,%d,%d,%d", &n[0], &n[1], &n[2], &n[3]);
        SB(TERR(1) + T_CASTLE, 0);
        SW(GARRISON(1) + A_SOLDIERS, n[0]); SW(GARRISON(1) + A_KNIGHTS, n[1]);
        SW(ARMY(4) + A_SOLDIERS, n[2]); SW(ARMY(4) + A_KNIGHTS, n[3]); SW(ARMY(4) + A_CATAPULTS, 0);
    }
    attack(4, 1, 1);
}
int main(int argc, char **argv)
{
    if (argc < 3) { SDL_Log("usage: battle_test GAME OUTDIR"); return 1; }
    char err[256];
    SDL_Init(0);
    if (!assets_load(&A, argv[1], err, sizeof err)) { SDL_Log("%s", err); return 1; }
    gfx_init(&A);
    if (SDL_getenv("DOTC_RULES") && SDL_strcmp(SDL_getenv("DOTC_RULES"), "dos") == 0) set_dos_rules(true);   /* as --rules=dos */
    if (SDL_getenv("PULL")) g_catapult_pull = SDL_atoi(SDL_getenv("PULL"));   /* --catapult-pull */
    if (SDL_getenv("SWORD")) g_sword_pace = SDL_atoi(SDL_getenv("SWORD"));   /* --sword-pace */
    if (SDL_getenv("DOTC_LOG")) gamelog_setup(GLOG_VERBOSE, SDL_getenv("DOTC_LOG"));
    sound_data(A.tunes, A.tunes_len, A.bg, A.bg_len);
    sys_set_speed(4);
    if (argc > 3 && (SDL_strcmp(argv[3], "siege") == 0 || SDL_strcmp(argv[3], "raid") == 0)) {
        siege_mode = SDL_strcmp(argv[3], "raid") == 0 ? 2 : 1;
        sys_start(game);
        Uint64 t0 = SDL_GetTicksNS();
        for (int i = 4; i < argc; i++) {
            double t = SDL_atof(argv[i]);
            const char *what = SDL_strchr(argv[i], ':') + 1;
            while ((double)(SDL_GetTicksNS() - t0) * 4 / 1e9 < t) {
                if (!sys_running()) goto done;
                SDL_Delay(1);
            }
            if (SDL_strncmp(what, "shot:", 5) == 0) shot(argv[2], what + 5);
            else sys_key((int)SDL_strtol(what, NULL, 16));
        }
    done:
        sys_stop();
        return 0;
    }
    sys_start(game);
    for (int i = 0; i < 40 && sys_running(); i++) {
        SDL_Delay(250);
        char n[32]; SDL_snprintf(n, sizeof n, "b%02d", i);
        shot(argv[2], n);
        if (i % 3 == 0) sys_key(0x1C);
    }
    sys_stop();
    return 0;
}
