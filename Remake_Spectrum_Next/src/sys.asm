; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; sys.asm: the original's timer, keyboard and tunes, as the Mac remake's
; sys.c and sound.c give them to the game (Remake/src/sys.h, sound.h).
;
; The timer: CTC channel 0 interrupts every 256 * 64 clocks (about 1709 a
; second at 28 MHz). Each interrupt adds its length in PC timer counts
; (1193182 a second) to three counters:
;   ret_acc   each time it passes 19886 (a 60th of a second) is a vertical
;             retrace of the PC's display, which the game's animations wait
;             for (present): the Next's own display runs at 50 Hz, so the
;             original's 60 are counted here, to keep its speed
;   tick_acc  a word: each time it wraps (65536 counts) is a BIOS tick, 18.2
;             a second (int 1Ch), when the speaker tune's timing moves on
;             (tick_player: the game times itself by it, in every mode)
;   ctc_acc   each time it passes the song's tempo, the Tandy music driver
;             runs once (tandy.asm)
;
; The keys: the Next's keyboard read as the PC's scan codes the game wants
; (bios_key): Enter, Space, S (skips parts of the opening),
; the cursor keys as the arrows, and 1-9 without Caps Shift as the numeric
; keypad (7 8 9 / 4 5 6 / 1 2 3), as the game's choices use it.


; ------------------------------------------------------------------ the interrupt

ctc_isr:
            push af
            push bc
            push de
            push hl
            push ix
            nextreg $C9, $01        ; acknowledge CTC 0, or it blocks the next one
            ld hl, ctc_count        ; the interrupts, for short waits (delay_ints)
            inc (hl)
            ld de, (ctc_step)
            ld hl, (ret_acc)        ; the PC's retraces, 60 a second
            add hl, de
            ld bc, RETRACE_COUNTS
            or a
            sbc hl, bc
            jp nc, ci_retrace
            add hl, bc
            ld (ret_acc), hl
            jp ci_bios
ci_retrace:
            ld (ret_acc), hl
            ld hl, retraces
            inc (hl)
            call key_latch
ci_bios:
            ld hl, (tick_acc)       ; the BIOS clock
            add hl, de
            ld (tick_acc), hl
            jp nc, ci_music
            ld hl, (bios_ticks)
            inc hl
            ld (bios_ticks), hl
            ld a, h
            or l
            jp nz, ci_tick
            ld hl, bios_hi
            inc (hl)
ci_tick:
            call tick_player
ci_music:
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

; 60 times a second (the interrupt's retraces): the keys down in each of the
; keyboard's 8 rows, kept until the game next reads the keys (scan_keys), as
; the PC's keyboard buffer keeps a key pressed and let go between its reads
key_latch:
            ld hl, key_seen
            ld bc, $FEFE
kl_row:
            in a, (c)
            cpl
            or (hl)
            ld (hl), a
            inc hl
            rlc b
            jp c, kl_row
            ret

; anything else (none is enabled): acknowledge all
other_isr:
            nextreg $C8, $FF
            nextreg $C9, $FF
            nextreg $CA, $FF
            ei
            reti

; ------------------------------------------------------------------ the speaker tune's timing (sound.c)

; the int 1Ch handler for the game's tune (AB 968A, sound.c tick_player)
tick_player:
            ld a, (spk_tune)
            or a
            ret z
            ld hl, (spk_flags)
            bit 7, h
            jp nz, tp_run
            set 0, l                ; stopped: flags bit 0 (ended)
            ld (spk_flags), hl
            ret
tp_run:
            ld hl, (spk_ticks)
            dec hl
            ld (spk_ticks), hl
            bit 7, h
            jp nz, tp_next          ; below 0
            ld a, h
            or l
            ret nz                  ; still above 0
tp_next:
            ld hl, (spk_index)
            inc hl                  ; the next note
            ld ix, (spk_notes)      ; IX: the tune's note count, then its notes from index 1
            ld e, (ix + 0)
            ld d, (ix + 1)
            ex de, hl               ; past the last? (count < index)
            or a
            sbc hl, de
            ex de, hl
            jp nc, tp_have
            ld a, (spk_flags + 1)
            bit 6, a
            jp nz, tp_again
            ld hl, 1                ; not looping: flags = 1, the tune has ended
            ld (spk_flags), hl
            ret
tp_again:
            ld hl, 1                ; looping: the first note again
tp_have:
            ld (spk_index), hl
            ex de, hl
            ld ix, (spk_notes)
            add ix, de              ; the note's length: the byte at notes + 2 + index
            ld e, (ix + 2)
            ld d, 0
            ld (spk_ticks), de
            ld hl, spk_flags
            res 0, (hl)
            ret

; A = tune (97h-9Eh, or 0), HL = flags (sound.c snd_play_tune): the game's
; tune for its timing, and the Tandy music for it (TANDY_SONG)
play_tune:
            di
            ld (spk_tune), a
            ld (spk_flags), hl
            ld hl, 0
            ld (spk_index), hl
            ld (spk_ticks), hl
            or a
            jp z, pt_quiet
            sub $97
            and 7
            ld e, a
            add a, a
            ld l, a
            ld h, 0
            ld bc, speaker
            add hl, bc
            ld c, (hl)              ; the tune's notes: speaker + its offset
            inc hl
            ld b, (hl)
            ld hl, speaker
            add hl, bc
            ld (spk_notes), hl
            ld a, (spk_flags + 1)
            bit 7, a
            jp z, pt_quiet          ; not playing: no music
            bit 5, a
            jp nz, pt_quiet         ; 2000h: stop the music
            ld d, 0                 ; the Tandy song
            ld hl, key_songs
            add hl, de
            ld a, (hl)
            ld hl, drv_playing      ; already playing that song: it goes on
            ld c, a
            ld a, (hl)
            or a
            jp z, pt_start
            ld a, (drv_song)
            cp c
            jp z, pt_done
pt_start:
            ld a, c
            call drv_start
            ld hl, 0
            ld (ctc_acc), hl
            jp pt_done
pt_quiet:
            call drv_stop
pt_done:
            ei
            ret

; 958E: wait for the game's tune to end (its loop flag off first). The Next's
; own: when the Tandy music is heard (flags 8000h without 2000h), its end ends
; the wait too. The opening's (97h) ends about 15 s before the speaker's
; timing, which the original (and the Mac remake) go on waiting for in silence.
wait_tune:
            di
            ld hl, spk_flags + 1
            res 6, (hl)
            ei
wt_loop:
            call get_key
            ld a, (spk_flags)
            bit 0, a
            ret nz
            ld a, (spk_flags + 1)
            and $A0
            cp $80
            jp nz, wt_loop
            ld a, (drv_playing)
            or a
            jp nz, wt_loop
            ret

; 95BE: A = 1 while the game's tune plays (C = n: 0 for any; else 0 once its note index reaches n)
tune_playing:
            push bc
            call get_key
            pop bc
            ld a, c
            or a
            jp z, tpl_flags
            ld hl, (spk_index)
            ld a, h
            or a
            jp nz, tpl_no
            ld a, l
            cp c
            jp nc, tpl_no
tpl_flags:
            ld a, (spk_flags)
            and 1
            xor 1
            ret
tpl_no:
            xor a
            ret

; ------------------------------------------------------------------ the keys

; the keys the game can have, in the order they are given: the scan code,
; the half-row (the port's high byte), the bit, and whether Caps Shift must be
; held (1), must not be (0), or doesn't matter (2)
KEYS        EQU 16              ; (a bit each in a word)
KEYBIT_S    EQU $04             ; S's bit
key_table:
            db KEY_ENTER, $BF, $01, 2
            db KEY_SPACE, $7F, $01, 0
            db KEY_S,     $FD, $02, 2
            db $4B,       $F7, $10, 1           ; Caps + 5: left
            db $50,       $EF, $10, 1           ; Caps + 6: down
            db $48,       $EF, $08, 1           ; Caps + 7: up
            db $4D,       $EF, $04, 1           ; Caps + 8: right
            db $47,       $EF, $08, 0           ; 7 8 9 / 4 5 6 / 1 2 3: the keypad
            db $48,       $EF, $04, 0
            db $49,       $EF, $02, 0
            db $4B,       $F7, $08, 0
            db $4C,       $F7, $10, 0
            db $4D,       $EF, $10, 0
            db $4F,       $F7, $01, 0
            db $50,       $F7, $02, 0
            db $51,       $F7, $04, 0

; HL = a bit for each key of key_table held now
scan_keys:
            ld bc, $FEFE            ; Caps Shift: row FEh, bit 0
            in a, (c)
            cpl
            ld e, a
            and $10                 ; V (bit 4), as it goes down: the picture stretched or not
            ld hl, sk_v
            cp (hl)
            ld (hl), a
            jp z, sk_no_v
            or a
            push de
            call nz, stretch_toggle
            pop de
sk_no_v:
            ld hl, key_seen         ; each row: the keys down now, or at a retrace since the last read
            ld de, sk_rows
            ld bc, $FEFE
            di
sk_row:
            in a, (c)
            cpl
            or (hl)
            ld (de), a
            ld (hl), 0
            inc hl
            inc de
            rlc b
            jp c, sk_row
            ei
            ld a, (sk_rows)
            and 1
            ld (sk_caps), a
            ld ix, key_table
            ld hl, 0
            ld de, 1                ; the key's bit
            ld a, KEYS
sk_key:
            push af
            push hl
            ld a, (ix + 1)          ; its row's entry: the place of the 0 in the port's high byte
            ld hl, sk_rows
sk_find:
            rrca
            jp nc, sk_found
            inc hl
            jp sk_find
sk_found:
            ld a, (hl)
            pop hl
            and (ix + 2)
            jp z, sk_next           ; not held
            ld a, (ix + 3)
            cp 2
            jp z, sk_held
            ld c, a
            ld a, (sk_caps)
            cp c
            jp nz, sk_next          ; Caps Shift isn't as this key needs
sk_held:
            ld a, l
            or e
            ld l, a
            ld a, h
            or d
            ld h, a
sk_next:
            sla e
            rl d
            ld bc, 4
            add ix, bc
            pop af
            dec a
            jp nz, sk_key
            ret

; 7F8C: a key pressed since last time (its scan code), else 0. Each key counts
; once when it goes down; several at once wait their turn. Held, they repeat as
; the PC's keyboard did: after about half a second, then 9 times a second.
; (7F5E get_key: the same; its keypad + and F1, Enter, the Next has neither.)
REPEAT_DELAY EQU 9                  ; BIOS ticks (18.2 a second)
REPEAT_RATE  EQU 2
get_key:
bios_key:
            call sys_check
            call scan_keys
            ld de, (keys_held)      ; the new ones: held now, not before
            ld (keys_held), hl
            ld a, h                 ; the same keys held as before (some): repeat them when due
            or l
            jp z, bk_rep_from
            push hl
            or a
            sbc hl, de
            jp nz, bk_rep_new
            ld hl, (bios_ticks)
            ld bc, (key_rep_at)
            or a
            sbc hl, bc
            jp m, bk_rep_not
            ld hl, (bios_ticks)
            ld bc, REPEAT_RATE
            add hl, bc
            ld (key_rep_at), hl
            ld de, 0                ; due: all held count as new
bk_rep_not:
            pop hl
            jp bk_new
bk_rep_new:
            pop hl
bk_rep_from:
            push hl                 ; changed: the first repeat after the delay
            ld hl, (bios_ticks)
            ld bc, REPEAT_DELAY
            add hl, bc
            ld (key_rep_at), hl
            pop hl
bk_new:
            ld a, e
            cpl
            and l
            ld e, a
            ld a, d
            cpl
            and h
            ld d, a
            ld hl, (keys_waiting)
            ld a, l
            or e
            ld l, a
            ld a, h
            or d
            ld h, a
            ld a, h
            or l
            jp z, bk_none
            ld ix, key_table        ; the first waiting
            ld de, 1
bk_find:
            ld a, l
            and e
            jp nz, bk_got
            ld a, h
            and d
            jp nz, bk_got
            sla e
            rl d
            ld bc, 4
            add ix, bc
            jp bk_find
bk_got:
            ld a, e                 ; no longer waiting
            cpl
            and l
            ld l, a
            ld a, d
            cpl
            and h
            ld h, a
            ld (keys_waiting), hl
            ld a, (ix + 0)
            ret
bk_none:
            ld (keys_waiting), hl
            jp key_none

; no key: A = 0 (the test's model can press Enter after a while, or give a key
; here as this read's: then as idle)
key_none:
            xor a
            jp idle

; 7F5E: keypad + and F1 are Enter (the Next has neither); 7F2A; 7FA7

wait_key:
            call bios_key
            or a
            ret nz
            call key_wait
            jp wait_key

; waiting for a key (the test's model can press Enter here, after a while)
key_wait:
            ret

flush_keys:
            call get_key
            or a
            jp nz, flush_keys
            ret

; the program waits here: nothing more to do until the next interrupt (the
; test's model jumps to it at once)
idle:
            ret

; ------------------------------------------------------------------ waits

; 7EF2: A = HL ticks or a key's scan code (the last read), reading keys meanwhile.
; Its first comparison is with a value the count never has: the first change
; counts at once.
wait_ticks:
            ld (wt_n), hl
            ld hl, (bios_ticks)
            inc hl
            ld (wt_last), hl
            xor a
            ld (wt_key), a
wti_loop:
            ld hl, (wt_n)
            ld a, h
            or l
            jp z, wti_done
            call get_key
            ld (wt_key), a
            ld hl, (bios_ticks)
            ld de, (wt_last)
            or a
            sbc hl, de
            jp z, wti_loop
            add hl, de
            ld (wt_last), hl
            ld hl, (wt_n)
            dec hl
            ld (wt_n), hl
            jp wti_loop
wti_done:
            ld a, (wt_key)
            ret

; 9CAF: HL ticks, keys left alone
delay_ticks:
            ld (wt_n), hl
            ld hl, (bios_ticks)
            inc hl
            ld (wt_last), hl
dt_loop:
            ld hl, (wt_n)
            ld a, h
            or l
            ret z
            call sys_check
            ld hl, (bios_ticks)
            ld de, (wt_last)
            or a
            sbc hl, de
            jp z, dt_wait
            add hl, de
            ld (wt_last), hl
            ld hl, (wt_n)
            dec hl
            ld (wt_n), hl
            jp dt_loop
dt_wait:
            call idle
            jp dt_loop

; A interrupts (about 0.585 ms each)
delay_ints:
            ld hl, ctc_count
            add a, (hl)
            ld c, a
di_wait:
            call idle
            ld a, (ctc_count)
            cp c
            jp nz, di_wait
            ret

; 9CE3: the next vertical retrace (of the PC's display: 60 a second, counted
; by the interrupt)
RETRACE_COUNTS EQU 19886        ; 1193182 / 60
retrace:
            call sys_check
            ld a, (retraces)
            ld c, a
rt_wait:
            call idle
            ld a, (retraces)
            cp c
            jp z, rt_wait
            ret

; A = the raster line's low byte (NextReg 1Fh; interrupts off between the port's
; select and read, as the interrupt routine uses the Next registers too)
raster:
            ld bc, REG_SELECT
            ld a, $1F
            di
            out (c), a
            inc b
            in a, (c)
            ei
            ret

; ------------------------------------------------------------------ skipping (the remake's own: S)

; HL = where to go on S, SP as it is in the caller's caller (the routine that armed it)
skip_arm:
            ld (skip_to), hl
            ld hl, 2
            add hl, sp
            ld (skip_sp), hl
            ld a, 1
            ld (skip_armed), a
            ret

skip_disarm:
            xor a
            ld (skip_armed), a
            ret

; S held while armed: off to where skip_arm said, the routines between left behind
sys_check:
            ld a, (skip_armed)
            or a
            ret z
            ld bc, $FDFE            ; S: row FDh, bit 1
            in a, (c)
            and $02
            ret nz
            xor a
            ld (skip_armed), a
            ld hl, (keys_held)      ; S counts as seen: not read again as a key
            ld a, l
            or KEYBIT_S
            ld l, a
            ld (keys_held), hl
            ld hl, (skip_sp)
            ld sp, hl
            ld hl, (skip_to)
            ei
            jp (hl)

; ------------------------------------------------------------------ files

; esxDOS (RST 08h) needs the 48K BASIC ROM at 0000h (slots 0 and 1 are), and the
; standard memory for its own use: slots 2-4 as at the start (banks 5 and 2)
files_on:
            ld a, $FF               ; (the ROM; spr_map's note of slot 0 kept true)
            ld (spr_page), a
            nextreg $50, a
            nextreg $51, a
            nextreg $52, 10
            nextreg $53, 11
            nextreg $54, 4
            ret

files_off:
            ld a, (ovl_cur)         ; (flags kept)
            nextreg $51, a
            nextreg $52, DS_PAGE
            nextreg $53, DS_PAGE + 1
            nextreg $54, DS_PAGE + 2
            ret

; A = picture 0-19: DOTC_GFX/C?.PIC into its place in the cache (pic_page: its
; first page; the picture's 160 column pairs, 40 to a page, and its 16 palette
; registers at 1F40h in the last page). Carry set if it couldn't be read (red
; border).
load_picture:
            ld (lp_pic), a
            add a, 'A'
            ld (pic_name + 10), a   ; the second letter of the name
            ld a, (lp_pic)
            ld l, a
            ld h, 0
            ld de, pic_page
            add hl, de
            ld a, (hl)
            ld ix, pic_name
            ld b, 4
            ; (on into load_file)

; the file named at IX (from the current folder) into B pages from page A,
; 8K each through slot 7 (the last may be short); carry if it can't be read
; (and a red border). Interrupts are off meanwhile; they are on after.
load_file:
            ld (lp_pg), a
            di
            call files_on
            push bc
            ld a, '*'               ; the current drive; the name relative to the current folder
            ld b, $01               ; read, the file must exist
            rst $08
            db F_OPEN
            pop bc
            jp c, lp_failed
            ld (pic_handle), a
lp_page:
            push bc
            ld a, (lp_pg)
            nextreg $57, a          ; slot 7 (E000h) onto the page
            ld a, (pic_handle)
            ld ix, WINDOW
            ld bc, $2000
            rst $08
            db F_READ
            pop de
            jp c, lp_close
            ld hl, lp_pg
            inc (hl)
            ld b, d
            djnz lp_page
            ld a, (pic_handle)
            rst $08
            db F_CLOSE
            call files_off
            ld a, (win_page)        ; the window as it was
            nextreg $57, a
            ei
            or a
            ret
lp_close:
            ld a, (pic_handle)
            rst $08
            db F_CLOSE
lp_failed:
            call files_off
            ld a, (win_page)
            nextreg $57, a
            ld a, 2                 ; red border
            out ($FE), a
            ei
            scf
            ret

; The scenes' sprite files, read from the card when a scene needs them, into
; the pages the opening's pictures leave once the game has begun (SCENE_PAGE
; on): A = 0 the siege's (Be), 1 the tournament's (BX), 2 the lane's (BY).
; Each is kept until another (or the saved back page, save_back) takes its
; pages. Carry if it can't be read.
load_sprites:
            ld (ls_id), a
            ld l, a                 ; its entry (6 bytes): the bit, the pages it takes from others,
            add a, a                ; its first page, how many, its name
            add a, l
            add a, a
            ld l, a
            ld h, 0
            ld de, scene_files
            add hl, de
            push hl
            pop iy
            ld a, (scene_has)
            and (iy + 0)
            ret nz                  ; (no carry)
            ld a, (iy + 1)
            cpl
            ld hl, scene_has
            and (hl)
            ld (hl), a
            ld l, (iy + 4)
            ld h, (iy + 5)
            push hl
            pop ix
            ld a, (iy + 2)
            ld b, (iy + 3)
            push iy
            call load_file
            pop iy
            ret c
            ld a, (scene_has)
            or (iy + 0)
            ld (scene_has), a
            ret
scene_files:                        ; (the bits of those whose pages it takes)
            db 1, $3A, SCENE_PAGE, 3        ; 0 the siege: pages 60-62
            dw sn_siege
            db 2, $39, SCENE_PAGE, 7        ; 1 the tournament: 60-66
            dw sn_tourn
            db 4, $18, SCENE_PAGE + 7, 12   ; 2 the lane: 67-78
            dw sn_lane
            db 8, $37, SCENE_PAGE, 17       ; 3 the ladies: 60-76
            dw sn_ladies
            db 16, $2F, SCENE_PAGE, 12      ; 4 the romance: 60-71
            dw sn_romance
            db 32, $1B, SCENE_PAGE, 5       ; 5 the window: 60-64
            dw sn_window
sn_siege:   db "DOTC_GFX/SIEGE.SPR", 0
sn_tourn:   db "DOTC_GFX/TOURN.SPR", 0
sn_lane:    db "DOTC_GFX/LANE.SPR", 0
sn_ladies:  db "DOTC_GFX/LADIES.SPR", 0
sn_romance: db "DOTC_GFX/ROMANCE.SPR", 0
sn_window:  db "DOTC_GFX/WINDOW.SPR", 0
