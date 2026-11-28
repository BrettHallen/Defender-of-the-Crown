; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; game.asm: the game's own logic, as the Mac remake's game.c and month.c
; (Remake/src) port the original's: its random numbers, the setup of a new
; game (AB 21CC-2556: in the overlay ov_setup.asm), the month (1B44), the map (4013), the status panel
; (90A3), the events (2F4E), the orders (1A91) and the options (1957).
;
; So far the month is the player's own: the computer lords' turns, and the
; orders other than Pass and Options, come next.
;
; The data segment's records (game.h): SIDE(i) at 9Fh + 24i, TERR(t) at 695h
; + 15t, ARMY(i) at 147h + 10i (7 + t: territory t's garrison), LADY(i) at
; 478h + 8i, LORD(i) at 4E7h + 16i, ENMITY(a, b) at 416h + 14a + 2b.

; ------------------------------------------------------------------ the data segment

; HL = the address of data segment offset HL (A, BC and DE kept)
dsp:
            push de
            ld de, DSEG
            add hl, de
            pop de
            ret

; HL = the word at offset HL
dsw:
            call dsp
            ld a, (hl)
            inc hl
            ld h, (hl)
            ld l, a
            ret

; the word at offset HL = DE
dssw:
            push de
            call dsp
            pop de
            ld (hl), e
            inc hl
            ld (hl), d
            ret

; HL = the signed byte at offset HL
dsb8:
            call dsp
            ld a, (hl)
sx_a:                               ; HL = A, sign-extended
            ld l, a
            rla
            sbc a, a
            ld h, a
            ret

; the records' offsets: HL = SIDE(A), TERR(A), ARMY(A), LADY(A), LORD(A) (DE changed)
side_ofs:
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            add hl, hl
            ld d, h
            ld e, l
            add hl, hl
            add hl, de
            ld de, $009F
            add hl, de
            ret
terr_ofs:
            ld l, a
            ld h, 0
            ld d, h
            ld e, l
            add hl, hl
            add hl, hl
            add hl, hl
            add hl, hl
            or a
            sbc hl, de
            ld de, $0695
            add hl, de
            ret
garrison_ofs:
            add a, 7
army_ofs:
            ld l, a
            ld h, 0
            add hl, hl
            ld d, h
            ld e, l
            add hl, hl
            add hl, hl
            add hl, de
            ld de, $0147
            add hl, de
            ret
lady_ofs:
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            add hl, hl
            ld de, $0478
            add hl, de
            ret
lord_ofs:
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            add hl, hl
            add hl, hl
            ld de, $04E7
            add hl, de
            ret

; HL = side A's field C (a word); player_w: the player's (D_PLAYER)
side_w:
            call side_ofs
            ld b, 0
            add hl, bc
            jp dsw
player_w:
            ld a, (DSEG + D_PLAYER)
            jp side_w

; side A's field C = DE
side_sw:
            push de
            call side_ofs
            ld b, 0
            add hl, bc
            pop de
            jp dssw

; HL = field C of the player's campaign army; army_sw: = DE
army_w:
            ld a, (DSEG + D_PLAYER)
            call army_ofs
            ld b, 0
            add hl, bc
            jp dsw
army_sw:
            push de
            ld a, (DSEG + D_PLAYER)
            call army_ofs
            ld b, 0
            add hl, bc
            pop de
            jp dssw

; A = territory A's byte C; terr_owner: its owner (FFh: none)
terr_owner:
            ld c, T_OWNER
terr_byte:
            call terr_ofs
            ld b, 0
            add hl, bc
            ld de, DSEG
            add hl, de
            ld a, (hl)
            ret

; ------------------------------------------------------------------ arithmetic

; HL = HL / DE, DE = the remainder (unsigned; DE under 8000h)
div16:
            push bc
            ld b, h
            ld c, l
            ld hl, 0
            ld a, 16
dv_bit:
            sla c
            rl b
            adc hl, hl
            or a
            sbc hl, de
            jp nc, dv_one
            add hl, de
            jp dv_next
dv_one:
            inc c
dv_next:
            dec a
            jp nz, dv_bit
            ex de, hl
            ld h, b
            ld l, c
            pop bc
            ret

; DE:HL = BC * DE (unsigned)
mul16:
            ld hl, 0
            ld a, 16
mu_bit:
            add hl, hl
            rl e
            rl d
            jp nc, mu_next
            add hl, bc
            jp nc, mu_next
            inc de
mu_next:
            dec a
            jp nz, mu_bit
            ret

; HL = HL * 60 (DE changed)
mul60:
            add hl, hl
            add hl, hl
            ld d, h
            ld e, l
            add hl, hl
            add hl, hl
            add hl, hl
            add hl, hl
            or a
            sbc hl, de
            ret

; ------------------------------------------------------------------ the clock

; At the start: the time of day from the Next's real-time clock (esxDOS
; M_GETDATE: DE the time as MS-DOS has it: hours, minutes, seconds / 2) as
; the PC BIOS counts it, ticks since midnight: seconds * 1193180 / 65536,
; that is seconds * 18 + seconds * 13532 / 65536. Without a clock: 0.
read_clock:
            di
            call files_on
            rst $08
            db M_GETDATE
            call files_off          ; (the flags kept)
            ld hl, 0                ; the BIOS clock counts on from here
            ld (bios_ticks), hl
            ld a, l
            ld (bios_hi), a
            jp c, rcl_done
            ld (td_time), de
            ld a, d                 ; hours: bits 15-11
            rrca
            rrca
            rrca
            and $1F
            ld l, a
            ld h, 0
            call mul60
            ld de, (td_time)        ; minutes: bits 10-5
            ld a, e
            rlca
            rlca
            rlca
            and 7
            ld c, a
            ld a, d
            and 7
            add a, a
            add a, a
            add a, a
            or c
            ld e, a
            ld d, 0
            add hl, de
            ld b, h                 ; seconds: minutes * 60 + (seconds / 2) * 2
            ld c, l
            ld de, 60
            call mul16
            ld a, (td_time)
            and $1F
            add a, a
            ld c, a
            ld b, 0
            add hl, bc
            jp nc, rcl_secs
            inc de
rcl_secs:
            ld (td_sec), hl
            ld a, e
            ld (td_sec + 2), a
            ld b, h                 ; * 18
            ld c, l
            ld de, 18
            call mul16
            ld a, (td_sec + 2)
            or a
            jp z, rcl_18
            ld a, e
            add a, 18
            ld e, a
rcl_18:
            ld (td_base), hl
            ld a, e
            ld (td_base + 2), a
            ld bc, (td_sec)         ; + * 13532 / 65536
            ld de, 13532
            call mul16
            ld a, (td_sec + 2)
            or a
            jp z, rcl_frac
            ld hl, 13532
            add hl, de
            ex de, hl
rcl_frac:
            ld hl, (td_base)
            add hl, de
            ld (td_base), hl
            jp nc, rcl_done
            ld hl, td_base + 2
            inc (hl)
rcl_done:
            ei
            ret

; E:HL = the BIOS clock (int 1Ah): the time of day at the start + the ticks since
sys_ticks:
            di
            ld hl, (bios_ticks)
            ld a, (bios_hi)
            ei
            ld e, a
            ld bc, (td_base)
            add hl, bc
            ld a, (td_base + 2)
            adc a, e
            ld e, a
            ret

; ------------------------------------------------------------------ the random numbers (9D96, 9DDB, 9DB3)

; 9DDB: D_RANDOM's next (a shift register: bit 0 out, B400h XORed in when it was 1); HL = it
lfsr_step:
            ld hl, (DSEG + D_RANDOM)
            srl h
            rr l
            jp nc, lf_done
            ld a, h
            xor $B4
            ld h, a
lf_done:
            ld (DSEG + D_RANDOM), hl
            ret

; 9DB3: seeded from the BIOS clock: DS:005D its high word, D_RANDOM its low
; word (never 0), then that many more steps; D_RANDOM_N FFFFh
seed_random:
            call sys_ticks
            ld a, h
            or l
            jp nz, sr_low
            inc hl                  ; (the original waits for the next tick)
sr_low:
            ld (DSEG + D_RANDOM), hl
            ld (sr_n), hl
            ld d, 0
            ld (DSEG + $5D), de
sr_step:
            call lfsr_step
            ld hl, (sr_n)
            dec hl
            ld (sr_n), hl
            ld a, h
            or l
            jp nz, sr_step
            ld hl, $FFFF
            ld (DSEG + D_RANDOM_N), hl
            ret

; 9D96: HL = the next random number (0 when the count runs out, and new seeds)
random_next:
            call lfsr_step
            push hl
            ld hl, (DSEG + D_RANDOM_N)
            dec hl
            ld (DSEG + D_RANDOM_N), hl
            ld a, h
            or l
            pop hl
            ret nz
            call seed_random
            ld hl, 0
            ret

; HL = (random_next * 7FFFh) & FFFFh, that is (r & 1) << 15 - r
random_7fff:
            call random_next
            ex de, hl
            ld hl, 0
            bit 0, e
            jp z, r7_even
            ld h, $80
r7_even:
            or a
            sbc hl, de
            ret

; 9CFC: HL = 0 .. A - 1 (A under 100h: the number's high byte)
random_n:
            or a
            jp z, rn_zero
            push af
            call random_7fff
            pop af
            ld e, a
            ld d, 0
            ld l, h
            ld h, 0
            call div16
            ex de, hl
            ret
rn_zero:
            ld hl, 0
            ret

; ------------------------------------------------------------------ the setup (game.c)

; 24B1: lady A to side C, flag B
lady_to_side:
            ld (lt_lady), a
            ld a, c
            ld (lt_side), a
            ld a, b
            ld (lt_flag), a
            ld a, (lt_lady)         ; her side before: without her
            call lady_ofs
            ld de, L_SIDE
            add hl, de
            call dsw
            ld a, h
            and l
            inc a
            jp z, lt_free
            ld a, l
            ld c, S_LADY
            ld de, $FFFF
            call side_sw
lt_free:
            ld a, (lt_lady)
            ld e, a
            ld d, 0
            ld a, (lt_side)
            ld c, S_LADY
            call side_sw
            ld a, (lt_lady)
            call lady_ofs
            push hl
            ld de, L_SIDE
            add hl, de
            ld a, (lt_side)
            ld e, a
            ld d, 0
            call dssw
            ld a, (lt_side)
            ld c, S_HOME
            call side_w
            ex de, hl
            pop hl
            push hl
            ld bc, L_TERR
            add hl, bc
            call dssw
            pop hl
            ld de, L_FLAG
            add hl, de
            ld a, (lt_flag)
            ld e, a
            ld d, 0
            jp dssw

; 2EEC: the next event in 5-12 months
next_event_in:
            ld a, 8
            call random_n
            ld de, 5
            add hl, de
            ld (DSEG + D_EVENT_IN), hl
            ret

; 25E5: the enmity between sides A and C changed by B (signed), both ways,
; kept within -10..10 (sides 1-6, not the same)
enmity_add:
            ld (ea_a), a
            dec a
            cp 6
            ret nc
            ld a, c
            ld (ea_b), a
            dec a
            cp 6
            ret nc
            ld a, (ea_a)
            cp c
            ret z
            ld a, b
            ld (ea_d), a
            ld a, (ea_a)
            ld c, a
            ld a, (ea_b)
            call ea_one
            ld a, (ea_b)
            ld c, a
            ld a, (ea_a)
ea_one:                             ; ENMITY(C, A) += d
            call enmity_ofs
            push hl
            call dsw
            ld a, (ea_d)
            ld e, a
            rla
            sbc a, a
            ld d, a
            add hl, de
            ld de, 10               ; v + 10 kept within 0..20
            add hl, de
            bit 7, h
            jp z, ea_low
            ld hl, 0
ea_low:
            ld a, l
            cp 21
            jp c, ea_high
            ld l, 20
ea_high:
            ld de, -10
            add hl, de
            ex de, hl
            pop hl
            jp dssw

; HL = ENMITY(C, A): 416h + 14c + 2a
enmity_ofs:
            ld l, c
            ld h, 0
            add hl, hl
            ld d, h
            ld e, l
            add hl, hl
            add hl, hl
            add hl, hl
            or a
            sbc hl, de
            ld e, a
            ld d, 0
            add hl, de
            add hl, de
            ld de, $0416
            add hl, de
            ret

; 9719: territory A's shape in its owner C's colour (the Tandy program's table at DS:0C70)
set_terr_colour:
            push af
            ld l, c
            ld h, 0
            add hl, hl
            ld de, DSEG + $0C70
            add hl, de
            ld e, (hl)
            inc hl
            ld d, (hl)
            ex de, hl
            pop af
            inc a
            jp set_region_colour

; ------------------------------------------------------------------ strings

; 948D: the string at offset HL copied to offset DE; HL = its end (the 0's offset)
str_append:
            ld bc, DSEG
            add hl, bc
            ex de, hl
            add hl, bc
            ex de, hl
sa_char:
            ld a, (hl)
            ld (de), a
            or a
            jp z, sa_end
            inc hl
            inc de
            jp sa_char
sa_end:
            ex de, hl
            or a
            sbc hl, bc
            ret

; the string at offset HL to where the word at offset DE points; HL = its end
line_str:
            push hl
            ex de, hl
            call dsw
            ex de, hl
            pop hl
            jp str_append

; 94B5: number HL written at offset DE (a space first under 10); HL = its end
num_append:
            ld (na_dst), de
            ld (na_n), hl
            ld b, 0
na_digit:
            ld de, 10
            call div16
            ld a, e
            add a, '0'
            push af
            inc b
            ld a, h
            or l
            jp nz, na_digit
            ld hl, (na_n)
            ld a, h
            or a
            jp nz, na_write
            ld a, l
            cp 10
            jp nc, na_write
            ld a, ' '
            push af
            inc b
na_write:
            ld hl, (na_dst)
            ld de, DSEG
            add hl, de
na_char:
            pop af
            ld (hl), a
            inc hl
            djnz na_char
            ld (hl), 0
            or a
            sbc hl, de
            ret

; ------------------------------------------------------------------ small helpers (month.c)

; 23AC: side A's income: the sum of its territories'
side_income:
            ld (si_side), a
            ld hl, 0
            ld (si_sum), hl
            ld a, 1
si_terr:
            ld (si_t), a
            call terr_ofs
            ld de, DSEG + T_OWNER
            add hl, de
            ld a, (si_side)
            cp (hl)
            jp nz, si_next
            inc hl                  ; T_INCOME: 3 on
            inc hl
            inc hl
            ld a, (hl)
            call sx_a
            ld de, (si_sum)
            add hl, de
            ld (si_sum), hl
si_next:
            ld a, (si_t)
            inc a
            cp 19
            jp c, si_terr
            ld de, (si_sum)
            ld a, (si_side)
            ld c, S_INCOME
            jp side_sw

; 9407: portrait A in its box at B (4-pixel units), C
show_portrait:
            ld (po_item), a
            ld a, b
            ld (DSEG + $1FE0), a
            ld a, c
            ld (DSEG + $1FE1), a
            push bc
            ld hl, $1FE0
            call dialog
            pop bc
            ld a, b
            add a, 4
            ld l, a
            ld h, 0
            ld a, c
            add a, 7
            ld e, a
            ld a, (po_item)
            ld c, PORTRAITS_PAGE
            jp put_sprite

; 9520: the speaker's tone (PIT divisor HL) for A ticks, on the second AY (the
; Tandy's speaker beside its sound chip): its tone A's period 1750000 / 16 /
; (1193182 / divisor) = divisor * 6007 / 65536
beep:
            push af
            call speaker_tone
            pop af
            ld l, a
            ld h, 0
            call delay_ticks
            jp speaker_off

; snd_speaker_click(250, 2): a click of about 2 ms (a refusal)
click:
            ld hl, 250
            call speaker_tone
            ld a, 4
            call delay_ints
            jp speaker_off

; the speaker's tone at PIT divisor HL, until speaker_off
speaker_tone:
            ld b, h
            ld c, l
            ld de, 6007
            call mul16
            di
            call ay1_on
            ld a, e
            ld e, 0
            call ay_set
            ld a, d
            ld e, 1
            call ay_set
            ld a, 13
            ld e, 8
            call ay_set
            call ay0_on
            ei
            ret
speaker_off:
            di
            call ay1_on
            xor a
            ld e, 8
            call ay_set
            call ay0_on
            ei
            ret

; ------------------------------------------------------------------ the map

; 3F4F: the castles (item: the castle's strength) at DS:0C14, and the player's
; campaign army (item 127) at DS:0C3A
draw_castles:
            ld a, 1
dc_terr:
            ld (dc_t), a
            ld c, T_CASTLE
            call terr_byte
            or a
            jp z, dc_next
            ld (dc_item), a
            ld a, (dc_t)
            ld hl, DSEG + $0C14
            call map_place
            ld a, (dc_item)
            ld c, PORTRAITS_PAGE
            call slot_sprite
dc_next:
            ld a, (dc_t)
            inc a
            cp 19
            jp c, dc_terr
            ld c, A_AT
            call army_w
            ld (DSEG + $0C60), hl
            ld a, l
            ld hl, DSEG + $0C3A
            call map_place
            ld a, 127
            ld c, PORTRAITS_PAGE
            call slot_sprite
            jp present

; HL = byte [HL + 2A] * 4, E = byte [HL + 2A + 1] (a place on the map: pixels, line)
map_place:
            ld e, a
            ld d, 0
            add hl, de
            add hl, de
            ld a, (hl)
            inc hl
            ld e, (hl)
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            ret

; territory A's shape XORed onto the map (at DS:0BEE)
terr_xor:
            push af
            ld hl, DSEG + $0BEE
            call map_place
            srl h                   ; (xor_mask wants 4-pixel units)
            rr l
            srl h
            rr l
            pop af
            inc a
            jp xor_mask

; 4013: the map (from the cache: its palette slot 0), the owned territories in
; their owners' colours, the castles
redraw_map:
            call use_palette
            call map_to_back
            ld a, 1                 ; the palette with the next present
            ld (pal_late), a
            ld hl, 1
            ld (DSEG + D_MAP_SHOWN), hl
            ld a, 1
rm_terr:
            ld (rm_t), a
            call terr_owner
            cp $FF
            jp z, rm_next
            ld a, (rm_t)
            call terr_xor
rm_next:
            ld a, (rm_t)
            inc a
            cp 19
            jp c, rm_terr
            jp draw_castles

; 40C6: territory A's shape XORed B times, a tick apart
flash_territory:
            ld (ft_t), a
            ld a, b
            ld (ft_n), a
ft_loop:
            ld a, (ft_n)
            or a
            ret z
            dec a
            ld (ft_n), a
            ld hl, (bios_ticks)
            ld (ft_t0), hl
ft_wait:
            call sys_check
            call idle
            ld hl, (bios_ticks)
            ld de, (ft_t0)
            or a
            sbc hl, de
            jp z, ft_wait
            ld a, (ft_t)
            call terr_xor
            call present
            jp ft_loop

; ------------------------------------------------------------------ the status panel (90A3)

; HL = the skill word (field A of the player's side)'s text (DS:37B1)
skill_str:
            ld c, a
            call player_w
            add hl, hl
            ld de, $37B1
            add hl, de
            jp dsw

month_status:
            ld c, S_INCOME          ; the income: less what was lost this month
            call player_w
            ld de, (DSEG + D_INCOME_LOST)
            or a
            sbc hl, de
            bit 7, h
            jp z, ms_income
            ld hl, 0
ms_income:
            ld (ms_si), hl
            ld hl, 0
            ld (DSEG + D_INCOME_LOST), hl
            ld ix, ms_skills
            ld b, 3
ms_skill:
            push bc
            ld l, (ix + 0)
            ld h, (ix + 1)
            ld e, (ix + 2)
            ld d, (ix + 3)
            call line_str
            push hl
            ld a, (ix + 4)
            call skill_str
            pop de
            call str_append
            ld de, 5
            add ix, de
            pop bc
            djnz ms_skill
            ld hl, $4018            ; where the army is
            ld de, $1C17
            call line_str
            push hl
            ld c, A_AT
            call army_w
            ld a, l
            call terr_ofs
            call dsw
            pop de
            call str_append
            ld ix, ms_counts
            ld b, 3
ms_count:
            push bc
            ld l, (ix + 0)
            ld h, (ix + 1)
            ld e, (ix + 2)
            ld d, (ix + 3)
            call line_str
            push hl
            ld c, (ix + 4)
            call army_w
            pop de
            call num_append
            ld de, 5
            add ix, de
            pop bc
            djnz ms_count
            ld hl, $404D
            ld de, $1C21
            call line_str
            ex de, hl
            ld hl, (ms_si)
            call num_append
            ld hl, $4061
            ld de, $1C23
            call line_str
            push hl
            ld c, S_GOLD
            call player_w
            pop de
            call num_append
            call redraw_map
            ld hl, $1C02
            call dialog
            ld hl, $1C26
            call dialog
            ld a, (DSEG + D_MORALE) ; the portrait by morale: 30 on 0, 20 on 1, else 2
            ld c, 0
            cp 30
            jp nc, ms_high
            inc c
            cp 20
            jp nc, ms_morale
            inc c
            jp ms_morale
ms_high:
            cp 51
            jp c, ms_morale
            ld a, 50
            ld (DSEG + D_MORALE), a
ms_morale:
            ld a, c
            ld (DSEG + $9D), a
            xor a
            ld (DSEG + $9E), a
            ld c, S_PORTRAIT
            call player_w
            ld a, (DSEG + $9D)
            add a, l
            ld b, $24
            ld c, 3
            call show_portrait
            ld c, S_LADY            ; the lady, at home
            call player_w
            ld a, h
            and l
            inc a
            jp z, ms_alone
            ld a, l
            ld (ms_lady), a
            ld c, S_HOME
            call player_w
            push hl
            ld a, (ms_lady)
            call lady_ofs
            ld de, L_TERR
            add hl, de
            pop de
            push de
            call dssw
            pop de
            ld a, d
            or e
            jp z, ms_alone
            ld a, (ms_lady)
            add a, $92
            ld b, $38
            ld c, 3
            call show_portrait
ms_alone:
            ld hl, 9
            call wait_ticks
            ld hl, (DSEG + D_MONTH_NO)  ; the next month
            inc hl
            ld a, l
            cp 12
            jp c, ms_month
            ld hl, (DSEG + D_YEAR)
            inc hl
            ld (DSEG + D_YEAR), hl
            ld hl, 0
ms_month:
            ld (DSEG + D_MONTH_NO), hl
            add hl, hl
            ld de, $372B
            add hl, de
            call dsw
            ld de, $1C31
            call line_str
            ex de, hl
            ld hl, (DSEG + D_YEAR)
            call num_append
            ld hl, 1000
            ld a, 2
            call beep
            ld hl, $1C26
            call dialog
            ld hl, 9
            call wait_ticks
ms_gold:                            ; the treasure counts up: 5 at a time while more than 10 are left
            ld hl, (ms_si)
            ld a, h
            or l
            jp z, ms_done
            ld de, 11
            or a
            sbc hl, de
            ld a, 1
            jp c, ms_step1
            ld a, 5
ms_step1:
            ld (ms_step), a
            ld hl, (ms_si)
            ld e, a
            ld d, 0
            or a
            sbc hl, de
            ld (ms_si), hl
            ld hl, $404D
            ld de, $1C4F
            call line_str
            ex de, hl
            ld hl, (ms_si)
            call num_append
            ld hl, 250
            ld a, 2
            call beep
            ld hl, $1C44
            call dialog
            ld hl, $4061
            ld de, $1C51
            call line_str
            push hl
            ld c, S_GOLD
            call player_w
            ld a, (ms_step)
            ld e, a
            ld d, 0
            add hl, de
            push hl
            ex de, hl
            ld a, (DSEG + D_PLAYER)
            ld c, S_GOLD
            call side_sw
            pop hl
            pop de
            call num_append
            ld hl, 250
            ld a, 2
            call beep
            ld hl, $1C44
            call dialog
            jp ms_gold
ms_done:
            ld hl, 40
            jp wait_ticks

ms_skills:  dw $3FEF, $1C0F         ; the label, the line's pointer, the side's field
            db S_LEAD
            dw $3FFD, $1C11
            db S_JOUST
            dw $400B, $1C13
            db S_SWORD
ms_counts:  dw $4021, $1C19         ; the label, the line's pointer, the army's field
            db A_SOLDIERS
            dw $4030, $1C1B
            db A_KNIGHTS
            dw $403F, $1C1D
            db A_CATAPULTS

; ------------------------------------------------------------------ the events (2F4E)

; 2EFB
show_plotters:
            ld a, PIC_PLOTTERS
            call show_picture
            call present
            call set_palette
            jp present

; 2F14: A = side A's highest-numbered territory that is not its home (0: none)
side_last:
            ld (sl_side), a
            ld c, S_HOME
            call side_w
            ld a, l
            ld (sl_home), a
            ld a, 18
sl_terr:
            ld (sl_t), a
            call terr_owner
            ld hl, sl_side
            cp (hl)
            jp nz, sl_next
            ld a, (sl_home)
            ld hl, sl_t
            cp (hl)
            jp z, sl_next
            ld a, (sl_t)
            ret
sl_next:
            ld a, (sl_t)
            dec a
            jp nz, sl_terr
            ret

; every side's campaign army at territory A goes home
send_home_at:
            ld (sh_t), a
            ld a, 1
sha_side:
            ld (sh_side), a
            call army_ofs
            call dsw
            ld a, (sh_t)
            cp l
            jp nz, sha_next
            ld a, (sh_side)         ; army_go_home: at, base and the side's place its home
            ld c, S_HOME
            call side_w
            ex de, hl
            push de
            ld a, (sh_side)
            ld c, S_AT
            call side_sw
            ld a, (sh_side)
            call army_ofs
            pop de
            push de
            push hl
            call dssw
            pop hl
            inc hl
            inc hl
            pop de
            call dssw
sha_next:
            ld a, (sh_side)
            inc a
            cp 7
            jp c, sha_side
            ret

; 423D: territory C to side A (FFh: nobody), flashing
set_owner:
            ld (so_owner), a
            ld a, c
            ld (so_t), a
            call terr_owner
            ld (so_old), a
            ld a, (so_t)
            ld b, 4
            call flash_territory
            ld a, (so_old)
            cp $FF
            jp z, so_new
            ld a, (so_t)
            ld b, 1
            call flash_territory
            ld a, (so_old)
            ld c, a
            ld a, (so_t)
            call set_terr_colour
so_new:
            ld a, (so_t)
            call terr_ofs
            ld de, DSEG + T_OWNER
            add hl, de
            ld a, (so_owner)
            ld (hl), a
            cp $FF
            jp z, so_done
            ld c, a
            ld a, (so_t)
            call set_terr_colour
            ld a, (so_t)
            ld b, 1
            call flash_territory
so_done:
            ld a, (so_t)
            ld b, 4
            call flash_territory
            ld c, A_AT
            call army_w
            ld (DSEG + $0C60), hl
            ld hl, (DSEG + D_MAP_SHOWN)
            ld a, h
            or l
            ret nz
            jp redraw_map

monthly_event:
            ld hl, (DSEG + D_EVENT_IN)
            dec hl
            ld (DSEG + D_EVENT_IN), hl
            ld a, h
            or l
            ret nz
            ld a, 10
            call random_n
            ld a, l
            inc a
            ld (me_n), a
            cp 1
            jp z, me_vikings
            cp 4
            jp c, me_lose
            jp z, me_sheriff
            cp 5
            jp z, me_catapult
            cp 6
            jp z, me_robin
            cp 7
            jp z, me_knights
            cp 8
            jp z, me_revolt
            jp next_event_in
me_vikings:                         ; 1: the garrison of the territory numbered as the player's side loses a third
            ld a, (DSEG + D_PLAYER)
            call garrison_ofs
            ld de, A_SOLDIERS
            add hl, de
            ld (me_at), hl
            call dsw
            ld (me_v), hl
            ld de, 3
            call div16
            ld a, h
            or l
            jp z, next_event_in
            ex de, hl
            ld hl, (me_v)
            or a
            sbc hl, de
            ex de, hl
            ld hl, (me_at)
            call dssw
            ld hl, $1C53
            jp me_dialog
me_lose:                            ; 2 the Danes, 3 Norman plotters: the player loses a territory
            ld a, (DSEG + D_PLAYER)
            call side_last
            or a
            jp z, next_event_in
            ld (me_t), a
            ld a, (me_n)
            cp 3
            call z, show_plotters
            ld hl, $1CC1
            ld a, (me_n)
            cp 2
            jp z, me_lost
            ld hl, $1D2F
me_lost:
            call dialog
            call redraw_map
            ld a, (me_t)
            ld c, a
            ld a, $FF
            call set_owner
            ld a, (me_t)
            call send_home_at
            jp next_event_in
me_sheriff:                         ; 4: half this month's income lost
            call show_plotters
            ld c, S_INCOME
            call player_w
            sra h
            rr l
            ld de, (DSEG + D_INCOME_LOST)
            add hl, de
            ld (DSEG + D_INCOME_LOST), hl
            ld hl, $1DA3
            jp me_dialog
me_catapult:                        ; 5: a catapult sabotaged
            ld c, A_CATAPULTS
            call army_w
            ld a, h
            or l
            jp z, next_event_in
            dec hl
            ex de, hl
            ld c, A_CATAPULTS
            call army_sw
            call show_plotters
            ld hl, $1E1A
            jp me_dialog
me_robin:                           ; 6: sides 1-3 25 gold
            ld a, 1
me_gold:
            ld (me_t), a
            ld c, S_GOLD
            call side_w
            ld de, 25
            add hl, de
            ex de, hl
            ld a, (me_t)
            ld c, S_GOLD
            call side_sw
            ld a, (me_t)
            inc a
            cp 4
            jp c, me_gold
            ld hl, $1E8C
            jp me_dialog
me_knights:                         ; 7: three knights join the campaign army
            ld c, A_KNIGHTS
            call army_w
            inc hl
            inc hl
            inc hl
            ex de, hl
            ld c, A_KNIGHTS
            call army_sw
            ld hl, $1EFA
            jp me_dialog
me_revolt:                          ; 8: a Norman's territory becomes the player's
            ld a, 4
me_norman:
            ld (me_t), a
            call side_last
            or a
            jp nz, me_revolted
            ld a, (me_t)
            inc a
            cp 7
            jp c, me_norman
            jp next_event_in
me_revolted:
            ld (me_t), a
            ld hl, $1F56
            call dialog
            call redraw_map
            ld a, (me_t)
            ld c, a
            ld a, (DSEG + D_PLAYER)
            call set_owner
            ld a, (me_t)
            call send_home_at
            jp next_event_in
me_dialog:
            call dialog
            jp next_event_in

; ------------------------------------------------------------------ the menus

; 1957: A = 1 when the game is to end
options_menu:
            ld a, 1
            ld (om_si), a
            ld hl, 0
            ld (DSEG + D_QUIT), hl
            xor a
            ld (DSEG + $3503), a
om_show:
            ld hl, $34BD            ; the joystick (the Next's game has none) and the music, on or off
            ld a, (DSEG + $08C5)
            or a
            jp z, om_joy
            ld hl, $34CF
om_joy:
            call dsw
            ld (DSEG + $350A), hl
            ld hl, $34E1
            ld a, (DSEG + D_SOUND_ON)
            or a
            jp z, om_music
            ld hl, $34F0
om_music:
            call dsw
            ld (DSEG + $350C), hl
            ld a, (om_si)
            dec a
            ld (DSEG + $3506), a
            ld hl, $34FF
            call dialog
            ld (om_si), a
            cp 1
            jp z, om_joystick
            cp 2
            jp z, om_sound
            cp 3
            jp z, om_new
            cp 4
            jp z, om_end
            cp 5
            jp nz, om_show
            xor a
            ret
om_joystick:
            ld a, (DSEG + $08C5)
            xor 1
            ld (DSEG + $08C5), a
            jp om_show
om_sound:                           ; with the music off the tunes still run, silently
            ld a, (DSEG + D_SOUND_ON)
            xor 1
            ld (DSEG + D_SOUND_ON), a
            ld hl, $8000
            ld de, $C000
            jp nz, om_flags
            ld hl, $A000
            ld de, $E000
om_flags:
            ld (DSEG + D_TUNE_ONCE), hl
            ld (DSEG + D_TUNE_LOOP), de
            jp om_show
om_new:
            ld hl, 1
            ld (DSEG + $2B), hl
            ld (DSEG + D_GAME_OVER), hl
            ld a, 1
            ret
om_end:
            ld hl, 1
            ld (DSEG + D_QUIT), hl
            ld (DSEG + D_GAME_OVER), hl
            ld a, 1
            ret

; 1A91: A = 1 when the month goes on (the orders other than Pass and Options: not yet)
orders_menu:
            call redraw_map
            ld hl, $2BC2
            call dialog
            ld (DSEG + $2BC9), a
            cp 1
            jp z, om_tournament
            cp 2
            jp z, seek_conquest
            cp 4
            jp z, buy_army
            cp 5
            jp z, read_map
            cp 6
            jp z, om_pass
            cp 7
            jp z, options_menu
            xor a                   ; (Go Raiding: still to come)
            ret
om_tournament:
            ld a, (DSEG + D_PLAYER)
            jp tournament
om_pass:
            ld hl, $3FE1            ; "... passes": the player's name
            ld de, $038F
            call str_append
            push hl
            ld c, S_NAME
            call player_w
            pop de
            call str_append
            ex de, hl
            ld hl, $3FE7
            call str_append
            ld hl, $2C97
            call dialog
            ld a, 1
            ret

; 4316: at the start of the player's month, if a Norman has kidnapped a lady
; (the raid comes with Go Raiding: none is kidnapped yet)
rescue_offer:
            xor a
            ret


; ------------------------------------------------------------------ the month (1B44)

; the back page cleared (colour 0)
clear_back:
            xor a
            ld (rc_x), a
            ld (rc_y), a
            ld a, 80
            ld (rc_w), a
            ld a, SCREEN_H
            ld (rc_h), a
            ld hl, 0
            ld (rc_colour), hl
            jp fill_rect

month:
            ld a, 1
mo_side:
            ld (mo_si), a
            call side_income
            ld a, (mo_si)
            ld hl, DSEG + D_PLAYER
            cp (hl)
            jp nz, mo_ai
            ld hl, (DSEG + D_MONTH)
            inc hl
            ld (DSEG + D_MONTH), hl
            call monthly_event
            call month_status
            call rescue_offer
mo_orders:
            or a
            jp nz, mo_ordered
            call orders_menu
            jp mo_orders
mo_ordered:
            ld hl, (DSEG + D_GAME_OVER)
            ld a, h
            or l
            jp nz, mo_after
            call redraw_map
            ld hl, $2C64
            call dialog
            ld c, S_HOME
            call player_w
            ld a, l
            ld b, 4
            call flash_territory
            jp mo_after
mo_ai:
            call ai_turn
mo_after:
            ld a, (mo_si)
            call side_income
            ld a, (DSEG + $073E)    ; the end: the three Norman castles held by one Saxon
            ld c, a
            ld a, (DSEG + $075C)
            cp c
            jp nz, mo_home
            ld a, (DSEG + $077A)
            cp c
            jp nz, mo_home
            ld a, c
            bit 7, a
            jp nz, mo_three
            cp 4
            jp nc, mo_home
mo_three:
            ld (mo_l2), a
            ld hl, 1
            ld (DSEG + D_GAME_OVER), hl
            call clear_back
            ld a, (mo_l2)
            ld hl, DSEG + D_PLAYER
            cp (hl)
            jp nz, mo_lost
            ld a, $9E               ; the player's: won
            ld hl, (DSEG + D_TUNE_ONCE)
            call play_tune
            ld hl, $3986
            call dialog
            ld hl, $3ACF
            call dialog
            ld a, PIC_LAND
            call show_picture
            call set_palette
            call present
            ld hl, $36
            call wait_ticks
            call wait_tune
            jp mo_home
mo_lost:
            ld a, $9D               ; another's: lost
            ld hl, (DSEG + D_TUNE_ONCE)
            call play_tune
            ld hl, $3E93
            call dialog
            call wait_tune
mo_home:
            ld c, S_HOME            ; the home castle
            call player_w
            ld a, l
            call terr_owner
            ld hl, DSEG + D_PLAYER
            cp (hl)
            jp z, mo_held
            ld hl, 1
            ld (DSEG + D_GAME_OVER), hl
            call clear_back
            ld a, $9D
            ld hl, (DSEG + D_TUNE_ONCE)
            call play_tune
            ld hl, $3C14
            call dialog
            call clear_back
            ld hl, $3D5A
            call dialog
            call wait_tune
            jp mo_over
mo_held:
            ld hl, (DSEG + D_QUIT)
            ld a, h
            or l
            jp z, mo_hostile
            ld hl, 1
            ld (DSEG + D_GAME_OVER), hl
            jp mo_over
mo_hostile:                         ; the code adds Buckingham's owner twice, never Cornwall's (1E6C)
            ld a, (DSEG + $075C)
            call sx_a
            add hl, hl
            push hl
            ld a, (DSEG + $073E)
            call sx_a
            pop de
            add hl, de
            ld de, 12
            or a
            sbc hl, de
            bit 7, h
            jp z, mo_over
            ld a, (DSEG + D_PLAYER)
            ld c, a
            ld a, 2
            ld b, 2
            call enmity_add
            ld a, (DSEG + D_PLAYER)
            ld c, a
            ld a, 3
            ld b, 2
            call enmity_add
mo_over:
            ld hl, (DSEG + D_GAME_OVER)
            ld a, h
            or l
            jp z, mo_next
            ld hl, (DSEG + D_QUIT)
            ld a, h
            or l
            ret nz
            ld hl, (DSEG + $2B)
            ld a, h
            or l
            ret nz
            ld hl, $24
            call wait_ticks
            call clear_back
            ld hl, $3541
            call dialog
            ld hl, $356C
            call dialog
            cp 2
            ret nz
            ld hl, 1
            ld (DSEG + D_QUIT), hl
            ret
mo_next:
            ld a, (mo_si)
            inc a
            cp 7
            jp c, mo_side
            ret

; ------------------------------------------------------------------ the game's variables

td_time:    dw 0                ; the clock
td_sec:     ds 3
td_base:    ds 3                ; the BIOS clock at the start
sr_n:       dw 0
lt_lady:    db 0
lt_side:    db 0
lt_flag:    db 0
ea_a:       db 0
ea_b:       db 0
ea_d:       db 0
na_dst:     dw 0
na_n:       dw 0
si_side:    db 0
si_t:       db 0
si_sum:     dw 0
po_item:    db 0
dc_t:       db 0
dc_item:    db 0
rm_t:       db 0
ft_t:       db 0
ft_n:       db 0
ft_t0:      dw 0
ms_si:      dw 0
ms_step:    db 0
ms_lady:    db 0
sl_side:    db 0
sl_home:    db 0
sl_t:       db 0
sh_t:       db 0
sh_side:    db 0
so_owner:   db 0
so_t:       db 0
so_old:     db 0
me_n:       db 0
me_t:       db 0
me_at:      dw 0
me_v:       dw 0
om_si:      db 0
mo_si:      db 0
mo_l2:      db 0
