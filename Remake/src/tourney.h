/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * tourney.h: tournaments and the joust.
 */
#ifndef DOTC_TOURNEY_H
#define DOTC_TOURNEY_H

/* 62BC: held by the player (Hold Tournament) or by a Saxon lord (his order 1);
 * the player jousts either way. 1 if it was held. */
int tournament(int side);

#endif
