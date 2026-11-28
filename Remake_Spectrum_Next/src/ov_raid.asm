; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; ov_raid.asm: an overlay (see ov_setup.asm) in page 1 (bank 0's upper half):
; Go Raiding (AB 45AC), as the Mac remake's raid.c ports it: the castle
; chosen (4538), the raid (45EC), The Attack and The Defense (5449, 5571),
; the sword fight (4F24, sword_pose 4CAC/4DE8, bar_shorten 4C5C), the offer
; to rescue a kidnapped lady (4316) and the romance after a rescue (48EB).
;
; The fight keeps its state where the original did, in the data segment: the
; player's fighter at DS:0B08 (x, y, legs, body, strength), the enemy at
; DS:0B12, the two fighters behind them in The Attack at DS:0B1C and 0B26 (x,
; y, legs, body). Bodies are Ba items 160 (sword raised), 161 (middle), 162
; (thrust), 163 (parry), the enemy's 170-173; legs 164 (standing) and 165-166
; (a step), the enemy's 174-176. Positions are in 4-pixel units.
;
; The romance's sprites are read from the card as each part comes (the
; ladies, Bj; the bedchamber's figures, Bk; the window, Bl). The ladies'
; pictures, larger than a page, are in strips (convert.py split_wide).

#include "defs.asm"
#include "../build/main_syms.asm"

D_RAIDED      EQU $0AFA         ; the side whose castle is raided
D_BAR_YOU     EQU $0AF2         ; x of the end of the player's strength bar
D_BAR_ENEMY   EQU $0B04
D_LIMIT_BACK  EQU $0B02         ; the player retreats past this x
D_LIMIT_ENEMY EQU $0B30         ; the enemy steps back no further
F_X           EQU $0B08
F_Y           EQU $0B0A
F_LEGS        EQU $0B0C
F_BODY        EQU $0B0E
F_STR         EQU $0B10
E_X           EQU $0B12
E_Y           EQU $0B14
E_LEGS        EQU $0B16
E_BODY        EQU $0B18
E_STR         EQU $0B1A
B_X           EQU $0B1C         ; the two behind (The Attack)
B_Y           EQU $0B1E
B_LEGS        EQU $0B20
B_BODY        EQU $0B22
BE_X          EQU $0B26
BE_Y          EQU $0B28
BE_LEGS       EQU $0B2A
BE_BODY       EQU $0B2C
D_ROBIN_ASKED EQU $004D
L_NAME        EQU 0
PIC_NIGHT     EQU 13
PIC_HALL      EQU 14
PIC_LADY      EQU 17
PIC_BEDCHAMBER EQU 18
PIC_WINDOW    EQU 19
TUNE_RAID     EQU $9B
TUNE_ROMANCE  EQU $99
SWORD_PACE    EQU 3             ; the remake's g_sword_pace: screens a frame of the fight
ITEM_FLAME1   EQU $B6
ITEM_FLAME2   EQU $B7

            org $2000
            jp o_go_raiding         ; 2000h: Go Raiding -> A: 1 if the month goes on
            jp o_rescue_offer       ; 2003h: the offer to rescue a kidnapped lady -> A: 1 if taken

; ------------------------------------------------------------------ words

; HL = the word at DS offset HL; rd_ws: DS offset HL = DE
rd_w        EQU dsw
rd_ws       EQU dssw

; HL = the player's field C
rd_pw:
            ld a, (DSEG + D_PLAYER)
            jp side_w

; 9464: morale + A (signed), kept within 1-50
rd_morale_add:
            ld e, a
            rla
            sbc a, a
            ld d, a
            ld hl, (DSEG + D_MORALE)
            add hl, de
            ld de, 1
            call rd_at_least
            ld de, 50
            call rd_at_most
            ld (DSEG + D_MORALE), hl
            ret

; the player's leadership + A (signed), kept within 0-10
rd_lead_add:
            ld (rd_d), a
            ld c, S_LEAD
            call rd_pw
            ld a, (rd_d)
            ld e, a
            rla
            sbc a, a
            ld d, a
            add hl, de
            ld de, 0
            call rd_at_least
            ld de, 10
            call rd_at_most
            ex de, hl
            ld a, (DSEG + D_PLAYER)
            ld c, S_LEAD
            jp side_sw

; HL = at least DE, at most DE (signed; small numbers)
rd_at_least:
            or a
            sbc hl, de
            add hl, de
            ret p
            ex de, hl
            ret
rd_at_most:
            or a
            sbc hl, de
            add hl, de
            ret m
            ret z
            ex de, hl
            ret

; HL = A x 4
rd_x4:
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            ret

; Z if the signed word at DS offset HL is 0 or less
rd_le0:
            call dsw
            bit 7, h
            jp nz, le_yes
            ld a, h
            or l
            ret
le_yes:
            xor a
            ret

; ------------------------------------------------------------------ the strength bars

; 4C5C: a point off the bar whose end's x is at DS offset HL: lines 195 and 196 of
; its last two pixels to 0
rd_bar_shorten:
            push hl
            call dsw
            ld (bs_x), hl
            call bs_shorten
            pop hl
            ld de, (bs_x)
            jp dssw
bs_shorten:
            call bs_pixel
bs_pixel:
            ld hl, (bs_x)
            ld e, 195
            ld d, BACK_PAGE
            xor a
            call put_pixel
            ld hl, (bs_x)
            ld e, 196
            ld d, BACK_PAGE
            xor a
            call put_pixel
            ld hl, (bs_x)
            dec hl
            ld (bs_x), hl
            ret

; the bars at the start of a fight, from full down to the strengths: a point off
; for each below 49 (the player's, from x 154) and below rd_from (the enemy's, from
; x 118h)
rd_bars_start:
            ld hl, 154
            ld (bs_x), hl
            ld hl, (DSEG + F_STR)
            ld (bs_to), hl
            ld a, 49
            call bs_down
            ld hl, (bs_x)
            ld (DSEG + D_BAR_YOU), hl
            ld hl, $0118
            ld (bs_x), hl
            ld hl, (DSEG + E_STR)
            ld (bs_to), hl
            ld a, (rd_from)
            call bs_down
            ld hl, (bs_x)
            ld (DSEG + D_BAR_ENEMY), hl
            ret
bs_down:                            ; from A while more than bs_to (signed)
            ld (bs_si), a
bs_more:
            ld a, (bs_si)
            ld l, a
            ld h, 0
            ld de, (bs_to)
            or a
            sbc hl, de
            jp z, bs_done
            ret m
            call bs_shorten
            ld hl, bs_si
            dec (hl)
            jp bs_more
bs_done:
            ret

; the bars' names: "You" (Bb 7) and "Enemy" (8) on line 192, XORed
rd_bars:
            ld a, 7
            ld c, END_PAGE
            ld hl, 8
            ld e, 192
            call xor_sprite
            ld a, 8
            ld c, END_PAGE
            ld hl, 43
            ld e, 192
            jp xor_sprite

; a spark (Bb A) XORed at B, C (units, lines) for a frame, and a point off the
; bar at DS offset HL
rd_spark:
            ld (sp_bar), hl
            ld (sp_item), a
            ld a, b
            ld (sp_x), a
            ld a, c
            ld (sp_y), a
            call sp_xor
            ld b, SWORD_PACE        ; held as long as a frame
sp_show:
            push bc
            call present
            pop bc
            djnz sp_show
            ld hl, (sp_bar)
            call rd_bar_shorten
sp_xor:
            ld a, (sp_x)
            ld l, a
            ld h, 0
            ld a, (sp_y)
            ld e, a
            ld a, (sp_item)
            ld c, END_PAGE
            jp xor_sprite

; ------------------------------------------------------------------ the fighters

; 4DE8 / 4CAC: a pair of fighters (the record at DS:0B08 + 2 x A) into four
; slots from C: bodies at (x, y), legs at (x, y + 24), the right one's legs 8
; units further on (kept in pz_*)
rd_pose:
            ld a, c
            ld (pz_slot), a
            ld l, b                 ; (B: the record x 2)
            ld h, 0
            ld de, $0B08
            add hl, de
            ld de, pz_vals          ; x, y, legs, body, (strength), ex, ey, elegs, ebody
            ld b, 9
pz_read:
            push bc
            push hl
            call dsw                ; (DE kept)
            ex de, hl
            ld (hl), e
            inc hl
            ld (hl), d
            inc hl
            ex de, hl
            pop hl
            inc hl
            inc hl
            pop bc
            djnz pz_read
            ld a, (pz_slot)         ; slot + 3: the legs
            add a, 3
            ld b, a
            ld a, (pz_y)
            add a, 24
            ld e, a
            ld a, (pz_x)
            call rd_x4
            ld a, (pz_legs)
            ld c, a
            call pz_set
            ld a, (pz_slot)         ; + 1: the body
            inc a
            ld b, a
            ld a, (pz_y)
            ld e, a
            ld a, (pz_x)
            call rd_x4
            ld a, (pz_body)
            ld c, a
            call pz_set
            ld a, (pz_slot)         ; + 2: the right one's legs
            add a, 2
            ld b, a
            ld a, (pz_ey)
            add a, 24
            ld e, a
            ld a, (pz_ex)
            add a, 8
            call rd_x4
            ld a, (pz_elegs)
            ld c, a
            call pz_set
            ld a, (pz_slot)         ; + 0: its body
            ld b, a
            ld a, (pz_ey)
            ld e, a
            ld a, (pz_ex)
            call rd_x4
            ld a, (pz_ebody)
            ld c, a
pz_set:                             ; slot B: x HL, y E, Ba item C
            ld a, b
            ld b, c
            ld c, SWORD_PAGE
            jp slot_set

; the two fighters behind (The Attack): a step now and then, and a new stance
rd_background:
            ld hl, (DSEG + B_LEGS)
            ld de, 165
            or a
            sbc hl, de
            jp c, bg_stand
            add hl, de              ; a step goes on
            inc hl
            ld de, 167
            or a
            sbc hl, de
            add hl, de
            jp c, bg_step
            ld hl, 164
bg_step:
            ld (DSEG + B_LEGS), hl
            ld de, 10
            add hl, de
            ld (DSEG + BE_LEGS), hl
            jp bg_pose
bg_stand:
            ld a, 9
            call random_n
            ld a, l
            ld (bg_si), a
            or a
            jp nz, bg_stance
            ld hl, (DSEG + B_BODY)  ; 0: a step, unless one of them thrusts
            ld de, 162
            or a
            sbc hl, de
            jp z, bg_stance
            ld hl, (DSEG + BE_BODY)
            ld de, 172
            or a
            sbc hl, de
            jp z, bg_stance
            ld hl, 165
            ld (DSEG + B_LEGS), hl
            ld hl, 175
            ld (DSEG + BE_LEGS), hl
            ld a, 2
            call random_n
            ld a, l
            or a
            ld hl, (DSEG + B_X)
            jp z, bg_back
            inc hl                  ; forward, to 10 at most (9)
            ld de, 11
            or a
            sbc hl, de
            add hl, de
            jp c, bg_x
            ld hl, 9
            jp bg_x
bg_back:
            dec hl                  ; back, to 4 at least (5)
            ld de, 4
            or a
            sbc hl, de
            add hl, de
            jp nc, bg_x
            ld hl, 5
bg_x:
            ld (DSEG + B_X), hl
            ld de, 6
            add hl, de
            ld (DSEG + BE_X), hl
bg_stance:
            ld a, (bg_si)           ; 5-8: the left one's stance (si + 155); 1-4: the right one's (si + 169)
            cp 5
            jp c, bg_right
            add a, 155
            ld l, a
            ld h, 0
            ld (DSEG + B_BODY), hl
            jp bg_pose
bg_right:
            or a
            jp z, bg_pose
            add a, 169
            ld l, a
            ld h, 0
            ld (DSEG + BE_BODY), hl
bg_pose:
            ld b, 20                ; the record 10: DS:0B1C, into slots 4-7
            ld c, 4
            jp rd_pose

; 4F24: one frame every SWORD_PACE screens. The keypad (or the arrows): Enter
; thrusts, 8 raises the sword, 2 parries, 7/4/1 step back and 9/6/3 forward
; (forward only while more than 5 apart) with the sword raised, in the middle
; or parrying. A: 1 if the enemy falls, 0 if the player retreats past the left
; limit or is captured. (sf_attack: The Attack, with the two behind.)
rd_sword_fight:
            ld (sf_attack), a
            ld a, $FF
            ld (sf_di), a
sf_frame:
            ld a, (sf_attack)
            or a
            call nz, rd_background
            ld b, 0
            ld c, 0
            call rd_pose
            call sprites_draw
            ld b, SWORD_PACE        ; (keys pressed meanwhile are read next)
sf_show:
            push bc
            call present
            pop bc
            djnz sf_show
            ld hl, (DSEG + F_X)     ; retreated
            ld de, (DSEG + D_LIMIT_BACK)
            or a
            sbc hl, de
            jp p, sf_not_back
            ld a, -10
            call rd_lead_add
            ld a, -2
            call rd_morale_add
            ld hl, $253A
            call dialog
            xor a
            jp sf_end
sf_not_back:
            ld hl, E_STR            ; the enemy falls
            call rd_le0
            jp nz, sf_not_won
            call sprites_erase
            ld a, 3
sf_off:
            push af
            call rd_slot_off
            pop af
            inc a
            cp 8
            jp c, sf_off
            ld a, (pz_y)
            add a, 24
            ld e, a
            ld a, (pz_x)
            call rd_x4
            ld a, (pz_legs)
            ld c, a
            ld b, 2
            call pz_set
            ld a, (pz_y)
            ld e, a
            ld a, (pz_x)
            call rd_x4
            ld a, (pz_body)
            ld c, a
            ld b, 1
            call pz_set
            ld a, (pz_ey)
            ld e, a
            ld a, (pz_ex)
            call rd_x4
            ld c, 178
            ld b, 0
            call pz_set
            call sprites_draw
            call present
            call sprites_erase
            call flush_keys
            ld hl, 2
            call wait_ticks
            ld a, (pz_ey)
            add a, 32
            ld e, a
            ld a, (pz_ex)
            call rd_x4
            ld c, 179
            ld b, 0
            call pz_set
            call sprites_draw       ; (left on the picture)
            call present
            call flush_keys
            ld a, 1
            jp sf_end
sf_not_won:
            ld hl, F_STR            ; captured
            call rd_le0
            jp nz, sf_player
            ld a, -1
            call rd_lead_add
            ld a, -1
            call rd_morale_add
            ld c, S_GOLD            ; half the gold, the ransom
            call rd_pw
            srl h
            rr l
            ld (sf_g), hl
            ld a, h
            or l
            jp z, sf_ransomed
            ld c, S_GOLD
            call rd_pw
            ld de, (sf_g)
            or a
            sbc hl, de
            ex de, hl
            ld a, (DSEG + D_PLAYER)
            ld c, S_GOLD
            call side_sw
            ld a, (DSEG + D_RAIDED)
            ld c, S_GOLD
            call side_w
            ld de, (sf_g)
            add hl, de
            ex de, hl
            ld a, (DSEG + D_RAIDED)
            ld c, S_GOLD
            call side_sw
sf_ransomed:
            ld hl, $240E
            call dialog
            xor a
            jp sf_end
sf_player:
            ld hl, (DSEG + F_LEGS)  ; a step goes on
            ld de, 165
            or a
            sbc hl, de
            jp c, sf_act
            add hl, de
            inc hl
            ld de, 167
            or a
            sbc hl, de
            add hl, de
            jp c, sf_legs
            ld hl, 164
sf_legs:
            ld (DSEG + F_LEGS), hl
            jp sf_enemy
sf_act:
            ld hl, (DSEG + E_X)     ; si: how far apart
            ld de, (DSEG + F_X)
            or a
            sbc hl, de
            ld (sf_si), hl
            ld hl, (DSEG + F_BODY)
            ld de, 162
            or a
            sbc hl, de
            jp nz, sf_key
            ld hl, 161              ; the thrust: back to the middle, a hit if close and not parried
            ld (DSEG + F_BODY), hl
            ld hl, (sf_si)
            ld de, 7
            or a
            sbc hl, de
            jp p, sf_enemy
            ld hl, (DSEG + E_BODY)
            ld de, 173
            or a
            sbc hl, de
            jp z, sf_enemy
            ld hl, (DSEG + E_STR)
            dec hl
            ld (DSEG + E_STR), hl
            ld a, (pz_x)
            add a, 7
            ld b, a
            ld a, (pz_y)
            add a, 17
            ld c, a
            ld a, 9
            ld hl, D_BAR_ENEMY
            call rd_spark
            jp sf_enemy
sf_key:
            ld hl, (sf_si)          ; forward only while more than 5 apart
            ld de, 6
            or a
            sbc hl, de
            ld a, 0
            jp m, sf_fwd
            inc a
sf_fwd:
            ld (sf_fwd_ok), a
            call get_key
            cp KEY_ENTER
            jp z, sf_thrust
            cp $47
            jp z, sf_back_raised
            cp $48
            jp z, sf_raised
            cp $49
            jp z, sf_fwd_raised
            cp $4B
            jp z, sf_back_middle
            cp $4D
            jp z, sf_fwd_middle
            cp $4F
            jp z, sf_back_parry
            cp $50
            jp z, sf_parry
            cp $51
            jp z, sf_fwd_parry
            jp sf_keyed
sf_thrust:
            ld a, 162
            jp sf_body
sf_back_raised:
            call sf_step_back
sf_raised:
            ld a, 160
            jp sf_body
sf_fwd_raised:
            call sf_step_fwd
            ld a, 160
            jp sf_body
sf_back_middle:
            call sf_step_back
            ld a, 161
            jp sf_body
sf_fwd_middle:
            call sf_step_fwd
            ld a, 161
            jp sf_body
sf_back_parry:
            call sf_step_back
sf_parry:
            ld a, 163
            jp sf_body
sf_fwd_parry:
            call sf_step_fwd
            ld a, 163
sf_body:
            ld l, a
            ld h, 0
            ld (DSEG + F_BODY), hl
sf_keyed:
            call flush_keys
            jp sf_enemy
sf_step_back:
            ld hl, (DSEG + F_X)
            dec hl
            ld (DSEG + F_X), hl
            ld hl, 165
            ld (DSEG + F_LEGS), hl
            ret
sf_step_fwd:
            ld a, (sf_fwd_ok)
            or a
            ret z
            ld hl, (DSEG + F_X)
            inc hl
            ld (DSEG + F_X), hl
            ld hl, 165
            ld (DSEG + F_LEGS), hl
            ret
sf_enemy:                           ; the enemy: a step goes on; otherwise he acts every other frame
            ld hl, (DSEG + E_LEGS)
            ld de, 175
            or a
            sbc hl, de
            jp c, sf_e_act
            add hl, de
            inc hl
            ld de, 177
            or a
            sbc hl, de
            add hl, de
            jp c, sf_e_legs
            ld hl, 174
sf_e_legs:
            ld (DSEG + E_LEGS), hl
            jp sf_next
sf_e_act:
            ld a, (sf_di)
            neg
            ld (sf_di), a
            bit 7, a
            jp nz, sf_next
            ld hl, (DSEG + E_X)
            ld de, (DSEG + F_X)
            or a
            sbc hl, de
            ld (sf_si), hl
            ld hl, (DSEG + E_BODY)
            ld de, 170
            or a
            sbc hl, de
            jp nz, sf_e_strike
            ld hl, 172              ; raised: he thrusts
            ld (DSEG + E_BODY), hl
            jp sf_next
sf_e_strike:
            ld hl, (DSEG + E_BODY)  ; his thrust hits if close and not parried
            ld de, 172
            or a
            sbc hl, de
            jp nz, sf_e_move
            ld hl, (sf_si)
            ld de, 7
            or a
            sbc hl, de
            jp p, sf_e_move
            ld hl, (DSEG + F_BODY)
            ld de, 163
            or a
            sbc hl, de
            jp z, sf_e_move
            ld hl, (DSEG + F_STR)
            dec hl
            ld (DSEG + F_STR), hl
            ld a, (pz_ex)
            dec a
            ld b, a
            ld a, (pz_y)
            add a, 16
            ld c, a
            ld a, 10
            ld hl, D_BAR_YOU
            call rd_spark
sf_e_move:
            ld hl, (sf_si)          ; far: forward (even chances to step)
            ld de, 7
            or a
            sbc hl, de
            jp m, sf_e_near
            ld hl, 171
            ld (DSEG + E_BODY), hl
            ld a, 2
            call random_n
            ld a, h
            or l
            jp z, sf_next
            ld hl, 175
            ld (DSEG + E_LEGS), hl
            ld hl, (DSEG + E_X)
            dec hl
            ld (DSEG + E_X), hl
            jp sf_next
sf_e_near:
            ld hl, (sf_si)          ; close: back, parrying, if he may
            ld de, 6
            or a
            sbc hl, de
            jp p, sf_e_stance
            ld hl, (DSEG + E_X)
            ld de, (DSEG + D_LIMIT_ENEMY)
            or a
            sbc hl, de
            jp p, sf_e_stance
            ld hl, 175
            ld (DSEG + E_LEGS), hl
            ld hl, 173
            ld (DSEG + E_BODY), hl
            ld hl, (DSEG + E_X)
            inc hl
            ld (DSEG + E_X), hl
            jp sf_next
sf_e_stance:
            ld a, 2                 ; raised or parrying
            call random_n
            ld a, h
            or l
            ld hl, 170
            jp nz, sf_e_body
            ld hl, 173
sf_e_body:
            ld (DSEG + E_BODY), hl
sf_next:
            call sprites_erase
            jp sf_frame
sf_end:
            ld (sf_result), a
            xor a
sf_clear:
            push af
            call rd_slot_off
            pop af
            inc a
            cp 8
            jp c, sf_clear
            ld a, (sf_result)
            ret

; slot A: not drawn
rd_slot_off:
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            add hl, hl
            ld de, slots
            add hl, de
            ld (hl), 0
            ret

; 5449: against the guards (strength 20), two more fighters behind
rd_attack:
            ld a, PIC_NIGHT
            call show_picture
            call rd_bars
            call present
            call set_palette
            ld a, TUNE_RAID
            ld hl, (DSEG + D_TUNE_LOOP)
            call play_tune
            ld hl, 20
            ld (DSEG + E_STR), hl
            ld a, 40
            ld (rd_from), a
            call rd_bars_start
            ld hl, at_fields
            call rd_fields
            ld a, 1
            jp rd_sword_fight
at_fields:  dw D_LIMIT_BACK, 30, D_LIMIT_ENEMY, 51
            dw F_X, 32, F_Y, 141, F_LEGS, 164, F_BODY, 161
            dw E_X, 54, E_Y, 141, E_LEGS, 174, E_BODY, 171
            dw B_X, 7, B_Y, 139, B_LEGS, 164, B_BODY, 161
            dw BE_X, 13, BE_Y, 139, BE_LEGS, 174, BE_BODY, 171, 0

; the data segment's words from the list at HL (offset, value; 0 ends it)
rd_fields:
            ld e, (hl)
            inc hl
            ld d, (hl)
            inc hl
            ld a, d
            or e
            ret z
            ld c, (hl)
            inc hl
            ld b, (hl)
            inc hl
            push hl
            ld hl, DSEG
            add hl, de
            ld (hl), c
            inc hl
            ld (hl), b
            pop hl
            jp rd_fields

; 5571: against the lord (his swordplay x 4). The hall is put up after 39
; back-to-back wait_ticks(1), about two seconds.
rd_defense:
            ld a, PIC_HALL
            call show_picture
            call rd_bars
            ld hl, 39
            call wait_ticks
            call present
            call set_palette
            ld a, (DSEG + D_RAIDED)
            ld c, S_SWORD
            call side_w
            add hl, hl
            add hl, hl
            ld (DSEG + E_STR), hl
            ld a, 39
            ld (rd_from), a
            call rd_bars_start
            ld hl, df_fields
            call rd_fields
            xor a
            jp rd_sword_fight
df_fields:  dw D_LIMIT_BACK, 4, D_LIMIT_ENEMY, 20
            dw F_X, 6, F_Y, 141, F_LEGS, 164, F_BODY, 161
            dw E_X, 23, E_Y, 141, E_LEGS, 174, E_BODY, 171, 0

; ------------------------------------------------------------------ the raid (45EC)

; the raid on territory A's castle
rd_raid:
            ld (rr_t), a
            ld c, T_OWNER
            call terr_byte
            ld l, a
            rla
            sbc a, a
            ld h, a
            ld (DSEG + D_RAIDED), hl
            ld a, (DSEG + D_PLAYER)
            ld c, a
            ld b, 1
            ld a, (DSEG + D_RAIDED)
            call enmity_add
            ld c, S_SWORD           ; the player's strength: swordplay x 4, or 50 with Robin's help
            call rd_pw
            add hl, hl
            add hl, hl
            ld (DSEG + F_STR), hl
            ld hl, (DSEG + D_ROBIN_ASKED)
            ld a, h
            or l
            jp z, rr_alone
            ld hl, 50
            ld (DSEG + F_STR), hl
            ld hl, 0
            ld (DSEG + D_ROBIN_ASKED), hl
rr_alone:
            ld hl, 2
            ld (DSEG + $08C7), hl
            call rd_attack
            or a
            jp z, rr_end
            call rd_defense
            or a
            jp z, rr_end
            ld a, TUNE_RAID
            ld hl, (DSEG + D_TUNE_STOP)
            call play_tune
            ld hl, (DSEG + D_KIDNAPPED)
            ld a, h
            and l
            inc a
            jp z, rr_gold
            ld a, l                 ; a lady rescued: the romance, she is yours, and her ward's land
            ld (rr_k), a
            ld a, PIC_HALL          ; (the last picture loaded, put up again without the fighters)
            call show_picture
            call present
            call set_palette
            ld a, (rr_k)
            call lady_ofs
            ld de, L_SIDE
            add hl, de
            call dsw
            ld a, l
            ld (rr_ward), a
            ld a, (rr_k)
            call rd_romance
            ld a, (DSEG + D_PLAYER)
            ld c, a
            ld b, 2
            ld a, (rr_k)
            call lady_to_side
            ld a, (DSEG + D_PLAYER)
            ld c, a
            ld a, (rr_ward)
            call side_falls
            jp rr_end
rr_gold:
            ld a, (DSEG + D_RAIDED) ; half the lord's gold
            ld c, S_GOLD
            call side_w
            srl h
            rr l
            ld (rr_g), hl
            ld a, (DSEG + D_RAIDED)
            ld c, S_GOLD
            call side_w
            ld de, (rr_g)
            or a
            sbc hl, de
            ex de, hl
            ld a, (DSEG + D_RAIDED)
            ld c, S_GOLD
            call side_sw
            ld c, S_GOLD
            call rd_pw
            ld de, (rr_g)
            add hl, de
            ex de, hl
            ld a, (DSEG + D_PLAYER)
            ld c, S_GOLD
            call side_sw
            ld a, 1
            call rd_morale_add
            ld a, 1
            call rd_lead_add
            ld hl, $22C0
            call dialog
rr_end:
            ld a, TUNE_RAID
            ld hl, (DSEG + D_TUNE_STOP)
            call play_tune
            ld hl, 3
            ld (DSEG + $08C7), hl
            ret

; 4538: another side's home castle that it still holds (your own cancels the
; order; Sherwood Forest asks Robin)
o_go_raiding:
            ld c, S_AT
            call rd_pw
            ld a, l
            call choose_territory
            or a
            jp nz, gr_chosen
            call ask_robin
            jp o_go_raiding
gr_chosen:
            ld (gr_t), a
            ld a, 1
gr_side:
            ld (gr_si), a
            ld c, S_HOME
            call side_w
            ld a, (gr_t)
            cp l
            jp nz, gr_next
            call terr_owner
            ld c, a
            ld a, (gr_si)
            cp c
            jp z, gr_target
gr_next:
            ld a, (gr_si)
            inc a
            cp 7
            jp c, gr_side
            ld hl, $207B            ; "Territory must have a home castle."
            call dialog
            jp o_go_raiding
gr_target:
            ld c, S_HOME            ; your own: no raid
            call rd_pw
            ld a, (gr_t)
            cp l
            jp nz, gr_raid
            xor a
            ret
gr_raid:
            call redraw_map
            ld hl, $2143
            call dialog
            ld a, (gr_t)
            call rd_raid
            ld a, 1
            ret

; 4316: at the start of the player's month, if a Norman has kidnapped a lady
o_rescue_offer:
            ld hl, (DSEG + D_KIDNAPPED)
            ld a, h
            and l
            inc a
            ret z                   ; (A = 0)
            ld a, l
            ld (rr_k), a
            call redraw_map
            ld hl, $4315            ; "... has kidnapped <her name> ..."
            ld de, (DSEG + $287C)
            call str_append
            push hl
            ld a, (rr_k)
            call lady_ofs
            call dsw
            pop de
            call str_append
            ld hl, $4321            ; "... <the territory>"
            ld de, (DSEG + $2880)
            call str_append
            push hl
            ld a, (rr_k)
            call lady_ofs
            ld de, L_TERR
            add hl, de
            call dsw
            ld a, l
            ld c, T_NAME
            call terr_ofs
            call dsw
            pop de
            call str_append
            ld hl, $2871
            call dialog
            ld hl, $2920
            call dialog
            ld hl, $2948
            call dialog
            cp 1
            jp nz, ro_leave
            ld a, (rr_k)
            call lady_ofs
            ld de, L_TERR
            add hl, de
            call dsw
            ld a, l
            call rd_raid
            ld a, 2
            call rd_lead_add
            ld a, 1
            jp ro_done
ro_leave:
            ld a, -2
            call rd_lead_add
            xor a
ro_done:
            ld hl, $FFFF
            ld (DSEG + D_KIDNAPPED), hl
            ret

; ------------------------------------------------------------------ the romance (48EB)

; The lady's picture (Bj, put whole; the large ones in strips): item A at
; DS-word x HL (units), y E
rd_lady_put:
            ld (lp_item), a
            add hl, hl
            add hl, hl
            ld (lp_x), hl
            ld a, e
            ld (lp_y), a
lp_strip:
            ld a, (lp_item)         ; (its width: the blit counts bl_w down)
            ld c, LADIES_PAGE
            call item_size
            ld hl, (bl_w)
            ld (lp_w), hl
            ld hl, (lp_x)
            ld a, (lp_y)
            ld e, a
            ld a, (lp_item)
            ld c, LADIES_PAGE
            ld b, OP_COPY
            call sprite
            ld a, (bl_masked)       ; a strip with another to its right
            and 4
            ret z
            ld a, (bl_adv)
            ld (lp_item), a
            ld hl, (lp_x)
            ld de, (lp_w)
            add hl, de
            ld (lp_x), hl
            jp lp_strip

; 479B: her eyes close and open again: items base + 2 .. + 5, then + 5 back to
; + 1, one a screen refresh
rd_lady_animate:
            ld a, (rm_lady)
            add a, a
            add a, a
            ld l, a
            ld h, 0
            push hl
            ld de, $0A9E
            add hl, de
            call dsw
            ld a, l
            ld (la_y), a
            pop hl
            ld de, $0AA0
            add hl, de
            call dsw
            ld (la_x), hl
            ld a, (rm_base)
            add a, 2
la_open:
            ld (la_si), a
            call la_put
            ld a, (la_si)
            inc a
            ld c, a
            ld a, (rm_base)
            add a, 6
            cp c
            ld a, c
            jp nz, la_open
            dec a
la_close:
            ld (la_si), a
            call la_put
            ld a, (la_si)
            dec a
            ld c, a
            ld a, (rm_base)
            cp c
            ld a, c
            jp nz, la_close
            ret
la_put:
            ld hl, (la_x)
            ld a, (la_y)
            ld e, a
            ld a, (la_si)
            call rd_lady_put
            call present
            ld hl, 1
            jp wait_ticks

; 4853: the hearth in the bedchamber, a frame a screen refresh: slot 4 at
; (128, 113) cycles off / flame 1 / flame 2 (font items B6h, B7h) with the
; figures drawn under it. B: frames.
rd_fire:
            ld a, b
            ld (fi_n), a
            xor a
            ld (fi_phase), a
fi_frame:
            call get_key
            ld a, (fi_phase)
            or a
            jp z, fi_off
            cp 1
            ld b, ITEM_FLAME1
            jp z, fi_on
            ld b, ITEM_FLAME2
fi_on:
            ld a, 4
            ld hl, 128
            ld e, 113
            ld c, FONT_PAGE
            call slot_set
fi_off:
            call sprites_draw
            call present
            call sprites_erase
            ld a, 4
            call rd_slot_off
            ld a, (fi_phase)
            inc a
            cp 3
            jp c, fi_phase_set
            xor a
fi_phase_set:
            ld (fi_phase), a
            ld hl, fi_n
            dec (hl)
            jp nz, fi_frame
            ret

; the two figures of the bedchamber, each in two halves (Bk item n, and n +
; 22 64 lines lower), at DS:0AC6 (x, units) / 0AC8 (y) for step n: A n, slots
; B (the top) and B - 1
rd_figure:
            ld (fg_n), a
            ld a, b
            ld (fg_slot), a
            ld a, (fg_n)
            add a, a
            add a, a
            ld l, a
            ld h, 0
            push hl
            ld de, $0AC6
            add hl, de
            call dsw
            add hl, hl
            add hl, hl
            ld (fg_x), hl
            pop hl
            ld de, $0AC8
            add hl, de
            call dsw
            ld a, l
            ld (fg_y), a
            ld e, a
            ld hl, (fg_x)
            ld a, (fg_n)
            ld b, a
            ld c, ROMANCE_PAGE
            ld a, (fg_slot)
            call slot_set
            ld a, (fg_y)
            add a, 64
            ld e, a
            ld hl, (fg_x)
            ld a, (fg_n)
            add a, 22
            ld b, a
            ld c, ROMANCE_PAGE
            ld a, (fg_slot)
            dec a
            jp slot_set

; 48EB: after a rescue: the lady opens and closes her eyes five times, the two
; figures come together in three steps by the flickering hearth (the Tandy
; program has no fourth: its third again), the window; morale 50. Lady A. (As
; the remake: the EGA program's order and timing.)
rd_romance:
            ld (rm_lady), a
            ld a, 3                 ; the ladies (Bj), over the pages the scenes share
            call load_sprites
            ld hl, $267F            ; "You creep into a torchlit chamber..."
            call dialog
            ld a, PIC_LADY
            call show_picture
            ld a, TUNE_ROMANCE
            ld hl, (DSEG + D_TUNE_ONCE)
            call play_tune
            ld a, (rm_lady)
            ld l, a
            ld h, 0
            add hl, hl
            ld de, $0ABE
            add hl, de
            call dsw
            ld a, l
            ld (rm_base), a
            ld a, (rm_lady)
            add a, a
            add a, a
            ld l, a
            ld h, 0
            push hl
            ld de, $0AAE
            add hl, de
            call dsw
            ld a, l
            ld (lp_y), a
            pop hl
            ld de, $0AB0
            add hl, de
            call dsw
            ld a, (lp_y)
            ld e, a
            ld a, (rm_base)
            call rd_lady_put
            call present
            call set_palette
            ld hl, rm_waits
rm_blink:
            ld a, (hl)
            or a
            jp z, rm_blinked
            inc hl
            push hl
            ld l, a
            ld h, 0
            call wait_ticks
            call rd_lady_animate
            pop hl
            jp rm_blink
rm_blinked:
            ld a, 4                 ; the bedchamber's figures (Bk)
            call load_sprites
            ld hl, $2781            ; "As the firelight reflects in her eyes, your pulse quickens."
            call dialog
            ld a, PIC_BEDCHAMBER
            call show_picture
            call set_palette
            ld a, 4
rm_step:
            ld (rm_n), a
            ld b, 3
            call rd_figure
            ld a, (rm_n)
            inc a
            ld b, 1
            call rd_figure
            call sprites_draw
            call present
            call sprites_erase
            ld b, 40
            call rd_fire
            ld a, (rm_n)
            add a, 2
            cp 10
            jp c, rm_step
            call sprites_draw       ; (the Tandy program: its third step again, for the fourth)
            call present
            call sprites_erase
            call slots_off
            ld a, 5                 ; the window (Bl)
            call load_sprites
            ld a, PIC_WINDOW
            call show_picture
            call present
            call set_palette
            ld a, 12
rm_window:
            ld (rm_n), a
            ld b, a
            xor a
            ld hl, 36 * 4
            ld e, 89
            ld c, WINDOW_PAGE
            call slot_set
            ld hl, 3
            call wait_ticks
            call sprites_draw
            call present
            call sprites_erase
            ld a, (rm_n)
            inc a
            cp 22
            jp c, rm_window
            call slots_off
            ld hl, 18
            call wait_ticks
            ld hl, $27CA            ; "You return to battle with renewed strength and determination..."
            call dialog
            call wait_tune
            ld hl, 50
            ld (DSEG + D_MORALE), hl
            ret
rm_waits:   db 18, 27, 9, 18, 27, 0

; ------------------------------------------------------------------ variables

rd_d:       db 0
rd_from:    db 0                ; the enemy's bar: full at this strength
bs_x:       dw 0
bs_to:      dw 0
bs_si:      db 0
sp_bar:     dw 0
sp_item:    db 0
sp_x:       db 0
sp_y:       db 0
pz_slot:    db 0
pz_vals:                        ; the pair's record as read (words)
pz_x:       dw 0
pz_y:       dw 0
pz_legs:    dw 0
pz_body:    dw 0
pz_str:     dw 0
pz_ex:      dw 0
pz_ey:      dw 0
pz_elegs:   dw 0
pz_ebody:   dw 0
bg_si:      db 0
sf_attack:  db 0
sf_di:      db 0                ; the enemy acts when this turns positive
sf_si:      dw 0
sf_fwd_ok:  db 0
sf_g:       dw 0
sf_result:  db 0
rr_t:       db 0
rr_k:       db 0
rr_ward:    db 0
rr_g:       dw 0
gr_t:       db 0
gr_si:      db 0
lp_item:    db 0
lp_x:       dw 0
lp_y:       db 0
lp_w:       dw 0
la_x:       dw 0
la_y:       db 0
la_si:      db 0
fi_n:       db 0
fi_phase:   db 0
fg_n:       db 0
fg_slot:    db 0
fg_x:       dw 0
fg_y:       db 0
rm_lady:    db 0
rm_base:    db 0
rm_n:       db 0
