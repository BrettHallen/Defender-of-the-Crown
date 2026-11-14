/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * conquest.h: the player's Seek Conquest and Read Map.
 */
#ifndef DOTC_CONQUEST_H
#define DOTC_CONQUEST_H

int seek_conquest(void);   /* 35E0: 1 if the month goes on */
int read_map(void);        /* 4084 */
void see_robin(void);      /* 2E37: Robin pledges his men for the next attack (or raid), three times a game */

#endif
