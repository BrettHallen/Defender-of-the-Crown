/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * gamelog.h: the debug log (--log, --log=verbose). Each game started gets
 * its own text file in the remake's folder under Logs/, named with the date,
 * the time and the lord chosen ("2026-11-15 09-12-03 Wilfred of Ivanhoe.log").
 * It starts with the game as it was set up (the sides, their lords and
 * homes, the territories, the armies, the ladies, the enmity between the
 * sides, the random generator), then one line for each decision and event,
 * after the date in the game: what the computer lords choose and why, the
 * player's orders, events, battles and their results.
 *
 * The start also lists the settings in effect (the settings file and the
 * command line, and where each came from); a switch of video mode (Tab) or
 * pixel shape (F2) during a game gets a line of its own.
 *
 * Logging only reads the game: it never calls the random numbers, so a
 * logged game plays as one not logged.
 */
#ifndef DOTC_GAMELOG_H
#define DOTC_GAMELOG_H

#include <stdbool.h>
#include <SDL3/SDL.h>

typedef enum { GLOG_OFF = 0, GLOG_NORMAL = 1, GLOG_VERBOSE = 2 } GameLogLevel;

void gamelog_setup(GameLogLevel level, const char *dir);
void gamelog_settings(const char *text); /* the settings in effect (main.c), written at the start of each log */
void gamelog_display(const char *mode, bool aspect_43);   /* the video mode and pixel shape now (main.c): a line when they change */
void gamelog_begin(int character);      /* the game is set up: open a log, write the start */
void gamelog_state(const char *title);  /* the whole state again (verbose: each month) */
void gamelog_end(const char *how);
bool gamelog_on(GameLogLevel level);
void gamelog_printf(const char *fmt, ...) SDL_PRINTF_VARARG_FUNC(1);
const char *gamelog_path(void);

/* words for the log (each call returns its own buffer, a few at a time) */
const char *glog_side(int side);        /* "side 4 (Brian de Bois-Guilbert, Norman)" */
const char *glog_terr(int t);           /* "Cornwall (13)" */
const char *glog_count(int n, const char *noun);   /* "1 knight", "3 knights" */

#define GLOG(level, ...) do { if (gamelog_on(level)) gamelog_printf(__VA_ARGS__); } while (0)

#endif
