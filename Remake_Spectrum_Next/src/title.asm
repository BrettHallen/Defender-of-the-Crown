; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; title.asm: the title test. Shows the Tandy 1000 title picture on Layer 2
; (320x256, 256 colours) and plays the Tandy music with the original's own
; driver (tandy.asm), timed by the Next's CTC.
;
;   1-8    the eight tunes, in the order of the game's tune numbers 97h-9Eh
;          (1 is the opening theme, which starts by itself)
;   Space  the current tune again from the top
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
;   banks 20-24  the picture (build/title.l2), shown by Layer 2
;
; Assemble with Boriel's zxbasm (pip install zxbasic):
;   zxbasm --zxnext src/title.asm -o build/title.bin

L2_BANK     EQU 20              ; the picture's first 16K bank
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

; ------------------------------------------------------------------ Layer 2, 320x256

            nextreg $15, $00        ; sprites off; layer order: sprites, Layer 2, ULA
            nextreg $70, $10        ; Layer 2 320x256 8-bit, palette offset 0
            nextreg $12, L2_BANK    ; the picture's banks
            nextreg $16, 0          ; no scroll
            nextreg $71, 0
            nextreg $17, 0
            nextreg $1C, $01        ; reset the Layer 2 clip window index
            nextreg $18, 0          ; x1 (in 320 mode the x values are halved)
            nextreg $18, 159        ; x2
            nextreg $18, 0          ; y1
            nextreg $18, 255        ; y2

            nextreg $43, $10        ; write Layer 2's first palette, auto-increment; show the first palettes
            nextreg $40, 0          ; from entry 0
            ld hl, palette
            ld b, 17 * 2            ; 17 colours, two bytes each (9-bit)
pal_loop:
            ld a, (hl)
            inc hl
            nextreg $44, a
            djnz pal_loop

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
            cp 8
            jp nz, ml_tune
            ld a, (cur_key)         ; Space: the current tune again
ml_tune:
            call play_key
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

; A = the key held: 0-7 for 1-8, 8 for Space, FFh for none
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
            ld e, $FF
rk_got:
            ld a, e
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
palette:    incbin "../build/title.pal"
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
