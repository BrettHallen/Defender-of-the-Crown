; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; tandy.asm: the booter's Tandy 1000 music driver (AC 7444-7C53), ported
; from the Mac remake's C (Remake/src/sound.c) to the Z80, playing the
; original music data (BG from GAME.DAT, in pages BG_PAGE on) on the Next's first AY.
;
; The Tandy's SN76496 writes become AY writes as they happen: a voice's tone
; register (n & 3FFh) through ay_period_tab, its attenuation through
; ay_vol_tab (both made by tools/convert.py). The fourth (noise) voice is
; driven as in the original but not heard: the music doesn't use it, and the
; Mac remake doesn't play it either.
;
;   drv_start      A = song 0-7: start it (the original's 7444)
;   drv_stop       silence, stop (7C53)
;   drv_interrupt  one of the driver's timer interrupts (75F4); called
;                  1193182 / drv_tempo times a second
;   drv_playing    non-zero while a song plays
;
; Every routine here may change AF, BC, DE, HL and IX.

V_PTR       EQU 0               ; word: the voice's next event in BG
V_DUR       EQU 2               ; word: ticks left of the current event
V_STATE     EQU 4               ; 1 attack, 2 decay, 3 sustain, 4 release, 5 off
V_ACTIVE    EQU 5
V_VOL       EQU 6               ; word: the attenuation being worked on
V_REL       EQU 8               ; word: release countdown
V_TONE      EQU 10              ; word
V_VIB       EQU 12              ; word: vibrato countdown
V_VSUB      EQU 14
V_VPH       EQU 15
V_INST      EQU 16              ; 6 words: attack, decay, sustain, release step, release interval, vibrato delay
V_NUM       EQU 28              ; the voice's number, 0-3
V_SIZE      EQU 32

; ------------------------------------------------------------------ BG access

; HL = the word at BG offset HL (BC, DE kept). BG is in its own pages
; (BG_PAGE on); each byte is read through slot 1 (2000h-3FFFh), which is the
; ROM again afterwards: only this driver uses it (and esxDOS, with interrupts off).
bgw:
            push de
            call bg_byte
            ld e, a
            inc hl
            call bg_byte
            ld d, a
            ex de, hl
            nextreg $51, $FF
            pop de
            ret

; A = the byte at BG offset HL (HL kept)
bg_byte:
            push hl
            ld a, h
            rlca
            rlca
            rlca
            and 7
            add a, BG_PAGE
            nextreg $51, a
            ld a, h
            and $1F
            or $20
            ld h, a
            ld a, (hl)
            pop hl
            ret

; ------------------------------------------------------------------ the chip

; voice IX's attenuation = A (0-15): its AY volume
sn_volume:
            ld c, a
            ld a, (ix + V_NUM)
            cp 3
            ret nc                  ; the noise voice
            add a, 8
            ld e, a
            ld b, 0
            ld hl, ay_vol_tab
            add hl, bc
            ld a, (hl)
            jp ay_set

; voice IX's tone register = HL (the original's 7820: n & 3FFh reaches the chip)
sn_tone:
            ld a, (ix + V_NUM)
            cp 3
            ret nc                  ; the noise voice's control
            add a, a
            ld e, a                 ; AY registers 2v, 2v + 1
            ld a, h
            and $03
            ld h, a
            add hl, hl
            ld bc, ay_period_tab
            add hl, bc
            ld a, (hl)
            call ay_set
            inc hl
            ld a, (hl)
            inc e
            jp ay_set

; ------------------------------------------------------------------ start and stop

; 7C78: every voice's attenuation to 15 (off), its envelope off, inactive
drv_silence:
            ld ix, voices
            ld b, 4
sil_voice:
            push bc
            ld a, 15
            call sn_volume
            ld (ix + V_STATE), 5
            ld (ix + V_ACTIVE), 0
            ld de, V_SIZE
            add ix, de
            pop bc
            djnz sil_voice
            ret

drv_stop:
            call drv_silence
            xor a
            ld (drv_playing), a
            ret

; 7444: A = song
drv_start:
            ld (drv_song), a
            ld hl, $FFFF            ; no loop point yet
            ld (drv_loop_at), hl
            add a, a
            ld l, a
            ld h, 0
            call bgw                ; the song's header
            ; fall through

; 747A / 74BA: the song whose header is at BG offset HL
drv_song_at:
            push hl
            call drv_stop
            pop hl
            ld (sa_bx), hl
            call bgw
            ld a, h
            and l
            inc a
            ret z                   ; FFFFh: no song
            ld a, h
            inc a
            jp nz, sa_noloop
            ld a, l
            cp $FE
            jp nz, sa_noloop
            ld hl, (sa_bx)          ; FFFEh: the song loops back to here
            ld (drv_loop_at), hl
            inc hl
            inc hl
            ld (sa_bx), hl
sa_noloop:
            ld hl, (sa_bx)
            call bgw
            ld (drv_tempo), hl
            ld hl, (sa_bx)
            inc hl
            inc hl
            ld (sa_vp), hl          ; the four voices' pointers follow
            ld ix, voices
            ld b, 4
sa_voice:
            push bc
            ld hl, (sa_vp)
            call bgw
            ld (sa_p), hl           ; p
            call bgw
            ld a, h
            or l
            jp nz, sa_inst
            ld (ix + V_ACTIVE), 0   ; w(p) = 0: the voice is silent in this song
            jp sa_rest
sa_inst:
            push ix                 ; the instrument: six words at p
            pop de
            ld hl, V_INST
            add hl, de
            ex de, hl               ; DE: where they go
            ld hl, (sa_p)
            ld (sa_q), hl
            ld b, 6
sa_word:
            ld hl, (sa_q)
            call bgw
            ex de, hl
            ld (hl), e
            inc hl
            ld (hl), d
            inc hl
            ex de, hl
            ld hl, (sa_q)
            inc hl
            inc hl
            ld (sa_q), hl
            djnz sa_word
            ld (ix + V_ACTIVE), 1
            ld hl, (sa_p)
            ld de, 12
            add hl, de
            ld (sa_p), hl           ; the notes follow
sa_rest:
            ld hl, (sa_p)
            ld (ix + V_PTR), l
            ld (ix + V_PTR + 1), h
            ld (ix + V_DUR), 1
            ld (ix + V_DUR + 1), 0
            ld (ix + V_VOL), 15
            xor a
            ld (ix + V_VOL + 1), a
            ld (ix + V_REL), a
            ld (ix + V_REL + 1), a
            ld (ix + V_TONE), a
            ld (ix + V_TONE + 1), a
            ld (ix + V_VIB), a
            ld (ix + V_VIB + 1), a
            ld (ix + V_VSUB), a
            ld (ix + V_VPH), a
            ld hl, (sa_vp)
            inc hl
            inc hl
            ld (sa_vp), hl
            ld de, V_SIZE
            add ix, de
            pop bc
            dec b
            jp nz, sa_voice
            ld a, 1
            ld (drv_subtick), a
            ld (drv_playing), a
            ret

; ------------------------------------------------------------------ the notes

; voice IX's next event (A = 0: a note or a rest; 1: the song went back to
; its loop point; 2: the song ended)
next_event:
            ld l, (ix + V_PTR)
            ld h, (ix + V_PTR + 1)
            ld (ne_bx), hl
            call bgw                ; the duration
            ld (ix + V_DUR), l
            ld (ix + V_DUR + 1), h
            ld a, h
            and l
            inc a
            jp nz, ne_note
            ld hl, (ne_bx)          ; FFFFh: the end of the voice's part
            inc hl
            inc hl
            call bgw
            ld c, 0                 ; C = 1 if FFFEh follows
            ld a, h
            inc a
            jp nz, ne_flag
            ld a, l
            cp $FE
            jp nz, ne_flag
            inc c
ne_flag:
            ld a, (ix + V_NUM)
            cp 2
            jp c, ne_test
            ld a, c                 ; voices 2 and 3 test the other way round
            xor 1
            ld c, a
ne_test:
            ld a, c
            or a
            jp z, ne_end
            ld hl, (drv_loop_at)
            ld a, h
            and l
            inc a
            jp z, ne_end            ; no loop point
            call drv_song_at
            ld a, 1
            ret
ne_end:
            call drv_stop
            ld a, 2
            ret
ne_note:
            ld hl, (ne_bx)
            inc hl
            inc hl
            ld (ne_bx), hl
            call bgw                ; the note
            ld (ne_n), hl
            ld a, h
            inc a
            jp nz, ne_tone
            ld a, l
            cp $FA
            jp nz, ne_tone
            ld (ix + V_INST + 10), $FF      ; FFFAh: no more vibrato for this voice
            ld (ix + V_INST + 11), $FF
            ld hl, (ne_bx)
            inc hl
            inc hl
            ld (ne_bx), hl
            ld hl, (ne_n)           ; (the original goes on with FFFAh as the note)
ne_tone:
            ld a, h
            or l
            jp nz, ne_play
            ld (ix + V_STATE), 4    ; 0: a rest, the note's release
            jp ne_done
ne_play:
            ld (ix + V_TONE), l
            ld (ix + V_TONE + 1), h
            call sn_tone
            ld (ix + V_STATE), 1    ; the attack
            ld a, (ix + V_INST + 10)
            ld (ix + V_VIB), a
            ld a, (ix + V_INST + 11)
            ld (ix + V_VIB + 1), a
            ld (ix + V_VPH), 0
ne_done:
            ld hl, (ne_bx)
            inc hl
            inc hl
            ld (ix + V_PTR), l
            ld (ix + V_PTR + 1), h
            xor a
            ret

; 7A83: voice IX's vibrato
vibrato:
            ld l, (ix + V_VIB)
            ld h, (ix + V_VIB + 1)
            dec hl
            ld (ix + V_VIB), l
            ld (ix + V_VIB + 1), h
            ld a, h
            or l
            jp z, vb_go
            bit 7, h
            ret z                   ; still counting down
vb_go:
            inc hl
            ld (ix + V_VIB), l
            ld (ix + V_VIB + 1), h
            ld a, (ix + V_VSUB)
            cp 2
            jp z, vb_step
            inc (ix + V_VSUB)
            ret
vb_step:
            ld (ix + V_VSUB), 0
            inc (ix + V_VPH)
            ld l, (ix + V_TONE)
            ld h, (ix + V_TONE + 1)
            ld a, (ix + V_VPH)
            cp 3
            jp nc, vb_down
            inc hl                  ; phases 1, 2: up
            jp vb_set
vb_down:
            cp 4
            jp nz, vb_dec
            ld (ix + V_VPH), 0
vb_dec:
            dec hl                  ; phases 3, 4: down
vb_set:
            ld (ix + V_TONE), l
            ld (ix + V_TONE + 1), h
            jp sn_tone

; 7A6F: A = HL (signed) kept to 0-15
clamp15:
            bit 7, h
            jp nz, cl_zero
            ld a, h
            or a
            jp nz, cl_15
            ld a, l
            cp 16
            ret c
cl_15:
            ld a, 15
            ret
cl_zero:
            xor a
            ret

; ------------------------------------------------------------------ the interrupt (75F4)

drv_interrupt:
            ld a, (drv_playing)
            or a
            ret z
            ld hl, drv_subtick
            dec (hl)
            jp nz, drv_envelopes
            ld (hl), 4              ; every fourth interrupt: the notes
            ld ix, voices
            ld b, 4
di_voice:
            push bc
            ld a, (drv_playing)
            or a
            jp z, di_out            ; the song ended
            ld a, (ix + V_ACTIVE)
            or a
            jp z, di_next
            ld l, (ix + V_DUR)
            ld h, (ix + V_DUR + 1)
            dec hl
            ld (ix + V_DUR), l
            ld (ix + V_DUR + 1), h
            ld a, h
            or l
            jp nz, di_vibrato
            call next_event
            cp 1
            jp z, di_out            ; back to the loop point: nothing more this time
            jp di_next
di_vibrato:
            ld a, (ix + V_INST + 10)
            and (ix + V_INST + 11)
            inc a
            jp z, di_next           ; FFFFh: no vibrato
            call vibrato
di_next:
            ld de, V_SIZE
            add ix, de
            pop bc
            dec b
            jp nz, di_voice
            ret
di_out:
            pop bc
            ret

; 7870: the other three interrupts in four, the envelopes. (Only active
; voices leave state 5, and those always have an instrument, so the
; original's zeros for a voice without one are never needed.)
drv_envelopes:
            ld ix, voices
            ld b, 4
en_voice:
            push bc
            ld a, (ix + V_STATE)
            cp 3
            jp z, en_next
            cp 5
            jp z, en_next
            cp 1
            jp nz, en_decay
            ld l, (ix + V_VOL)      ; 1, the attack: vol - attack, to 0 (loudest)
            ld h, (ix + V_VOL + 1)
            ld e, (ix + V_INST)
            ld d, (ix + V_INST + 1)
            or a
            sbc hl, de
            call clamp15
            ld (ix + V_VOL), a
            ld (ix + V_VOL + 1), 0
            or a
            jp nz, en_out
            ld (ix + V_STATE), 2
            jp en_out
en_decay:
            cp 2
            jp nz, en_release
            ld l, (ix + V_VOL)      ; 2, the decay: vol + decay, to the sustain level
            ld h, (ix + V_VOL + 1)
            ld e, (ix + V_INST + 2)
            ld d, (ix + V_INST + 3)
            add hl, de
            ld (ix + V_VOL), l
            ld (ix + V_VOL + 1), h
            call clamp15
            ld c, a
            ld a, (ix + V_INST + 5)
            or a
            jp nz, en_below         ; sustain > 255
            ld a, c
            cp (ix + V_INST + 4)
            jp c, en_below
            ld a, (ix + V_INST + 4) ; reached: hold at the sustain level
            ld (ix + V_VOL), a
            ld (ix + V_VOL + 1), 0
            ld (ix + V_STATE), 3
            jp en_out
en_below:
            ld a, c
            jp en_out
en_release:
            ld l, (ix + V_REL)      ; 4, the release: a step every interval
            ld h, (ix + V_REL + 1)
            ld a, h                 ; (the original: if (--rel > 0) wait, so a step when rel was 0 or 1)
            or a
            jp nz, en_wait
            ld a, l
            cp 2
            jp c, en_step
en_wait:
            dec hl
            ld (ix + V_REL), l
            ld (ix + V_REL + 1), h
            jp en_next
en_step:
            ld a, (ix + V_INST + 8)
            ld (ix + V_REL), a
            ld a, (ix + V_INST + 9)
            ld (ix + V_REL + 1), a
            ld l, (ix + V_VOL)
            ld h, (ix + V_VOL + 1)
            ld e, (ix + V_INST + 6)
            ld d, (ix + V_INST + 7)
            add hl, de
            ld (ix + V_VOL), l
            ld (ix + V_VOL + 1), h
            call clamp15
            cp 15
            jp c, en_out
            ld (ix + V_STATE), 5    ; faded out
            ld a, 15
en_out:
            call sn_volume
en_next:
            ld de, V_SIZE
            add ix, de
            pop bc
            dec b
            jp nz, en_voice
            ret

; ------------------------------------------------------------------ the driver's state

drv_playing: db 0
drv_song:    db 0               ; the song started last
drv_subtick: db 0
drv_tempo:   dw 0               ; PIT counts (1193182 Hz) between interrupts
drv_loop_at: dw $FFFF
sa_bx:       dw 0
sa_vp:       dw 0
sa_p:        dw 0
sa_q:        dw 0
ne_bx:       dw 0
ne_n:        dw 0
voices:      db 0,0,0,0,0,5,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
             db 0,0,0,0,0,5,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0
             db 0,0,0,0,0,5,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0
             db 0,0,0,0,0,5,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0
