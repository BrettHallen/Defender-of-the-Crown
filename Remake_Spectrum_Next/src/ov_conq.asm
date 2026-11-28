; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; ov_conq.asm: an overlay (see ov_setup.asm): the player's orders on the map,
; as the Mac remake's month.c and conquest.c port them: choosing a territory
; (4142), Buy Home Army (39C7), Read Map (4084, 3DB4), Seek Conquest (35E0)
; with Transfer Forces (3721), marching (3585, 3135) and Robin (2E37, 2E84).

#include "defs.asm"
#include "../build/main_syms.asm"

D_ROBIN_TIMES EQU $004B         ; pledges asked for (3 in a game)
D_ROBIN_ASKED EQU $004D         ; Robin's men join the next attack
D_PRICE       EQU $0A90         ; words by item 2-5: soldier 1, knight 8, catapult 15, castle 20
D_SEEK_OPEN   EQU $0990         ; the Seek Conquest menu stays up
D_CUR_TERR    EQU $0B54         ; Read Map's territory
T_NB          EQU 8

            org $2000
            jp o_buy_army           ; 2000h: buy_army -> A: 1 if anything was bought
            jp o_read_map           ; 2003h: read_map -> A: 0
            jp o_seek_conquest      ; 2006h: seek_conquest -> A: 1 if the month goes on
            jp o_choose_territory   ; 2009h: choose_territory (A: from) -> A: the territory
            jp see_robin            ; 200Ch: ask_robin

; ------------------------------------------------------------------ choosing a territory (4142)

; From territory A a cursor on the map: it flashes; the keypad moves it
; through the table DS:0B56 (8 a territory: up, down, right, left, up-right,
; down-left, up-left, down-right); Enter chooses: A
o_choose_territory:
            ld (ct_si), a
            ld (ct_key), a
            call redraw_map
            ld hl, $2B68
            call dialog
ct_loop:
            ld a, (ct_si)
            ld b, 2
            call flash_territory
            ld a, (ct_key)
            or a
            call nz, flush_keys
            ld a, (ct_key)          ; the keypad's keys (47h-51h): a direction
            sub $47
            jp c, ct_read
            cp 11
            jp nc, ct_read
            ld e, a
            ld d, 0
            ld hl, ct_dirs
            add hl, de
            ld a, (hl)
            or a
            jp m, ct_read
            ld e, a                 ; si = DS:0B56 + 8 si + the direction
            ld a, (ct_si)
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            add hl, hl
            add hl, de
            ld de, DSEG + $0B56
            add hl, de
            ld a, (hl)
            ld (ct_si), a
ct_read:
            call get_key
            ld (ct_key), a
            cp KEY_ENTER
            jp nz, ct_loop
            ld a, (ct_si)
            ret
ct_dirs:    db 6, 0, 4, -1, 3, -1, 2, -1, 5, 1, 7      ; by scan code 47h-51h

; ------------------------------------------------------------------ Buy Home Army (39C7)

; Right (or Enter on Castles) buys, Left sells back what was bought this time
; (not more); a refusal is a click. Castles: choose a territory of the
; player's without one (a castle of 35, and 10 soldiers in its garrison).
o_buy_army:
            ld c, S_HOME
            call player_w
            ld a, l
            ld (by_home), a
            xor a
            ld (by_bought), a
            ld a, ' '
            ld (glyph_from), a
            ld a, '>'
            ld (glyph_to), a
            ld a, (by_home)         ; what there is: the home's garrison
            call garrison_ofs
            ld de, A_SOLDIERS
            add hl, de
            call dsp
            ld de, by_have
            ld bc, 6
            ldir
            ld hl, by_have
            ld de, by_had
            ld bc, 6
            ldir
            call redraw_map
            ld a, 2
            ld (by_si), a
            ld hl, 0
            ld (DSEG + D_LEFTRIGHT), hl
by_loop:
            ld a, (by_si)
            cp 6
            jp z, by_done
            cp 5                    ; Castles: Enter as Right
            jp nz, by_price
            ld hl, (DSEG + D_LEFTRIGHT)
            ld a, h
            or l
            jp nz, by_price
            ld hl, 1
            ld (DSEG + D_LEFTRIGHT), hl
by_price:
            ld a, (by_si)
            add a, a
            ld l, a
            ld h, 0
            ld de, D_PRICE
            add hl, de
            call dsw
            ld (by_price_n), hl
            ld hl, (DSEG + D_LEFTRIGHT)
            ld a, h
            or l
            jp z, by_show
            bit 7, h
            jp nz, by_sell
            ld c, S_GOLD            ; buying: enough gold?
            call player_w
            ld de, (by_price_n)
            or a
            sbc hl, de
            jp p, by_afford
            call click
            jp by_show
by_afford:
            ld a, (by_si)
            cp 5
            jp z, by_castle
            ex de, hl               ; a soldier, knight or catapult
            ld a, (DSEG + D_PLAYER)
            ld c, S_GOLD
            call side_sw
            call by_count
            inc (hl)
            jp nz, by_one
            inc hl
            inc (hl)
by_one:
            ld hl, by_bought
            inc (hl)
            jp by_show
by_castle:
            ld c, S_AT
            call player_w
            ld a, l
            call o_choose_territory
            ld (by_t), a
            call terr_owner
            ld hl, DSEG + D_PLAYER
            cp (hl)
            ld hl, $2CF1            ; not the player's
            jp nz, by_refused
            ld a, (by_t)
            ld c, T_CASTLE
            call terr_byte
            or a
            ld hl, $2D1D            ; a castle there already
            jp nz, by_refused
            ld a, (by_t)
            call terr_ofs
            ld de, DSEG + T_CASTLE
            add hl, de
            ld (hl), 35
            ld a, (by_t)
            call garrison_ofs
            ld de, A_SOLDIERS
            add hl, de
            push hl
            call dsw
            ld de, 10
            add hl, de
            ex de, hl
            pop hl
            call dssw
            ld c, S_GOLD
            call player_w
            ld de, (by_price_n)
            or a
            sbc hl, de
            ex de, hl
            ld a, (DSEG + D_PLAYER)
            ld c, S_GOLD
            call side_sw
            ld hl, by_bought
            inc (hl)
            jp by_castled
by_refused:
            call dialog
by_castled:
            call redraw_map
            jp by_show
by_sell:
            call by_count           ; selling back: only what was bought this time
            ld e, (hl)
            inc hl
            ld d, (hl)
            ld bc, by_had - by_have - 1
            add hl, bc
            ld a, (hl)
            inc hl
            ld h, (hl)
            ld l, a
            or a                    ; had - have < 0: have > had
            sbc hl, de
            jp p, by_cant
            call by_count
            ld e, (hl)
            inc hl
            ld d, (hl)
            dec de
            ld (hl), d
            dec hl
            ld (hl), e
            ld hl, by_bought
            dec (hl)
            ld c, S_GOLD
            call player_w
            ld de, (by_price_n)
            add hl, de
            ex de, hl
            ld a, (DSEG + D_PLAYER)
            ld c, S_GOLD
            call side_sw
            jp by_show
by_cant:
            call click
by_show:
            ld hl, $40A0            ; "You have n gold pieces"
            ld de, $3816
            call line_str
            push hl
            ld c, S_GOLD
            call player_w
            pop de
            call num_append
            ex de, hl
            ld hl, $40AA
            call str_append
            ld hl, $40B7            ; the soldiers, knights, catapults
            ld de, $381A
            call line_str
            ex de, hl
            ld hl, (by_have)
            call num_append
            ld hl, $40C9
            ld de, $381C
            call line_str
            ex de, hl
            ld hl, (by_have + 2)
            call num_append
            ld hl, $40DB
            ld de, $381E
            call line_str
            ex de, hl
            ld hl, (by_have + 4)
            call num_append
            ld a, (by_si)
            ld (DSEG + $3812), a
            call speaker_off
            ld hl, $380B
            call dialog
            inc a
            ld (by_si), a
            jp by_loop
by_done:
            ld a, (by_home)         ; the garrison as bought
            call garrison_ofs
            ld de, A_SOLDIERS
            add hl, de
            call dsp
            ex de, hl
            ld hl, by_have
            ld bc, 6
            ldir
            xor a
            ld (glyph_from), a
            ld a, (by_bought)
            or a
            ret z
            ld a, 1
            ret
; HL = the count of item by_si (2-4) in by_have
by_count:
            ld a, (by_si)
            sub 2
            add a, a
            ld l, a
            ld h, 0
            ld de, by_have
            add hl, de
            ret

; ------------------------------------------------------------------ Read Map (4084)

; 3DB4: a territory's name, income and vassals, and its owner's ratings (with
; his portrait when it is his home)
territory_info:
            ld hl, (DSEG + D_CUR_TERR)
            ld a, l
            call o_choose_territory
            ld (ti_t), a
            ld l, a
            ld h, 0
            ld (DSEG + D_CUR_TERR), hl
            call terr_owner
            ld (ti_si), a
            ld a, (ti_t)            ; its name, income and vassals
            call terr_ofs
            call dsw
            ld de, $1FF6
            call line_str
            ld a, (ti_t)
            ld c, T_INCOME
            call terr_byte
            ld l, a
            ld h, 0
            push hl
            ld hl, $1FF8
            call dsw
            ex de, hl
            pop hl
            call num_append
            ex de, hl
            ld hl, $4074
            call str_append
            ld a, (ti_t)
            ld c, T_VASSALS
            call terr_byte
            ld l, a
            ld h, 0
            push hl
            ld hl, $1FFA
            call dsw
            ex de, hl
            pop hl
            call num_append
            ex de, hl
            ld hl, $4082
            call str_append
            ld a, (ti_t)            ; the box: wider for Sherwood
            or a
            ld a, 23
            jp nz, ti_wide
            ld a, 25
ti_wide:
            ld (DSEG + $1FEE), a
            ld a, (ti_si)
            cp $FF
            jp nz, ti_owned
            ld hl, $408B            ; "Not Owned"
            ld (DSEG + $1FFC), hl
            jp ti_show
ti_owned:
            ld c, S_NAME            ; the owner and his ratings
            call side_w
            ld (DSEG + $200A), hl
            ld ix, ti_skills
            ld b, 3
ti_skill:
            push bc
            ld l, (ix + 0)
            ld h, (ix + 1)
            ld e, (ix + 2)
            ld d, (ix + 3)
            call line_str
            push hl
            ld a, (ti_si)
            ld c, (ix + 4)
            call side_w
            add hl, hl
            ld de, $37B1
            add hl, de
            call dsw
            pop de
            call str_append
            ld de, 5
            add ix, de
            pop bc
            djnz ti_skill
            ld a, (ti_si)
            ld c, S_HOME
            call side_w
            ld a, (ti_t)
            cp l
            jp nz, ti_other
            ld hl, $4095            ; "Home", with his portrait
            ld (DSEG + $1FFC), hl
            ld a, (ti_si)
            ld c, S_PORTRAIT
            call side_w
            ld a, l
            ld b, 25
            ld c, 3
            call show_portrait
            ld a, 45
            jp ti_box
ti_other:
            ld hl, $409A            ; "Owned"
            ld (DSEG + $1FFC), hl
            ld a, 25
ti_box:
            ld (DSEG + $1FFF), a
            ld hl, $1FFF
            call dialog
ti_show:
            ld hl, $1FEB
            jp dialog
ti_skills:  dw $3FEF, $200C
            db S_LEAD
            dw $3FFD, $200E
            db S_JOUST
            dw $400B, $2010
            db S_SWORD

o_read_map:
            ld c, S_HOME
            call player_w
            ld (DSEG + D_CUR_TERR), hl
            call redraw_map
rm_menu:
            ld hl, $202B            ; Read Territory / Continue
            call dialog
            cp 1
            jp nz, rm_done
            call territory_info
            jp rm_menu
rm_done:
            xor a
            ret

; ------------------------------------------------------------------ Robin (2E37, 2E84)

see_robin:
            call redraw_map
            ld hl, (DSEG + D_ROBIN_ASKED)
            ld a, h
            or l
            jp nz, sr_again
            ld hl, (DSEG + D_ROBIN_TIMES)
            ld de, 3
            or a
            sbc hl, de
            jp m, sr_pledge
            ld hl, $1ACE            ; "--- Sherwood Again ---": no more
            jp dialog
sr_pledge:
            ld hl, 1
            ld (DSEG + D_ROBIN_ASKED), hl
            ld hl, (DSEG + D_ROBIN_TIMES)
            inc hl
            ld (DSEG + D_ROBIN_TIMES), hl
sr_again:
            ld hl, $19F8
            jp dialog

; 2E84: HL = 1.5 x the defenders' soldiers less the player's, 2 to 50
robin_men:
            ld a, (sa_t)
            call garrison_ofs
            ld c, A_SOLDIERS
            call rec_w
            ld (rb_n), hl
            ld a, (sa_owner)        ; (nobody's: ARMY(-1), DS:013D, as the original reads)
            ld hl, $013D
            cp $FF
            call nz, army_ofs
            push hl
            call dsw
            ld a, (sa_t)
            cp l
            pop hl
            jp nz, rb_half
            ld c, A_SOLDIERS
            call rec_w
            ld de, (rb_n)
            add hl, de
            ld (rb_n), hl
rb_half:
            ld hl, (rb_n)           ; si / 2 + si - the player's soldiers
            ld de, 2
            call sdiv
            ld de, (rb_n)
            add hl, de
            push hl
            ld c, A_SOLDIERS
            call army_w
            ex de, hl
            pop hl
            or a
            sbc hl, de
            ld de, 51
            push hl
            or a
            sbc hl, de
            pop hl
            jp m, rb_low
            ld hl, 50
            ret
rb_low:
            ld de, 2
            push hl
            or a
            sbc hl, de
            pop hl
            ret p
            ld hl, 2
            ret

; ------------------------------------------------------------------ marching (3D82, 3585, 3135)

; 3D82: Z if territory C is a neighbour of territory A
is_neighbour:
            push bc
            call terr_ofs
            ld de, DSEG + T_NB
            add hl, de
            pop bc
            ld b, 7
in_nb:
            ld a, (hl)
            cp c
            ret z
            inc hl
            djnz in_nb
            or 1
            ret

; 3585: A = a neighbour of where the army is (or that territory itself);
; Sherwood Forest asks Robin and the choice goes on
choose_destination:
            ld c, S_AT
            call player_w
            ld a, l
            ld (cd_at), a
cd_loop:
            ld a, (cd_at)
            call o_choose_territory
            or a
            jp nz, cd_chosen
            call see_robin
            jp cd_loop
cd_chosen:
            ld (cd_t), a
            ld hl, cd_at
            cp (hl)
            ret z
            ld c, a
            ld a, (cd_at)
            call is_neighbour
            ld a, (cd_t)
            ret z
            ld hl, $2B88            ; not a neighbour
            call dialog
            jp cd_loop

; 3135: the army moves in and attacks territory A; Robin's men join for it,
; and half of them go again afterwards (an army left with fewer than 5
; soldiers gets 5): A = the attack's result
send_army:
            ld (sa_t), a
            ld c, a
            ld a, (DSEG + D_PLAYER)
            call army_move_to
            ld a, (sa_t)
            call terr_owner
            ld (sa_owner), a
            ld hl, 0
            ld (sa_extra), hl
            ld hl, (DSEG + D_ROBIN_ASKED)
            ld a, h
            or l
            jp z, sa_attack
            call robin_men
            ld (sa_extra), hl
            ld c, A_SOLDIERS
            call sa_add
sa_attack:
            ld a, (sa_owner)
            ld c, a
            ld a, (sa_t)
            ld b, a
            ld a, (DSEG + D_PLAYER)
            call attack
            ld (sa_r), a
            ld hl, (DSEG + D_ROBIN_ASKED)
            ld a, h
            or l
            jp z, sa_done
            ld hl, (sa_extra)       ; half of them go back
            ld de, 2
            call sdiv
            ex de, hl
            ld hl, 0
            or a
            sbc hl, de
            ld (sa_extra), hl
            call sa_add
            ld c, A_SOLDIERS
            call army_w
            ld de, 5
            or a
            sbc hl, de
            jp p, sa_done
            ld de, 5
            ld c, A_SOLDIERS
            call army_sw
sa_done:
            ld hl, 0
            ld (DSEG + D_ROBIN_ASKED), hl
            ld a, (sa_r)
            ret
; the player's soldiers + sa_extra
sa_add:
            ld c, A_SOLDIERS
            call army_w
            ld de, (sa_extra)
            add hl, de
            ex de, hl
            ld c, A_SOLDIERS
            jp army_sw

; HL = the word at field C of record HL; HL = HL / DE signed (as ov_war's)
rec_w:
            ld b, 0
            add hl, bc
            jp dsw
sdiv:
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

; ------------------------------------------------------------------ Transfer Forces (3721)

; Right moves one from the garrison to the campaign army, Left back
transfer_forces:
            ld c, A_AT
            call army_w
            ld a, l
            ld (tf_t), a
            call garrison_ofs       ; gar[1-3], arm[1-3]
            ld de, A_SOLDIERS
            add hl, de
            call dsp
            ld de, tf_gar
            ld bc, 6
            ldir
            ld a, (DSEG + D_PLAYER)
            call army_ofs
            ld de, A_SOLDIERS
            add hl, de
            call dsp
            ld de, tf_arm
            ld bc, 6
            ldir
            ld c, S_HOME            ; the heading: home, garrison or territory
            call player_w
            ld a, (tf_t)
            cp l
            ld hl, $3914
            jp z, tf_head
            ld c, T_CASTLE
            call terr_byte
            or a
            ld hl, $392F
            jp nz, tf_head
            ld hl, $394B
tf_head:
            call dsw
            ld (DSEG + $3972), hl
            ld a, ' '
            ld (glyph_from), a
            ld a, '>'
            ld (glyph_to), a
            xor a
            ld (DSEG + $396B), a
            ld a, 1
            ld (tf_si), a
            ld hl, 0
            ld (DSEG + D_LEFTRIGHT), hl
tf_loop:
            ld a, (tf_si)
            cp 4
            jp z, tf_done
            ld hl, (DSEG + D_LEFTRIGHT)
            ld a, h
            or l
            jp z, tf_show
            bit 7, h
            ld hl, tf_gar           ; Right: from the garrison to the army
            ld de, tf_arm
            jp z, tf_move
            ex de, hl               ; Left: back
tf_move:
            call tf_entry
            push hl
            ld a, (hl)
            inc hl
            ld h, (hl)
            ld l, a
            dec hl
            bit 7, h
            pop bc
            jp z, tf_take
            call click
            jp tf_show
tf_take:
            ld a, l                 ; one less there ...
            ld (bc), a
            inc bc
            ld a, h
            ld (bc), a
            ex de, hl               ; ... one more here
            call tf_entry
            ld e, (hl)
            inc hl
            ld d, (hl)
            inc de
            ld (hl), d
            dec hl
            ld (hl), e
tf_show:
            ld ix, tf_lines
            ld b, 3
            ld iy, 0
tf_line:
            push bc
            ld l, (ix + 0)          ; " " gar[i] " " text arm[i]
            ld h, (ix + 1)
            call dsw
            ex de, hl
            ld hl, $432C
            call str_append
            ex de, hl
            push iy
            pop bc
            ld hl, tf_gar
            add hl, bc
            ld a, (hl)
            inc hl
            ld h, (hl)
            ld l, a
            call num_append
            ex de, hl
            ld hl, $432A
            call str_append
            ex de, hl
            ld l, (ix + 2)
            ld h, (ix + 3)
            call str_append
            ex de, hl
            push iy
            pop bc
            ld hl, tf_arm
            add hl, bc
            ld a, (hl)
            inc hl
            ld h, (hl)
            ld l, a
            call num_append
            ld de, 4
            add ix, de
            inc iy
            inc iy
            pop bc
            djnz tf_line
            ld a, (tf_si)
            ld (DSEG + $396E), a
            call speaker_off
            ld hl, $3967
            call dialog
            ld (tf_si), a
            jp tf_loop
tf_done:
            ld a, (tf_t)            ; the forces as they are now
            call garrison_ofs
            ld de, A_SOLDIERS
            add hl, de
            call dsp
            ex de, hl
            ld hl, tf_gar
            ld bc, 6
            ldir
            ld a, (DSEG + D_PLAYER)
            call army_ofs
            ld de, A_SOLDIERS
            add hl, de
            call dsp
            ex de, hl
            ld hl, tf_arm
            ld bc, 6
            ldir
            xor a
            ld (glyph_from), a
            ret
; HL = line tf_si's word in the table HL (DE kept)
tf_entry:
            ld a, (tf_si)
            dec a
            add a, a
            add a, l
            ld l, a
            ret nc
            inc h
            ret
tf_lines:   dw $3974, $40EC         ; the line's pointer, the text between the numbers
            dw $3976, $40FB
            dw $3978, $410A

; ------------------------------------------------------------------ Seek Conquest (35E0)

; The menu stays up until a move ends the order (and the month). Moving into
; a territory of the player's own (1), a siege refused for want of a catapult
; (3) and safe passage (8) keep it up. Continue leaves without ending the month.
o_seek_conquest:
            ld hl, 1
            ld (DSEG + D_SEEK_OPEN), hl
            xor a
            ld (sc_di), a
sc_loop:
            ld a, (sc_di)
            or a
            ret nz
            ld hl, (DSEG + D_SEEK_OPEN)
            ld a, h
            or l
            ret z
            call redraw_map
            ld hl, $3852
            call dialog
            cp 1
            jp z, sc_send
            cp 2
            jp z, sc_transfer
            cp 3
            jp z, sc_map
            cp 4
            jp z, sc_robin
            cp 5
            jp nz, sc_loop
            ld hl, 0
            ld (DSEG + D_SEEK_OPEN), hl
            jp sc_loop
sc_send:
            ld c, A_SOLDIERS        ; no men in the campaign army
            call army_w
            push hl
            ld c, A_KNIGHTS
            call army_w
            pop de
            add hl, de
            ld a, h
            or l
            jp nz, sc_dest
            ld hl, $38AC
            call dialog
            jp sc_loop
sc_dest:
            call choose_destination
            or a
            jp nz, sc_where
            call see_robin
            jp sc_loop
sc_where:
            ld (sc_t), a            ; where it is already: nothing
            ld c, a
            ld hl, (DSEG + D_PLAYER)
            push bc
            ld c, S_AT
            call player_w
            pop bc
            ld a, l
            call is_neighbour
            jp nz, sc_loop
            ld a, (sc_t)
            call send_army
            cp 1
            jp z, sc_loop
            cp 8
            jp z, sc_loop
            cp 3
            jp z, sc_loop
            ld hl, sc_di
            ld (hl), 1
            cp 6
            jp nz, sc_loop
            ld a, (DSEG + D_PLAYER)
            call army_settle
            jp sc_loop
sc_transfer:
            ld c, S_AT              ; only in a territory of the player's
            call player_w
            ld a, l
            call terr_owner
            ld hl, DSEG + D_PLAYER
            cp (hl)
            jp z, sc_transfer_ok
            ld hl, $38E4
            call dialog
            jp sc_loop
sc_transfer_ok:
            call transfer_forces
            jp sc_loop
sc_map:
            call o_read_map
            jp sc_loop
sc_robin:
            call see_robin
            jp sc_loop

; ------------------------------------------------------------------ the overlay's variables

ct_si:      db 0
ct_key:     db 0
by_home:    db 0
by_bought:  db 0
by_si:      db 0
by_t:       db 0
by_price_n: dw 0
by_have:    ds 6                ; soldiers, knights, catapults
by_had:     ds 6
ti_t:       db 0
ti_si:      db 0
rb_n:       dw 0
cd_at:      db 0
cd_t:       db 0
sa_t:       db 0
sa_owner:   db 0
sa_extra:   dw 0
sa_r:       db 0
tf_t:       db 0
tf_si:      db 0
tf_gar:     ds 6
tf_arm:     ds 6
sc_di:      db 0
sc_t:       db 0
ov_conq_end:
