/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * sys.h: the game runs as the original did, one routine calling the next and
 * waiting for keys and timer ticks, on its own thread. The main thread keeps
 * the window, feeds it the keys and shows what it presents.
 *
 * Keys are the PC's scan codes, as the original read them (int 16h AH).
 */
#ifndef DOTC_SYS_H
#define DOTC_SYS_H

#include <setjmp.h>
#include <stdbool.h>
#include <stdint.h>

enum {
    KEY_ESC = 0x01, KEY_ENTER = 0x1C, KEY_SPACE = 0x39, KEY_F1 = 0x3B,
    KEY_HOME = 0x47, KEY_UP = 0x48, KEY_PGUP = 0x49, KEY_KP_MINUS = 0x4A, KEY_LEFT = 0x4B,
    KEY_KP5 = 0x4C, KEY_RIGHT = 0x4D, KEY_KP_PLUS = 0x4E, KEY_END = 0x4F, KEY_DOWN = 0x50, KEY_PGDN = 0x51,
};

/* main thread */
void sys_start(void (*game)(void));   /* starts the game thread */
void sys_stop(void);                  /* asks it to end and waits */
bool sys_running(void);
void sys_key(int scan);               /* a key pressed */
uint32_t sys_frames(void);            /* presents so far (the main thread redraws when it changes) */
void sys_set_speed(double s);         /* tests: the game's clock runs s times as fast */

/* the game thread: the original's timer and keys */
uint32_t sys_ticks(void);             /* the BIOS tick count (int 1Ah), 18.2 a second */
int  bios_key(void);                  /* 7F8C: a waiting key's scan code, else 0 */
int  get_key(void);                   /* 7F5E: keypad + and F1 read as Enter */
int  wait_key(void);                  /* 7F2A */
void flush_keys(void);                /* 7FA7 */
int  wait_ticks(int n);               /* 7EF2: n ticks or a key (returned) */
void delay_ticks(int n);              /* 9CAF: n ticks, keys left alone */
void sys_retrace(void);               /* 9CE3: the next vertical retrace (60 a second) */
void sys_frame_done(void);            /* present has put a new screen up */
void sys_check(void);                 /* leaves the game thread if the window is closing */
void sys_dos_ticks(bool on);          /* wait_ticks and delay_ticks as DOC.EXE's (the last tick kept between calls) */

/* The remake's own: while armed, Enter is not passed to the game but makes the
 * next wait (any key read, tick wait or retrace) longjmp to `to` (the opening
 * and Sherwood can be skipped). Disarmed by the jump. */
void sys_skip_arm(jmp_buf *to);
void sys_skip_disarm(void);

#endif
