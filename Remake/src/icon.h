/*
 * Defender of the Crown (1986) - remake
 * Nov 2026 using Claude Opus 5.5
 * "Guided" by Brett Hallen
 * Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
 * IBM PC versions by Master Designer Software (1987 DOS) and the booter (GAME.DAT)
 * * icon.h: the app icon, drawn from the player's own game files: the title
 * picture ("Defender of the Crown" on the stone wall; the EGA one, else the
 * Tandy one, else the booter's CGA one) in its 4:3 shape on a black rounded
 * square, as macOS icons are laid out (as The Ancient Art of War remake does).
 */
#ifndef DOTC_ICON_H
#define DOTC_ICON_H

#include "assets.h"

/* Draw the icon at size x size into rgba (size * size * 4 bytes, straight
 * alpha). False if the game files have no title picture. */
bool icon_render(const Assets *a, int size, uint8_t *rgba);

#endif
