/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * month.h: the month (AB 1B44), the map, the status panel and the menus.
 */
#ifndef DOTC_MONTH_H
#define DOTC_MONTH_H

void month(void);

/* used elsewhere */
void redraw_map(void);                       /* 4013 */
void side_income(int side);                  /* 23AC */
void morale_add(int d);                      /* 9464 */
void show_portrait(int portrait, int x, int y);   /* 9407 */
void flash_territory(int t, int n);          /* 40C6 */
int  str_append(int src, int dst);           /* 948D: returns the end */
int  num_append(unsigned n, int dst);        /* 94B5 */
int  choose_territory(int t);                /* 4142: a cursor on the map from t; Enter chooses */

/* game.c */
void lady_to_side(int lady, int side, int flag);
void next_event_in(void);
void enmity_add(int a, int b, int d);
void set_region_colour(int t, int owner);

#endif
