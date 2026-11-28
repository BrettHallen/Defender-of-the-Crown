; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; main.asm: the game for the Next, from the booter's Tandy 1000 program (AC),
; following the Mac remake's port of it (Remake/src). So far: the opening,
; the setup of a new game and the player's month (the map, the status panel,
; the events, the orders Pass and Options).
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
;   pages 20-21  BC, the font         pages 60-83  the picture cache: pictures
;   page 22      BF, the name boxes                0-5 (4 pages each)
;   pages 24-36  BR + BS: the map's   pages 84-91  the map, a byte a pixel
;                shapes, the castles, pages 92-95  the other pictures, one at a
;                the portraits                     time
; Up to page 95: the Next's 1MB is enough.
;
; Assemble with Boriel's zxbasm (pip install zxbasic):
;   zxbasm --zxnext src/main.asm -o build/main.bin
; It INCBINs the converter's tables from build/ (tools/convert.py). The game's
; logic beyond the month's own is in overlays (ov_*.asm), assembled after it.

#include "defs.asm"

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
            ld hl, HI_TAB & $FFFF   ; the high nibbles' table
            xor a
hi_fill:
            ld c, a
            rrca
            rrca
            rrca
            rrca
            and $0F
            ld (hl), a
            ld a, c
            inc a
            inc l
            jp nz, hi_fill
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
            call stretch_init       ; (V: the picture on 240 lines, by the copper)

; ------------------------------------------------------------------ the AY

            ld a, $08               ; NextReg 08h bit 1: Turbosound on (the AY selection works)
            call get_reg
            or $02
            nextreg $08, a
            ld a, $09               ; NextReg 09h bit 5: AY 0 in mono, as the Tandy's one speaker
            call get_reg
            or $20
            nextreg $09, a
            ld a, $09               ; ... and AY 1, the speaker's beeps (beep)
            call get_reg
            or $40
            nextreg $09, a
            call ay1_on
            ld e, 7
            ld a, $3E               ; mixer: tone A only
            call ay_set
            ld e, 8
            xor a                   ; silent
            call ay_set
            call ay0_on
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
            call map_keep           ; and the map
            call read_clock
            ei

; ------------------------------------------------------------------ main (1014)

game_loop:
            ld hl, (DSEG + D_QUIT)
            ld a, h
            or l
            jp nz, quit
            xor a
            ld h, a
            ld l, a
            call play_tune
            call new_game
            ld hl, 0
            ld (DSEG + $2B), hl
            ld (DSEG + D_GAME_OVER), hl
            ld (DSEG + D_FIRST_GAME), hl
gl_month:
            ld hl, (DSEG + D_GAME_OVER)
            ld a, h
            or l
            jp nz, game_loop
            call month
            jp gl_month
quit:                               ; End Present Game: back to the Next's menu (a soft reset)
            di
            nextreg $02, $01
            jp quit

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

; the AY registers' writes go to AY 1 (ay1_on) or AY 0 (ay0_on, the music's);
; with interrupts off, as the music writes AY 0's in its interrupt (BC changed)
ay1_on:
            ld a, $FE
            jp ay_chip
ay0_on:
            ld a, $FF
ay_chip:
            ld bc, AY_SELECT
            out (c), a
            ret

; ------------------------------------------------------------------ the overlays

; The game's logic beyond the month's own is in overlays: 8K pages (OV_...)
; assembled at 2000h, each paged into slot 1 while it runs. A stub calls one
; of an overlay's entries (its table of jumps at 2000h):
;       call ovl_go
;       db page
;       dw entry
; with A, BC, DE, HL as the caller left them; the entry returns through
; ovl_ret, which puts back the page that was there (the ROM, or the overlay
; that called it), its A, BC, DE, HL and flags kept. ovl_cur is the page in
; slot 1: the music driver's interrupt, and the file calls, put it back.
ovl_go:
            ld (og_a), a
            ld (og_hl), hl
            pop hl                  ; the stub's page and entry
            ld a, (ovl_cur)
            ld (og_prev), a
            ld a, (hl)
            ld (ovl_cur), a
            nextreg $51, a
            inc hl
            ld a, (hl)
            inc hl
            ld h, (hl)
            ld l, a
            ld (og_jump + 1), hl
            ld hl, (og_prev)        ; the page to put back (L), on the stack
            push hl
            ld hl, ovl_ret
            push hl
            ld hl, (og_hl)
            ld a, (og_a)
og_jump:
            jp $2000
ovl_ret:
            ld (og_a), a
            ex (sp), hl             ; L: the page that was there
            ld a, l
            ld (ovl_cur), a
            nextreg $51, a
            pop hl
            ld a, (og_a)
            ret

; the stubs: the overlays' entries, by their names
game_setup:
            call ovl_go
            db OV_SETUP
            dw $2000
ai_turn:                            ; A: the side
            call ovl_go
            db OV_WAR
            dw $2000
attack:                             ; A: the attacker, C: the defender, B: the territory -> A: the result
            call ovl_go
            db OV_WAR
            dw $2003
side_falls:                         ; A: the side, C: the winner
            call ovl_go
            db OV_WAR
            dw $2006

army_move_to:                       ; A: the side, C: the territory
            call ovl_go
            db OV_WAR
            dw $2009
army_settle:                        ; A: the side
            call ovl_go
            db OV_WAR
            dw $200C
buy_army:                           ; -> A: 1 if anything was bought
            call ovl_go
            db OV_CONQ
            dw $2000
read_map:
            call ovl_go
            db OV_CONQ
            dw $2003
seek_conquest:                      ; -> A: 1 if the month goes on
            call ovl_go
            db OV_CONQ
            dw $2006
choose_territory:                   ; A: from -> A: the territory
            call ovl_go
            db OV_CONQ
            dw $2009

bombard:                            ; A: the territory -> A: the castle's protection
            call ovl_go
            db OV_SIEGE
            dw $2000

tournament:                         ; A: the side holding it -> A: 1 if held
            call ovl_go
            db OV_TOURN
            dw $2000
army_home:                          ; A: the side (its campaign army home)
            call ovl_go
            db OV_WAR
            dw $200F

#include "sys.asm"
#include "gfx.asm"
#include "opening.asm"
#include "tandy.asm"
#include "game.asm"

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
pr_retrace: db 0                ; retraces at the last present
bios_ticks: dw 0                ; the BIOS clock (int 1Ah's low word)
bios_hi:    db 0                ; (its high word's low byte)
ovl_cur:    db $FF              ; the page in slot 1 (FFh: the ROM)
og_prev:    dw 0                ; ovl_go
og_a:       db 0
og_hl:      dw 0
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
sk_v:       db 0                ; V held
stretched:  db 0                ; the copper stretches the picture
cp_lines:   dw 312              ; the frame's lines
cp_j:       db 0
keys_held:  dw 0
keys_waiting: dw 0
key_rep_at: dw 0                ; when the keys held repeat (BIOS ticks)
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
            db SPARE_PAGE, SPARE_PAGE, SPARE_PAGE, SPARE_PAGE, SPARE_PAGE
            db SPARE_PAGE, SPARE_PAGE, SPARE_PAGE, SPARE_PAGE, SPARE_PAGE
            db SPARE_PAGE, SPARE_PAGE, SPARE_PAGE, SPARE_PAGE
spare_pic:  db $FF              ; the picture in the spare pages (FFh: none)
scene_has:  db 0                ; the scenes' sprite files read: 1 the siege's, 2 the tournament's, 4 the lane's
ls_id:      db 0
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
pal_slot:   ds 16               ; 9C31: the map's palette (slot 0)
pal_late:   db 0                ; 1: set_palette with the next present
rg_colour:  dw 0                ; set_region_colour
mk_k:       db 0                ; the map's copy
mb_x:       dw 0
mb_src:     dw 0
mb_page:    db 0
mb_dir:     db 0
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
glyph_from: db 0                ; gfx_glyph_alias (0: none)
glyph_to:   db 0
bl_maxrows: db 255              ; a slot's rows (blit draws at most these)
slots:      ds NUM_SLOTS * SLOT_SIZE    ; the sprite slots
slot_saved: ds NUM_SLOTS * SAVED_SIZE
sd_k:       db 0
pool_page:  db 0
pool_off:   dw 0
pc_dir:     db 0
pc_scr:     dw 0                ; the column's address in the window
pc_left:    dw 0
pc_page:    db 0
pc_off:     dw 0
sp_pic:     db 0                ; show_picture
sp_page:    db 0
sp_pair:    db 0
sp_n:       db 0
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
dl_first:   db 0                ; dialog's menus
dl_last:    db 0
dl_start:   db 0
dl_si:      db 0
dl_prev:    db 0
dl_keyv:    db 0
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
code_end:

            org $DF00
vectors:    dw other_isr, other_isr, other_isr, ctc_isr     ; line, UART 0 Rx, UART 1 Rx, CTC 0
            dw other_isr, other_isr, other_isr, other_isr   ; CTC 1-4
            dw other_isr, other_isr, other_isr, other_isr   ; CTC 5-7, ULA
            dw other_isr, other_isr, other_isr, other_isr   ; UART 0 Tx, UART 1 Tx, (spare)
vectors_end:

            end start
