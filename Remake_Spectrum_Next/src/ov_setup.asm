; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; ov_setup.asm: an overlay (8K at 2000h, in slot 1, while it runs): the
; setup of a new game (AB 21CC-2556, game.c): the homes, the lords, the
; castles, the ladies, the garrisons, the armies and the enmities.
;
; An overlay begins with a table of jumps, its entries: the program calls
; them through its stubs (main.asm ovl_go), which page it in and back out.
; It calls the program by its labels (build/main_syms.asm), but holds no
; NEXTREG or esxDOS call of its own: those stay in the program.

#include "defs.asm"
#include "../build/main_syms.asm"

            org $2000
            jp o_game_setup         ; 2000h: game_setup

; 9D33: shuffled[0 .. A - 1] = 0 .. A - 1 in a random order
shuffle:
            ld (sh_n), a
            ld b, a
            ld hl, shuffled
            xor a
sh_fill:
            ld (hl), a
            inc hl
            inc a
            djnz sh_fill
            xor a
            ld (sh_i), a
sh_next:
            call random_7fff        ; j = that % n (the whole word)
            ld a, (sh_n)
            ld e, a
            ld d, 0
            call div16
            ld hl, shuffled         ; swap shuffled[i] and shuffled[j]
            add hl, de
            ex de, hl
            ld a, (sh_i)
            ld l, a
            ld h, 0
            ld bc, shuffled
            add hl, bc
            ld a, (de)
            ld c, (hl)
            ld (hl), a
            ld a, c
            ld (de), a
            ld hl, sh_i
            inc (hl)
            ld a, (sh_n)
            cp (hl)
            jp nz, sh_next
            ret

; 236D: lord record HL (offset) into side record DE (offset)
copy_lord:
            ld (cl_from), hl
            ld (cl_to), de
            ld ix, cl_map
            ld b, 8
cl_word:
            push bc
            ld hl, (cl_from)
            ld e, (ix + 0)
            ld d, 0
            add hl, de
            call dsw
            push hl
            ld hl, (cl_to)
            ld e, (ix + 1)
            ld d, 0
            add hl, de
            pop de
            call dssw
            inc ix
            inc ix
            pop bc
            djnz cl_word
            ret
cl_map:     db 0, 0, 2, 2, 4, 4, 6, $10, 8, $0E, $0A, $12, $0C, $0C, $0E, $16   ; from, to

; 21CC: the sides' homes, the lords who hold them, their incomes
setup_sides:
            ld a, 3
            call shuffle
            ld ix, shuffled
            ld a, (ix + 0)
            inc a
            ld c, S_HOME
            ld de, 1
            call side_sw
            ld a, (ix + 1)
            inc a
            ld c, S_HOME
            ld de, 5
            call side_sw
            ld a, (ix + 2)
            inc a
            ld c, S_HOME
            ld de, 8
            call side_sw
            ld a, 4
            ld c, S_HOME
            ld de, 11
            call side_sw
            ld a, 5
            ld c, S_HOME
            ld de, 13
            call side_sw
            ld a, 6
            ld c, S_HOME
            ld de, 15
            call side_sw
            ld hl, 0
            ld (DSEG + $9D), hl
            ld a, (DSEG + D_PLAYER) ; the character chosen becomes side 1
            dec a
            call lord_ofs
            ld de, $00B7
            call copy_lord
            ld hl, 1
            ld (DSEG + D_PLAYER), hl
            ld a, 1
            ld c, S_NAME
            call side_w
            ld (DSEG + $1C0D), hl
            ld a, 4                 ; two of the other three Saxons
            call shuffle
            ld a, 2
            ld (ss_di), a
            xor a
            ld (ss_i), a
ss_saxon:
            ld a, (ss_i)
            ld e, a
            ld d, 0
            ld hl, shuffled
            add hl, de
            ld a, (hl)
            ld (ss_lord), a
            call lord_ofs
            call dsw
            push hl
            ld a, 1
            ld c, S_NAME
            call side_w
            pop de
            or a
            sbc hl, de
            jp z, ss_skip           ; the player's own lord
            ld a, (ss_lord)
            call lord_ofs
            push hl
            ld a, (ss_di)
            call side_ofs
            ex de, hl
            pop hl
            call copy_lord
            ld hl, ss_di
            inc (hl)
ss_skip:
            ld hl, ss_i
            inc (hl)
            ld a, (ss_di)
            cp 4
            jp c, ss_saxon
            ld a, 5                 ; three of the five Normans: (a << 4) + 537h
            call shuffle
            xor a
ss_norman:
            ld (ss_i), a
            ld e, a
            ld d, 0
            ld hl, shuffled
            add hl, de
            ld a, (hl)
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            add hl, hl
            add hl, hl
            ld de, $0537
            add hl, de
            push hl
            ld a, (ss_i)
            add a, 4
            call side_ofs
            ex de, hl
            pop hl
            call copy_lord
            ld a, (ss_i)
            inc a
            cp 3
            jp c, ss_norman
            ld a, 1                 ; each side: no lady, at home, its home's income
ss_side:
            ld (ss_i), a
            ld c, S_LADY
            ld de, $FFFF
            call side_sw
            ld a, (ss_i)
            ld c, S_HOME
            call side_w
            push hl
            ex de, hl
            ld a, (ss_i)
            ld c, S_AT
            call side_sw
            pop hl
            ld a, l
            ld c, T_INCOME
            call terr_byte
            call sx_a
            ex de, hl
            ld a, (ss_i)
            ld c, S_INCOME
            call side_sw
            ld a, (ss_i)
            inc a
            cp 7
            jp c, ss_side
            ret

; 3CAF: the owners and castles: the three Saxon homes their sides', the
; Norman ones (73Eh, 75Ch, 77Ah); the castles' strength 30
place_castles:
            ld ix, pk_list
pk_next:
            ld l, (ix + 0)
            ld h, (ix + 1)
            ld a, h
            or l
            jp z, pk_homes
            ld de, DSEG
            add hl, de
            ld a, (ix + 2)
            ld (hl), a
            inc ix
            inc ix
            inc ix
            jp pk_next
pk_homes:
            ld a, 1
pk_home:
            ld (ss_i), a
            ld c, S_HOME
            call side_w
            ld a, l
            call terr_ofs
            ld de, DSEG + T_OWNER
            add hl, de
            ld a, (ss_i)
            ld (hl), a
            inc a
            cp 4
            jp c, pk_home
            ret
pk_list:    dw $06A9
            db 30
            dw $06B7
            db $FF
            dw $06B8
            db 0
            dw $06C6
            db $FF
            dw $06C7
            db 0
            dw $06D5
            db $FF
            dw $06D6
            db 0
            dw $06E5
            db 30
            dw $06F3
            db $FF
            dw $06F4
            db 0
            dw $0702
            db $FF
            dw $0703
            db 0
            dw $0712
            db 30
            dw $0720
            db $FF
            dw $0721
            db 0
            dw $072F
            db $FF
            dw $0730
            db 0
            dw $073E
            db 4
            dw $073F
            db 30
            dw $074D
            db $FF
            dw $074E
            db 0
            dw $075C
            db 5
            dw $075D
            db 30
            dw $076B
            db $FF
            dw $076C
            db 0
            dw $077A
            db 6
            dw $077B
            db 30
            dw $0789
            db $FF
            dw $078A
            db 0
            dw $0798
            db $FF
            dw $0799
            db 0
            dw $07A7
            db $FF
            dw $07A8
            db 0
            dw 0

; 243B: no lady kidnapped; two of the four with sides 2 and 3
setup_ladies:
            ld hl, $FFFF
            ld (DSEG + D_KIDNAPPED), hl
            ld a, 4
            call shuffle
            xor a
sl_lady:
            push af
            call lady_ofs
            call dsp
            inc hl
            inc hl
            ld (hl), $FF            ; L_SIDE -1
            inc hl
            ld (hl), $FF
            inc hl
            ld (hl), 0              ; L_TERR 0
            inc hl
            ld (hl), 0
            inc hl
            ld (hl), 0              ; L_FLAG 0
            inc hl
            ld (hl), 0
            pop af
            inc a
            cp 4
            jp c, sl_lady
            ld a, (shuffled + 0)
            ld c, 2
            ld b, 1
            call lady_to_side
            ld a, (shuffled + 1)
            ld c, 3
            ld b, 1
            jp lady_to_side

; 1FB3: each territory's garrison: there, its vassals as soldiers
setup_garrisons:
            ld a, 1
sg_terr:
            ld (sg_t), a
            call garrison_ofs
            call dsp
            push hl
            pop ix
            ld a, (sg_t)
            ld (ix + A_AT), a
            ld (ix + A_AT + 1), 0
            ld (ix + A_BASE), a
            ld (ix + A_BASE + 1), 0
            ld c, T_VASSALS
            call terr_byte
            call sx_a
            ld (ix + A_SOLDIERS), l
            ld (ix + A_SOLDIERS + 1), h
            xor a
            ld (ix + A_KNIGHTS), a
            ld (ix + A_KNIGHTS + 1), a
            ld (ix + A_CATAPULTS), a
            ld (ix + A_CATAPULTS + 1), a
            ld a, (sg_t)
            inc a
            cp 19
            jp c, sg_terr
            ret

; 1F11: each side's campaign army at its home, 15 soldiers (the player's none);
; its home's garrison 5 (the player's 10)
setup_armies:
            ld a, 1
sa_side:
            ld (sg_t), a
            ld c, S_HOME
            call side_w
            ld a, l
            ld (sg_home), a
            ld a, (sg_t)
            call army_ofs
            call dsp
            push hl
            pop ix
            ld a, (sg_home)
            ld (ix + A_AT), a
            ld (ix + A_AT + 1), 0
            ld (ix + A_BASE), a
            ld (ix + A_BASE + 1), 0
            ld (ix + A_SOLDIERS), 15
            xor a
            ld (ix + A_SOLDIERS + 1), a
            ld (ix + A_KNIGHTS), a
            ld (ix + A_KNIGHTS + 1), a
            ld (ix + A_CATAPULTS), a
            ld (ix + A_CATAPULTS + 1), a
            ld c, 5
            ld a, (sg_t)
            cp 1
            jp nz, sa_garrison
            ld c, 10
            ld (ix + A_SOLDIERS), 0
sa_garrison:
            push bc
            ld a, (sg_home)
            call garrison_ofs
            ld de, A_SOLDIERS
            add hl, de
            pop bc
            ld e, c
            ld d, 0
            call dssw
            ld a, (sg_t)
            inc a
            cp 7
            jp c, sa_side
            ret

; 2556: Saxons and Normans 2 against each other; the Normans 3 more against the player
setup_enmity:
            ld a, 6
se_si:
            ld (ea_a), a
            ld a, 6
se_di:
            ld (ea_b), a
            ld b, 0                 ; (si < 4 && di > 3) || (si > 3 && di < 4): 2
            ld a, (ea_a)
            cp 4
            ld a, (ea_b)
            jp nc, se_norman
            cp 4
            jp c, se_set
            ld b, 2
            jp se_set
se_norman:
            cp 4
            jp nc, se_set
            ld b, 2
se_set:
            ld a, (ea_a)
            ld c, a
            ld a, (ea_b)
            call enmity_ofs
            ld e, b
            ld d, 0
            call dssw
            ld a, (ea_b)
            dec a
            jp nz, se_di
            ld a, (ea_a)
            dec a
            jp nz, se_si
            ld a, 4
            ld c, 1
            ld b, 3
            call enmity_add
            ld a, 5
            ld c, 1
            ld b, 3
            call enmity_add
            ld a, 6
            ld c, 1
            ld b, 3
            jp enmity_add

; the end of new_game (10B2): the setup
o_game_setup:
            ld hl, pic_loaded       ; the opening's pictures leave their pages to the scenes
            ld b, 6                 ; (a new game's choice and Sherwood read again when needed)
gs_free:
            ld (hl), 0
            inc hl
            djnz gs_free
            ld hl, pic_page
            ld b, 6
gs_spare:
            ld (hl), SPARE_PAGE
            inc hl
            djnz gs_spare
            xor a
            ld (scene_has), a
            ld a, 1
            ld (DSEG + $2BC9), a
            ld hl, 0
            ld (DSEG + $3B), hl
            ld (DSEG + $3D), hl
            ld (DSEG + $3F), hl
            ld (DSEG + $4B), hl
            ld (DSEG + $4D), hl
            ld (DSEG + $4F), hl
            ld (DSEG + D_MONTH), hl
            ld hl, $FFFF
            ld (DSEG + $41), hl
            ld hl, 8
            ld (DSEG + D_MONTH_NO), hl
            ld hl, 1149
            ld (DSEG + D_YEAR), hl
            ld hl, 30
            ld (DSEG + D_MORALE), hl
            call setup_sides
            call place_castles
            call setup_ladies
            call setup_garrisons
            call setup_armies
            call next_event_in
            call setup_enmity
            ld hl, DSEG + $24B
            ld b, 14
gs_minus:
            ld (hl), $FF
            inc hl
            djnz gs_minus
            ld a, 1
gs_colour:
            ld (sg_t), a
            call terr_owner
            cp $FF
            jp z, gs_none
            ld c, a
            ld a, (sg_t)
            call set_terr_colour
gs_none:
            ld a, (sg_t)
            inc a
            cp 19
            jp c, gs_colour
            ld a, $98
            ld hl, (DSEG + D_TUNE_STOP)
            jp play_tune


; ------------------------------------------------------------------ the overlay's variables

shuffled:   ds 6
sh_n:       db 0
sh_i:       db 0
cl_from:    dw 0
cl_to:      dw 0
ss_di:      db 0
ss_i:       db 0
ss_lord:    db 0
sg_t:       db 0
sg_home:    db 0
ov_setup_end:
