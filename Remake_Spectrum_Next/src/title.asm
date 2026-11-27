; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; title.asm: the title test. Shows the Tandy 1000 pictures on Layer 2
; (320x256, 256 colours), loaded from the SD card, and plays the Tandy music
; with the original's own driver (tandy.asm), timed by the Next's CTC.
;
;   1-8    the eight tunes, in the order of the game's tune numbers 97h-9Eh
;          (1 is the opening theme, which starts by itself)
;   Space  the current tune again from the top
;   O, P   the previous, next picture (the title, CB, is shown first)
;
; The pictures: DOTC_GFX/CA.PIC-CT.PIC beside the .nex (tools/convert.py), each a
; Layer 2 screen (81920 bytes) and its 17 colours. One is read, through
; esxDOS (RST 08h), into the Layer 2 buffer not on show, 8K at a time through
; MMU slot 3 (6000h-7FFFh), and its colours into the Layer 2 palette not in
; use; then both are switched over together, below the picture, so it never
; shows half loaded. Interrupts are off while a file is read (the API
; document says nothing about them), so the music waits meanwhile.
;
; The timing: CTC channel 0 interrupts about 1700 times a second (28 MHz /
; 256 / 64; one channel, as CSpect doesn't chain them). Each interrupt adds
; its length in PC timer counts (1193182 a second) to ctc_acc; each time that
; passes the song's tempo (the PC timer's count between the driver's
; interrupts), the driver runs once. So the driver runs at the original's
; 1193182 / tempo a second (149-239 for these songs), within 0.6 ms.
;
; Memory (16K banks, as tools/make_nex.py loads them):
;   8000h-9EFFh  this code, the palette, the AY tables
;   9F00h-9F1Fh  the IM2 vector table (hardware IM2: CTC 0 at offset 06h)
;   A000h-E72Dh  BG, the Tandy music (build/bg.bin)
;   the stack below 0000h
;   banks 20-24, 25-29  the two Layer 2 buffers
;
; Assemble with Boriel's zxbasm (pip install zxbasic):
;   zxbasm --zxnext src/title.asm -o build/title.bin

L2_BANK_A   EQU 20              ; the two Layer 2 buffers' first 16K banks
L2_BANK_B   EQU 25
MMU3_HOME   EQU 11              ; MMU slot 3's page normally (bank 5's upper half)
F_OPEN      EQU $9A             ; esxDOS calls (RST 08h, then the code)
F_CLOSE     EQU $9B
F_READ      EQU $9D
PICTURES    EQU 20              ; CA-CT
BG_BASE     EQU $A000           ; the music data
REG_SELECT  EQU $243B           ; Next register select / access ports
AY_SELECT   EQU $FFFD           ; AY register select (and Turbosound chip select)
AY_DATA     EQU $BFFD
LAYER2_PORT EQU $123B
CTC0        EQU $183B           ; CTC channel 0
CTC_TC      EQU 64              ; its time constant (with the 256 prescaler)

            org $8000

start:
            di
            ld sp, $0000            ; the stack grows down from FFFFh, above the music
            nextreg $07, 3          ; 28 MHz
            xor a
            out ($FE), a            ; black border (hidden by Layer 2 320x256 anyway)
            ld bc, $7FFD            ; the 48K BASIC ROM at 0000h, as esxDOS calls need
            ld a, $10               ; (and RAM bank 0 at C000h, as it is)
            out (c), a
            ld b, $1F
            ld a, $04
            out (c), a
            ld hl, $4000            ; the ULA screen black, until a picture is on
            ld de, $4001
            ld bc, $1AFF
            ld (hl), 0
            ldir

; ------------------------------------------------------------------ Layer 2, 320x256

            nextreg $15, $00        ; sprites off; layer order: sprites, Layer 2, ULA
            nextreg $70, $10        ; Layer 2 320x256 8-bit, palette offset 0
            nextreg $16, 0          ; no scroll
            nextreg $71, 0
            nextreg $17, 0
            nextreg $1C, $01        ; reset the Layer 2 clip window index
            nextreg $18, 0          ; x1 (in 320 mode the x values are halved)
            nextreg $18, 159        ; x2
            nextreg $18, 0          ; y1
            nextreg $18, 255        ; y2

            ; Layer 2 stays off until the first picture is loaded

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

            ld a, vectors >> 8      ; hardware IM2, the vectors at 9F00h
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

            ld a, 1                 ; the title (CB)
            ld (cur_pic), a
            call load_picture
            xor a                   ; key 1: the opening theme
            call play_key
            ei

; ------------------------------------------------------------------ the keys

main_loop:
            call read_key           ; A = 0-7 for keys 1-8, 8 for Space, FFh none
            ld hl, last_key
            cp (hl)
            jp z, main_loop         ; held, or still none
            ld (hl), a
            cp $FF
            jp z, main_loop
            cp 9
            jp z, ml_prev
            cp 10
            jp z, ml_next
            cp 8
            jp nz, ml_tune
            ld a, (cur_key)         ; Space: the current tune again
ml_tune:
            call play_key
            jp main_loop
ml_prev:
            ld a, (cur_pic)         ; O: the previous picture
            or a
            jp nz, ml_prev1
            ld a, PICTURES
ml_prev1:
            dec a
            jp ml_pic
ml_next:
            ld a, (cur_pic)         ; P: the next picture
            inc a
            cp PICTURES
            jp c, ml_pic
            xor a
ml_pic:
            ld (cur_pic), a
            call load_picture
            jp main_loop

; A = key 0-7: start the tune (interrupts off meanwhile)
play_key:
            ld (cur_key), a
            ld e, a
            ld d, 0
            ld hl, key_songs
            add hl, de
            ld a, (hl)
            di
            call drv_start
            ld hl, 0
            ld (ctc_acc), hl
            ei
            ret

; A = the key held: 0-7 for 1-8, 8 for Space, 9 for O, 10 for P, FFh for none
read_key:
            ld bc, $F7FE            ; 1-5: bits 0-4
            in a, (c)
            ld e, 0
            ld d, 5
rk_low:
            rrca
            jp nc, rk_got
            inc e
            dec d
            jp nz, rk_low
            ld b, $EF               ; 6, 7, 8: bits 4, 3, 2
            in a, (c)
            bit 4, a
            ld e, 5
            jp z, rk_got
            bit 3, a
            ld e, 6
            jp z, rk_got
            bit 2, a
            ld e, 7
            jp z, rk_got
            ld b, $7F               ; Space: bit 0
            in a, (c)
            ld e, 8
            rrca
            jp nc, rk_got
            ld b, $DF               ; P, O: bits 0, 1
            in a, (c)
            ld e, 10
            rrca
            jp nc, rk_got
            ld e, 9
            rrca
            jp nc, rk_got
            ld e, $FF
rk_got:
            ld a, e
            ret

; ------------------------------------------------------------------ the pictures

; A = picture 0-19: read DOTC_GFX/C?.PIC into the Layer 2 buffer not on show, and
; its colours into the Layer 2 palette not in use, then show both. If it can't
; be read, the screen stays as it was and the border turns red.
load_picture:
            add a, 'A'
            ld (pic_name + 10), a   ; the second letter of the name
            di
            ld a, '*'               ; the current drive; the name is relative to the current folder
            ld ix, pic_name
            ld b, $01               ; read, the file must exist
            rst $08
            db F_OPEN
            jp c, lp_failed
            ld (pic_handle), a
            ld a, (back_bank)
            add a, a
            ld (lp_pg), a           ; the buffer's first 8K page
            ld b, 10                ; 81920 bytes: ten 8K pages
lp_page:
            push bc
            ld a, (lp_pg)
            nextreg $53, a          ; MMU slot 3 (6000h) onto the page
            ld a, (pic_handle)
            ld ix, $6000
            ld bc, $2000
            rst $08
            db F_READ
            pop de
            jp c, lp_close
            ld a, b                 ; all 8K?
            cp $20
            jp nz, lp_close
            ld a, c
            or a
            jp nz, lp_close
            ld hl, lp_pg
            inc (hl)
            ld b, d
            djnz lp_page
            nextreg $53, MMU3_HOME
            ld a, (pic_handle)      ; the 17 colours
            ld ix, pic_colours
            ld bc, 17 * 2
            rst $08
            db F_READ
            jp c, lp_close
            ld a, c
            cp 17 * 2
            jp nz, lp_close
            ld a, (pic_handle)
            rst $08
            db F_CLOSE

            ld a, (back_pal)        ; the colours into the palette not in use:
            or a                    ; NextReg 43h bits 6-4 = 001 (Layer 2's first) or 101 (second),
            ld a, $10               ; bit 2 = the one shown, kept
            jp z, lp_sel
            ld a, $50
lp_sel:
            ld e, a
            ld a, (back_pal)
            xor 1                   ; the one shown now
            add a, a
            add a, a
            or e
            nextreg $43, a
            nextreg $40, 0
            ld hl, pic_colours
            ld b, 17 * 2
lp_colour:
            ld a, (hl)
            inc hl
            nextreg $44, a
            djnz lp_colour

            ld a, 210               ; switch below the picture (in the black band at the bottom)
            call wait_line
            ld a, (back_bank)
            nextreg $12, a          ; the new buffer ...
            ld a, (back_pal)
            add a, a
            add a, a
            or $10                  ; (writes still aimed at Layer 2's first palette)
            nextreg $43, a          ; ... and its palette
            ld bc, LAYER2_PORT
            ld a, $02               ; Layer 2 on (it is off until the first picture)
            out (c), a
            ld a, (back_bank)       ; the other buffer is now the one not on show
            cp L2_BANK_A
            ld a, L2_BANK_B
            jp z, lp_other
            ld a, L2_BANK_A
lp_other:
            ld (back_bank), a
            ld a, (back_pal)
            xor 1
            ld (back_pal), a
            xor a
            out ($FE), a
            ei
            ret

lp_close:
            nextreg $53, MMU3_HOME
            ld a, (pic_handle)
            rst $08
            db F_CLOSE
lp_failed:
            nextreg $53, MMU3_HOME
            ld a, 2                 ; red border
            out ($FE), a
            ei
            ret

; wait for the raster to reach line A (NextReg 1Fh: the line's low byte;
; lines run 0-311, so lines below 56 are ambiguous: use 56-255)
wait_line:
            ld e, a
            ld bc, REG_SELECT
            ld a, $1F
            out (c), a
            inc b
wl_leave:
            in a, (c)
            cp e
            jp z, wl_leave
wl_reach:
            in a, (c)
            cp e
            jp nz, wl_reach
            ret

; ------------------------------------------------------------------ the interrupts

; CTC channel 0
ctc_isr:
            push af
            push bc
            push de
            push hl
            push ix
            nextreg $C9, $01        ; acknowledge CTC 0, or it blocks the next one
            ld a, (drv_playing)
            or a
            jp z, ci_done
            ld hl, (ctc_acc)
            ld de, (ctc_step)
            add hl, de
            ld de, (drv_tempo)
            or a
            sbc hl, de
            jp nc, ci_run
            add hl, de              ; not yet
            ld (ctc_acc), hl
            jp ci_done
ci_run:
            ld (ctc_acc), hl
            call drv_interrupt
ci_done:
            pop ix
            pop hl
            pop de
            pop bc
            pop af
            ei
            reti

; anything else (none is enabled): acknowledge all
other_isr:
            nextreg $C8, $FF
            nextreg $C9, $FF
            nextreg $CA, $FF
            ei
            reti

; ------------------------------------------------------------------ helpers

; A = Next register A
get_reg:
            ld bc, REG_SELECT
            out (c), a
            inc b                   ; 253Bh: the register's value
            in a, (c)
            ret

; AY register E = A (BC changed)
ay_set:
            ld bc, AY_SELECT
            out (c), e
            ld b, AY_DATA >> 8
            out (c), a
            ret

#include "tandy.asm"

; ------------------------------------------------------------------ data

; the CTC's interrupt in PC timer counts: 1193182 * 256 * 64 / the CTC clock,
; for each video timing (NextReg 11h): 28, 28.57, 29.46, 30, 31, 32, 33 MHz
; (VGA 0-6) and 27 MHz (HDMI)
ctc_steps:  dw 698, 684, 663, 652, 631, 611, 592, 724
ctc_step:   dw 698
ctc_acc:    dw 0
; the Tandy song for each key: tunes 97h-9Eh (sound.c TANDY_SONG)
key_songs:  db 5, 6, 4, 2, 0, 3, 7, 1
cur_key:    db 0
last_key:   db $FF
cur_pic:    db 0
back_bank:  db L2_BANK_A        ; the Layer 2 buffer not on show
back_pal:   db 0                ; the Layer 2 palette not in use (0 first, 1 second)
pic_handle: db 0
lp_pg:      db 0
pic_name:   db "DOTC_GFX/CB.PIC", 0
pic_colours:
            ds 17 * 2
ay_period_tab:
            incbin "../build/ay_period.bin"     ; 1024 words: the AY period for each Tandy tone register
ay_vol_tab:
            incbin "../build/ay_volume.bin"     ; 16 bytes: the AY volume for each Tandy attenuation
code_end:

            org $9F00
vectors:    dw other_isr, other_isr, other_isr, ctc_isr     ; line, UART 0 Rx, UART 1 Rx, CTC 0
            dw other_isr, other_isr, other_isr, other_isr   ; CTC 1-4
            dw other_isr, other_isr, other_isr, other_isr   ; CTC 5-7, ULA
            dw other_isr, other_isr, other_isr, other_isr   ; UART 0 Tx, UART 1 Tx, (spare)

            org BG_BASE
bg:         incbin "../build/bg.bin"
bg_end:

            end start
