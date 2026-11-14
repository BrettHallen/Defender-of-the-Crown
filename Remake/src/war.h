/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * war.h: the armies, the conquest of territories, the battles and the sieges.
 * Armies are DS offsets (ARMY(side) for a campaign army, GARRISON(t) for a
 * territory's garrison).
 */
#ifndef DOTC_WAR_H
#define DOTC_WAR_H

int  army_strength(int a);             /* 26EF: 4 x knights + soldiers */
int  army_empty(int a);                /* 2016: no soldiers and no knights */
void army_move_to(int side, int t);    /* 2034 */
void army_go_home(int side);           /* 2079 */
void army_settle(int side);            /* 2114: back where it came from if still its own (and not empty), else home */
void army_merge(int from, int to);     /* 21A0 */
void send_others_home(int t, int except);   /* 20BD */
void send_home_armies_at(int t);       /* 20EB */
void set_owner(int owner, int t);      /* 423D: the map shows it (the territory flashes) */
void side_falls(int side, int winner); /* 2406: all its territories go to the winner */
int  attack(int att, int def, int t);  /* 31D5: the result code (GAME_LOGIC.md) */

#endif
