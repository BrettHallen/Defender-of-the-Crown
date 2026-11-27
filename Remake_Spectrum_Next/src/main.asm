; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; main.asm: the game for the Next, from the booter's Tandy 1000 program (AC),
; following the Mac remake's port of it (Remake/src). So far: the opening,
; to Sherwood.
;
; Memory (8K pages; slots are the Z80's 8K windows):
;   slot 0  0000h  the ROM; the sprites and the picture cache are read here
;   slot 1  2000h  the ROM; the music driver reads BG here (in its interrupt)
;   slots 2-4      the data segment (BH): DSEG + offset, as the original's DS:offset
;   slots 5-6      this code (A000h-DFFFh): the vectors at DF00h, the stack below
;   slot 7  E000h  the window onto Layer 2's pages (and the files' while reading)
;
;   pages 12-14  the data segment     pages 40-49  Layer 2: the screen
;   pages 16-18  BG, the Tandy music  pages 50-59  Layer 2: the back page
;   pages 20-22  BC, the font         pages 60-83  the picture cache (6 x 4)
;   page 24      BF, the name boxes
;
; Assemble with Boriel's zxbasm (pip install zxbasic):
;   zxbasm --zxnext src/main.asm -o build/main.bin
; It INCBINs the converter's tables from build/ (tools/convert.py).

DSEG          EQU $4000           ; the data segment
WINDOW      EQU $E000           ; slot 7
DS_PAGE     EQU 12
BG_PAGE     EQU 16
FONT_PAGE   EQU 20
CHARS_PAGE  EQU 24
SCREEN_BANK EQU 20              ; Layer 2's two buffers (16K banks)
BACK_BANK   EQU 25
SCREEN_PAGE EQU SCREEN_BANK * 2
BACK_PAGE   EQU BACK_BANK * 2
CACHE_PAGE  EQU 60
STACK_TOP   EQU $DE00
TOP         EQU 28              ; the picture's first row in Layer 2's 256
SCREEN_H    EQU 200

REG_SELECT  EQU $243B           ; Next register select / access ports
AY_SELECT   EQU $FFFD           ; AY register select (and Turbosound chip select)
AY_DATA     EQU $BFFD
LAYER2_PORT EQU $123B
CTC0        EQU $183B           ; CTC channel 0
CTC_TC      EQU 64              ; its time constant (with the 256 prescaler)
F_OPEN      EQU $9A             ; esxDOS calls (RST 08h, then the code)
F_CLOSE     EQU $9B
F_READ      EQU $9D

OP_COPY     EQU 0               ; blit's ways
OP_XOR      EQU 1
OP_MASKED   EQU 2
IT_GLYPH    EQU 4               ; a sprite item that is a letter

            org $A000

start:
            di
            ld sp, STACK_TOP
            nextreg $07, 3          ; 28 MHz
            xor a
            out ($FE), a            ; black border (hidden by Layer 2 320x256 anyway)
            ld bc, $7FFD            ; the 48K BASIC ROM at 0000h, as esxDOS calls need
            ld a, $10               ; (and RAM bank 0 at C000h, as it is)
            out (c), a
            ld b, $1F
            ld a, $04
            out (c), a
            nextreg $50, $FF        ; slots 0, 1: the ROM
            nextreg $51, $FF
            nextreg $52, DS_PAGE    ; slots 2-4: the data segment
            nextreg $53, DS_PAGE + 1
            nextreg $54, DS_PAGE + 2
            ld a, SCREEN_PAGE
            ld (win_page), a
            nextreg $57, a

; ------------------------------------------------------------------ Layer 2, 320x256

            ld b, 20                ; both buffers black (palette entry 16)
            ld c, SCREEN_PAGE
cl_page:
            push bc
            ld a, c
            call win_map
            ld hl, WINDOW
            ld de, WINDOW + 1
            ld bc, $1FFF
            ld (hl), 16
            ldir
            pop bc
            inc c
            djnz cl_page
            nextreg $15, $00        ; sprites off; layer order: sprites, Layer 2, ULA
            nextreg $70, $10        ; Layer 2 320x256 8-bit, palette offset 0
            nextreg $12, SCREEN_BANK
            nextreg $16, 0          ; no scroll
            nextreg $71, 0
            nextreg $17, 0
            nextreg $1C, $01        ; reset the Layer 2 clip window index
            nextreg $18, 0          ; x1 (in 320 mode the x values are halved)
            nextreg $18, 159        ; x2
            nextreg $18, 0          ; y1
            nextreg $18, 255        ; y2
            call set_palette        ; 16 colours (all black so far: pal_next is 0)
            nextreg $40, 16         ; entry 16: the black around the picture
            nextreg $44, 0
            nextreg $44, 0
            ld bc, LAYER2_PORT
            ld a, $02               ; Layer 2 on
            out (c), a

; ------------------------------------------------------------------ the AY

            ld a, $08               ; NextReg 08h bit 1: Turbosound on (the AY selection works)
            call get_reg
            or $02
            nextreg $08, a
            ld a, $09               ; NextReg 09h bit 5: AY 0 in mono, as the Tandy's one speaker
            call get_reg
            or $20
            nextreg $09, a
            ld bc, AY_SELECT
            ld a, $FF               ; Turbosound: AY 0 (bits 1-0 = 11), left and right on
            out (c), a
            ld e, 7
            ld a, $38               ; mixer: tones A, B, C on; no noise
            call ay_set
            ld ix, voices           ; the three tone registers as the Tandy chip's after a reset (0)
            ld b, 3
ay_init:
            push bc
            ld hl, 0
            call sn_tone
            ld de, V_SIZE
            add ix, de
            pop bc
            djnz ay_init
            call drv_stop           ; and the volumes off

; ------------------------------------------------------------------ the timer

            ld a, $11               ; the CTC's clock follows the video timing (NextReg 11h bits 2-0)
            call get_reg
            and $07
            add a, a
            ld l, a
            ld h, 0
            ld de, ctc_steps
            add hl, de
            ld a, (hl)
            inc hl
            ld h, (hl)
            ld l, a
            ld (ctc_step), hl

            ld a, vectors >> 8      ; hardware IM2, the vectors at DF00h
            ld i, a
            im 2
            nextreg $C0, $01        ; vector bits 7-5 = 000, hardware IM2 mode
            nextreg $C4, $00        ; no ULA frame or line interrupt
            nextreg $C5, $01        ; CTC channel 0 only
            nextreg $C6, $00        ; no UART
            nextreg $C8, $FF        ; clear anything pending
            nextreg $C9, $FF
            nextreg $CA, $FF
            ld bc, CTC0
            ld a, $03               ; reset the channel (twice, as the Klive book's demo)
            out (c), a
            out (c), a
            ld a, $A7               ; interrupt on, timer, prescaler 256, time constant follows, reset, control
            out (c), a
            ld a, CTC_TC
            out (c), a

; ------------------------------------------------------------------ the opening's pictures, then the game

            xor a                   ; read before the opening, so it never waits for the card
pre_load:
            push af
            call load_picture
            pop af
            jp c, pre_next
            ld l, a
            ld h, 0
            ld de, pic_loaded
            add hl, de
            ld (hl), 1
pre_next:
            inc a
            cp 6
            jp nz, pre_load
            ei
            call new_game
the_end:
            call idle               ; (the month comes next)
            jp the_end

; ------------------------------------------------------------------ helpers

; A = Next register A (at the start, with interrupts off: once they are on, the
; interrupt routine uses the Next registers too)
get_reg:
            ld bc, REG_SELECT
            out (c), a
            inc b
            in a, (c)
            ret

; AY register E = A (BC changed)
ay_set:
            ld bc, AY_SELECT
            out (c), e
            ld b, AY_DATA >> 8
            out (c), a
            ret

#include "sys.asm"
#include "gfx.asm"
#include "opening.asm"
#include "tandy.asm"

; ------------------------------------------------------------------ data

; the CTC's interrupt in PC timer counts: 1193182 * 256 * 64 / the CTC clock,
; for each video timing (NextReg 11h): 28, 28.57, 29.46, 30, 31, 32, 33 MHz
; (VGA 0-6) and 27 MHz (HDMI)
ctc_steps:  dw 698, 684, 663, 652, 631, 611, 592, 724
ctc_step:   dw 698
ctc_acc:    dw 0                ; PC timer counts towards the music driver's next interrupt
tick_acc:   dw 0                ; ... towards the next BIOS tick
ret_acc:    dw 0                ; ... towards the PC's next retrace
retraces:   db 0                ; the PC's retraces (60 a second)
bios_ticks: dw 0                ; the BIOS clock (int 1Ah's low word)
ctc_count:  db 0                ; the interrupts (delay_ints)
; the Tandy song for each tune 97h-9Eh (sound.c TANDY_SONG)
key_songs:  db 5, 6, 4, 2, 0, 3, 7, 1
; the game's tune (sound.c's TuneState): its number, note, ticks left, flags
spk_tune:   db 0
spk_index:  dw 0
spk_ticks:  dw 0
spk_flags:  dw 1
spk_notes:  dw speaker
; the keys
sk_caps:    db 0
keys_held:  dw 0
keys_waiting: dw 0
; the waits
wt_n:       dw 0
wt_last:    dw 0
wt_key:     db 0
skip_armed: db 0
skip_to:    dw 0
skip_sp:    dw 0
; the files and pictures
lp_pic:     db 0
lp_pg:      db 0
pic_handle: db 0
pic_name:   db "DOTC_GFX/CB.PIC", 0
pic_loaded: ds 20               ; 1: in the cache
pic_page:   db CACHE_PAGE, CACHE_PAGE + 4, CACHE_PAGE + 8, CACHE_PAGE + 12, CACHE_PAGE + 16, CACHE_PAGE + 20
            ds 14               ; (the others: with the rest of the game)
; the screen
win_page:   db 0                ; slot 7's page
spr_page:   db $FF              ; slot 0's (FFh: the ROM)
dirty_lo:   dw 320              ; the back page's columns changed since the last present
dirty_hi:   dw 0                ; (none: lo > hi)
cb_col:     dw 0
cb_end:     dw 0
pp_colour:  db 0
pal_next:   ds 16               ; CS:0103: the palette set_palette will show
pal:        ds 16               ; the palette registers
rc_x:       db 0                ; rectangles (4-pixel units, lines)
rc_y:       db 0
rc_w:       db 0
rc_h:       db 0
rc_colour:  dw 0
rc_byte:    db 0
rc_op:      db 0
rc_col:     dw 0
rc_cols:    dw 0
rc_n:       db 0
rc_value:   db 0
bl_item:    db 0                ; blit
bl_file:    db 0
bl_x:       dw 0
bl_y:       db 0
bl_op:      db 0
bl_dest:    db 0
bl_kind:    db 0
bl_masked:  db 0
bl_w:       dw 0
bl_h:       db 0
bl_adv:     db 0
bl_src:     dw 0
bl_stride:  dw 0
bl_next_src: dw 0
bl_pairs:   dw 0
bl_n:       db 0
bl_col:     dw 0
sv_w:       db 0                ; saving a rectangle
sv_h:       db 0
sv_dir:     db 0
sv_col:     dw 0
sv_y:       db 0
sv_ptr:     dw 0
sv_left:    db 0
sp_pic:     db 0                ; show_picture
sp_page:    db 0
sp_pair:    db 0
; the opening
dl_x0:      db 0                ; dialog
dl_y0:      db 0
dl_n:       db 0
dl_wd:      db 0
dl_icon:    db 0
dl_wait:    db 0
dl_lines:   dw 0
dl_x1:      db 0
dl_y1:      db 0
dl_di:      db 0
dl_px:      db 0
dl_py:      db 0
dl_ty:      db 0
dl_tx:      dw 0
dl_lp:      dw 0
dl_s:       dw 0
dl_left:    db 0
tw_x:       dw 0                ; the sparkles
tw_y:       db 0
tw_d:       db 0
tw_k:       db 0
tw_saved:   ds 45
cc_di:      db 0                ; the choice
cc_key:     db 0
cc_item:    db 0
cc_y:       db 0
ff_n:       db 0                ; the fire
fire_phase: db 0
fire_saved: db 0
fd_item:    db 0
; the converter's tables
rgb16:      incbin "../build/rgb16.bin"         ; the Tandy's 16 colours, as the Next's (2 bytes each)
speaker:    incbin "../build/speaker.bin"       ; the speaker tunes' note lengths
ay_period_tab:
            incbin "../build/ay_period.bin"     ; 1024 words: the AY period for each Tandy tone register
ay_vol_tab:
            incbin "../build/ay_volume.bin"     ; 16 bytes: the AY volume for each Tandy attenuation
save_buf:   ds 64 * 47                          ; what the fire covers
code_end:

            org $DF00
vectors:    dw other_isr, other_isr, other_isr, ctc_isr     ; line, UART 0 Rx, UART 1 Rx, CTC 0
            dw other_isr, other_isr, other_isr, other_isr   ; CTC 1-4
            dw other_isr, other_isr, other_isr, other_isr   ; CTC 5-7, ULA
            dw other_isr, other_isr, other_isr, other_isr   ; UART 0 Tx, UART 1 Tx, (spare)
vectors_end:

            end start
