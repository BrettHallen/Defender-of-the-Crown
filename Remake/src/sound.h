/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 *
 * sound.h: the PC speaker and the Tandy 1000's sound chip.
 *
 * The game is timed by the PC-speaker tunes in every mode (the EGA and CGA
 * programs wait for them; with the music off they still run, silently). The
 * eight tunes are BB items 97h-9Eh, played a note a timer tick by the int 1Ch
 * handler (AB 968A). In the Tandy mode the matching Tandy song (BG, AC's
 * driver 7444-7C53) is heard instead, while the speaker tune keeps time
 * unheard. Tab between the speaker and the Tandy restarts the tune being
 * played from the top on the new sound; the game's timing goes on as it was.
 */
#ifndef DOTC_SOUND_H
#define DOTC_SOUND_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

bool sound_init(void);       /* false: no audio device (the game runs silent) */
void sound_quit(void);
void sound_data(const uint8_t *tunes, size_t tunes_len, const uint8_t *bg, size_t bg_len);

/* the timer tick (int 1Ch, 18.2 a second): sys calls it for each tick */
void sound_tick(void);

/* the speaker as the program drives it: speaker_tone (AB 9541) and speaker_off (953A) */
void snd_speaker_tone(int divisor);
void snd_speaker_off(void);
/* a tone of a few ms: speaker_tone .. speaker_off around a little work (buy_army's refusal) */
void snd_speaker_click(int divisor, int ms);

/* play_tune (AB 9559): tune 97h-9Eh, flags 8000h play, 4000h loop, 2000h silent; 0 stops */
void snd_play_tune(int tune, int flags);
int  snd_tune_flags(void);       /* the header's flags word: bit 0 set when stopped */
int  snd_tune_index(void);       /* the note being played (1..count) */
void snd_tune_clear_loop(void);  /* wait_tune clears 4000h */

/* the sound heard: the speaker (false) or the Tandy chip (true); switching
 * restarts the tune being played from the top on the new sound */
void snd_use_tandy(bool tandy);
bool snd_tandy_used(void);

#endif
