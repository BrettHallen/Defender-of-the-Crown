/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * ini.h: a small INI file reader and writer for the settings file
 * (DefenderOfTheCrown.ini). Lines are kept as they are, so a value set by the
 * remake (the game folder) leaves the rest of the file, comments and all, alone.
 *   [section]          names are matched without regard to case
 *   key = value        spaces around the key and the value are dropped
 *   ; comment          (or #) only at the start of a line
 */
#ifndef DOTC_INI_H
#define DOTC_INI_H

#include <stdbool.h>
#include <stddef.h>

typedef struct {
    char **line;
    int    count, cap;
} Ini;

bool        ini_load(Ini *ini, const char *path);    /* false if there is no such file */
void        ini_text(Ini *ini, const char *text);    /* lines from a string (the default file) */
const char *ini_get(const Ini *ini, const char *section, const char *key);   /* NULL if not there */
bool        ini_set(Ini *ini, const char *section, const char *key, const char *value);   /* adds the key (and section) if missing */
int         ini_add_missing(Ini *ini, const Ini *defaults);   /* the keys of defaults not in ini, with their comments: how many */
bool        ini_save(const Ini *ini, const char *path);
void        ini_free(Ini *ini);

#endif
