/* joust_test GAME OUTDIR RESULT: plays joust_outcome(RESULT) (0 near miss,
 * 1 opponent unhorsed, 2 player unhorsed, 3 the horse) and writes every frame
 * presented (EGA, or JMODE=cga1|cga2|tandy) as OUTDIR/oNNN.bmp, to compare with DOSBox frame by frame.
 * RESULT "lane": a pass down the lane with no keys, then its outcome;
 * "approach": the knights riding in. */
#define tournament tournament_copy   /* this file has its own copy of tourney.c's routines */
#include "../src/tourney.c"
#undef tournament
#include "../src/assets.h"
#include <SDL3/SDL.h>
static Assets A;
static int result;
static void game(void)
{
    SDL_memcpy(ds, A.bh, A.bh_len);
    if (result == -2) {   /* "approach": the knights ride in (against side 2) */
        gfx_show_picture(PIC_TOURNAMENT);
        gfx_set_palette();
        slot_set(0, 41 * 4, 76, F_TOURN, 2, 0);
        slot_set(1, 15 * 4, 88, F_TOURN, 30, 0);
        gfx_sprites_draw(); present(); gfx_sprites_erase();
        gfx_video()->slot[0].active = false;
        SW(D_PLAYER, 1); SW(D_OPPONENT, 2);
        joust_approach();
        return;
    }
    if (result < 0) {   /* "lane": a whole pass down the lane, no keys (Enter starts it) */
        lance_item = 20;
        SW(D_PLAYER, 1);
        joust(1);
        return;
    }
    joust_outcome(result);
}
int main(int argc, char **argv)
{
    if (SDL_getenv("DOTC_RULES") && SDL_strcmp(SDL_getenv("DOTC_RULES"), "dos") == 0) set_dos_rules(true);   /* as --rules=dos */
    g_joust_pace = SDL_getenv("JPACE") ? SDL_atoi(SDL_getenv("JPACE")) : 1;   /* a step a frame, to compare with DOSBox; JPACE=N as --joust-pace=N */
    char err[256];
    if (argc < 4) { SDL_Log("usage: joust_test GAME OUTDIR RESULT"); return 1; }
    SDL_Init(0);
    if (!assets_load(&A, argv[1], err, sizeof err)) { SDL_Log("%s", err); return 1; }
    gfx_init(&A);
    sound_data(A.tunes, A.tunes_len, A.bg, A.bg_len);
    result = SDL_strcmp(argv[3], "lane") == 0 ? -1 : SDL_strcmp(argv[3], "approach") == 0 ? -2 : SDL_atoi(argv[3]);
    static uint32_t rgb[SCREEN_W * SCREEN_H];
    uint32_t seen = sys_frames();
    int n = 0;
    sys_set_speed(0.2);   /* slowly, so no frame is missed */
    sys_start(game);
    if (result == -1) sys_key(0x1C);
    while (sys_running()) {
        if (sys_frames() != seen) {
            seen = sys_frames();
            Mode jm = MODE_EGA;
            if (SDL_getenv("JMODE")) mode_from_name(SDL_getenv("JMODE"), &jm);   /* JMODE=cga1 ...: that mode's frames */
            gfx_to_rgb(jm, rgb);
            SDL_Surface *s = SDL_CreateSurfaceFrom(SCREEN_W, SCREEN_H, SDL_PIXELFORMAT_XRGB8888, rgb, SCREEN_W * 4);
            char path[600];
            SDL_snprintf(path, sizeof path, "%s/o%03d.bmp", argv[2], n++);
            SDL_SaveBMP(s, path);
            SDL_DestroySurface(s);
        }
        SDL_Delay(1);
    }
    sys_stop();
    SDL_Log("%d frames", n);
    return 0;
}
