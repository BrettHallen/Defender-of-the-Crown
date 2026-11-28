; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; ov_war.asm: an overlay (see ov_setup.asm): the computer lords and the wars,
; as the Mac remake's ai.c and war.c port them:
;   ai_turn (AB 2995), ai_reinforce_garrison (2C60), ai_choose_order (2D84),
;   ai_do_order (2D10), the search for a target (2704, 2803, 28B8), buying
;   (2A9E, 2A3C), the Normans' raids (4428, 43F6);
;   the armies (2016-21CC), side_falls (2406), attack and apply_result (31D5,
;   33E5), the battles (5781, 600C, 60EB) and the computer lords' sieges (78A9).
;
; The numbers are the original's 16-bit words: its divisions are signed, its
; products keep their low word.

#include "defs.asm"
#include "../build/main_syms.asm"

D_SEARCH_PATH   EQU $0069       ; 5 words: the way to the best target so far
D_SEARCH_BEST   EQU $0073
D_SEARCH_SEEN   EQU $0075       ; 19 words
D_SEARCH_TARGET EQU $009B
D_LAST_ORDER    EQU $024B       ; words by side: the computer lords' last orders
D_DMG_TO_ATT    EQU $0B4C
D_DMG_TO_DEF    EQU $0B4E
D_SIEGE_SHOWN   EQU $003F
S_SPEND         EQU 12
T_NB            EQU 8

            org $2000
            jp o_ai_turn            ; 2000h: ai_turn (A: the side)
            jp o_attack             ; 2003h: attack (A: attacker, C: defender, B: territory) -> A: the result
            jp o_side_falls         ; 2006h: side_falls (A: the side, C: the winner)
            jp o_army_move_to       ; 2009h: army_move_to (A: the side, C: the territory)
            jp o_army_settle        ; 200Ch: army_settle (A: the side)
            jp army_go_home         ; 200Fh: army_home (A: the side)

; ------------------------------------------------------------------ words

; HL = the word at field C of record HL (offsets)
rec_w:
            ld b, 0
            add hl, bc
            jp dsw

; field C of record HL = DE
rec_sw:
            ld b, 0
            add hl, bc
            jp dssw

; HL = HL / DE, signed, truncated towards 0 (DE > 0)
sdiv:
            bit 7, h
            jp z, div16
            xor a                   ; -(-HL / DE)
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

; HL = HL * A (the low word)
mul_a:
            ld d, h
            ld e, l
            ld hl, 0
            or a
            ret z
mula_bit:
            add hl, de
            dec a
            jp nz, mula_bit
            ret

; ------------------------------------------------------------------ the armies

; 26EF: HL = army HL's strength: 4 x knights + soldiers
strength:
            push hl
            ld c, A_KNIGHTS
            call rec_w
            add hl, hl
            add hl, hl
            ex (sp), hl
            ld c, A_SOLDIERS
            call rec_w
            pop de
            add hl, de
            ret

; 2016: Z if army HL has no soldiers and no knights
army_empty:
            push hl
            ld c, A_SOLDIERS
            call rec_w
            ld a, h
            or l
            pop hl
            ret nz
            ld c, A_KNIGHTS
            call rec_w
            ld a, h
            or l
            ret

; HL = campaign army A's offset; garrison: of territory A
army_of:
            jp army_ofs
garrison_of:
            jp garrison_ofs

; side A's campaign army to territory C (its base where it was)
o_army_move_to:
            ld (am_si), a
            ld a, c
            ld (am_t), a
            ld e, a
            ld d, 0
            ld a, (am_si)
            ld c, S_AT
            call side_sw
            ld a, (am_si)
            call army_ofs
            push hl
            call dsw                ; A_AT
            ex de, hl
            pop hl
            push hl
            inc hl
            inc hl
            call dssw               ; A_BASE = A_AT
            pop hl
            ld a, (am_t)
            ld e, a
            ld d, 0
            jp dssw

; side A's campaign army home
army_go_home:
            ld (am_si), a
            ld c, S_HOME
            call side_w
            ex de, hl
            ld (am_v), de
            ld a, (am_si)
            ld c, S_AT
            call side_sw
            ld a, (am_si)
            call army_ofs
            ld de, (am_v)
            push hl
            call dssw
            pop hl
            inc hl
            inc hl
            ld de, (am_v)
            jp dssw

; every other side's campaign army at territory A goes home (but side C's)
send_others_home:
            ld (sn_t), a
            ld a, c
            ld (sn_except), a
            ld a, 1
sn_side:
            ld (sn_si), a
            ld hl, sn_except
            cp (hl)
            jp z, sn_next
            call army_ofs
            call dsw
            ld a, (sn_t)
            cp l
            jp nz, sn_next
            ld a, h
            or a
            jp nz, sn_next
            ld a, (sn_si)
            call army_go_home
sn_next:
            ld a, (sn_si)
            inc a
            cp 7
            jp c, sn_side
            ret

; side A's campaign army settles at its base (or its home, if the base is not
; its side's or the army is empty)
o_army_settle:
            ld (am_si), a
            call army_ofs
            ld (am_a), hl
            ld c, A_BASE
            call rec_w
            ld a, l
            call terr_owner
            ld hl, am_si
            cp (hl)
            jp nz, as_home
            ld hl, (am_a)           ; soldiers + knights > 0
            ld c, A_SOLDIERS
            call rec_w
            push hl
            ld hl, (am_a)
            ld c, A_KNIGHTS
            call rec_w
            pop de
            add hl, de
            dec hl
            bit 7, h
            jp z, as_base
as_home:
            ld a, (am_si)
            ld c, S_HOME
            call side_w
            ex de, hl
            ld hl, (am_a)
            ld c, A_BASE
            call rec_sw
as_base:
            ld hl, (am_a)
            ld c, A_BASE
            call rec_w
            ex de, hl
            ld (am_v), de
            ld hl, (am_a)
            call dssw               ; A_AT
            ld a, (am_si)
            ld c, S_AT
            ld de, (am_v)
            jp side_sw

; army HL's men and catapults into army DE (offsets)
army_merge:
            ld (mg_from), hl
            ld (mg_to), de
            ld a, A_SOLDIERS
mg_field:
            ld (mg_f), a
            ld c, a
            ld hl, (mg_from)
            call rec_w
            ld (mg_n), hl
            ld a, (mg_f)
            ld c, a
            ld hl, (mg_to)
            call rec_w
            ld de, (mg_n)
            add hl, de
            ex de, hl
            ld a, (mg_f)
            ld c, a
            ld hl, (mg_to)
            call rec_sw
            ld a, (mg_f)
            ld c, a
            ld hl, (mg_from)
            ld de, 0
            call rec_sw
            ld a, (mg_f)
            add a, 2
            cp A_CATAPULTS + 2
            jp c, mg_field
            ret

; 2406: every territory of side A to side C (redrawn first)
o_side_falls:
            ld (sf_side), a
            ld a, c
            ld (sf_winner), a
            call redraw_map
            ld a, 1
sf_terr:
            ld (sf_t), a
            call terr_owner
            ld hl, sf_side
            cp (hl)
            jp nz, sf_next
            ld a, (sf_t)
            ld c, a
            ld a, (sf_winner)
            call set_owner
sf_next:
            ld a, (sf_t)
            inc a
            cp 19
            jp c, sf_terr
            ret

; ------------------------------------------------------------------ battle rounds

; 6202: HL = army HL's damage with tactic A (1-5)
army_damage:
            ld (ad_army), hl
            ld (ad_tactic), a
            ld c, 32                ; soldiers / l2 + knights / si
            ld b, 8
            cp 1
            jp z, ad_4
            cp 3
            jp nz, ad_5
ad_4:
            ld b, 4
            jp ad_go
ad_5:
            cp 5
            jp nz, ad_go
            ld c, 48
            ld b, 16
ad_go:
            push bc
            ld hl, (ad_army)
            ld c, A_SOLDIERS
            call rec_w
            pop bc
            push bc
            ld e, c
            ld d, 0
            call sdiv
            ld (ad_n), hl
            ld hl, (ad_army)
            ld c, A_KNIGHTS
            call rec_w
            pop bc
            ld e, b
            ld d, 0
            call sdiv
            ld de, (ad_n)
            add hl, de
            ld a, (ad_tactic)
            cp 3
            ret nz
            ld (ad_n), hl           ; Bombard: + random_n(catapults + 1)
            ld hl, (ad_army)
            ld c, A_CATAPULTS
            call rec_w
            ld a, l
            inc a
            call random_n
            ld de, (ad_n)
            add hl, de
            ret

; 627C: HL = (HL x lead A + 5) / 10
percent_of_lead:
            call mul_a
            ld de, 5
            add hl, de
            ld de, 10
            jp sdiv

; 60EB: the damage each side does in a round (tactic A), into D_DMG_TO_DEF and
; D_DMG_TO_ATT; br_pct the castle's protection off the attackers' damage
battle_round:
            ld (br_tactic), a
            cp 5
            jp nz, br_both
            ld a, (br_t)
            call garrison_ofs
            ld a, 5
            call army_damage
            ld (DSEG + D_DMG_TO_ATT), hl
            jp br_random
br_both:
            ld a, (br_att)
            call army_ofs
            ld a, (br_tactic)
            call army_damage
            ld (DSEG + D_DMG_TO_DEF), hl
            ld a, (br_t)
            call garrison_ofs
            ld a, (br_tactic)
            call army_damage
            ld (DSEG + D_DMG_TO_ATT), hl
            ld a, (br_tactic)       ; + their own lord's lead% (Outflank: - the other's)
            cp 4
            ld a, (br_att)
            jp nz, br_lead1
            ld a, (br_def)
br_lead1:
            ld c, S_LEAD
            call side_w
            ld a, l
            ld hl, (DSEG + D_DMG_TO_DEF)
            push hl
            call percent_of_lead
            pop de
            call br_apply
            ld (DSEG + D_DMG_TO_DEF), hl
            ld a, (br_tactic)
            cp 4
            ld a, (br_def)
            jp nz, br_lead2
            ld a, (br_att)
br_lead2:
            ld c, S_LEAD
            call side_w
            ld a, l
            ld hl, (DSEG + D_DMG_TO_ATT)
            push hl
            call percent_of_lead
            pop de
            call br_apply
            ld (DSEG + D_DMG_TO_ATT), hl
br_random:
            ld a, 3                 ; the defenders' damage + random_n(3) - (pct x it + 50) / 100
            call random_n
            ld de, (DSEG + D_DMG_TO_DEF)
            add hl, de
            ld (DSEG + D_DMG_TO_DEF), hl
            ld a, (br_pct)
            call mul_a
            ld de, 50
            add hl, de
            ld de, 100
            call sdiv
            ex de, hl
            ld hl, (DSEG + D_DMG_TO_DEF)
            or a
            sbc hl, de
            bit 7, h
            jp z, br_def_ok
            ld hl, 0
br_def_ok:
            ld (DSEG + D_DMG_TO_DEF), hl
            ld a, 3
            call random_n
            ld de, (DSEG + D_DMG_TO_ATT)
            add hl, de
            bit 7, h
            jp z, br_att_ok
            ld hl, 0
br_att_ok:
            ld (DSEG + D_DMG_TO_ATT), hl
            ret
; HL = DE + HL, or DE - HL with Outflank (tactic 4)
br_apply:
            ld a, (br_tactic)
            cp 4
            jp z, br_minus
            add hl, de
            ret
br_minus:
            ex de, hl
            or a
            sbc hl, de
            ret

; 6290: army HL loses DE men: soldiers first, then knights
take_losses:
            ld (tl_army), hl
tl_one:
            dec de
            bit 7, d
            ret nz
            push de
            ld hl, (tl_army)
            ld c, A_SOLDIERS
            call tl_take
            jp nc, tl_next
            ld hl, (tl_army)
            ld c, A_KNIGHTS
            call tl_take
tl_next:
            pop de
            jp tl_one
; field C of army HL down by one if above 0 (NC); else carry
tl_take:
            ld b, 0
            add hl, bc
            push hl
            call dsw
            dec hl
            bit 7, h
            pop de
            scf
            ret nz
            ex de, hl
            call dssw
            or a
            ret

; the round (tactic A), then the losses
round_and_losses:
            call battle_round
            ld a, (br_t)
            call garrison_ofs
            ld de, (DSEG + D_DMG_TO_DEF)
            call take_losses
            ld a, (br_att)
            call army_ofs
            ld de, (DSEG + D_DMG_TO_ATT)
            jp take_losses

; 600C: a battle the player is not in, fought out at once with Stand and Fight: A = the result
battle_auto:
            ld a, (br_def)
            call army_ofs
            push hl
            call dsw
            ld a, (br_t)
            cp l
            pop hl
            jp nz, ba_round
            ld a, (br_t)
            push hl
            call garrison_ofs
            ex de, hl
            pop hl
            call army_merge
ba_round:
            ld a, 2
            call round_and_losses
            ld a, (br_t)
            call garrison_ofs
            call army_empty
            ld c, 0
            jp nz, ba_att
            inc c
ba_att:
            push bc
            ld a, (br_att)
            call army_ofs
            call army_empty
            pop bc
            jp nz, ba_att_men
            ld a, c                 ; the attackers' gone: both 7, else 5
            or a
            ld a, 5
            ret z
            ld a, 7
            ret
ba_att_men:
            ld a, c
            or a
            jp z, ba_round
            ld a, 4
            ret

; 5781: A = the result of the battle br_att, br_def, br_t, br_pct (shown: br_shown)
battle:
            ld a, (br_shown)
            or a
            jp z, battle_auto
            call battle_shown
            push af
            call redraw_map
            pop af
            ret

; ------------------------------------------------------------------ the battle the player is in (57BB)

; The player's battle: br_att attacks territory br_t of br_def, br_pct the
; castle's protection. The tactic (Ferocious Attack, Stand and Fight, Bombard,
; Outflank, Retreat!) is chosen with Up, Down and Enter; a round takes 28
; ticks, in which the men are animated (Ba items 160-181). A = the result.
battle_shown:
            ld a, (br_t)            ; no men defend it: 4
            call garrison_ofs
            push hl
            ld c, A_SOLDIERS
            call rec_w
            ex (sp), hl
            ld c, A_KNIGHTS
            call rec_w
            pop de
            add hl, de
            dec hl
            bit 7, h
            jp z, bt_men
            call redraw_map
            ld a, (DSEG + D_PLAYER)
            ld hl, br_att
            cp (hl)
            jp nz, bt_nomen
            ld hl, $3607
            call dialog
bt_nomen:
            ld a, $9C
            ld hl, (DSEG + D_TUNE_STOP)
            call play_tune
            ld a, 4
            ret
bt_men:
            ld hl, (DSEG + D_SIEGE_SHOWN)   ; (a siege has said it already)
            ld a, h
            or l
            jp nz, bt_field
            call redraw_map
            ld a, (DSEG + D_PLAYER)
            ld hl, br_att
            cp (hl)
            jp nz, bt_attacked
            ld a, (br_def)          ; the player attacks: its army there, or its garrison
            call army_ofs
            call dsw
            ld a, (br_t)
            cp l
            ld hl, $4150
            jp z, bt_which
            ld hl, $4171
bt_which:
            ld de, $221F
            call line_str
            push hl
            ld a, (br_def)
            ld c, S_NAME
            call side_w
            pop de
            call str_append
            ld hl, $2212
            call dialog
            jp bt_tune
bt_attacked:
            ld hl, $4192            ; the attacker's name; the territory's: taken with the
            ld de, $2294            ; defender's side number (AB 58D1)
            call line_str
            push hl
            ld a, (br_att)
            ld c, S_NAME
            call side_w
            pop de
            call str_append
            ld hl, $41AC
            ld de, $2296
            call line_str
            push hl
            ld a, (br_def)
            call terr_ofs
            call dsw
            pop de
            call str_append
            ld hl, $2287
            call dialog
bt_tune:
            ld a, $9C
            ld hl, (DSEG + D_TUNE_LOOP)
            call play_tune
bt_field:
            ld hl, 0
            ld (DSEG + D_MAP_SHOWN), hl
            ld (DSEG + D_SIEGE_SHOWN), hl
            call clear_back
            ld hl, $3582
            call dialog
            ld a, 4                 ; the last tactic: Retreat
            ld (bt_last), a
            ld a, (br_t)            ; l4 the enemy's men, l2 the player's
            call garrison_ofs
            ld (bt_l4), hl
            ld a, (br_att)
            call army_ofs
            ld (bt_l2), hl
            ld a, (DSEG + D_PLAYER)
            ld hl, br_def
            cp (hl)
            jp nz, bt_sides
            ld hl, (bt_l4)
            ld de, (bt_l2)
            ld (bt_l4), de
            ld (bt_l2), hl
            ld c, A_AT              ; no retreat but with its army there, away from home
            call army_w
            ld a, (br_t)
            cp l
            jp nz, bt_last3
            ld c, S_HOME
            call player_w
            ld a, (br_t)
            cp l
            jp nz, bt_sides
bt_last3:
            ld a, 3
            ld (bt_last), a
bt_sides:
            ld hl, 1
            ld (DSEG + $0B50), hl
            call show_armies
            ld a, 1
            ld (bt_chosen), a
            ld (bt_shown), a
            ld (bt_sel), a
            call flush_keys
            ld a, (DSEG + $3583)    ; the bar: line 1 (Stand and Fight), chosen
            add a, 22
            ld (bt_hy), a
            call bt_cursor
            ld a, (bt_hy)
            call bt_chosen_bar
            ld a, 3
            ld (bt_group), a
            ld a, 75
            ld (bt_menn), a
            ld a, 30
            ld (bt_kn), a
            ld hl, (bt_l4)
            ld c, A_SOLDIERS
            call rec_w
            ld (bt_l34), hl
            ld hl, (bt_l2)
            ld c, A_SOLDIERS
            call rec_w
            ld (bt_l32), hl
            ld hl, (bt_l4)
            ld c, A_KNIGHTS
            call rec_w
            ld (bt_l30), hl
            ld hl, (bt_l2)
            ld c, A_KNIGHTS
            call rec_w
            ld (bt_l28), hl
            ld hl, (bios_ticks)     ; (the first frame at once)
            dec hl
            ld (bt_tick), hl
bt_round:
            ld a, (bt_chosen)
            inc a
            call round_and_losses
            ld a, 28
            ld (bt_frames), a
bt_frame:
            call get_key
            or a
            jp z, bt_time
            cp KEY_ENTER
            jp nz, bt_up
            ld a, (bt_chosen)       ; Enter: the tactic under the cursor chosen
            ld hl, bt_sel
            cp (hl)
            jp z, bt_moved
            call bt_line_y
            call bt_chosen_bar
            ld a, (bt_sel)
            ld (bt_chosen), a
            ld a, (bt_hy)
            call bt_chosen_bar
            jp bt_moved
bt_up:
            cp KEY_UP
            jp nz, bt_down
            ld a, (bt_sel)
            dec a
            jp p, bt_sel_set
            ld a, (bt_last)
            jp bt_sel_set
bt_down:
            cp KEY_DOWN
            jp nz, bt_moved
            ld a, (bt_sel)
            inc a
            ld hl, bt_last
            cp (hl)
            jp c, bt_sel_set
            jp z, bt_sel_set
            xor a
bt_sel_set:
            ld (bt_sel), a
bt_moved:
            ld a, (bt_sel)          ; the cursor follows
            ld hl, bt_shown
            cp (hl)
            jp z, bt_time
            ld (hl), a
            ld a, (bt_hy)
            call bt_cursor
            ld a, (bt_sel)
            call bt_line_y
            ld (bt_hy), a
            call bt_cursor
bt_time:
            ld hl, (bios_ticks)     ; a tick: the men move
            ld de, (bt_tick)
            or a
            sbc hl, de
            jp z, bt_draw
            add hl, de
            ld (bt_tick), hl
            ld hl, bt_frames
            dec (hl)
            call bt_animate
bt_draw:
            call sprites_draw
            call present
            call sprites_erase
            ld a, (bt_frames)
            or a
            jp nz, bt_frame
            call slots_off          ; the round's end
            ld hl, 0
            ld (DSEG + $0B50), hl
            ld hl, (bt_l4)          ; no men: no catapults
            call bt_no_men
            ld hl, (bt_l2)
            call bt_no_men
            call show_armies
            ld a, (bt_chosen)
            cp 4
            jp nz, bt_both
            ld a, -3                ; Retreat
            ld (bt_morale), a
            ld a, (br_t)
            call terr_owner
            ld hl, DSEG + D_PLAYER
            cp (hl)
            ld a, 6
            jp nz, bt_over
            ld a, (br_t)
            call garrison_ofs
            push hl
            ld a, (DSEG + D_PLAYER)
            call army_ofs
            ex de, hl
            pop hl
            call army_merge
            ld a, (DSEG + D_PLAYER)
            call o_army_settle
            ld a, 4
            jp bt_over
bt_both:
            ld a, (br_t)
            call garrison_ofs
            call army_empty
            ld c, 0
            jp nz, bt_att
            inc c
bt_att:
            push bc
            ld a, (br_att)
            call army_ofs
            call army_empty
            pop bc
            jp nz, bt_att_men
            ld a, c
            or a
            jp z, bt_def_won
            ld a, -1                ; both gone
            ld (bt_morale), a
            ld a, 7
            jp bt_over
bt_def_won:
            ld b, 3                 ; the defenders win: good for the player if his
            ld a, 5
            jp bt_morale_of
bt_att_men:
            ld a, c
            or a
            jp z, bt_round
            ld b, -3                ; the attackers win
            ld a, 4
bt_morale_of:
            ld (bt_r), a
            ld a, (DSEG + D_PLAYER)
            ld hl, br_def
            cp (hl)
            ld a, b
            jp z, bt_mset
            neg
bt_mset:
            ld (bt_morale), a
            ld a, (bt_r)
bt_over:
            ld (bt_r), a
            ld a, (bt_morale)       ; 9464: morale, kept within 1-50
            call sx_a
            ld de, (DSEG + D_MORALE)
            add hl, de
            ld a, h
            or a
            jp m, bt_m_one
            jp nz, bt_m_fifty
            ld a, l
            or a
            jp z, bt_m_one
            cp 51
            jp c, bt_m_set
bt_m_fifty:
            ld hl, 50
            jp bt_m_set
bt_m_one:
            ld hl, 1
bt_m_set:
            ld (DSEG + D_MORALE), hl
            ld hl, 27
            call wait_ticks
            ld a, $9C
            ld hl, (DSEG + D_TUNE_STOP)
            call play_tune
            ld a, (bt_r)
            ret

; army HL: no soldiers and no knights, no catapults
bt_no_men:
            push hl
            call army_empty
            pop hl
            ret nz
            ld c, A_CATAPULTS
            ld de, 0
            jp rec_sw

; A = line A's y: (A + 1) x 11 + y0
bt_line_y:
            inc a
            ld c, a
            add a, a
            add a, a
            add a, a
            add a, c
            add a, c
            add a, c
            ld hl, DSEG + $3583
            add a, (hl)
            ret

; the cursor's bar (XOR FFh) and the chosen tactic's (XOR 88h) at line y A
bt_cursor:
            ld c, $FF
            jp bt_bar
bt_chosen_bar:
            ld c, $88
bt_bar:
            ld (rc_y), a
            ld a, 11
            ld (rc_h), a
            ld a, (DSEG + $3582)
            add a, 4
            ld (rc_x), a
            ld a, (DSEG + $3585)
            sub 8
            ld (rc_w), a
            ld a, c
            jp xor_rect

; a tick of the battle: the men of each side by groups (3 of them, a tick each)
bt_animate:
            ld a, (bt_menn)
            sub 25
            ld (bt_menn), a
            ld a, (bt_kn)
            sub 10
            ld (bt_kn), a
            ld a, (bt_group)
            dec a
            jp p, ba_group
            ld a, 50
            ld (bt_menn), a
            ld a, 20
            ld (bt_kn), a
            ld a, 2
ba_group:
            ld (bt_group), a
            ld a, 4                 ; the two sides' men's poses
            call random_n
            ld a, l
            add a, 160
            ld (bt_l22), a
            ld a, 4
            call random_n
            ld a, l
            add a, 170
            ld (bt_l20), a
            ld a, (bt_group)
            cp 2
            jp nc, ba_men
            ld hl, (bt_l2)          ; the knights
            ld c, A_KNIGHTS
            call rec_w
            ld de, $0B34
            ld ix, bt_l28
            ld b, 180
            call ba_knight
            ld hl, (bt_l4)
            ld c, A_KNIGHTS
            call rec_w
            ld de, $0B3A
            ld ix, bt_l30
            ld b, 181
            call ba_knight
ba_men:
            ld hl, (bt_l2)          ; the player's men
            ld c, A_SOLDIERS
            call rec_w
            call ba_more
            jp c, ba_mine_fewer
            ld a, 9                 ; slot 9 + group: legs (165), 6 + group: the men
            ld de, $0B40
            ld b, 165
            ld c, 0
            ld l, 24
            call ba_slot
            ld a, 6
            ld de, $0B40
            ld a, (bt_l22)
            ld b, a
            ld a, 6
            ld c, 0
            ld l, 0
            call ba_slot
            jp ba_theirs
ba_mine_fewer:
            ld hl, (bt_l32)
            call ba_more
            jp c, ba_theirs
            ld a, (bt_menn)
            ld l, a
            ld h, 0
            ld (bt_l32), hl
            ld a, 6
            ld de, $0B40
            ld b, 169
            ld c, 0
            ld l, 32
            call ba_slot
ba_theirs:
            ld hl, (bt_l4)          ; the enemy's
            ld c, A_SOLDIERS
            call rec_w
            call ba_more
            jp c, ba_theirs_fewer
            ld a, 3
            ld de, $0B46
            ld b, 175
            ld c, 8
            ld l, 24
            call ba_slot
            ld a, (bt_l20)
            ld b, a
            xor a
            ld de, $0B46
            ld c, 0
            ld l, 0
            jp ba_slot
ba_theirs_fewer:
            ld hl, (bt_l34)
            call ba_more
            ret c
            ld a, (bt_menn)
            ld l, a
            ld h, 0
            ld (bt_l34), hl
            xor a
            ld de, $0B46
            ld b, 179
            ld c, 0
            ld l, 32
            jp ba_slot

; NC if HL (men, >= 0) is more than bt_menn
ba_more:
            ld a, h
            or a
            ret nz
            ld a, (bt_menn)
            cp l
            ccf
            ret nz                  ; (l > men: NC)
            scf
            ret

; knights HL (the army's) at the place at DS:DE + 2 x group: put whole while
; more than bt_kn; else, once, XORed off (its count in the word at IX)
ba_knight:
            ld a, h
            or a
            jp nz, bk_put
            ld a, (bt_kn)
            cp l
            jp c, bk_put
            ld l, (ix + 0)          ; the count shown: more than bt_kn?
            ld h, (ix + 1)
            ld a, h
            or a
            jp nz, bk_xor
            ld a, (bt_kn)
            cp l
            ret nc
bk_xor:
            ld a, (bt_kn)
            ld (ix + 0), a
            ld (ix + 1), 0
            call ba_place
            ld a, b
            ld c, SWORD_PAGE
            jp xor_sprite
bk_put:
            call ba_place
            ld a, b
            ld c, SWORD_PAGE
            jp put_sprite
; HL = byte [DS:DE + 2 x group] (4-pixel units), E = the next byte (B kept)
ba_place:
            ld a, (bt_group)
            add a, a
            ld l, a
            ld h, 0
            add hl, de
            ld de, DSEG
            add hl, de
            ld a, (hl)
            inc hl
            ld e, (hl)
            ld l, a
            ld h, 0
            ret

; slot A + group: item B at the place at DS:DE + 2 x group, (x + C) x 4 pixels, y + L
ba_slot:
            push bc
            push hl
            ld hl, bt_group
            add a, (hl)
            ld (ba_k), a
            call ba_place
            pop bc                  ; C: the lines down
            ld a, e
            add a, c
            ld e, a
            pop bc                  ; B: the item, C: the units across
            ld a, l
            add a, c
            ld l, a
            add hl, hl
            add hl, hl
            ld a, (ba_k)
            ld c, SWORD_PAGE
            jp slot_set

; 5684: "Your Army / Enemy Army" with the numbers (bt_l2 the player's, bt_l4
; the enemy's); the space drawn as the font's '>' while the lines are put
show_armies:
            ld a, ' '
            ld (glyph_from), a
            ld a, '>'
            ld (glyph_to), a
            ld ix, sm_lines
            ld b, 3
sm_line:
            push bc
            ld l, (ix + 0)          ; bx: the line
            ld h, (ix + 1)
            call dsw
            ld (sm_bx), hl
            call dsp
            ld (hl), ' '
            inc hl
            ld (hl), ' '
            ld hl, (bt_l2)
            ld c, (ix + 4)
            call rec_w
            ld de, (sm_bx)
            inc de
            inc de
            call num_append
            ex de, hl
            ld l, (ix + 2)
            ld h, (ix + 3)
            call str_append
            push hl
            ld hl, (bt_l4)
            ld c, (ix + 4)
            call rec_w
            pop de
            call num_append
            call dsp
            ld (hl), '>'
            inc hl
            ld (hl), 0
            ld de, 5
            add ix, de
            pop bc
            djnz sm_line
            ld hl, $35D2
            call dialog
            xor a
            ld (glyph_from), a
            ret
sm_lines:   dw $35DF, $4118         ; the line's pointer, the text between the numbers, the field
            db A_SOLDIERS
            dw $35E1, $412B
            db A_KNIGHTS
            dw $35E3, $413E
            db A_CATAPULTS

; ------------------------------------------------------------------ sieges (78A9)

; 78A9: a computer lord besieges a castle: A = the result
siege_of_player:
            ld a, (br_att)
            call army_ofs
            ld c, A_CATAPULTS
            call rec_w
            ld a, h
            or l
            ld a, 6
            ret z
            ld a, (DSEG + D_PLAYER)
            ld hl, br_def
            cp (hl)
            jp nz, sq_besiege
            ld a, 1
            ld (DSEG + D_SIEGE_SHOWN), a
            xor a
            ld (DSEG + D_SIEGE_SHOWN + 1), a
            ld a, $9C
            ld hl, (DSEG + D_TUNE_LOOP)
            call play_tune
            ld c, S_HOME
            call player_w
            ld a, (br_t)
            cp l
            jp nz, sq_other
            ld hl, $4238            ; "... besieges your home": the attacker's name
            ld de, $29B6
            call line_str
            push hl
            ld a, (br_att)
            ld c, S_NAME
            call side_w
            pop de
            call str_append
            ld hl, $29A9
            call dialog
            jp sq_besiege
sq_other:
            ld hl, $4261            ; the territory's name, the attacker's
            ld de, $2A5E
            call line_str
            push hl
            ld a, (br_t)
            call terr_ofs
            call dsw
            pop de
            call str_append
            ld hl, $4290
            ld de, $2A60
            call line_str
            push hl
            ld a, (br_att)
            ld c, S_NAME
            call side_w
            pop de
            call str_append
            ld hl, $2A51
            call dialog
sq_besiege:
            ld a, 3                 ; the protection: 90 - (random_n(3) + 3) x 15
            call random_n
            ld a, l
            add a, 3
            ld l, a
            ld h, 0
            ld a, 15
            call mul_a
            ex de, hl
            ld hl, 90
            or a
            sbc hl, de
            ld a, l
            ld (br_pct), a
            ld a, (br_t)            ; the garrison loses soldiers / (random_n(7) + 2), at least 1
            call garrison_ofs
            ld de, A_SOLDIERS
            add hl, de
            ld (sq_at), hl
            call dsw
            ld (sq_n), hl
            ld a, 7
            call random_n
            inc hl
            inc hl
            ex de, hl
            ld hl, (sq_n)
            call sdiv
            ld a, h
            or l
            jp nz, sq_lost
            inc hl
sq_lost:
            ld (sq_lost_n), hl
            ex de, hl
            ld hl, (sq_n)
            or a
            sbc hl, de
            dec hl
            bit 7, h
            inc hl
            jp z, sq_left
            ld hl, 1
sq_left:
            ex de, hl
            ld hl, (sq_at)
            call dssw
            ld a, (DSEG + D_PLAYER)
            ld hl, br_def
            cp (hl)
            jp nz, battle
            call redraw_map         ; "Your castle strength is n percent. m men were killed..."
            ld hl, $42AA
            ld de, $2A97
            call line_str
            ex de, hl
            ld a, (br_pct)
            ld l, a
            ld h, 0
            call num_append
            ex de, hl
            ld hl, $42C3
            call str_append
            ld hl, (sq_lost_n)
            ld a, h
            or a
            jp nz, sq_many
            ld a, l
            cp 1
            jp nz, sq_many
            ld hl, $42CD
            ld de, $2A99
            call line_str
            jp sq_shown
sq_many:
            ld hl, $2A99
            call dsw
            ex de, hl
            ld hl, (sq_lost_n)
            call num_append
            ex de, hl
            ld hl, $42F2
            call str_append
sq_shown:
            ld hl, $2A8A
            call dialog
            jp battle

; 331C: entering the land of one of the other Saxons whose enmity to the
; player is 0 or less: "Do you seek safe passage through my land?" Accept: NZ
; (the army passes). Attack: Z, and both Saxons +5 against the player.
ask_passage:
            ld a, (br_t)
            call terr_owner
            ld (ap_si), a
            cp 4                    ; (unsigned: nobody's is FFh)
            jp nc, ap_no
            ld hl, DSEG + D_PLAYER
            cp (hl)
            jp z, ap_no
            ld c, a                 ; ENMITY(si, p) > 0: no
            ld a, (DSEG + D_PLAYER)
            call enmity_ofs
            call dsw
            dec hl
            bit 7, h
            jp z, ap_no
            call redraw_map
            ld a, (ap_si)
            ld c, S_PORTRAIT
            call side_w
            ld a, l
            ld b, 9
            ld c, 3
            call show_portrait
            ld a, (ap_si)
            ld c, S_NAME
            call side_w
            ld (DSEG + $2F64), hl
            ld a, 1
            ld (DSEG + $2F59), a
            ld hl, $2F59
            call dialog
            ld hl, $36CC
            call dialog
            cp 1
            jp z, ap_yes
            ld a, (DSEG + D_PLAYER)
            ld c, a
            ld a, 2
            ld b, 5
            call enmity_add
            ld a, (DSEG + D_PLAYER)
            ld c, a
            ld a, 3
            ld b, 5
            call enmity_add
ap_no:
            xor a
            ret
ap_yes:
            or a
            ret

; 763E: the player besieges a castle: without a catapult, back (3); else the
; bombardment (ov_siege), then the battle at the castle's protection
siege_by_player:
            call redraw_map
            ld c, A_CATAPULTS
            call army_w
            ld a, h
            or l
            jp nz, sbp_siege
            ld hl, $295E
            call dialog
            ld a, 3
            ret
sbp_siege:
            ld a, (br_t)
            call bombard
            ld (br_pct), a
            ld a, 1
            ld (br_shown), a
            jp battle

; the siege's state, then the siege
siege:
            ld hl, 6
            ld (DSEG + $0A82), hl
            ld (DSEG + $0A88), hl
            ld (DSEG + $0A8A), hl
            ld hl, 2
            ld (DSEG + $0A8C), hl
            ld (DSEG + $0A8E), hl
            ld hl, 1
            ld (DSEG + $0A86), hl
            ld a, (DSEG + D_PLAYER)
            ld hl, br_att
            cp (hl)
            jp z, siege_by_player
            jp siege_of_player

; ------------------------------------------------------------------ attack (31D5)

; 33E5: the result A of br_att's attack on br_t, of br_def
apply_result:
            cp 2
            jp z, ar_2
            cp 3
            jp z, ar_36
            cp 6
            jp z, ar_36
            cp 4
            jp z, ar_4
            cp 5
            jp z, ar_5
            cp 7
            jp z, ar_7
            ret
ar_2:
            ld a, (br_t)
            ld c, a
            ld a, (br_att)
            jp set_owner
ar_36:
            ld a, (br_att)
            jp o_army_settle
ar_4:
            call ar_enmity
            ld c, S_HOME
            call player_w
            ld a, (br_t)
            cp l
            jp z, ar_4_home
            ld c, a
            ld a, (br_att)
            call set_owner
ar_4_home:
            ld a, (br_def)
            ld c, S_HOME
            call side_w
            ld a, (br_t)
            cp l
            jp nz, ar_4_garrison
            ld a, (br_att)
            ld c, a
            ld a, (br_def)
            call o_side_falls
            ld a, (br_def)
            ld c, S_AT
            ld de, $FFFF
            call side_sw
            ld a, (br_def)
            call army_ofs
            push hl
            ld de, $FFFF
            call dssw
            pop hl
            ld de, A_SOLDIERS
            add hl, de
            call dsp
            ld b, 6
            xor a
ar_4_zero:
            ld (hl), a
            inc hl
            djnz ar_4_zero
ar_4_garrison:
            ld a, (br_t)
            call garrison_ofs
            ld c, A_CATAPULTS
            ld de, 0
            call rec_sw
            ld a, (br_att)
            ld c, a
            ld a, (br_t)
            jp send_others_home
ar_5:
            call ar_enmity
            ld a, (br_att)
            call army_ofs
            ld c, A_CATAPULTS
            ld de, 0
            call rec_sw
            ld a, (br_att)
            call army_go_home
            ld a, (br_def)
            call army_ofs
            push hl
            call dsw
            ld a, (br_t)
            cp l
            pop de
            ret nz
            push de
            ld a, (br_t)
            call garrison_ofs
            pop de
            jp army_merge
ar_7:
            call ar_enmity
            ld a, (br_att)
            call army_ofs
            ld c, A_CATAPULTS
            ld de, 0
            call rec_sw
            ld a, (br_t)
            call garrison_ofs
            ld c, A_CATAPULTS
            ld de, 0
            call rec_sw
            ld a, (br_t)
            call send_home_at
            ld a, (br_def)
            ld c, S_HOME
            call side_w
            ld a, (br_t)
            cp l
            ret z
            ld c, a
            ld a, $FF
            jp set_owner
ar_enmity:
            ld a, (br_att)
            ld c, a
            ld a, (br_def)
            ld b, 6
            jp enmity_add

; 31D5: side A attacks territory B, of side C: A = the result
o_attack:
            ld (br_att), a
            ld a, c
            ld (br_def), a
            ld a, b
            ld (br_t), a
            xor a
            ld (br_pct), a
            ld (br_shown), a
            ld a, (br_att)          ; no army, and not its own: back
            call army_ofs
            call strength
            ld a, h
            or l
            jp nz, at_army
            ld a, (br_t)
            call terr_owner
            ld hl, br_att
            cp (hl)
            ld a, 6
            ret nz                  ; (without apply_result)
at_army:
            ld a, (DSEG + D_PLAYER) ; shown: the player's attack, or the player's castle or army attacked
            ld hl, br_att
            cp (hl)
            jp z, at_shown
            ld hl, br_def
            cp (hl)
            jp nz, at_which
            ld a, (br_t)
            ld c, T_CASTLE
            call terr_byte
            or a
            jp nz, at_shown
            ld c, S_AT
            call player_w
            ld a, (br_t)
            cp l
            jp nz, at_which
at_shown:
            ld a, 1
            ld (br_shown), a
at_which:
            ld a, (DSEG + D_PLAYER) ; the player's march: safe passage through a friendly Saxon's land
            ld hl, br_att
            cp (hl)
            jp nz, at_owner
            call ask_passage
            ld a, 8
            jp nz, at_done
at_owner:
            ld a, (br_t)
            call terr_owner
            ld hl, br_att
            cp (hl)
            ld a, 1
            jp z, at_done
            ld a, (br_t)
            call terr_owner
            cp $FF
            ld a, 2
            jp z, at_done
            ld a, (br_def)          ; the defending army joins the garrison
            call army_ofs
            push hl
            call dsw
            ld a, (br_t)
            cp l
            pop hl
            jp nz, at_castle
            ld a, (br_t)
            push hl
            call garrison_ofs
            ex de, hl
            pop hl
            call army_merge
at_castle:
            ld a, (br_t)
            ld c, T_CASTLE
            call terr_byte
            or a
            jp z, at_battle
            call siege
            jp at_done
at_battle:
            call battle
at_done:
            ld (at_r), a
            call apply_result
            ld a, (at_r)
            ret

; ------------------------------------------------------------------ the target (2704, 28B8, 2803)

; 2704: HL = the value to side ai_side of territory A, B steps away (FFFFh: never)
target_value:
            ld (tv_t), a
            ld a, b
            ld (tv_steps), a
            ld a, (tv_t)
            or a
            jp z, tv_never
            call terr_owner
            ld (tv_owner), a
            ld hl, ai_side
            cp (hl)
            jp z, tv_never
            cp $FF
            jp nz, tv_owned
            ld a, (tv_steps)        ; nobody's: 1000 - steps
            ld e, a
            ld d, 0
            ld hl, 1000
            or a
            sbc hl, de
            ret
tv_owned:
            ld a, (tv_owner)        ; the enmity: 0, never
            ld c, a
            ld a, (ai_side)
            ld b, a
            ld a, c
            ld c, b
            call enmity_ofs         ; ENMITY(side, owner)
            call dsw
            ld (tv_enmity), hl
            ld a, h
            or l
            jp z, tv_never
            ld a, (ai_side)
            call army_ofs
            call strength
            ld (tv_own), hl
            ld a, (tv_t)
            call garrison_ofs
            call strength
            ld (tv_def), hl
            ld a, (tv_owner)        ; its owner's campaign army there too
            call army_ofs
            push hl
            call dsw
            ld a, (tv_t)
            cp l
            pop hl
            jp nz, tv_castle
            ld a, h                 ; (A_AT's high byte: 0)
            call strength
            ld de, (tv_def)
            add hl, de
            ld (tv_def), hl
tv_castle:
            ld hl, (tv_own)         ; own - def + enmity
            ld de, (tv_def)
            or a
            sbc hl, de
            ld de, (tv_enmity)
            add hl, de
            push hl
            ld a, (tv_t)
            ld c, T_CASTLE
            call terr_byte
            pop hl
            or a
            ret z
            push hl                 ; a castle: no catapult, never; else (def / 2 + own - def + enmity) x 3
            ld a, (ai_side)
            call army_ofs
            ld c, A_CATAPULTS
            call rec_w
            ld a, h
            or l
            pop hl
            jp z, tv_never
            push hl
            ld hl, (tv_def)
            ld de, 2
            call sdiv
            pop de
            add hl, de
            ld d, h
            ld e, l
            add hl, hl
            add hl, de
            ret
tv_never:
            ld hl, $FFFF
            ret

; 28B8: from territory A, B steps from the army, through the side's own
; territories (depth first, up to 4 steps): each other territory reached the
; first time gets its value; the best (compared unsigned, as AB 2957's jbe)
; is kept, with the way to it (here: as_path, 5 words a level)
ai_search:
            ld c, a
            ld a, b
            cp 4
            ret nc
            ld (as_d), a
            ld a, c
            ld (as_t), a
            ld a, (as_d)            ; here = the path given (the level above's)
            or a
            jp z, as_seen
            call as_level
            ld d, h
            ld e, l
            ld bc, -10
            add hl, bc
            ld bc, 10
            ldir
as_seen:
            ld a, (as_t)
            call as_mark
            xor a
as_nb:
            ld (as_i), a
            ld a, (as_t)            ; nb = TERR(t)'s neighbour i
            call terr_ofs
            ld a, (as_i)
            add a, T_NB
            ld e, a
            ld d, 0
            add hl, de
            call dsp
            ld a, (hl)
            or a
            jp z, as_next
            ld (as_n), a
            call as_seen_w
            jp nz, as_next
            ld a, (as_n)
            call terr_owner
            ld hl, ai_side
            cp (hl)
            jp nz, as_other
            call as_level           ; its own: here[depth + 1] = nb, and on from it
            ld a, (as_d)
            inc a
            add a, a
            ld e, a
            ld d, 0
            add hl, de
            ld a, (as_n)
            ld (hl), a
            inc hl
            ld (hl), 0
            ld a, (as_t)
            ld h, a
            ld a, (as_i)
            ld l, a
            push hl
            ld a, (as_d)
            push af
            inc a
            ld b, a
            ld a, (as_n)
            call ai_search
            pop af
            ld (as_d), a
            pop hl
            ld a, h
            ld (as_t), a
            ld a, l
            ld (as_i), a
            jp as_next
as_other:
            ld a, (as_n)
            call as_mark
            ld a, (as_d)
            ld b, a
            ld a, (as_n)
            call target_value
            ld a, h                 ; -1: never
            and l
            inc a
            jp z, as_next
            ex de, hl               ; better (unsigned) than the best so far?
            ld hl, (DSEG + D_SEARCH_BEST)
            or a
            sbc hl, de
            jp nc, as_next
            ld (DSEG + D_SEARCH_BEST), de
            ld a, (as_n)
            ld l, a
            ld h, 0
            ld (DSEG + D_SEARCH_TARGET), hl
            call as_level
            ld de, DSEG + D_SEARCH_PATH
            ld bc, 10
            ldir
as_next:
            ld a, (as_i)
            inc a
            cp 7
            jp c, as_nb
            ret
; HL = level as_d's path
as_level:
            ld a, (as_d)
            ld l, a
            add a, a
            add a, a
            add a, l
            add a, a
            ld l, a
            ld h, 0
            ld de, as_path
            add hl, de
            ret
; territory A seen
as_mark:
            call as_seen_at
            ld (hl), 1
            inc hl
            ld (hl), 0
            ret
; NZ if territory as_n has been seen
as_seen_w:
            ld a, (as_n)
            call as_seen_at
            ld a, (hl)
            inc hl
            or (hl)
            ret
as_seen_at:
            add a, a
            ld l, a
            ld h, 0
            ld de, DSEG + D_SEARCH_SEEN
            add hl, de
            ret

; 2803: NZ if side ai_side has a target (in D_SEARCH_TARGET)
ai_find_target:
            ld a, (ai_side)
            call army_ofs
            call strength
            ld a, h
            or l
            ret z
            ld hl, DSEG + D_SEARCH_SEEN
            ld b, 38
            xor a
ft_clear:
            ld (hl), a
            inc hl
            djnz ft_clear
            ld hl, as_path          ; start: the army's place, then 0s
            ld b, 10
ft_start:
            ld (hl), a
            inc hl
            djnz ft_start
            ld a, (ai_side)
            ld c, S_AT
            call side_w
            ld (as_path), hl
            ld (ft_at), hl
            ld hl, 0
            ld (DSEG + D_SEARCH_BEST), hl
            ld (DSEG + D_SEARCH_TARGET), hl
            ld a, (ft_at)
            ld b, 0
            call ai_search
            ld hl, (DSEG + D_SEARCH_TARGET)
            ld a, h
            or l
            ret

; ------------------------------------------------------------------ buying (2A3C, 2A9E)

; 2A3C: A = side ai_side's territory without a castle with the highest income (0: none)
best_site:
            xor a
            ld (bs_di), a
bs_terr:
            ld (bs_si), a
            call terr_owner
            ld hl, ai_side
            cp (hl)
            jp nz, bs_next
            ld a, (bs_si)
            ld c, T_CASTLE
            call terr_byte
            or a
            jp nz, bs_next
            ld a, (bs_di)
            or a
            jp z, bs_take
            ld c, T_INCOME
            call terr_byte
            ld (bs_inc), a
            ld a, (bs_si)
            ld c, T_INCOME
            call terr_byte
            ld hl, bs_inc           ; signed: income(si) > income(di)
            sub (hl)
            jp z, bs_next
            jp po, bs_cmp
            xor $80
bs_cmp:
            jp m, bs_next
bs_take:
            ld a, (bs_si)
            ld (bs_di), a
bs_next:
            ld a, (bs_si)
            inc a
            cp 19
            jp c, bs_terr
            ld a, (bs_di)
            ret

; 2A9E. Whether it has a catapult is read from its campaign army and the
; garrison of the territory numbered as its side (AB 2AD1)
ai_buy:
            ld a, (ai_side)
            ld c, S_HOME
            call side_w
            ld a, l
            ld (ab_home), a
            ld a, (ai_side)
            call army_ofs
            ld c, A_CATAPULTS
            call rec_w
            push hl
            ld a, (ai_side)
            call garrison_ofs
            ld c, A_CATAPULTS
            call rec_w
            pop de
            add hl, de
            dec hl
            bit 7, h
            jp z, ab_spend
            ld a, (ai_side)         ; none: one for 15 gold, or nothing
            ld c, S_GOLD
            call side_w
            ld de, 15
            or a
            sbc hl, de
            ret m
            ex de, hl
            ld a, (ai_side)
            ld c, S_GOLD
            call side_sw
            ld a, (ab_home)
            call garrison_ofs
            ld c, A_CATAPULTS
            push hl
            call rec_w
            inc hl
            ex de, hl
            pop hl
            ld c, A_CATAPULTS
            call rec_sw
ab_spend:
            ld a, (ai_side)         ; spend = spending x gold / 10
            ld c, S_GOLD
            call side_w
            ld (ab_gold), hl
            ld a, (ai_side)
            ld c, S_SPEND
            call side_w
            ld a, l
            ld hl, (ab_gold)
            call mul_a
            ld de, 10
            call sdiv
            ld (ab_spend_n), hl
            ex de, hl
            ld hl, (ab_gold)
            or a
            sbc hl, de
            ex de, hl
            ld a, (ai_side)
            ld c, S_GOLD
            call side_sw
            ld hl, (ab_spend_n)     ; knights = (spend / 2) / 8, the rest soldiers
            ld de, 2
            call sdiv
            ld de, 8
            call sdiv
            ld (ab_knights), hl
            ld a, (ab_home)
            ld c, A_KNIGHTS
            call ab_add
            ld hl, (ab_knights)
            add hl, hl
            add hl, hl
            add hl, hl
            ex de, hl
            ld hl, (ab_spend_n)
            or a
            sbc hl, de
            ld (ab_knights), hl
            ld a, (ab_home)
            ld c, A_SOLDIERS
            call ab_add
ab_castles:
            ld a, (ai_side)         ; castles, 20 gold each, while there is a site
            ld c, S_GOLD
            call side_w
            ld de, 20
            or a
            sbc hl, de
            jp m, ab_join
            push hl
            call best_site
            pop de
            or a
            jp z, ab_join
            ld (ab_site), a
            push de
            ld a, (ab_site)
            call terr_ofs
            ld de, DSEG + T_CASTLE
            add hl, de
            ld (hl), 35
            ld hl, 10
            ld (ab_knights), hl
            ld a, (ab_site)
            ld c, A_SOLDIERS
            call ab_add
            pop de
            ld a, (ai_side)
            ld c, S_GOLD
            call side_sw
            jp ab_castles
ab_join:
            ld a, (ai_side)         ; 80% of the men of the garrison where its army stands join it, and its catapults
            ld c, S_AT
            call side_w
            ld a, l
            call garrison_ofs
            ld (ab_g), hl
            ld a, (ai_side)
            call army_ofs
            ld (ab_a), hl
            ld c, A_SOLDIERS
            call ab_join80
            ld c, A_KNIGHTS
            call ab_join80
            ld hl, (ab_g)
            ld c, A_CATAPULTS
            call rec_w
            ld (ab_knights), hl
            ld hl, (ab_a)
            ld c, A_CATAPULTS
            call rec_w
            ld de, (ab_knights)
            add hl, de
            ex de, hl
            ld hl, (ab_a)
            ld c, A_CATAPULTS
            call rec_sw
            ld hl, (ab_g)
            ld c, A_CATAPULTS
            ld de, 0
            jp rec_sw
; field C of garrison A += ab_knights
ab_add:
            push bc
            call garrison_ofs
            pop bc
            push hl
            push bc
            call rec_w
            ld de, (ab_knights)
            add hl, de
            ex de, hl
            pop bc
            pop hl
            jp rec_sw
; field C: n = garrison's x 8 / 10 from ab_g to ab_a
ab_join80:
            ld a, c
            ld (ab_f), a
            ld hl, (ab_g)
            call rec_w
            push hl
            add hl, hl
            add hl, hl
            add hl, hl
            ld de, 10
            call div16
            ld (ab_n), hl
            pop de                  ; the garrison's less n
            ex de, hl
            or a
            sbc hl, de
            ex de, hl
            ld hl, (ab_g)
            ld a, (ab_f)
            ld c, a
            call rec_sw
            ld hl, (ab_a)
            ld a, (ab_f)
            ld c, a
            call rec_w
            ld de, (ab_n)
            add hl, de
            ex de, hl
            ld hl, (ab_a)
            ld a, (ab_f)
            ld c, a
            jp rec_sw

; ------------------------------------------------------------------ raids (43F6, 4428)

; 4428: a Norman raids one of the three Saxons
ai_raid:
            ld a, 3                 ; 43F6: the victim, if its home stands
            call random_n
            ld a, l
            inc a
            ld (rd_si), a
            ld c, S_HOME
            call side_w
            ld a, l
            call terr_owner
            ld hl, rd_si
            cp (hl)
            ret nz
            ld c, a                 ; enmity +1
            ld a, (ai_side)
            ld b, 1
            call enmity_add
            ld a, (rd_si)           ; its lady, if the player has none, after 10 months: kidnapped
            ld c, S_LADY
            call side_w
            ld a, h
            and l
            inc a
            jp z, rd_gold
            ld (rd_lady), hl
            ld c, S_LADY
            call player_w
            ld a, h
            and l
            inc a
            jp nz, rd_gold
            ld hl, (DSEG + D_MONTH)
            ld de, 11
            or a
            sbc hl, de
            jp m, rd_gold
            ld hl, (rd_lady)
            ld (DSEG + D_KIDNAPPED), hl
            ld a, (ai_side)
            ld c, S_HOME
            call side_w
            ex de, hl
            ld a, (rd_lady)
            call lady_ofs
            ld bc, L_TERR
            add hl, bc
            jp dssw
rd_gold:
            ld a, (rd_si)           ; half its gold
            ld c, S_GOLD
            call side_w
            ld de, 2
            call sdiv
            ld a, h
            or l
            ret z
            ld (rd_n), hl
            ld a, (rd_si)
            ld c, S_GOLD
            call side_w
            ld de, (rd_n)
            or a
            sbc hl, de
            ex de, hl
            ld a, (rd_si)
            ld c, S_GOLD
            call side_sw
            ld a, (ai_side)
            ld c, S_GOLD
            call side_w
            ld de, (rd_n)
            add hl, de
            ex de, hl
            ld a, (ai_side)
            ld c, S_GOLD
            call side_sw
            ld a, (DSEG + D_PLAYER)
            ld hl, rd_si
            cp (hl)
            ret nz
            ld hl, $20BA
            call dialog
            jp redraw_map

; ------------------------------------------------------------------ the turn (2995)

; 2C60: men from the campaign army into the garrison where it is, when the
; garrison has fewer than half (at home) or a fifth (elsewhere) of its soldiers
ai_reinforce:
            ld a, (ai_side)
            call army_ofs
            ld (ri_a), hl
            call dsw
            ld a, l
            ld (ri_t), a
            ld hl, (ri_a)
            ld c, A_SOLDIERS
            call rec_w
            ld (ri_s), hl
            ld a, (ai_side)
            ld c, S_HOME
            call side_w
            ld a, (ri_t)
            cp l
            ld de, 2
            jp z, ri_div
            ld de, 5
ri_div:
            ld hl, (ri_s)
            call sdiv
            ld (ri_want), hl
            ld a, (ri_t)
            call garrison_ofs
            ld c, A_SOLDIERS
            call rec_w
            ld de, (ri_want)        ; garrison >= want (signed): nothing
            or a
            sbc hl, de
            jp p, ri_none
            ld hl, (ri_want)        ; di = want > 2 ? want : s > 2 ? 2 : 0
            ld de, 3
            or a
            sbc hl, de
            ld hl, (ri_want)
            jp p, ri_move
            ld hl, (ri_s)
            or a
            sbc hl, de
            ld hl, 2
            jp p, ri_move
            ld hl, 0
ri_move:
            ld (ri_di), hl
            ld hl, (ri_a)
            ld c, A_SOLDIERS
            call rec_w
            ld de, (ri_di)
            or a
            sbc hl, de
            ex de, hl
            ld hl, (ri_a)
            ld c, A_SOLDIERS
            call rec_sw
            ld a, (ri_t)
            call garrison_ofs
            push hl
            ld c, A_SOLDIERS
            call rec_w
            ld de, (ri_di)
            add hl, de
            ex de, hl
            pop hl
            ld c, A_SOLDIERS
            jp rec_sw
ri_none:
            ret

; DS:005B's bits after a step of the random numbers: Z if (D_RANDOM & A) is 0
ai_bits:
            push af
            call random_next
            pop af
            ld hl, DSEG + D_RANDOM
            and (hl)
            ret

; 2D84: A = the order: 9 go home, 4 buy, 2 conquest, 6 pass, 3 raid, 1 tournament
ai_choose_order:
            ld a, (ai_side)
            ld c, S_HOME
            call side_w
            push hl
            ld a, (ai_side)
            ld c, S_AT
            call side_w
            pop de
            or a
            sbc hl, de
            jp z, co_buy
            ld a, 3                 ; away: 1 in 4 home
            call ai_bits
            ld a, 9
            jp z, co_done
co_buy:
            ld a, (ai_side)         ; didn't buy last time: 1 in 4 buys
            add a, a
            ld l, a
            ld h, 0
            ld de, DSEG + D_LAST_ORDER
            add hl, de
            ld a, (hl)
            cp 4
            jp nz, co_buy2
            inc hl
            ld a, (hl)
            or a
            jp z, co_conquest
co_buy2:
            ld a, 3
            call ai_bits
            ld a, 4
            jp z, co_done
co_conquest:
            ld a, 7                 ; 7 in 8: conquest, if there's a target; else buy or pass
            call ai_bits
            jp z, co_eighth
            call ai_find_target
            ld a, 2
            jp nz, co_done
            ld a, 1
            call ai_bits
            ld a, 4
            jp nz, co_done
            ld a, 6
            jp co_done
co_eighth:
            ld a, (ai_side)         ; 1 in 8: a Norman raids; a Saxon after 1149 holds a tournament, or buys
            cp 4
            ld a, 3
            jp nc, co_done
            ld hl, (DSEG + D_YEAR)
            ld de, 1150
            or a
            sbc hl, de
            ld a, 1
            jp nc, co_done
            ld a, 4
co_done:
            ld (co_order), a
            ld a, (ai_side)
            add a, a
            ld l, a
            ld h, 0
            ld de, DSEG + D_LAST_ORDER
            add hl, de
            ld a, (co_order)
            ld (hl), a
            inc hl
            ld (hl), 0
            ret

; 2D10
ai_do_order:
            cp 1
            jp z, do_tournament
            cp 2
            jp z, do_conquest
            cp 3
            jp z, ai_raid
            cp 4
            jp z, ai_buy
            cp 9
            ret nz
            ld a, (ai_side)
            jp army_go_home
do_tournament:
            ld a, (ai_side)
            jp tournament
do_conquest:
            ld a, (DSEG + D_SEARCH_TARGET)
            ld (dc_target), a
            ld c, a
            ld a, (ai_side)
            call o_army_move_to
            ld a, (dc_target)
            call terr_owner
            ld c, a
            ld a, (dc_target)
            ld b, a
            ld a, (ai_side)
            jp o_attack

; 2995: side A's turn
o_ai_turn:
            ld (ai_side), a
            ld hl, (DSEG + D_QUIT)
            ld a, h
            or l
            ret nz
            ld a, (ai_side)         ; its home fallen: nothing
            ld c, S_HOME
            call side_w
            ld a, l
            ld (ai_home), a
            call terr_owner
            ld hl, ai_side
            cp (hl)
            ret nz
            ld a, (ai_side)         ; its income into its gold
            ld c, S_INCOME
            call side_w
            push hl
            ld a, (ai_side)
            ld c, S_GOLD
            call side_w
            pop de
            add hl, de
            ex de, hl
            ld a, (ai_side)
            ld c, S_GOLD
            call side_sw
            call ai_reinforce
            ld a, (ai_home)
            ld b, 7
            call flash_territory
            call get_key
            ld a, (ai_home)
            ld b, 7
            call flash_territory
            call get_key
            call ai_choose_order
            push af
            call ai_do_order
            pop af
            ld (co_order), a
            ld a, (ai_side)
            add a, a
            ld l, a
            ld h, 0
            ld de, DSEG + D_LAST_ORDER
            add hl, de
            ld a, (co_order)
            ld (hl), a
            inc hl
            ld (hl), 0
            ret

; ------------------------------------------------------------------ the overlay's variables

ai_side:    db 0
ai_home:    db 0
co_order:   db 0
dc_target:  db 0
am_si:      db 0
am_t:       db 0
am_v:       dw 0
am_a:       dw 0
sn_t:       db 0
sn_except:  db 0
sn_si:      db 0
mg_from:    dw 0
mg_to:      dw 0
mg_f:       db 0
mg_n:       dw 0
sf_side:    db 0
sf_winner:  db 0
sf_t:       db 0
ad_army:    dw 0
ad_tactic:  db 0
ad_n:       dw 0
br_att:     db 0                ; the battle: the attacker, the defender, the territory
br_def:     db 0
br_t:       db 0
br_pct:     db 0                ; the castle's protection
br_shown:   db 0
br_tactic:  db 0
tl_army:    dw 0
at_r:       db 0
sq_at:      dw 0
sq_n:       dw 0
sq_lost_n:  dw 0
tv_t:       db 0
tv_steps:   db 0
tv_owner:   db 0
tv_enmity:  dw 0
tv_own:     dw 0
tv_def:     dw 0
as_d:       db 0
as_t:       db 0
as_i:       db 0
as_n:       db 0
as_path:    ds 50               ; 5 levels of 5 words: the way down
ft_at:      dw 0
bs_di:      db 0
bs_si:      db 0
bs_inc:     db 0
ab_home:    db 0
ab_gold:    dw 0
ab_spend_n: dw 0
ab_knights: dw 0
ab_site:    db 0
ab_g:       dw 0
ab_a:       dw 0
ab_f:       db 0
ab_n:       dw 0
rd_si:      db 0
rd_lady:    dw 0
rd_n:       dw 0
ri_a:       dw 0
ri_t:       db 0
ri_s:       dw 0
ri_want:    dw 0
ri_di:      dw 0
ap_si:      db 0
bt_last:    db 0                ; the battle shown
bt_l4:      dw 0
bt_l2:      dw 0
bt_chosen:  db 0
bt_shown:   db 0
bt_sel:     db 0
bt_hy:      db 0
bt_group:   db 0
bt_menn:    db 0
bt_kn:      db 0
bt_l34:     dw 0
bt_l32:     dw 0
bt_l30:     dw 0
bt_l28:     dw 0
bt_l22:     db 0
bt_l20:     db 0
bt_tick:    dw 0
bt_frames:  db 0
bt_morale:  db 0
bt_r:       db 0
ba_k:       db 0
sm_bx:      dw 0
ov_war_end:
