; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; opening.asm: the start of a new game (AB 10B2), as the Mac remake's
; new_game (Remake/src/game.c) in Tandy mode: the credits on the scroll, the
; title and its sparkles, the cast, the introduction, the choice of
; character, and Sherwood with its campfire. S skips the opening, and
; Sherwood (the remake's own). The setup of the game itself comes with the
; month.
;
; The dialog boxes (7A80) and the texts are the original's, in its data
; segment (BH, at DS).

; ------------------------------------------------------------------ new_game (10B2)

new_game:
            call seed_random
            ld hl, 0
            ld (DSEG + $67), hl
            ld hl, 1
            ld (DSEG + D_PLAYER), hl
            ld a, $97
            ld hl, (DSEG + D_TUNE_STOP)
            call play_tune
            ld hl, (DSEG + D_FIRST_GAME)
            ld a, h
            or l
            jp z, ng_choose
            ld hl, ng_skipped       ; S skips the rest of the opening
            call skip_arm
            ld a, PIC_SCROLL
            call show_picture
            call set_palette
            ld hl, $12D4            ; the credits
            call dialog
            ld a, $97
            ld hl, (DSEG + D_TUNE_ONCE)
            call play_tune
            ld hl, $1351
            call dialog
            ld a, PIC_TITLE
            call show_picture
            call present
            call set_palette
            ld hl, 36
            call delay_ticks
            call get_key            ; a key: no sparkles, no more credits
            or a
            jp nz, ng_cut
            ld ix, twinkles
            ld b, 6
ng_twinkle:
            push bc
            push ix
            ld l, (ix + 0)
            ld h, (ix + 1)
            ld e, (ix + 2)
            ld a, (ix + 3)
            call title_twinkle
            pop ix
            pop bc
            or a
            jp nz, ng_cut
            ld de, 4
            add ix, de
            djnz ng_twinkle
            ld a, PIC_SCROLL        ; the credits again, on the scroll
            call show_picture
            ld hl, $1405
            call dialog
            call clear_crown
            ld hl, $14A9
            call dialog
            ld hl, $1505
            call dialog
            ld hl, $155B
            call dialog
            call clear_crown
            ld hl, $15F7
            call dialog
            ld hl, $163D
            call dialog
            ld hl, $1689
            call dialog
ng_credit:                          ; the Next's own credit card, after the original's
            ld hl, cr_box - DSEG
            call dialog
ng_credit_end:
            ld a, PIC_CAST
            call show_picture
            call present
            call set_palette
            ld hl, 108
            call wait_ticks
            ld a, PIC_INTRO
            call show_picture
            call present
            call set_palette
            ld hl, 180
            call wait_ticks
            jp ng_opened
ng_cut:
            ld a, $97
            ld hl, (DSEG + D_TUNE_STOP)
            call play_tune
ng_opened:
            call skip_disarm
            jp ng_choose
ng_skipped:
            ld a, $97
            call skipped
ng_choose:
            call wait_tune          ; (the map's palette and planes: kept at the start, map_keep)
            ld a, PIC_CHOOSE
            call show_picture
            call present
            call set_palette
            call character_choice
            ld hl, ng_sherwood_skipped  ; S skips Sherwood
            call skip_arm
            ld a, PIC_SHERWOOD
            call show_picture
            call present
            call set_palette
            ld a, $98
            ld hl, (DSEG + D_TUNE_ONCE)
            call play_tune
            ld hl, $16DD
            call dialog
ng_fire1:
            ld c, 0
            call tune_playing
            or a
            jp z, ng_story2
            ld a, 4
            call fire_flicker
            jp ng_fire1
ng_story2:
            ld a, $98
            ld hl, (DSEG + D_TUNE_ONCE)
            call play_tune
            ld a, PIC_SHERWOOD
            call show_picture
            call set_palette
            ld hl, $1865
            call dialog
ng_fire2:
            ld c, 0
            call tune_playing
            or a
            jp z, ng_fire3
            ld a, 4
            call fire_flicker
            jp ng_fire2
ng_fire3:
            ld a, 125
            call fire_flicker
            call skip_disarm
            jp ng_setup
ng_sherwood_skipped:
            ld a, $98
            call skipped
ng_setup:
            jp game_setup

; the crown's place on the scroll cleared (fill_rect(20, 61, 42, 78, DDFFh))
clear_crown:
            ld a, 20
            ld (rc_x), a
            ld a, 61
            ld (rc_y), a
            ld a, 42
            ld (rc_w), a
            ld a, 78
            ld (rc_h), a
            ld hl, $DDFF
            ld (rc_colour), hl
            jp fill_rect

; after S: what was left half done (A = the tune)
skipped:
            ld hl, (DSEG + D_TUNE_STOP)
            call play_tune
            call fire_erase
            jp flush_keys

; ------------------------------------------------------------------ dialog (7A80)

; HL = the box (12 bytes in the data segment): x (4-pixel units), y, lines,
; width, icon (-2: the text only; -3: a box without its frame; -1: the box but
; no text), the first and last line to choose from (the first < 0: not a
; menu), the line chosen at first, the ticks to wait at the end, then a word:
; the table of the lines' pointers. A menu returns the line chosen in A (1:
; the first it can choose); Left and Right set DS:0A9C to -1 or 1 and end it.
dialog:
            ld de, DSEG
            add hl, de
            push hl
            pop ix
            ld a, (ix + 0)
            ld (dl_x0), a
            ld a, (ix + 1)
            ld (dl_y0), a
            ld a, (ix + 2)
            ld (dl_n), a
            ld a, (ix + 3)
            ld (dl_wd), a
            ld a, (ix + 4)
            ld (dl_icon), a
            ld a, (ix + 5)
            ld (dl_first), a
            ld a, (ix + 6)
            ld (dl_last), a
            ld a, (ix + 7)
            ld (dl_start), a
            ld a, (ix + 8)
            ld (dl_wait), a
            ld l, (ix + 9)
            ld h, (ix + 10)
            ld (dl_lines), hl
            ld a, (dl_icon)
            cp $FE                  ; -2
            jp z, dl_text
            ld a, (dl_x0)           ; x1 = x0 + width - 4
            ld hl, dl_wd
            add a, (hl)
            sub 4
            ld (dl_x1), a
            ld a, (dl_n)            ; y1 = (lines + 1) * 11 + y0
            inc a
            ld c, a
            add a, a
            add a, a
            add a, a
            add a, c
            add a, c
            add a, c
            ld hl, dl_y0
            add a, (hl)
            ld (dl_y1), a
            ld a, (dl_x0)           ; fill_rect(x0 + 4, y0 + 11, width - 8, y1 - y0 - 11, DDFFh)
            add a, 4
            ld (rc_x), a
            ld a, (dl_y0)
            add a, 11
            ld (rc_y), a
            ld a, (dl_wd)
            sub 8
            ld (rc_w), a
            ld a, (dl_y0)
            ld c, a
            ld a, (dl_y1)
            sub c
            sub 11
            ld (rc_h), a
            ld hl, $DDFF
            ld (rc_colour), hl
            call fill_rect
            ld a, (dl_icon)
            cp $FD                  ; -3
            jp z, dl_text
            ld a, (dl_x0)           ; the corners
            ld c, a
            ld a, (dl_y0)
            ld e, a
            ld a, $7B
            call dl_piece
            ld a, (dl_x0)
            ld c, a
            ld a, (dl_y1)
            ld e, a
            ld a, $7C
            call dl_piece
            ld a, (dl_x1)
            ld c, a
            ld a, (dl_y0)
            ld e, a
            ld a, $7D
            call dl_piece
            ld a, (dl_x1)
            ld c, a
            ld a, (dl_y1)
            ld e, a
            ld a, $7E
            call dl_piece
            ld a, $14               ; the top and bottom (14h-19h)
            ld (dl_di), a
            ld a, (dl_x0)
            add a, 4
            ld (dl_px), a
dl_edges:
            ld a, (dl_x1)
            ld c, a
            ld a, (dl_px)
            cp c
            jp nc, dl_sides
            ld c, a
            ld a, (dl_y0)
            ld e, a
            ld a, (dl_di)
            call dl_piece
            ld a, (dl_px)
            ld c, a
            ld a, (dl_y1)
            ld e, a
            ld a, (dl_di)
            inc a
            call dl_piece
            ld a, (dl_di)
            add a, 2
            cp $1A
            jp c, dl_di1
            ld a, $14
dl_di1:
            ld (dl_di), a
            ld a, (dl_px)
            add a, 2
            ld (dl_px), a
            jp dl_edges
dl_sides:
            ld a, $1A               ; the sides (1Ah-1Dh)
            ld (dl_di), a
            ld a, (dl_y0)
            add a, 11
            ld (dl_py), a
dl_side:
            ld a, (dl_y1)
            ld c, a
            ld a, (dl_py)
            cp c
            jp nc, dl_text
            ld e, a
            ld a, (dl_x0)
            ld c, a
            ld a, (dl_di)
            call dl_piece
            ld a, (dl_py)
            ld e, a
            ld a, (dl_x1)
            ld c, a
            ld a, (dl_di)
            inc a
            call dl_piece
            ld a, (dl_di)
            add a, 2
            cp $1E
            jp c, dl_di2
            ld a, $1A
dl_di2:
            ld (dl_di), a
            ld a, (dl_py)
            add a, 11
            ld (dl_py), a
            jp dl_side
dl_text:
            ld a, (dl_icon)
            cp $FF                  ; -1
            jp z, dl_shown
            ld a, (dl_y0)           ; the lines: from x0 * 4 + 20, y0 + 13, 11 lines apart
            add a, 13
            ld (dl_ty), a
            ld hl, (dl_lines)
            ld (dl_lp), hl
            ld a, (dl_n)
            ld (dl_left), a
dl_line:
            ld a, (dl_left)
            or a
            jp z, dl_shown
            dec a
            ld (dl_left), a
            ld a, (dl_x0)
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            ld de, 20
            add hl, de
            ld (dl_tx), hl
            ld hl, (dl_lp)          ; the line: DSEG + the word at DSEG + lp
            ld de, DSEG
            add hl, de
            ld e, (hl)
            inc hl
            ld d, (hl)
            ld hl, DSEG
            add hl, de
            ld (dl_s), hl
dl_char:
            ld hl, (dl_s)
            ld a, (hl)
            or a
            jp z, dl_eol
            inc hl
            ld (dl_s), hl
            ld hl, (dl_tx)
            ld e, a
            ld a, (dl_ty)
            ld d, a
            ld a, e
            ld e, d
            call glyph
            ld e, a
            ld d, 0
            ld hl, (dl_tx)
            add hl, de
            ld (dl_tx), hl
            jp dl_char
dl_eol:
            ld hl, (dl_lp)
            inc hl
            inc hl
            ld (dl_lp), hl
            ld a, (dl_ty)
            add a, 11
            ld (dl_ty), a
            jp dl_line
dl_shown:
            call present
            ld a, (dl_first)
            bit 7, a
            jp z, dl_menu
            call dl_end_wait        ; not a menu: A = the first (< 0)
            ld a, (dl_first)
            ret
dl_menu:
            call flush_keys
            ld a, (dl_start)
            bit 7, a
            jp z, dl_from
            ld a, (dl_first)
dl_from:
            ld (dl_si), a
            ld a, $FF
            ld (dl_prev), a
            xor a
            ld (dl_keyv), a
            ld h, a
            ld l, a
            ld (DSEG + $0A9C), hl
dl_loop:
            ld a, (dl_keyv)
            cp $48
            jp z, dl_up
            cp $50
            jp z, dl_down
            cp $4B
            jp z, dl_go_left
            cp $4D
            jp z, dl_go_right
            jp dl_moved
dl_up:
            ld a, (dl_si)
            ld hl, dl_first
            cp (hl)
            jp z, dl_up_wrap
            dec a
            jp dl_set
dl_up_wrap:
            ld a, (dl_last)
            jp dl_set
dl_down:
            ld a, (dl_si)
            ld hl, dl_last
            cp (hl)
            jp z, dl_down_wrap
            inc a
            jp dl_set
dl_down_wrap:
            ld a, (dl_first)
dl_set:
            ld (dl_si), a
            jp dl_moved
dl_go_left:
            ld hl, $FFFF
            jp dl_lr
dl_go_right:
            ld hl, 1
dl_lr:
            ld a, (dl_start)        ; only where a line is chosen at first, and not with icon 1
            bit 7, a
            jp nz, dl_moved
            ld a, (dl_icon)
            cp 1
            jp z, dl_moved
            ld (DSEG + $0A9C), hl
dl_moved:
            ld a, (dl_si)           ; the bar moves
            ld hl, dl_prev
            cp (hl)
            jp z, dl_present
            ld a, (hl)
            cp $FF
            call nz, dl_bar
            ld a, (dl_si)
            ld (dl_prev), a
            call dl_bar
dl_present:
            call present
            ld hl, (DSEG + $0A9C)
            ld a, h
            or l
            jp nz, dl_chosen
            call wait_key
            ld (dl_keyv), a
            cp KEY_ENTER
            jp nz, dl_loop
dl_chosen:
            ld a, (dl_si)           ; the bar off
            call dl_bar
            call present
            call dl_end_wait
            ld a, (dl_first)
            ld c, a
            ld a, (dl_si)
            sub c
            inc a
            ret

; the bar over line A XORed: xor_rect3(x0 + 4, (A + 1) * 11 + y0, width - 8, 11, FFFFh)
dl_bar:
            inc a
            ld c, a
            add a, a
            add a, a
            add a, a
            add a, c
            add a, c
            add a, c
            ld hl, dl_y0
            add a, (hl)
            ld (rc_y), a
            ld a, 11
            ld (rc_h), a
            ld a, (dl_x0)
            add a, 4
            ld (rc_x), a
            ld a, (dl_wd)
            sub 8
            ld (rc_w), a
            ld hl, $FFFF
            ld (rc_colour), hl
            jp xor_rect3

dl_end_wait:
            ld a, (dl_wait)
            ld l, a
            ld h, 0
            jp wait_ticks

; piece A of the frame at C (4-pixel units), E (masked, from the font)
dl_piece:
            ld l, c
            ld h, 0
            add hl, hl
            add hl, hl
            ld c, FONT_PAGE
            ld b, OP_MASKED
            jp sprite

; ------------------------------------------------------------------ the title's sparkles (179A)

; a sparkle around HL, E (pixels, lines), on the screen itself: 11 rounds of 4
; pixels (offsets DS:0936) turn white, a pause of 2 ticks, the same 11 rounds
; put back, the centre put back, then A ticks. Each round waits about 7 ms.
; A = a key pressed meanwhile (0: none).
title_twinkle:
            ld (tw_x), hl
            ld (tw_d), a
            ld a, e
            ld (tw_y), a
            ld d, SCREEN_PAGE       ; the centre
            call get_pixel
            ld (tw_saved), a
            ld hl, (tw_x)
            ld a, (tw_y)
            ld e, a
            ld d, SCREEN_PAGE
            ld a, $0F
            call put_pixel
            xor a
            ld (tw_k), a
            ld b, 11
tw_out:
            push bc
            ld b, 4
tw_out4:
            push bc
            ld hl, tw_k
            inc (hl)
            call tw_place           ; HL, E: pixel k
            push hl
            push de
            ld d, SCREEN_PAGE
            call get_pixel
            call tw_slot
            ld (hl), a
            pop de
            pop hl
            ld d, SCREEN_PAGE
            ld a, $0F
            call put_pixel
            pop bc
            djnz tw_out4
            call frame_done
            ld a, 12
            call delay_ints
            call sys_check
            pop bc
            djnz tw_out
            ld hl, 2
            call delay_ticks
            ld b, 11
tw_back:
            push bc
            ld b, 4
tw_back4:
            push bc
            call tw_place
            push hl
            push de
            call tw_slot
            ld a, (hl)
            pop de
            pop hl
            ld d, SCREEN_PAGE
            call put_pixel
            ld hl, tw_k
            dec (hl)
            pop bc
            djnz tw_back4
            call frame_done
            ld a, 12
            call delay_ints
            call sys_check
            pop bc
            djnz tw_back
            ld hl, (tw_x)           ; the centre back
            ld a, (tw_y)
            ld e, a
            ld d, SCREEN_PAGE
            ld a, (tw_saved)
            call put_pixel
            call frame_done
            ld a, (tw_d)
            ld l, a
            ld h, 0
            call delay_ticks
            jp get_key

; HL, E = the sparkle's pixel k: x + the signed byte at DS:0936 + 2k, y + DS:0937 + 2k
tw_place:
            ld a, (tw_k)
            ld l, a
            ld h, 0
            add hl, hl
            ld de, DSEG + $0936
            add hl, de
            ld a, (hl)              ; dx
            inc hl
            ld c, (hl)              ; dy
            ld e, a
            ld d, 0
            bit 7, a
            jp z, tp_dx
            dec d
tp_dx:
            ld hl, (tw_x)
            add hl, de
            ld a, (tw_y)
            add a, c
            ld e, a
            ret

; HL = where pixel k is kept (A kept)
tw_slot:
            push af
            ld a, (tw_k)
            ld e, a
            ld d, 0
            ld hl, tw_saved
            add hl, de
            pop af
            ret

; the six sparkles: x, y, the ticks after
; the Next's own credit card: a box as the credits' (1689: no frame, 54 ticks),
; kept here (the dialog's offsets reach it past the data segment)
cr_box:     db $14, $48, 3, $2E, $FD, $FF, $00, $FF, $36
            dw cr_lines - DSEG
cr_lines:   dw cr_l1 - DSEG, cr_l2 - DSEG, cr_l3 - DSEG
cr_l1:      db "  ZX Spectrum Next remake", 0
cr_l2:      db "    using Claude Opus 5.5,", 0
cr_l3:      db "          Nov. 2026", 0

twinkles:
            dw 55
            db 67, 9
            dw $112
            db 41, 18
            dw 117
            db 98, 9
            dw 223
            db 97, 18
            dw 122
            db 156, 9
            dw 247
            db 141, 9

; ------------------------------------------------------------------ the choice of character

; the keypad moves the choice (DS:0906, 8 bytes for each character: the one
; to go to for 8 9 6 3 2 1 4 7); each is shown by its name box XORed in
; (BF items 8-11 at DS:08F2, DS:08FC); Enter chooses
character_choice:
            ld a, $FF
            ld (cc_di), a
            xor a
            ld (cc_key), a
cc_loop:
            ld a, (cc_key)
            ld hl, cc_keys
            ld b, 8
            ld c, 0
cc_find:
            cp (hl)
            jp z, cc_found
            inc hl
            inc c
            djnz cc_find
            jp cc_show
cc_found:
            ld hl, (DSEG + D_PLAYER)  ; the next: DS:0906 + 8 * player + ofs
            add hl, hl
            add hl, hl
            add hl, hl
            ld de, DSEG + $0906
            add hl, de
            ld e, c
            ld d, 0
            add hl, de
            ld a, (hl)
            or a
            jp z, cc_show
            ld l, a
            ld h, 0
            bit 7, a
            jp z, cc_set
            dec h
cc_set:
            ld (DSEG + D_PLAYER), hl
cc_show:
            ld a, (DSEG + D_PLAYER)
            ld hl, cc_di
            cp (hl)
            jp z, cc_present
            ld a, (hl)
            cp $FF
            call nz, cc_xor         ; the last one's box off
            ld a, (DSEG + D_PLAYER)
            ld (cc_di), a
            call cc_xor             ; the new one's on
cc_present:
            call present
            call wait_key
            ld (cc_key), a
            cp KEY_ENTER
            ret z
            jp cc_loop

; the name box of character A XORed in: BF item A + 7 at (DS:08F2 + 2A) * 4, DS:08FC + 2A
cc_xor:
            ld (cc_item), a
            add a, a
            ld e, a
            ld d, 0
            ld hl, DSEG + $08FC
            add hl, de
            ld a, (hl)
            ld (cc_y), a
            ld hl, DSEG + $08F2
            add hl, de
            ld a, (hl)
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            ld a, (cc_y)
            ld e, a
            ld a, (cc_item)
            add a, 7
            ld c, CHARS_PAGE
            ld b, OP_XOR
            jp sprite

cc_keys:    db $48, $49, $4D, $51, $50, $4F, $4B, $47   ; 8 9 6 3 2 1 4 7

; ------------------------------------------------------------------ the campfire (18C9)

; A frames of the fire: off, flame 1, flame 2 in turn (the font's B6h, B7h at
; 144, 121), each on the back page then the bottom half presented, then taken off
fire_flicker:
            ld (ff_n), a
ff_loop:
            ld a, (ff_n)
            or a
            ret z
            dec a
            ld (ff_n), a
            call get_key
            call fire_draw
            call present_bottom
            call fire_erase
            ld a, (fire_phase)
            inc a
            cp 3
            jp c, ff_phase
            xor a
ff_phase:
            ld (fire_phase), a
            jp ff_loop

fire_draw:
            ld a, (fire_phase)
            or a
            ret z
            add a, $B5
            ld (fd_item), a
            ld c, FONT_PAGE         ; its size
            call item_size
            ld a, (bl_w)
            ld (sv_w), a
            ld a, (bl_h)
            ld (sv_h), a
            ld hl, 144              ; what it covers kept
            ld e, 121
            call sv_save
            ld a, 1
            ld (fire_saved), a
            ld a, (fd_item)
            ld hl, 144
            ld e, 121
            ld c, FONT_PAGE
            ld b, OP_MASKED
            jp sprite

fire_erase:
            ld a, (fire_saved)
            or a
            ret z
            xor a
            ld (fire_saved), a
            ld hl, 144
            ld e, 121
            jp sv_restore
