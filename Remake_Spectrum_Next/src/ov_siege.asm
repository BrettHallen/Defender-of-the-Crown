; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; ov_siege.asm: an overlay (see ov_setup.asm): the player's siege, its
; bombardment, as the Mac remake's war.c ports it: the ammunition (7505), the
; catapult (7168), the shot's flight (739D), up to 6 days of it (763E). The
; battle that follows is ov_war's.
;
; The siege's sprites (Be: the catapult, its loads, the shots, the holes in
; the wall) are read from the card (load_sprites). The catapult and its shots
; are put at x 39 (the shot 41) in 4-pixel units, the Tandy program's one
; unit to the left (AC 62D1): 152 and 160 pixels.

#include "defs.asm"
#include "../build/main_syms.asm"

D_SIEGE_BOULDERS EQU $0A82
D_SIEGE_AMMO     EQU $0A84      ; the ammunition chosen last (the menu starts on it)
D_SIEGE_DISEASE  EQU $0A86
D_SIEGE_DAYS     EQU $0A88
D_SIEGE_WALL     EQU $0A8A      ; the wall's height (6 at first)
D_SIEGE_FIRE     EQU $0A8C
D_SIEGE_HOLE     EQU $0A8E      ; the Be item of the hole in the wall (3-7)
D_SIEGE_SHOWN    EQU $003F
D_PULL           EQU 2          ; the remake's g_catapult_pull: screens a step of the arm is held
PIC_SIEGE1       EQU 15
PIC_SIEGE2       EQU 16
CAT_X            EQU 39 * 4 - 4 ; the catapult's slot (pixels)

            org $2000
            jp o_bombard            ; 2000h: the bombardment of territory A -> A: the castle's protection

; ------------------------------------------------------------------ the ammunition (7505)

; A = 1 Greek Fire, 2 Disease, 3 Boulders (while there are any), 4 Cease Fire
choose_ammo:
            ld a, (sg_t)            ; no soldiers in the garrison: 1
            call garrison_ofs
            ld (sg_g), hl
            ld c, A_SOLDIERS
            call sg_w
            dec hl
            bit 7, h
            jp z, ca_menu
            ld de, 1
            ld hl, (sg_g)
            ld c, A_SOLDIERS
            call sg_sw
ca_menu:
            ld hl, $41D4            ; the days left, the garrison, the loads
            ld de, $3692
            call line_str
            ex de, hl
            ld hl, (DSEG + D_SIEGE_DAYS)
            call num_append
            ld hl, (sg_g)
            ld c, A_SOLDIERS
            call sg_w
            push hl
            ld hl, (sg_g)
            ld c, A_KNIGHTS
            call sg_w
            pop de
            add hl, de
            push hl
            ld hl, $41EE
            ld de, $3694
            call line_str
            ex de, hl
            pop hl
            call num_append
            ld hl, $41FF
            ld de, $3698
            call line_str
            ex de, hl
            ld hl, (DSEG + D_SIEGE_FIRE)
            call num_append
            ld hl, $4212
            ld de, $369A
            call line_str
            ex de, hl
            ld hl, (DSEG + D_SIEGE_DISEASE)
            call num_append
            ld hl, $4225
            ld de, $369C
            call line_str
            ex de, hl
            ld hl, (DSEG + D_SIEGE_BOULDERS)
            call num_append
            ld a, (DSEG + D_SIEGE_AMMO)
            add a, 4
            ld (DSEG + $368A), a
            ld hl, $3683
            call dialog
            ld (DSEG + D_SIEGE_AMMO), a
            xor a
            ld (DSEG + D_SIEGE_AMMO + 1), a
            ld a, (DSEG + D_SIEGE_AMMO)
            cp 4
            ret z
            ld hl, D_SIEGE_FIRE     ; one of it left?
            cp 1
            jp z, ca_left
            ld hl, D_SIEGE_DISEASE
            cp 2
            jp z, ca_left
            ld hl, D_SIEGE_BOULDERS
            cp 3
            jp nz, ca_menu
ca_left:
            push hl
            call dsw
            ld a, h
            or l
            pop de
            jp z, ca_menu
            dec hl
            ex de, hl
            call dssw
            ld a, (DSEG + D_SIEGE_AMMO)
            ret

; HL = field C of record HL; = DE
sg_w:
            ld b, 0
            add hl, bc
            jp dsw
sg_sw:
            ld b, 0
            add hl, bc
            jp dssw

; ------------------------------------------------------------------ the catapult (7168)

; Enter starts drawing the arm back, Enter again (or the arm at its furthest)
; lets go: A = the shot's height 0-7 ((tension - 140) / 2). With Greek Fire
; its flame (Be 52) is XORed at the arm each step, so it flickers. The steps
; go at the screen's pace (the original's delay_ticks(1) end at once), each
; held D_PULL screens.
catapult_aim:
            ld a, 136
            ld (cm_si), a
            call present
            call set_palette
            ld a, (sg_ammo)         ; the catapult, loaded: ammo x 14 - 4
            ld b, a
            add a, a
            add a, a
            add a, a
            sub b
            add a, a
            ld (cm_l4), a           ; ammo x 14
            sub 4
            ld b, a
            xor a
            ld hl, CAT_X
            ld a, (cm_si)
            ld e, a
            xor a
            ld c, SIEGE_PAGE
            call slot_set
            call sprites_draw
            call present
cm_wait:
            call get_key
            cp KEY_ENTER
            jp z, cm_pull
            ld a, (sg_ammo)         ; (only Greek Fire's flame is presented)
            cp 1
            jp nz, cm_wait
            call cm_flame
            call present
            jp cm_wait
cm_pull:
            ld hl, 1
            ld (DSEG + $08C7), hl
cm_step:
            call get_key
            cp KEY_ENTER
            jp z, cm_let_go
            ld hl, cm_si
            inc (hl)
            ld a, (hl)
            cp 160
            jp nc, cm_let_go
            call sprites_erase
            ld a, (cm_si)
            ld (slots + 3), a       ; slot 0's y
            call sprites_draw
            call cm_flame
            call present
            ld b, D_PULL - 1        ; held: Enter read each screen
cm_hold:
            push bc
            call get_key
            pop bc
            cp KEY_ENTER
            jp z, cm_let_go
            push bc
            call present
            pop bc
            djnz cm_hold
            jp cm_step
cm_let_go:
            ld hl, 3
            ld (DSEG + $08C7), hl
            ld a, (cm_si)           ; the height: (si - 140) / 2, 0-7
            sub 140
            ld c, 0
            jp c, cm_h
            srl a
            ld c, a
            cp 8
            jp c, cm_h
            ld c, 7
cm_h:
            ld a, c
            ld (cm_h_n), a
cm_forward:                         ; the arm goes forward
            ld a, (cm_si)
            cp 137
            jp c, cm_swing
            call sprites_erase
            ld a, (cm_si)
            sub 8
            ld (cm_si), a
            ld (slots + 3), a
            call sprites_draw
            call present
            jp cm_forward
cm_swing:
            ld hl, cm_swings        ; its swing: ammo x 14 - 3 at 132, 8 at 146, 9 at 125
            ld (cm_sw), hl
cm_swing_one:
            call sprites_erase
            ld hl, (cm_sw)          ; (the slots' routines use IX and IY)
            ld a, (hl)
            or a
            jp nz, cm_item
            ld a, (cm_l4)
            sub 3
cm_item:
            ld (slots + 5), a
            inc hl
            ld a, (hl)
            ld (slots + 3), a
            inc hl
            ld (cm_sw), hl
            ld hl, CAT_X
            ld (slots + 1), hl
            call sprites_draw
            call present
            ld hl, (cm_sw)
            ld de, cm_swings + 6
            or a
            sbc hl, de
            jp nz, cm_swing_one
            ld a, 125               ; the shot leaves the arm: ammo x 14 - 2, then - 1
            ld (cm_si), a
            ld a, (cm_l4)
            sub 2
            ld (cm_item_n), a
            ld c, 112
            call cm_leave
            ld a, (cm_l4)
            dec a
            ld (cm_item_n), a
            ld c, 100
            call cm_leave
            call sprites_erase
            xor a
            ld (slots + SLOT_SIZE), a   ; slot 1 off (the catapult, slot 0, stays)
            ld a, (cm_h_n)
            ret
cm_swings:  db 0, 132, 8, 146, 9, 125

; the shot up 3 lines a screen while above line C (slot 1 at x 41: the Tandy
; program too has it there, AC 6449)
cm_leave:
            ld a, (cm_si)
            cp c
            ret c
            ret z
            push bc
            call sprites_erase
            ld a, (cm_si)
            sub 3
            ld (cm_si), a
            ld e, a
            ld hl, 41 * 4
            ld a, (cm_item_n)
            ld b, a
            ld c, SIEGE_PAGE
            ld a, 1
            call slot_set
            call sprites_draw
            call present
            pop bc
            jp cm_leave

; Greek Fire's flame XORed at the arm (Be 52, at x 38)
cm_flame:
            ld a, (sg_ammo)
            cp 1
            ret nz
            ld hl, 38
            ld a, (cm_si)
            ld e, a
            ld a, 52
            ld c, SIEGE_PAGE
            jp xor_sprite

; ------------------------------------------------------------------ the shot's flight (739D)

; 30 frames: its height by the table DS:0992 (30 bytes for each height 0-7),
; its picture one of 10 (ammo x 14 + 0..9), the next every 3 frames. (The x
; would move on at frame 10, but the test is made only at frames 2, 5, 8,
; 11 ...: it never does.)
show_shot:
            xor a
            ld (ss_l2), a
            ld a, (cm_l4)
            ld (ss_l4), a
ss_loop:
            ld a, (ss_l2)
            cp 29
            ret nc
            call ss_y               ; slot 1 at x 41 (less the Tandy unit: 160 pixels)
            ld e, a
            ld hl, 41 * 4 - 4
            ld a, (ss_l4)
            ld b, a
            ld c, SIEGE_PAGE
            ld a, 1
            call slot_set
            call ss_frame
            call ss_y
            ld (slots + SLOT_SIZE + 3), a
            call ss_frame
            call ss_y
            ld (slots + SLOT_SIZE + 3), a
            ld hl, 41 * 4 - 4
            ld (slots + SLOT_SIZE + 1), hl
            call ss_frame
            ld hl, ss_l4
            inc (hl)
            jp ss_loop
ss_frame:
            call sprites_draw
            call present
            call sprites_erase
            ld hl, ss_l2
            inc (hl)
            ret                     ; (wait_ticks(1): at once)
; A = the shot's line at frame ss_l2
ss_y:
            ld a, (cm_h_n)
            ld l, a
            ld h, 0
            ld d, h
            ld e, l
            add hl, hl
            add hl, hl
            add hl, hl
            add hl, hl
            or a
            sbc hl, de              ; 15h
            add hl, hl              ; 30h
            ld a, (ss_l2)
            ld e, a
            add hl, de
            ld de, DSEG + $0992
            add hl, de
            ld a, (hl)
            ret

; the shot's end: slot 1 off, drawn and presented once more
ss_done:
            xor a
            ld (slots + SLOT_SIZE), a
            call sprites_draw
            call present
            jp sprites_erase

; ------------------------------------------------------------------ the siege (763E)

; Territory A besieged by the player, with a catapult. A = the castle's
; protection for the battle (90%, less 15 for each boulder that hit the wall).
o_bombard:
            ld (sg_t), a
            ld a, 90
            ld (sg_prot), a
            ld hl, $2AB7
            call dialog
            ld a, $9C
            ld hl, (DSEG + D_TUNE_LOOP)
            call play_tune
            xor a                   ; the siege's sprites (the tournament's pages)
            call load_sprites
            ld a, (sg_t)            ; a Norman's castle, or a Saxon's
            call terr_owner
            cp 4
            ld a, PIC_SIEGE2
            jp m, sg_pic
            ld a, PIC_SIEGE1
sg_pic:
            call show_picture
            call save_back
            ld hl, 1
            ld (DSEG + D_SIEGE_AMMO), hl
sg_day:
            ld hl, (DSEG + D_SIEGE_DAYS)
            ld a, h
            or l
            jp z, sg_over
            call choose_ammo
            ld (sg_ammo), a
            call restore_back
            ld a, (sg_ammo)
            cp 4
            jp c, sg_shoot
            ld hl, 1                ; Cease Fire: this the last day
            ld (DSEG + D_SIEGE_DAYS), hl
            jp sg_next
sg_shoot:
            call catapult_aim
            call show_shot
            call ss_done
            ld a, (cm_h_n)          ; a hit: a height 1-6
            or a
            jp z, sg_next
            cp 7
            jp nc, sg_next
            ld a, (sg_ammo)
            cp 1
            jp z, sg_fire
            cp 2
            jp z, sg_disease
            ld hl, (DSEG + D_SIEGE_WALL)    ; Boulders: at the wall's height, it breaks
            ld a, (cm_h_n)
            cp l
            jp nz, sg_least
            dec hl
            ld (DSEG + D_SIEGE_WALL), hl
            ld a, (sg_prot)
            sub 15
            ld (sg_prot), a
            ld hl, (DSEG + D_SIEGE_HOLE)
            inc hl
            ld a, l
            cp 8
            jp c, sg_hole
            ld l, 7
sg_hole:
            ld (DSEG + D_SIEGE_HOLE), hl
            ld a, l                 ; stamped on the picture: drawn, then left out of the erase
            ld b, a
            ld hl, CAT_X
            ld e, 75
            ld c, SIEGE_PAGE
            ld a, 1
            call slot_set
            call sprites_draw
            call present
            xor a
            ld (slots + SLOT_SIZE), a
            call sprites_erase
            xor a
            ld (slots), a
            jp sg_least
sg_fire:                            ; Greek Fire over the wall: soldiers / (random_n(25) + 6) die
            ld hl, (DSEG + D_SIEGE_WALL)
            ld a, (cm_h_n)
            cp l
            jp c, sg_least
            jp z, sg_least
            ld a, 25
            call random_n
            ld de, 6
            add hl, de
            ex de, hl
            ld hl, (sg_g)
            ld c, A_SOLDIERS
            call sg_w
            push hl
            call div16
            pop de
            ex de, hl
            or a
            sbc hl, de
            ex de, hl
            ld hl, (sg_g)
            ld c, A_SOLDIERS
            call sg_sw
            jp sg_least
sg_disease:                         ; Disease over the wall: soldiers x days / 15 die
            ld hl, (DSEG + D_SIEGE_WALL)
            ld a, (cm_h_n)
            cp l
            jp c, sg_least
            jp z, sg_least
            ld hl, (sg_g)
            ld c, A_SOLDIERS
            call sg_w
            push hl
            ld a, (DSEG + D_SIEGE_DAYS)
            call sg_mul
            ld de, 15
            call sg_sdiv
            pop de
            ex de, hl
            or a
            sbc hl, de
            ex de, hl
            ld hl, (sg_g)
            ld c, A_SOLDIERS
            call sg_sw
sg_least:
            ld hl, (sg_g)           ; at least one soldier left
            ld c, A_SOLDIERS
            call sg_w
            dec hl
            bit 7, h
            jp z, sg_next
            ld de, 1
            ld hl, (sg_g)
            ld c, A_SOLDIERS
            call sg_sw
sg_next:
            call save_back          ; the day's hole in the wall kept for the next
            ld hl, (DSEG + D_SIEGE_DAYS)
            dec hl
            ld (DSEG + D_SIEGE_DAYS), hl
            ld hl, 27
            call delay_ticks
            jp sg_day
sg_over:
            ld hl, 1                ; (the catapult's slot 0 stays, unless a boulder hit: it is
            ld (DSEG + D_SIEGE_SHOWN), hl   ; drawn over the battle's first round)
            ld a, (sg_prot)
            ret

; HL = HL x A (the low word); HL = HL / DE, signed
sg_mul:
            ld d, h
            ld e, l
            ld hl, 0
            or a
            ret z
sm_add:
            add hl, de
            dec a
            jp nz, sm_add
            ret
sg_sdiv:
            bit 7, h
            jp z, div16
            xor a
            sub l
            ld l, a
            sbc a, a
            sub h
            ld h, a
            call div16
            xor a
            sub l
            ld l, a
            sbc a, a
            sub h
            ld h, a
            ret

; ------------------------------------------------------------------ the overlay's variables

sg_t:       db 0
sg_g:       dw 0                ; the garrison's record
sg_prot:    db 0
sg_ammo:    db 0
cm_si:      db 0
cm_l4:      db 0
cm_h_n:     db 0
cm_item_n:  db 0
cm_sw:      dw 0
ss_l2:      db 0
ss_l4:      db 0
ov_siege_end:
