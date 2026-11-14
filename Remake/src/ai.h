/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * ai.h: the computer lords' turns (AB 2995 ai_turn).
 */
#ifndef DOTC_AI_H
#define DOTC_AI_H

void ai_turn(int side);

/* month.c */
int tournament(int side);   /* 62BC */

#endif
