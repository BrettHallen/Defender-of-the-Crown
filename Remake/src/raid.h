/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * raid.h: Go Raiding, the sword fight and the rescue of a kidnapped lady.
 */
#ifndef DOTC_RAID_H
#define DOTC_RAID_H

int  go_raiding(void);                 /* 45AC: 1 if the month goes on */
int  rescue_offer(void);               /* 4316: 1 if the player went to rescue her */
void leadership_add(int side, int d);  /* 7113: kept within 0-10 */

#endif
