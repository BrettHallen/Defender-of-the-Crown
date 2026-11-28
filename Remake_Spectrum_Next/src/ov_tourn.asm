; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; ov_tourn.asm: an overlay (see ov_setup.asm): the tournament, as the Mac
; remake's tourney.c ports it: the tournament (AB 62BC, 26AA), a round of it
; (6475, choose_opponent 7094), the knights riding in (6850), the joust down
; the lane (6EC2, lance_step 6B09) and its outcome over the stands (6C59).
;
; Its sprites (BX: the tournament from above, the outcome's knights; BY: the
; opponent charging, the lance) are read from the card (load_sprites). The
; outcome's four scripts (BX items 37-40) are kept here (tourn_scripts.bin).
; The remake's own S skips the trumpeters' fanfare and the knights riding in.

#include "defs.asm"
#include "../build/main_syms.asm"

D_BANNED     EQU $003D          ; disgraced: no more tournaments
D_LAST_TOURN EQU $0041          ; year x 12 + month of the last tournament
D_IN_TOURN   EQU $0D16          ; words by side: still in the tournament
D_OPPONENT   EQU $0D10          ; the opponent shown (and who takes or loses the land)
D_LANCE_X    EQU $0D0C          ; the lance's point, 20-50 (4-pixel units)
D_LANCE_Y    EQU $0D14          ; 120-180
D_GALLOP     EQU $005F          ; the lance's step: the speaker's divisor
D_BOB_LEFT   EQU $0061          ; steps until the bob turns
D_BOB        EQU $0063          ; the bob: +-2 lines a step
D_HOOVES     EQU $0065          ; the outcome's beat
PIC_TRUMPETERS EQU 6
PIC_TOURNAMENT EQU 7
PIC_LANE     EQU 8
PIC_STANDS   EQU 9
TUNE_TOURN   EQU $9A
JOUST_PACE   EQU 4              ; the remake's g_joust_pace: screens a step of the lance

            org $2000
            jp o_tournament         ; 2000h: a tournament held by side A -> A: 1 if held

; ------------------------------------------------------------------ words

; HL = side A's field C (A = FFh: the record before the first, as the original reads it)
tu_side_w:
            call tu_side_ofs
            ld b, 0
            add hl, bc
            jp dsw
; side A's field C = DE
tu_side_sw:
            push de
            call tu_side_ofs
            ld b, 0
            add hl, bc
            pop de
            jp dssw
tu_side_ofs:
            cp $FF
            jp nz, side_ofs
            ld hl, $009F - 24
            ret

; HL = the address of side A's word "still in the tournament"
tu_in_ofs:
            add a, a
            ld l, a
            ld h, 0
            ld de, DSEG + D_IN_TOURN
            add hl, de
            ret
; HL = that word
tu_in_w:
            call tu_in_ofs
            ld a, (hl)
            inc hl
            ld h, (hl)
            ld l, a
            ret

; HL = A x 4
tu_x4:
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            ret

; the slots drawn, the screen, the slots taken off
tu_frame:
            call sprites_draw
            call present
            jp sprites_erase

; 9464: morale + A (signed), kept within 1-50
tu_morale_add:
            ld e, a
            rla
            sbc a, a
            ld d, a
            ld hl, (DSEG + D_MORALE)
            add hl, de
            ld de, 1
            call tu_at_least
            ld de, 50
            call tu_at_most
            ld (DSEG + D_MORALE), hl
            ret

; the player's leadership + A (signed), kept within 0-10
tu_lead_add:
            ld (tu_d), a
            ld a, (tu_p)
            ld c, S_LEAD
            call tu_side_w
            ld a, (tu_d)
            ld e, a
            rla
            sbc a, a
            ld d, a
            add hl, de
            ld de, 0
            call tu_at_least
            ld de, 10
            call tu_at_most
            ex de, hl
            ld a, (tu_p)
            ld c, S_LEAD
            jp tu_side_sw

; HL = at least DE, at most DE (signed; small numbers)
tu_at_least:
            or a
            sbc hl, de
            add hl, de
            ret p
            ex de, hl
            ret
tu_at_most:
            or a
            sbc hl, de
            add hl, de
            ret m
            ret z
            ex de, hl
            ret

; the beat at offset HL: its pitch falls by 500 a step, from 30000 to 28500 and round again
tu_next_beat:
            push hl
            call dsw
            ld de, -500
            add hl, de
            ld de, $6F54
            or a
            sbc hl, de
            add hl, de
            jp p, nb_set
            ld hl, $7530
nb_set:
            ex de, hl
            pop hl
            jp dssw

; ------------------------------------------------------------------ the tournament (62BC)

o_tournament:
            ld (tu_di), a
            ld a, (DSEG + D_PLAYER)
            ld (tu_p), a
            ld hl, (DSEG + D_BANNED)
            ld a, h
            or l
            ld hl, $2E1B            ; "You may not call a tournament, you have been banned from Ashby."
            jp nz, ot_refuse
            ld hl, (DSEG + D_YEAR)  ; now: year x 12 + month
            add hl, hl
            add hl, hl
            ld d, h
            ld e, l
            add hl, hl
            add hl, de
            ld de, (DSEG + D_MONTH_NO)
            add hl, de
            ld (tu_now), hl
            ld de, (DSEG + D_LAST_TOURN)
            or a
            sbc hl, de
            jp z, ot_recent
            dec hl
            ld a, h
            or l
            jp nz, ot_gold
ot_recent:
            ld hl, $3477            ; "The Lords have just returned from the last tournament!"
            jp ot_refuse
ot_gold:
            ld a, (tu_di)
            ld c, S_GOLD
            call tu_side_w
            ld de, 5
            or a
            sbc hl, de
            jp p, ot_hold
            ld hl, $2CA4            ; "You must have at least 5 pieces of gold to hold a Tournament."
ot_refuse:
            ld a, (tu_p)
            ld c, a
            ld a, (tu_di)
            cp c
            call z, dialog
            xor a
            ret
ot_hold:
            ex de, hl               ; 5 gold
            ld a, (tu_di)
            ld c, S_GOLD
            call tu_side_sw
            ld a, 1                 ; 26AA: every lord's enmity towards him -1
ot_enmity:
            ld (tu_si), a
            ld a, (tu_di)
            ld c, a
            ld b, $FF
            ld a, (tu_si)
            call enmity_add
            ld a, (tu_si)
            inc a
            cp 7
            jp c, ot_enmity
            ld hl, DSEG + D_IN_TOURN + 2    ; every lord in it, the player not
            ld b, 6
ot_in:
            ld (hl), 1
            inc hl
            ld (hl), 0
            inc hl
            djnz ot_in
            ld a, (tu_p)
            call tu_in_ofs
            ld (hl), 0
            inc hl
            ld (hl), 0
            ld a, 1                 ; its sprites (the pages the siege's and the saved back page share)
            call load_sprites
            ld a, 2
            call load_sprites
            call redraw_map
            ld a, (tu_di)           ; "... bids all knights to attend the games of Chivalry."
            ld c, S_NAME
            call tu_side_w
            ld de, (DSEG + $2FF5)
            call str_append
            ld hl, $2FEA
            call dialog
            call tu_fanfare
            ld a, 3                 ; up to three rounds, while they are won
ot_round:
            ld (tu_rounds), a
            call tu_joust_round
            cp 1
            jp nz, ot_done
            ld a, (tu_rounds)
            dec a
            jp nz, ot_round
            ld hl, $319C            ; "--- The Champion ---"
            call dialog
ot_done:
            ld hl, (tu_now)
            ld (DSEG + D_LAST_TOURN), hl
            call redraw_map
            ld a, 1
            ret

; the remake's own: S skips the trumpeters' fanfare
tu_fanfare:
            ld hl, tf_skip
            call skip_arm
            ld a, PIC_TRUMPETERS
            call show_picture
            call present
            call set_palette
            ld a, TUNE_TOURN
            ld hl, (DSEG + D_TUNE_ONCE)
            call play_tune
            call wait_tune
            jp skip_disarm
tf_skip:
            ld a, TUNE_TOURN
            ld hl, (DSEG + D_TUNE_STOP)
            call play_tune
            jp flush_keys

; ------------------------------------------------------------------ a round (6475)

; The stakes: Land only if a lord still in the tournament owns a territory
; without a castle and so does the player (his highest-numbered one is at
; stake); the player then chooses the territory to win, whose owner is the
; opponent. Otherwise, or for Fame, the player chooses the opponent. The
; joust is judged by the jousting of the owner of the territory the first
; search stopped at, not the opponent's, as the original. A = 1 won, 2 lost,
; 3 disgraced.
tu_joust_round:
            ld a, PIC_TOURNAMENT
            call show_picture
            call present
            call set_palette
            ld a, TUNE_TOURN
            ld hl, (DSEG + D_TUNE_ONCE)
            call play_tune
            ld hl, 27
            call wait_ticks
            ld a, 1
            ld (jr_fame), a
            ld a, 18                ; the lords' land: the highest without a castle
jr_s1:
            ld (jr_si), a
            call terr_owner
            ld (jr_di), a
            cp $FF
            jp z, jr_s1_next
            call tu_in_w
            ld a, h
            or l
            jp z, jr_s1_next
            ld a, (jr_si)
            ld c, T_CASTLE
            call terr_byte
            or a
            jp z, jr_s1_found
jr_s1_next:
            ld a, (jr_si)
            dec a
            jp nz, jr_s1
            jp jr_no_land
jr_s1_found:
            ld a, 18                ; the player's: the highest without a castle
jr_s2:
            ld (jr_si), a
            call terr_owner
            ld c, a
            ld a, (tu_p)
            cp c
            jp nz, jr_s2_next
            ld a, (jr_si)
            ld c, T_CASTLE
            call terr_byte
            or a
            jp z, jr_stakes
jr_s2_next:
            ld a, (jr_si)
            dec a
            jp nz, jr_s2
            jp jr_no_land
jr_stakes:
            ld hl, $2FB1            ; Choose the Stakes: Fame / Land / Read Map
            call dialog
            cp 3
            jp nz, jr_chosen
            call read_map
            jp jr_stakes
jr_chosen:
            cp 1
            jp nz, jr_land
            call tu_choose_opp
            jp jr_opponent
jr_land:
            call redraw_map
jr_pick:
            ld a, (tu_p)
            ld c, S_HOME
            call tu_side_w
            ld a, l
            call choose_territory
            ld (jr_l2), a
            call terr_owner
            ld (jr_o), a
            ld hl, $2D4F            ; not owned by a lord in the tournament
            cp $FF
            jp z, jr_refused
            ld c, a
            ld a, (tu_p)
            cp c
            ld hl, $2DE8            ; "You may not choose your own territory"
            jp z, jr_refused
            ld a, (jr_l2)
            ld c, T_CASTLE
            call terr_byte
            or a
            ld hl, $2DAB            ; "... with a castle."
            jp nz, jr_refused
            ld a, (jr_o)
            ld l, a
            ld h, 0
            ld (DSEG + D_OPPONENT), hl
            call tu_in_w
            ld a, h
            or l
            jp nz, jr_picked
            ld hl, $2D4F
jr_refused:
            call dialog
            jp jr_pick
jr_picked:
            xor a
            ld (jr_fame), a
            call redraw_map
            ld hl, $3453            ; "Your opponent chooses:"
            call dialog
            ld a, (jr_si)
            ld b, 36
            call flash_territory
            jp jr_go
jr_no_land:
            xor a
            ld (jr_si), a
            ld hl, $2F67            ; "There is no land to joust for, so you must joust for fame."
            call dialog
            call tu_choose_opp
jr_opponent:
            ld l, a
            ld h, 0
            ld (DSEG + D_OPPONENT), hl
jr_go:
            ld a, (DSEG + D_OPPONENT)
            ld (jr_o), a
            call tu_in_ofs          ; (the booter does this after showing the two knights)
            ld (hl), 0
            inc hl
            ld (hl), 0
            call tu_ride_in
            call tu_meet
            ld a, PIC_LANE
            call show_picture
            ld a, (jr_di)
            call tu_joust
            ld (jr_r), a
            cp 1
            jp z, jr_won
            cp 2
            jp z, jr_lost
            ld hl, 1                ; disgrace: banned, morale 19, all the land but the home lost
            ld (DSEG + D_BANNED), hl
            ld hl, 19
            ld (DSEG + D_MORALE), hl
            ld hl, $3066            ; "--- Disgrace ---"
            call dialog
            call redraw_map
            ld a, 18
jr_lose_all:
            ld (jr_si), a
            call terr_owner
            ld c, a
            ld a, (tu_p)
            cp c
            jp nz, jr_lose_next
            ld c, S_HOME
            call tu_side_w
            ld a, (jr_si)
            cp l
            jp z, jr_lose_next
            ld c, a
            ld a, $FF
            call set_owner
jr_lose_next:
            ld a, (jr_si)
            dec a
            jp nz, jr_lose_all
            ld a, (tu_p)
            call army_home
            jp jr_ret
jr_won:
            ld hl, $2E6A            ; "Congratulations, you won that round."
            call dialog
            ld a, 1
            call tu_morale_add
            ld a, (jr_fame)
            or a
            jp z, jr_won_land
            ld a, 1
            call tu_lead_add
            jp jr_ret
jr_won_land:
            call redraw_map
            ld a, (jr_l2)
            ld c, a
            ld a, (tu_p)
            call set_owner
            ld a, (jr_l2)           ; that lord's army there: home
            ld c, a
            ld a, (jr_di)
            jp jr_home_if
jr_lost:
            ld a, -1
            call tu_morale_add
            ld hl, $328E            ; "--- A Long Day ---"
            call dialog
            ld a, (jr_fame)
            or a
            jp z, jr_lost_land
            ld a, -1
            call tu_lead_add
            jp jr_ret
jr_lost_land:
            call redraw_map
            ld a, (jr_si)
            ld c, a
            ld a, (jr_o)
            call set_owner
            ld a, (jr_si)           ; the player's army there: home
            ld c, a
            ld a, (tu_p)
jr_home_if:                         ; side A's army home if it is at territory C
            ld (jr_side), a
            ld a, c
            ld (jr_at), a
            ld a, (jr_side)
            ld c, S_AT
            call tu_side_w
            ld a, h
            or a
            jp nz, jr_ret
            ld a, (jr_at)
            cp l
            jp nz, jr_ret
            ld a, (jr_side)
            call army_home
jr_ret:
            ld a, (jr_r)
            ret

; 7094: a menu of the lords still in the tournament -> A: the side chosen (0: none)
tu_choose_opp:
            xor a
            ld (co_k), a
            inc a
co_side:
            ld (co_si), a
            call tu_in_w
            ld a, h
            or l
            jp z, co_next
            ld hl, co_k
            inc (hl)
            ld a, (co_si)
            ld c, S_NAME
            call tu_side_w
            ex de, hl
            ld a, (co_k)
            add a, a
            ld l, a
            ld h, 0
            ld bc, DSEG + $2C43
            add hl, bc
            ld (hl), e
            inc hl
            ld (hl), d
            ld a, (co_k)
            ld l, a
            ld h, 0
            ld bc, co_sides
            add hl, bc
            ld a, (co_si)
            ld (hl), a
co_next:
            ld a, (co_si)
            inc a
            cp 7
            jp c, co_side
            ld a, (co_k)
            ld (DSEG + $2C3E), a
            inc a
            ld (DSEG + $2C3A), a
            ld hl, $2C38
            call dialog
            or a
            ret z
            ld c, a
            ld a, (co_k)
            cp c
            jp c, co_none
            ld l, c
            ld h, 0
            ld de, co_sides
            add hl, de
            ld a, (hl)
            ret
co_none:
            xor a
            ret

; ------------------------------------------------------------------ the knights ride in (6850)

; the remake's own: S skips the knights riding in
tu_ride_in:
            ld hl, ri_skip
            call skip_arm
            ld a, PIC_TOURNAMENT
            call show_picture
            xor a
            ld hl, 41 * 4
            ld e, 76
            ld c, TOURN_PAGE
            ld b, 2
            call slot_set
            ld a, 1
            ld hl, 15 * 4
            ld e, 88
            ld c, TOURN_PAGE
            ld b, 30
            call slot_set
            call tu_frame
            xor a                   ; the other knight (slot 1) waits on
            ld (slots), a
            call wait_tune
            call tu_approach
            jp skip_disarm
ri_skip:
            ld a, TUNE_TOURN
            ld hl, (DSEG + D_TUNE_STOP)
            call play_tune
            call slots_off
            ld a, PIC_TOURNAMENT
            call show_picture
            call present
            jp flush_keys

; over the tournament from above: the first knight rides in (BX 2-22, x 41 to
; 61), turns (23, 24) and rides back (25-29) while the other comes in (30-35,
; x 15 on)
tu_approach:
            ld a, PIC_TOURNAMENT
            call show_picture
            ld a, 41
            ld (ta_di), a
            ld a, 2
ta_in:
            ld (ta_si), a
            ld b, a
            ld a, (ta_di)
            inc a
            ld (ta_di), a
            dec a
            call tu_x4
            ld e, 76
            ld c, TOURN_PAGE
            xor a
            call slot_set
            call tu_frame
            ld hl, 3
            call wait_ticks
            call get_key
            ld a, (ta_si)
            inc a
            cp 23
            jp c, ta_in
            ld (ta_si), a
            ld a, 2                 ; it turns
ta_turn:
            ld (ta_k), a
            ld a, (ta_si)
            ld b, a
            inc a
            ld (ta_si), a
            ld hl, 60 * 4
            ld e, 76
            ld c, TOURN_PAGE
            xor a
            call slot_set
            call tu_frame
            ld hl, 3
            call wait_ticks
            ld a, (ta_k)
            dec a
            jp nz, ta_turn
            ld a, 60
            ld (ta_di), a
            ld a, 15
            ld (ta_x2), a
ta_back:
            ld a, (ta_si)           ; it rides back
            ld b, a
            inc a
            ld (ta_si), a
            ld a, (ta_di)
            dec a
            ld (ta_di), a
            inc a
            call tu_x4
            ld e, 76
            ld c, TOURN_PAGE
            xor a
            call slot_set
            call tu_frame
            ld hl, 1
            call wait_ticks
            ld a, (ta_si)           ; the other comes in
            add a, 4
            ld b, a
            ld a, (ta_x2)
            inc a
            ld (ta_x2), a
            dec a
            call tu_x4
            ld e, 88
            ld c, TOURN_PAGE
            ld a, 1
            call slot_set
            call tu_frame
            ld hl, 2
            call wait_ticks
            call get_key
            ld a, (ta_si)
            cp 30
            jp c, ta_back
            add a, 5
            ld b, a
            ld a, (ta_x2)
            call tu_x4
            ld e, 88
            ld c, TOURN_PAGE
            ld a, 1
            call slot_set
            call tu_frame
            call slots_off
            ld hl, 4
            jp wait_ticks

; the end of 6D3F: the two lords' portraits and names, and "An expectant hush..."
tu_meet:
            ld a, (jr_o)
            ld c, S_PORTRAIT
            call tu_side_w
            ld a, l
            ld b, 9
            ld c, 3
            call show_portrait
            ld a, (jr_o)
            ld c, S_NAME
            call tu_side_w
            ld (DSEG + $2F64), hl
            ld a, 1
            ld (DSEG + $2F59), a
            ld hl, $2F59
            call dialog
            ld a, (tu_p)
            ld c, S_PORTRAIT
            call tu_side_w
            ld de, (DSEG + $009D)
            add hl, de
            ld a, l
            ld b, 53
            ld c, 3
            call show_portrait
            ld a, (tu_p)
            ld c, S_NAME
            call tu_side_w
            ld (DSEG + $2F64), hl
            ld a, 45
            ld (DSEG + $2F59), a
            ld hl, $2F59
            call dialog
            ld hl, $2E9E            ; "An expectant hush..."
            call dialog
            ld a, 20
            ld (tu_lance), a
            ret

; ------------------------------------------------------------------ the joust (6EC2)

; A pass down the lane after a key: 17 pictures of the opponent coming
; closer, three lance steps each. Then the point (x 20-50, y 120-180) is
; judged: within x 26 +- (1 if the player jousts better, else 0) and y 138 +-
; (the player's jousting + 2 - the opponent's; 0 is 1, as the EGA program
; compares it unsigned) the opponent falls (1); x below 30 with y over 170
; is the horse (3); otherwise random(opponent's jousting) of 2 or more
; unhorses the player (2), else a near miss and another pass (the fourth
; pass is always lost). A: the side whose jousting it is judged by.
tu_joust:
            ld (tj_opp), a
            xor a
            ld (tj_passes), a
tj_pass:
            call wait_key
            ld a, PIC_LANE
            call show_picture
            call present
            call set_palette
            ld hl, 40
            ld (DSEG + D_LANCE_X), hl
            ld hl, 125
            ld (DSEG + D_LANCE_Y), hl
            ld a, 3
tj_picture:
            ld (tj_si), a
            call tu_lance_step
            xor a
            call tu_lance_step
            xor a
            call tu_lance_step
            ld a, (tj_si)
            inc a
            cp 20
            jp c, tj_picture
            call slots_off
            ld a, (tu_p)
            ld c, S_JOUST
            call tu_side_w
            ld (tj_pj), hl
            ld a, (tj_opp)
            ld c, S_JOUST
            call tu_side_w
            ld (tj_oj), hl
            ex de, hl               ; l4 = pj + 2 - oj (0: 1)
            ld hl, (tj_pj)
            inc hl
            inc hl
            or a
            sbc hl, de
            ld a, h
            or l
            jp nz, tj_l4
            inc hl
tj_l4:
            ld (tj_l4v), hl
            ld hl, (tj_oj)          ; l6 = 1 if pj > oj (unsigned)
            ld de, (tj_pj)
            or a
            sbc hl, de
            ld a, 0
            adc a, 0
            ld (tj_l6), a
            ld b, a                 ; x within 26 +- l6, y within 138 +- l4 (unsigned)
            ld a, 26
            sub b
            ld e, a
            ld d, 0
            ld hl, (DSEG + D_LANCE_X)
            or a
            sbc hl, de
            jp c, tj_not
            ld a, (tj_l6)
            add a, 26
            ld l, a
            ld h, 0
            ld de, (DSEG + D_LANCE_X)
            or a
            sbc hl, de
            jp c, tj_not
            ld hl, 138
            ld de, (tj_l4v)
            or a
            sbc hl, de
            ex de, hl
            ld hl, (DSEG + D_LANCE_Y)
            or a
            sbc hl, de
            jp c, tj_not
            ld hl, 138
            ld de, (tj_l4v)
            add hl, de
            ld de, (DSEG + D_LANCE_Y)
            or a
            sbc hl, de
            jp c, tj_not
            ld a, 1
            jp tj_result
tj_not:
            ld hl, (DSEG + D_LANCE_X)   ; the horse: x below 30, y over 170
            ld de, 30
            or a
            sbc hl, de
            jp nc, tj_chance
            ld hl, 170
            ld de, (DSEG + D_LANCE_Y)
            or a
            sbc hl, de
            jp nc, tj_chance
            ld a, 3
            jp tj_result
tj_chance:
            ld a, (tj_oj)
            call random_n
            ld de, 2
            or a
            sbc hl, de
            ld a, 2
            jp nc, tj_result
            xor a
tj_result:
            ld (tj_r), a
            ld hl, tj_passes
            inc (hl)
            ld a, (hl)
            cp 4
            jp c, tj_outcome
            ld a, 2
            ld (tj_r), a
tj_outcome:
            ld a, (tj_r)
            call tu_outcome
            ld a, (tj_r)
            or a
            ret nz
            ld hl, $3372            ; "--- A Near Miss ---"
            call dialog
            ld hl, $2E9E            ; "An expectant hush..."
            call dialog
            jp tj_pass

; 6B09: a step of the charge, JOUST_PACE screens: the keypad moves the lance's
; point by the table DS:0CDC (7/8/9 up, 1/2/3 down, 4/6 and the diagonals
; sideways; x only moves on a step that also shows the opponent, or when the
; key moves it), the gallop bobs it up and down (DS:0063, turned every 6
; steps and at the ends). A: the opponent's next picture (BY 3-19, placed by
; the table DS:0C8C) or 0.
tu_lance_step:
            ld (tl_item), a
            ld hl, (DSEG + D_GALLOP)
            call speaker_tone
            call get_key
            sub $47
            cp 11
            jp c, tl_key
            ld a, 3
tl_key:
            ld (tl_si), a
            ld a, (tl_item)
            or a
            jp z, tl_moves
            ld l, a                 ; the opponent: x DS:0C8C x 4, y DS:0C8E + 1
            ld h, 0
            add hl, hl
            add hl, hl
            ld de, DSEG + $0C8C
            add hl, de
            ld e, (hl)
            inc hl
            ld d, (hl)
            inc hl
            ld a, (hl)
            inc a
            ex de, hl
            add hl, hl
            add hl, hl
            ld e, a
            ld a, (tl_item)
            ld b, a
            ld c, LANE_PAGE
            ld a, 1
            call slot_set
tl_moves:
            ld a, (tl_si)           ; the key's move: x, y
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            ld de, DSEG + $0CDC
            add hl, de
            ld e, (hl)
            inc hl
            ld d, (hl)
            inc hl
            ld c, (hl)
            inc hl
            ld b, (hl)
            ld (tl_dy), bc
            ld a, d
            or e
            jp nz, tl_x
            ld a, (tl_item)
            or a
            jp z, tl_y
tl_x:
            ld hl, (DSEG + D_LANCE_X)
            add hl, de
            ld de, 20
            call tu_at_least
            ld de, 50
            call tu_at_most
            ld (DSEG + D_LANCE_X), hl
tl_y:
            ld hl, (DSEG + D_LANCE_Y)
            ld de, (tl_dy)
            add hl, de
            ld de, (DSEG + D_BOB)
            add hl, de
            ld de, 180
            or a
            sbc hl, de
            add hl, de
            jp z, tl_y_low
            jp m, tl_y_low
            ex de, hl
            jp tl_y_end
tl_y_low:
            ld de, 120
            or a
            sbc hl, de
            add hl, de
            jp p, tl_y_set
            ex de, hl
tl_y_end:
            ld de, 1                ; at an end: the bob turns
            ld (DSEG + D_BOB_LEFT), de
tl_y_set:
            ld (DSEG + D_LANCE_Y), hl
            ld hl, (DSEG + D_LANCE_X)   ; the lance
            add hl, hl
            add hl, hl
            ld a, (DSEG + D_LANCE_Y)
            ld e, a
            ld a, (tu_lance)
            ld b, a
            ld c, LANE_PAGE
            xor a
            call slot_set
            call sprites_draw
            ld b, JOUST_PACE        ; (keys pressed meanwhile are read next)
tl_show:
            push bc
            call present_bottom
            pop bc
            djnz tl_show
            call sprites_erase
            ld hl, (DSEG + D_BOB_LEFT)
            dec hl
            ld (DSEG + D_BOB_LEFT), hl
            ld a, h
            or l
            jp nz, tl_beep
            ld hl, 6
            ld (DSEG + D_BOB_LEFT), hl
            ld de, (DSEG + D_BOB)
            or a
            sbc hl, hl
            sbc hl, de
            ld (DSEG + D_BOB), hl
tl_beep:
            ld hl, (DSEG + D_GALLOP)
            ld a, 1
            call beep
            ld hl, D_GALLOP
            jp tu_next_beat

; 6C59: over the stands, the script A (0 a near miss, 1 the opponent unhorsed,
; 2 the player, 3 the horse hit): a frame is 4 bytes a knight, the BX item -
; 20, the rows drawn (the rest is behind the barrier), x and y; a y of 0
; takes the knight away, an x over 80 ends it. Two beats of the hooves a frame.
tu_outcome:
            push af
            call flush_keys
            ld a, PIC_STANDS
            call show_picture
            call present
            call set_palette
            pop af
            add a, a
            ld l, a
            ld h, 0
            ld de, tu_scripts
            add hl, de
            ld e, (hl)
            inc hl
            ld d, (hl)
            ld hl, tu_scripts
            add hl, de
            ld (to_pos), hl
            ld a, $FF
            ld (to_y1), a
            ld (to_y2), a
to_frame:
            call get_key
            ld hl, (to_pos)
            ld a, (to_y1)
            or a
            jp z, to_second
            ld a, (hl)
            add a, 20
            ld (to_it1), a
            inc hl
            ld a, (hl)
            ld (to_rows1), a
            inc hl
            ld a, (hl)
            ld (to_x1), a
            inc hl
            cp 81
            ret nc
            ld a, (hl)
            ld (to_y1), a
            inc hl
to_second:
            ld a, (to_y2)
            or a
            jp z, to_read
            ld a, (hl)
            add a, 20
            ld (to_it2), a
            inc hl
            ld a, (hl)
            ld (to_rows2), a
            inc hl
            ld a, (hl)
            ld (to_x2), a
            inc hl
            cp 81
            ret nc
            ld a, (hl)
            ld (to_y2), a
            inc hl
to_read:
            ld (to_pos), hl
            call to_beat
            ld hl, (DSEG + D_HOOVES)
            call speaker_tone
            ld a, (to_y1)
            or a
            jp z, to_one
            ld e, a
            ld a, (to_it1)
            ld b, a
            ld a, (to_x1)
            call tu_x4
            ld c, TOURN_PAGE
            ld a, 1
            call slot_set
            ld a, (to_rows1)
            ld (slots + SLOT_SIZE + 7), a
to_one:
            ld a, (to_y2)
            or a
            jp z, to_draw
            ld e, a
            ld a, (to_it2)
            ld b, a
            ld a, (to_x2)
            call tu_x4
            ld c, TOURN_PAGE
            xor a
            call slot_set
            ld a, (to_rows2)
            ld (slots + 7), a
to_draw:
            call sprites_draw
            call present_bottom
            call sprites_erase
            call slots_off
            call to_beat
            jp to_frame
to_beat:
            ld hl, (DSEG + D_HOOVES)
            ld a, 1
            call beep
            ld hl, D_HOOVES
            jp tu_next_beat

tu_scripts:
            incbin "../build/tourn_scripts.bin"

; ------------------------------------------------------------------ variables

tu_di:      db 0                ; the side holding the tournament
tu_p:       db 0                ; the player
tu_si:      db 0
tu_d:       db 0
tu_now:     dw 0
tu_rounds:  db 0
tu_lance:   db 0                ; DS:0D0E: the lance (BY item 20)
jr_fame:    db 0                ; jousting for fame (else land)
jr_si:      db 0                ; the player's territory at stake
jr_di:      db 0                ; whose jousting judges the joust
jr_l2:      db 0                ; the territory to win
jr_o:       db 0                ; the opponent
jr_r:       db 0
jr_side:    db 0
jr_at:      db 0
co_k:       db 0
co_si:      db 0
co_sides:   ds 8                ; the menu's lords (0: none)
ta_di:      db 0
ta_si:      db 0
ta_k:       db 0
ta_x2:      db 0
tj_opp:     db 0
tj_passes:  db 0
tj_si:      db 0
tj_pj:      dw 0
tj_oj:      dw 0
tj_l4v:     dw 0
tj_l6:      db 0
tj_r:       db 0
tl_item:    db 0
tl_si:      db 0
tl_dy:      dw 0
to_pos:     dw 0
to_y1:      db 0
to_y2:      db 0
to_it1:     db 0
to_it2:     db 0
to_rows1:   db 0
to_rows2:   db 0
to_x1:      db 0
to_x2:      db 0
