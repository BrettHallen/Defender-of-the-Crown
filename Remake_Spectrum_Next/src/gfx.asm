; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; gfx.asm: the screen, as the Tandy program drew it (AC 71B9-9F54; the Mac
; remake's gfx.c in Tandy mode). Two Layer 2 320x256 buffers stand for the
; original's pages: the screen (shown) and the back page, which everything is
; drawn on before present copies it to the screen (the Next's DMA). A pixel
; is a byte, the Tandy's colour 0-15 (the palette maps it); the 320x200
; picture sits in rows TOP to TOP + 199; columns are whole in memory (x * 256
; + y), 32 to an 8K page, which slot 7 (WINDOW) is moved onto as needed.
; Sprites (the converter's sprite_blob) are read through slot 0.
;
; Positions are the original's: x in 4-pixel units (the CGA program's bytes)
; where it says so, else in pixels; y in lines.

; ------------------------------------------------------------------ the window

; slot 7 onto page A (unless it is there already); HL kept
win_map:
            push hl
            ld hl, win_page
            cp (hl)
            jp z, wm_done
            ld (hl), a
            nextreg $57, a
wm_done:
            pop hl
            ret

; column HL (0-319), row E (0-199) of the buffer whose first page is D: its
; page in the window, HL its address there
l2_addr:
            push hl
            ld a, l                 ; the page: D + x / 32
            rlca
            rlca
            rlca
            and 7
            ld c, a
            ld a, h
            add a, a
            add a, a
            add a, a
            or c
            add a, d
            call win_map
            pop hl
            ld a, l                 ; E000h + (x & 31) * 256 + TOP + y
            and $1F
            or WINDOW >> 8
            ld h, a
            ld a, e
            add a, TOP
            ld l, a
            ret

; 87DB, AC 7E72: the pixel at HL, E (pixels, lines) of buffer D = A (its colour's
; low nibble), if on the screen
put_pixel:
            and $0F
            ld (pp_colour), a
            ld a, h
            or a
            jp z, pp_x
            ld a, l
            cp 320 - 256
            ret nc
pp_x:
            ld a, e
            cp SCREEN_H
            ret nc
            push hl
            push de
            call l2_addr
            ld a, (pp_colour)
            ld (hl), a
            pop de
            pop hl
            ld a, d                 ; the back page: the column to be presented;
            cp BACK_PAGE            ; the screen itself: the next present puts it all back
            ex de, hl
            jp z, mark_col
            jp mark_all

; A = the pixel at HL, E of buffer D (0 off the screen)
get_pixel:
            ld a, h
            or a
            jp z, gp_x
            ld a, l
            cp 320 - 256
            jp nc, gp_off
gp_x:
            ld a, e
            cp SCREEN_H
            jp nc, gp_off
            call l2_addr
            ld a, (hl)
            ret
gp_off:
            xor a
            ret

; ------------------------------------------------------------------ rectangles

; 80EA: fill the back page's rectangle (x, w in 4-pixel units: rc_x, rc_w; rc_y,
; rc_h in lines) with colour word rc_colour: the Tandy program's high byte,
; its high nibble on even pixels, its low nibble on odd ones (AC 71E5)
fill_rect:
            ld a, (rc_colour + 1)
            ld (rc_byte), a
            ld a, OP_COPY
            jp rect

; 8223: XOR the back page's rectangle with colour byte A (the Tandy program's
; own: its high nibble on even pixels, its low nibble on odd ones)
xor_rect:
            ld (rc_byte), a
            ld a, OP_XOR
rect:
            ld (rc_op), a
            ld a, (rc_x)            ; the pixels: x * 4 to (x + w) * 4
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            ld (rc_col), hl
            ld a, (rc_w)
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            ld (rc_cols), hl
            ld a, (rc_y)            ; the rows on the screen: from y, at most 200 - y
            cp SCREEN_H
            ret nc
            ld c, a
            ld a, SCREEN_H
            sub c
            ld c, a
            ld a, (rc_h)
            or a
            ret z
            cp c
            jp c, rc_rows
            ld a, c
rc_rows:
            ld (rc_n), a
            ld de, (rc_col)         ; its columns are to be presented
            call mark_col
            ld hl, (rc_col)
            ld de, (rc_cols)
            add hl, de
            dec hl
            ex de, hl
            call mark_last
rc_column:
            ld hl, (rc_cols)
            ld a, h
            or l
            ret z
            dec hl
            ld (rc_cols), hl
            ld hl, (rc_col)
            ld a, h                 ; off the right: done
            or a
            jp z, rc_on
            ld a, l
            cp 320 - 256
            ret nc
rc_on:
            ld a, (rc_byte)         ; the column's value: high nibble even, low odd
            bit 0, l
            jp nz, rc_low
            rrca
            rrca
            rrca
            rrca
rc_low:
            and $0F
            ld (rc_value), a
            ld d, BACK_PAGE
            ld a, (rc_y)
            ld e, a
            call l2_addr
            ld a, (rc_n)
            ld b, a
            ld a, (rc_op)
            cp OP_XOR
            ld a, (rc_value)
            ld c, a
            jp z, rc_xor
rc_fill:
            ld (hl), c
            inc l
            djnz rc_fill
            jp rc_next
rc_xor:
            ld a, (hl)
            xor c
            ld (hl), a
            inc l
            djnz rc_xor
rc_next:
            ld hl, (rc_col)
            inc hl
            ld (rc_col), hl
            jp rc_column

; ------------------------------------------------------------------ sprites

; slot 0 onto page A (sprites are read there; FFh: the ROM); HL kept
spr_map:
            push hl
            ld hl, spr_page
            cp (hl)
            jp z, sm_done
            ld (hl), a
            nextreg $50, a
sm_done:
            pop hl
            ret

; the item bl_item of the sprite file whose first page is bl_file, at bl_x
; (pixels), bl_y on the buffer whose first page is bl_dest, by bl_op: OP_COPY
; (8495), OP_XOR (82D2) or OP_MASKED (ANDed with its mask, then ORed: the slot
; sprites and the letters). bl_kind, bl_adv get the item's kind and advance
; (0, 0 if there is no such item). Slot 0 is the ROM again afterwards.
blit:
            xor a
            ld (bl_kind), a
            ld (bl_adv), a
            call find_item          ; HL: the item (kind, flags, w, h, adv, the columns)
            jp z, bl_done
            ld a, (hl)
            ld (bl_kind), a
            inc hl
            ld a, (hl)
            ld (bl_masked), a
            inc hl
            ld e, (hl)
            inc hl
            ld d, (hl)
            inc hl
            ld (bl_w), de
            ld a, (hl)
            ld (bl_h), a
            inc hl
            ld a, (hl)
            ld (bl_adv), a
            inc hl
            ld (bl_src), hl
            ld a, (bl_h)            ; an unmasked item's column: h bytes
            ld e, a
            ld d, 0
            ld (bl_stride), de
            ld a, (bl_y)            ; rows: from y, at most 200 - y
            cp SCREEN_H
            jp nc, bl_done
            ld c, a
            ld a, SCREEN_H
            sub c
            ld c, a
            ld a, (bl_h)
            or a
            jp z, bl_done
            cp c
            jp c, bl_rows
            ld a, c
bl_rows:
            ld hl, bl_maxrows       ; (a slot's rows: at most bl_maxrows)
            cp (hl)
            jp c, bl_rows_n
            ld a, (hl)
bl_rows_n:
            ld (bl_n), a
            ld a, (bl_dest)         ; drawn on the back page: its columns are to be presented
            cp BACK_PAGE
            jp nz, bl_marked
            ld de, (bl_x)
            call mark_col
            ld hl, (bl_x)
            ld de, (bl_w)
            add hl, de
            dec hl
            ex de, hl
            call mark_last
bl_marked:
            ld hl, (bl_x)
            ld (bl_col), hl
bl_column:
            ld hl, (bl_w)
            ld a, h
            or l
            jp z, bl_done
            dec hl
            ld (bl_w), hl
            ld hl, (bl_col)
            ld a, h                 ; off the right: done
            or a
            jp z, bl_on
            ld a, l
            cp 320 - 256
            jp nc, bl_done
bl_on:
            ld a, (bl_masked)
            or a
            jp nz, bl_spanned
            ld a, (bl_dest)
            ld d, a
            ld a, (bl_y)
            ld e, a
            call l2_addr            ; HL: the screen's column
            ex de, hl               ; DE: the screen's column, HL: the item's
            ld hl, (bl_src)
            ld a, (bl_n)
            ld b, a
            ld a, (bl_op)
            cp OP_XOR
            jp z, bl_xor
bl_copy:
            ld a, (hl)
            ld (de), a
            inc hl
            inc e
            djnz bl_copy
            jp bl_next
bl_xor:
            ld a, (de)
            xor (hl)
            ld (de), a
            inc hl
            inc e
            djnz bl_xor
            jp bl_next
bl_spanned:                         ; a masked item's column: its span's first row and length,
            ld a, (bl_op)           ; then mask and pixel for each row of it
            cp OP_COPY
            jp nz, bl_span
            ld a, (bl_dest)         ; put whole: the see-through rows are its 0 pixels
            ld d, a
            ld a, (bl_y)
            ld e, a
            call l2_addr
            ld a, (bl_n)
            ld b, a
            xor a
bl_zero:
            ld (hl), a
            inc l
            djnz bl_zero
bl_span:
            ld hl, (bl_src)
            ld c, (hl)              ; the first row
            inc hl
            ld b, (hl)              ; the length
            inc hl
            push hl
            ld l, b                 ; the next column's: after 2 * length bytes
            ld h, 0
            add hl, hl
            pop de
            add hl, de
            ld (bl_next_src), hl
            ld (bl_pairs), de
            ld a, b
            or a
            jp z, bl_span_next
            ld a, (bl_maxrows)      ; the rows from the item's top: at most bl_maxrows
            sub c
            jp c, bl_span_next
            jp z, bl_span_next
            cp b
            jp nc, bl_span_rows
            ld b, a
bl_span_rows:
            ld a, (bl_y)            ; the span's first row on the screen, and how many fit
            add a, c
            jp c, bl_span_next
            cp SCREEN_H
            jp nc, bl_span_next
            ld e, a
            ld a, SCREEN_H
            sub e
            cp b
            jp nc, bl_span_fits
            ld b, a
bl_span_fits:
            push bc
            ld a, (bl_dest)
            ld d, a
            ld hl, (bl_col)
            call l2_addr
            pop bc
            ex de, hl               ; DE: the screen, HL: the pairs
            ld hl, (bl_pairs)
            ld a, (bl_op)
            cp OP_MASKED
            jp z, bl_mask
            cp OP_XOR
            jp z, bl_mxor
bl_mcopy:
            inc hl
            ld a, (hl)
            ld (de), a
            inc hl
            inc e
            djnz bl_mcopy
            jp bl_span_next
bl_mxor:
            inc hl
            ld a, (de)
            xor (hl)
            ld (de), a
            inc hl
            inc e
            djnz bl_mxor
            jp bl_span_next
bl_mask:
            ld a, (de)              ; (the screen AND the mask) OR the pixel
            and (hl)
            inc hl
            or (hl)
            inc hl
            ld (de), a
            inc e
            djnz bl_mask
bl_span_next:
            ld hl, (bl_next_src)
            ld (bl_src), hl
            jp bl_next_col
bl_next:
            ld hl, (bl_src)
            ld de, (bl_stride)
            add hl, de
            ld (bl_src), hl
bl_next_col:
            ld hl, (bl_col)
            inc hl
            ld (bl_col), hl
            jp bl_column
bl_done:
            ld a, $FF               ; the ROM again
            jp spr_map

; bl_w, bl_h = the size of item A of sprite file (first page) C (0, 0: none)
item_size:
            ld (bl_item), a
            ld a, c
            ld (bl_file), a
            ld hl, 0
            ld (bl_w), hl
            xor a
            ld (bl_h), a
            call find_item
            jp z, bl_done
            inc hl
            inc hl
            ld e, (hl)
            inc hl
            ld d, (hl)
            inc hl
            ld (bl_w), de
            ld a, (hl)
            ld (bl_h), a
            jp bl_done

; the item bl_item of the sprite file whose first page is bl_file: slot 0 onto
; its page, HL its address there, NZ; Z if the file has no such item (each
; item's 3 bytes at the file's start: its page in the file, its address)
find_item:
            ld a, (bl_file)
            call spr_map
            ld a, (bl_item)
            ld l, a
            ld h, 0
            ld e, l
            ld d, h
            add hl, hl
            add hl, de
            ld c, (hl)
            inc hl
            ld e, (hl)
            inc hl
            ld d, (hl)
            ld a, c
            or e
            or d
            ret z
            ld a, (bl_file)
            add a, c
            call spr_map
            ex de, hl
            or 1
            ret

; the item A of sprite file (first page) C at HL (pixels), E on the back page, by B (OP_...)
sprite:
            ld (bl_item), a
            ld a, c
            ld (bl_file), a
            ld (bl_x), hl
            ld a, e
            ld (bl_y), a
            ld a, b
            ld (bl_op), a
            ld a, BACK_PAGE
            ld (bl_dest), a
            jp blit

; 8591, AC 73BB: letter A at HL (pixels), E on the back page; A = its advance
; (the width word / 2 + 1; 0 if the font has no such letter)
glyph:
            push hl
            ld hl, glyph_from       ; gfx_glyph_alias: one letter drawn as another
            cp (hl)
            jp nz, gl_letter
            ld a, (glyph_to)
gl_letter:
            pop hl
            ld c, FONT_PAGE
            ld b, OP_MASKED
            call sprite
            ld a, (bl_kind)
            cp IT_GLYPH
            ld a, (bl_adv)
            ret z
            xor a
            ret

; ------------------------------------------------------------------ saving a rectangle

; the back page's columns HL (pixels) to HL + sv_w - 1, rows E to E + sv_h - 1,
; to save_buf (sv_save) or back from it (sv_restore), a column at a time by
; the DMA. Columns off the screen are left out (the same ones both ways).
sv_save:
            xor a
            jp sv_go
sv_restore:
            ld a, 1
sv_go:
            ld (sv_dir), a
            ld (sv_col), hl
            or a
            jp z, sv_marked
            push hl                 ; restoring: the columns are to be presented
            push de
            ex de, hl
            call mark_col
            pop de
            pop hl
            push hl
            push de
            ld a, (sv_w)
            ld e, a
            ld d, 0
            add hl, de
            dec hl
            ex de, hl
            call mark_last
            pop de
            pop hl
sv_marked:
            ld a, e
            ld (sv_y), a
            ld hl, save_buf
            ld (sv_ptr), hl
            ld a, (sv_w)
            ld (sv_left), a
sv_column:
            ld a, (sv_left)
            or a
            ret z
            dec a
            ld (sv_left), a
            ld hl, (sv_col)
            ld a, h
            or a
            jp z, sv_on
            ld a, l
            cp 320 - 256
            ret nc
sv_on:
            ld d, BACK_PAGE
            ld a, (sv_y)
            ld e, a
            call l2_addr            ; HL: the column
            ld de, (sv_ptr)         ; DE: the buffer
            ld a, (sv_h)
            ld c, a
            ld b, 0
            push bc
            ld a, (sv_dir)
            or a
            jp z, sv_dma
            ex de, hl               ; restoring: the buffer to the column
sv_dma:
            call dma_run
            pop bc
            ld hl, (sv_ptr)
            add hl, bc
            ld (sv_ptr), hl
            ld hl, (sv_col)
            inc hl
            ld (sv_col), hl
            jp sv_column

; ------------------------------------------------------------------ the picture's proportions (the copper)

; The PC showed its 320x200 on a 4:3 screen, its pixels taller than wide; the
; Next's 320x256 fills one with near-square pixels. So the copper (the Next's
; display co-processor) shows the picture's 200 lines on 240 of the 256: one
; line in five shown twice, by Layer 2's vertical scroll (NextReg 17h) set
; back a line every 6 lines, in the right border's blanking. Nothing is drawn
; differently. V switches it on and off (scan_keys): off at the start.
;
; Display line s (0-255) shows the buffer's row s + scroll: rows 0-27 and
; 228-255 are black, the picture is in 28-227. The scroll is 20 for lines
; 0-8, then 19 - j from line 9 + 6j (j = 0-39): line 247 shows row 227.
; The copper's line 0 is the ULA's first (the 256 lines' 33rd); its WAIT
; matches the line exactly, and it starts again at line 0 each frame
; (mode 11), so the 32 lines above come at the end of the previous frame.

; At the start: the frame's line count (cp_lines); the picture as it is, until V
stretch_init:
            ld a, $11               ; HDMI: 312 (50 Hz), 262 (60 Hz)
            call get_reg
            and 7
            cp 7
            ld hl, 312
            jp z, si_hz
            ld a, $03               ; else by the machine's timing: 128K and +3, 311 and 261
            call get_reg
            rrca
            rrca
            rrca
            rrca
            and 7
            cp 2
            jp z, si_128
            cp 3
            jp z, si_128
            cp 4
            jp nz, si_hz
            ld hl, 320              ; Pentagon (50 Hz only)
            jp si_lines
si_128:
            ld hl, 311
si_hz:
            ld a, $05               ; 60 Hz: 50 lines fewer
            call get_reg
            and 4
            jp z, si_lines
            ld de, -50
            add hl, de
si_lines:
            ld (cp_lines), hl
            ret

; the copper's program written, and started
stretch_on:
            ld a, 1
            ld (stretched), a
            nextreg $62, $00        ; stopped, at instruction 0
            nextreg $61, $00
            ld a, 4                 ; the changes on lines 0-223 (display 33 on): j = 4-39
            ld (cp_j), a
co_mid:
            ld a, (cp_j)
            ld b, a
            add a, a
            add a, b
            add a, a                ; 6j
            sub 24                  ; WAIT line 6j - 24 (the line before 9 + 6j - 32)
            ld l, a
            ld h, 0
            ld a, 19
            sub b
            call co_change
            ld hl, cp_j
            inc (hl)
            ld a, (hl)
            cp 40
            jp nz, co_mid
            ld hl, (cp_lines)       ; then the top 32 lines, at the frame's end: scroll 20 from
            ld de, -33              ; display line 0 (the line before: lines - 33)
            add hl, de
            ld a, 20
            call co_change
            xor a                   ; j = 0-3: lines - 24 + 6j
            ld (cp_j), a
co_top:
            ld a, (cp_j)
            ld b, a
            add a, a
            add a, b
            add a, a
            ld e, a
            ld d, 0
            ld hl, (cp_lines)
            add hl, de
            ld de, -24
            add hl, de
            ld a, 19
            sub b
            call co_change
            ld hl, cp_j
            inc (hl)
            ld a, (hl)
            cp 4
            jp nz, co_top
            ld a, $FF               ; HALT
            nextreg $60, a
            nextreg $60, a
            nextreg $62, $C0        ; on: from instruction 0 at each frame's line 0
            ret

; WAIT for line HL at H 40 (320 pixels: the blanking after Layer 2's right
; edge, 288), then MOVE A into NextReg 17h
co_change:
            ld c, a
            ld a, h
            and 1
            or $80 + (40 << 1)      ; 1HHHHHHV
            nextreg $60, a
            ld a, l
            nextreg $60, a
            ld a, $17
            nextreg $60, a
            ld a, c
            nextreg $60, a
            ret

; the copper stopped, the picture as it is (200 lines)
stretch_off:
            xor a
            ld (stretched), a
            nextreg $62, $00
            nextreg $17, 0
            ret

; V: one or the other
stretch_toggle:
            ld a, (stretched)
            or a
            jp nz, stretch_off
            jp stretch_on

; ------------------------------------------------------------------ the sprite slots (gfx.c)

; The game's sprite slots (12, the Mac remake's gfx_video()->slot): set them,
; then sprites_draw puts each (11 first, so 0 is on top) masked on the back
; page, keeping what it covers in the pool's pages (SLOTPOOL_PAGE on), and
; sprites_erase, after the present, puts that back (0 first).
; A slot: active, x (word, pixels), y, its file's page, its item, trim (rows
; left off its bottom), rows (if not 0: at most these).

; slot A: item B of file (page) C at HL (pixels), E; trim and rows 0
slot_set:
            push bc
            push de
            push hl
            call slot_at
            pop hl
            pop de
            pop bc
            ld (ix + 0), 1
            ld (ix + 1), l
            ld (ix + 2), h
            ld (ix + 3), e
            ld (ix + 4), c
            ld (ix + 5), b
            ld (ix + 6), 0
            ld (ix + 7), 0
            ret

; IX = slot A's record (DE changed)
slot_at:
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            add hl, hl
            ld de, slots
            add hl, de
            push hl
            pop ix
            ret

; every slot off
slots_off:
            ld hl, slots
            ld de, SLOT_SIZE
            ld b, NUM_SLOTS
so_slot:
            ld (hl), 0
            add hl, de
            djnz so_slot
            ret

sprites_draw:
            ld a, SLOTPOOL_PAGE
            ld (pool_page), a
            ld hl, 0
            ld (pool_off), hl
            ld a, NUM_SLOTS - 1
sd_slot:
            ld (sd_k), a
            call sd_saved           ; not kept, so far
            ld (iy + 5), 0
            ld a, (sd_k)
            call slot_at
            ld a, (ix + 0)
            or a
            jp z, sd_next
            ld a, (ix + 5)          ; its size
            ld c, (ix + 4)
            call item_size
            ld a, (bl_h)            ; the rows: h - trim, at most rows (if set)
            sub (ix + 6)
            jp c, sd_next
            jp z, sd_next
            ld c, a
            ld a, (ix + 7)
            or a
            jp z, sd_rows
            cp c
            jp nc, sd_rows
            ld c, a
sd_rows:
            ld a, c
            ld (bl_maxrows), a
            ld a, (ix + 3)          ; on the screen: at most 200 - y of them
            cp SCREEN_H
            jp nc, sd_next
            ld b, a
            ld a, SCREEN_H
            sub b
            cp c
            jp nc, sd_fit
            ld c, a
sd_fit:
            ld (iy + 5), c          ; what it covers, kept
            ld a, (ix + 1)
            ld (iy + 0), a
            ld a, (ix + 2)
            ld (iy + 1), a
            ld a, (ix + 3)
            ld (iy + 2), a
            ld hl, (bl_w)
            ld (iy + 3), l
            ld (iy + 4), h
            ld a, (pool_page)
            ld (iy + 6), a
            ld hl, (pool_off)
            ld (iy + 7), l
            ld (iy + 8), h
            xor a
            call pool_copy
            ld l, (ix + 1)          ; then the sprite
            ld h, (ix + 2)
            ld e, (ix + 3)
            ld c, (ix + 4)
            ld a, (ix + 5)
            ld b, OP_MASKED
            call sprite
sd_next:
            ld a, (sd_k)
            dec a
            jp p, sd_slot
            ld a, 255
            ld (bl_maxrows), a
            jp bl_done

sprites_erase:
            xor a
se_slot:
            ld (sd_k), a
            call sd_saved
            ld a, (iy + 5)
            or a
            jp z, se_next
            ld a, (sd_k)            ; (an inactive slot is left as drawn)
            call slot_at
            ld a, (ix + 0)
            or a
            jp z, se_next
            ld e, (iy + 0)          ; its columns are to be presented
            ld d, (iy + 1)
            call mark_col
            ld l, (iy + 0)
            ld h, (iy + 1)
            ld e, (iy + 3)
            ld d, (iy + 4)
            add hl, de
            dec hl
            ex de, hl
            call mark_last
            ld a, 1
            call pool_copy
            ld (iy + 5), 0
se_next:
            ld a, (sd_k)
            inc a
            cp NUM_SLOTS
            jp c, se_slot
            jp bl_done

; what saved record IY covers, from the back page to its place in the pool
; (A = 0) or back (A = 1): column by column, by the DMA (a column never
; across a page of the pool)
pool_copy:
            ld (pc_dir), a
            ld a, (iy + 6)
            ld (pc_page), a
            ld l, (iy + 7)
            ld h, (iy + 8)
            ld (pc_off), hl
            ld l, (iy + 3)          ; the columns on the screen: HL how many, DE the first
            ld h, (iy + 4)
            ld e, (iy + 0)
            ld d, (iy + 1)
            bit 7, d
            jp z, pc_right
            add hl, de              ; (starting left of it: the w + x on it, from 0)
            ld de, 0
            bit 7, h
            jp nz, pc_done
pc_right:
            ld a, h
            or l
            jp z, pc_done
            ld b, h
            ld c, l
            ld hl, 319              ; at most to the right edge
            or a
            sbc hl, de
            jp c, pc_done
            inc hl
            or a
            sbc hl, bc
            jp nc, pc_count
            add hl, bc
            ld b, h
            ld c, l
pc_count:
            ld (pc_left), bc
            ex de, hl
            ld d, BACK_PAGE
            ld e, (iy + 2)
            call l2_addr            ; the first column's address in the window (slot 7)
            ld (pc_scr), hl
            ld a, (iy + 5)          ; each column's rows: the DMA's length
            ld (dma_copy + 4), a
            xor a
            ld (dma_copy + 5), a
            ld a, (pc_page)
            call spr_map            ; the pool (slot 0)
pc_column:
            ld c, (iy + 5)          ; room in this page of the pool? (a column never across one)
            ld b, 0
            ld hl, (pc_off)
            add hl, bc
            ld de, $2001
            or a
            sbc hl, de
            jp c, pc_room
            ld hl, pc_page
            inc (hl)
            ld a, (hl)
            call spr_map
            ld hl, 0
            ld (pc_off), hl
pc_room:
            ld hl, (pc_scr)
            ld de, (pc_off)
            ld a, (pc_dir)
            or a
            jp z, pc_dma
            ex de, hl
pc_dma:
            ld (dma_copy + 2), hl   ; the DMA's program, its addresses set
            ld (dma_copy + 11), de
            call dma_go
            ld hl, (pc_off)
            ld c, (iy + 5)
            ld b, 0
            add hl, bc
            ld (pc_off), hl
            ld hl, (pc_left)
            dec hl
            ld (pc_left), hl
            ld a, h
            or l
            jp z, pc_done
            ld hl, pc_scr + 1       ; the next column: 256 on, or the next page's first
            inc (hl)
            jp nz, pc_column
            ld (hl), WINDOW >> 8
            ld a, (win_page)
            inc a
            call win_map
            jp pc_column
pc_done:
            ld a, (pc_page)
            ld (pool_page), a
            ld hl, (pc_off)
            ld (pool_off), hl
            ret

; IY = slot sd_k's saved record
sd_saved:
            ld a, (sd_k)
            ld l, a
            ld h, 0
            ld d, h
            ld e, l
            add hl, hl
            add hl, hl
            add hl, hl
            add hl, de
            ld de, slot_saved
            add hl, de
            push hl
            pop iy
            ret

; ------------------------------------------------------------------ pictures, palettes, presenting

; 98C3: picture A to the back page (from the cache, loaded first if need be),
; its palette registers to pal_next
show_picture:
            call pic_cached
            ret c
sp_have:
            ld de, pal_next         ; its palette to pal_next
            call pic_palette
            ld a, (sp_pic)
            jp pt_have

; 9993: picture A to the back page (its palette left alone)
picture_to:
            call pic_cached
            ret c
pt_have:
            ld a, (sp_pic)
            ld l, a
            ld h, 0
            ld de, pic_page
            add hl, de
            ld a, (hl)
            ld (sp_page), a
            call mark_all
            xor a                   ; the 160 column pairs, 40 to a page
            ld (sp_pair), a
sp_pairs:
            ld a, (sp_pair)
            cp 160
            jp z, bl_done           ; (slot 0: the ROM again)
            ld c, 0                 ; the source page: pair / 40, offset (pair % 40) * 200
sp_div:
            cp 40
            jp c, sp_mod
            sub 40
            inc c
            jp sp_div
sp_mod:
            ld l, a                 ; HL = (pair % 40) * 200
            ld h, 0
            add hl, hl
            add hl, hl
            add hl, hl              ; 8
            ld d, h
            ld e, l
            add hl, hl
            add hl, hl              ; 32
            add hl, de              ; 40
            ld d, h
            ld e, l
            add hl, hl
            add hl, hl              ; 160
            add hl, de              ; 200
            push hl
            ld a, (sp_page)
            add a, c
            call spr_map
            ld a, (sp_pair)         ; the destination: columns 2 * pair and the next
            ld l, a
            ld h, 0
            add hl, hl
            ld d, BACK_PAGE
            ld e, 0
            call l2_addr
            ex de, hl               ; DE: column 2p, row 0; D + 1: column 2p + 1
            pop hl                  ; HL: the pair's 200 bytes (2p in the high nibbles)
            ld b, HI_TAB >> 8       ; (BC: the high nibble of C, from the table)
            ld a, SCREEN_H / 8
            ld (sp_n), a
sp_rows:                            ; 8 rows at a time
            ld c, (hl)
            ld a, (bc)
            ld (de), a
            ld a, c
            and $0F
            inc d
            ld (de), a
            dec d
            inc hl
            inc e
            ld c, (hl)
            ld a, (bc)
            ld (de), a
            ld a, c
            and $0F
            inc d
            ld (de), a
            dec d
            inc hl
            inc e
            ld c, (hl)
            ld a, (bc)
            ld (de), a
            ld a, c
            and $0F
            inc d
            ld (de), a
            dec d
            inc hl
            inc e
            ld c, (hl)
            ld a, (bc)
            ld (de), a
            ld a, c
            and $0F
            inc d
            ld (de), a
            dec d
            inc hl
            inc e
            ld c, (hl)
            ld a, (bc)
            ld (de), a
            ld a, c
            and $0F
            inc d
            ld (de), a
            dec d
            inc hl
            inc e
            ld c, (hl)
            ld a, (bc)
            ld (de), a
            ld a, c
            and $0F
            inc d
            ld (de), a
            dec d
            inc hl
            inc e
            ld c, (hl)
            ld a, (bc)
            ld (de), a
            ld a, c
            and $0F
            inc d
            ld (de), a
            dec d
            inc hl
            inc e
            ld c, (hl)
            ld a, (bc)
            ld (de), a
            ld a, c
            and $0F
            inc d
            ld (de), a
            dec d
            inc hl
            inc e
            ld a, (sp_n)
            dec a
            ld (sp_n), a
            jp nz, sp_rows
            ld hl, sp_pair
            inc (hl)
            jp sp_pairs

; picture A in the cache (read from the card if need be): sp_pic = A; carry if it can't be read
pic_cached:
            ld (sp_pic), a
            ld l, a
            ld h, 0
            ld de, pic_loaded
            add hl, de
            ld a, (hl)
            or a
            ret nz                  ; (no carry)
            ld a, (sp_pic)          ; one kept in the spare pages: the one there before is not
            ld l, a
            ld h, 0
            ld de, pic_page
            add hl, de
            ld a, (hl)
            cp SPARE_PAGE
            jp nz, pc_load
            ld a, (spare_pic)
            cp $FF
            jp z, pc_spare
            ld l, a
            ld h, 0
            ld de, pic_loaded
            add hl, de
            ld (hl), 0
pc_spare:
            ld a, (sp_pic)
            ld (spare_pic), a
pc_load:
            ld a, (sp_pic)
            call load_picture
            ret c
            ld a, (sp_pic)
            ld l, a
            ld h, 0
            ld de, pic_loaded
            add hl, de
            ld (hl), 1
            or a
            ret

; picture sp_pic's 16 palette registers (cached) to DE
pic_palette:
            push de
            ld a, (sp_pic)
            ld l, a
            ld h, 0
            ld de, pic_page
            add hl, de
            ld a, (hl)
            add a, 3                ; the last page, 1F40h
            call spr_map
            pop de
            ld hl, $1F40
            ld bc, 16
            ldir
            jp bl_done

; ------------------------------------------------------------------ the map's own copy

; At the start: the map (picture 10, read into the spare pages) unpacked into
; MAP_PAGE's 8 pages, a byte a pixel, 40 columns of 200 to a page, so that
; redraw_map puts it on the back page by the DMA (gfx_copy_page(PAGE_BACK,
; PAGE_MAP)) and not by unpacking it each time; its palette into slot 0
; (9C31: gfx_keep_palette(PIC_MAP, 0)). Carry if it can't be read.
map_keep:
            ld a, PIC_MAP
            call pic_cached
            ret c
            ld de, pal_slot
            call pic_palette
            xor a
            ld (sp_pair), a
mk_pair:
            ld a, (sp_pair)         ; the source: pair / 40, (pair % 40) * 200, as picture_to
            ld c, 0
mk_div:
            cp 40
            jp c, mk_mod
            sub 40
            inc c
            jp mk_div
mk_mod:
            ld (mk_k), a
            ld a, (pic_page + PIC_MAP)
            add a, c
            call spr_map
            ld a, c                 ; the destination: columns 2p and 2p + 1, 20 pairs a page
            add a, a                ; (page (2p) / 40 = 2c or 2c + 1)
            ld c, a
            ld a, (mk_k)
            cp 20
            jp c, mk_first
            sub 20
            inc c
mk_first:
            ld e, a                 ; the even column's address: (2p % 40) * 200 = (k mod 20) * 400
            ld a, MAP_PAGE
            add a, c
            call win_map
            ld l, e
            ld h, 0
            add hl, hl
            add hl, hl
            add hl, hl
            add hl, hl              ; 16k
            ld d, h
            ld e, l
            add hl, hl              ; 32k
            ld b, h
            ld c, l
            add hl, hl
            add hl, hl
            add hl, hl              ; 256k
            add hl, bc
            add hl, de              ; 304k ... + 96k:
            ld b, h
            ld c, l
            ld hl, 0
            add hl, de
            add hl, de
            add hl, de
            add hl, de
            add hl, de
            add hl, de              ; 96k
            add hl, bc              ; 400k
            ld de, WINDOW
            add hl, de
            ex de, hl               ; DE: the even column's 200 bytes; + 200 the odd one's
            ld a, (mk_k)            ; the source's 200 bytes: k * 200
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            add hl, hl
            ld b, h
            ld c, l
            add hl, hl
            add hl, hl
            add hl, bc
            ld b, h
            ld c, l
            add hl, hl
            add hl, hl
            add hl, bc
            ld b, SCREEN_H
mk_rows:
            ld a, (hl)
            rrca
            rrca
            rrca
            rrca
            and $0F
            ld (de), a
            push de
            ex de, hl
            ld a, l                 ; the odd column: 200 on
            add a, SCREEN_H
            ld l, a
            jp nc, mk_odd
            inc h
mk_odd:
            ex de, hl
            ld a, (hl)
            and $0F
            ld (de), a
            pop de
            inc hl
            inc de
            djnz mk_rows
            ld hl, sp_pair
            inc (hl)
            ld a, (hl)
            cp 160
            jp nz, mk_pair
            jp bl_done

; the map's copy onto the back page: each column's 200 bytes by the DMA
map_to_back:
            ld a, MAP_PAGE
            ; (on into from_compact)

; the back page from a copy kept a byte a pixel from page A on (40 columns of
; 200 to a page), all of it to be presented; to_compact: the other way
from_compact:
            ld c, 0
            push af
            call mark_all
            pop af
            jp compact_copy
to_compact:
            ld c, 1
compact_copy:
            ld (mb_page), a
            ld a, c
            ld (mb_dir), a
            ld hl, 0
            ld (mb_x), hl
            ld (mb_src), hl
            xor a
            ld (mk_k), a
mb_column:
            ld a, (mb_page)
            call spr_map
            ld hl, (mb_x)           ; the back page's page for the column: x / 32
            ld a, l
            rlca
            rlca
            rlca
            and 7
            ld c, a
            ld a, h
            add a, a
            add a, a
            add a, a
            or c
            add a, BACK_PAGE
            call win_map
            ld a, l                 ; its address: (x % 32) * 256 + TOP
            and $1F
            or WINDOW >> 8
            ld d, a
            ld e, TOP
            ld hl, (mb_src)
            ld bc, SCREEN_H
            ld a, (mb_dir)
            or a
            jp z, mb_dma
            ex de, hl
mb_dma:
            call dma_run
            ld hl, (mb_src)         ; the next column
            ld de, SCREEN_H
            add hl, de
            ld (mb_src), hl
            ld hl, mk_k
            inc (hl)
            ld a, (hl)
            cp 40
            jp nz, mb_next
            ld (hl), 0
            ld hl, 0
            ld (mb_src), hl
            ld hl, mb_page
            inc (hl)
mb_next:
            ld hl, (mb_x)
            inc hl
            ld (mb_x), hl
            ld a, h
            or a
            jp z, mb_column
            ld a, l
            cp 320 - 256
            jp c, mb_column
            jp bl_done

; gfx_copy_page(PAGE_SAVE, PAGE_BACK), and back: the back page kept in
; SAVE_PAGE's 8 (which the tournament's and the lane's sprites leave)
save_back:
            ld a, (scene_has)
            and 1
            ld (scene_has), a
            ld a, SAVE_PAGE
            jp to_compact
restore_back:
            ld a, SAVE_PAGE
            jp from_compact

; 9C31: picture A's palette to the slot (one slot: 0, the map's)
keep_palette:
            call pic_cached
            ret c
            ld de, pal_slot
            jp pic_palette

; 9C5F: the slot to pal_next
use_palette:
            ld hl, pal_slot
            ld de, pal_next
            ld bc, 16
            ldir
            ret

; 9CA1: show pal_next (the 16 palette registers: each one of the Tandy's 16 colours)
set_palette:
            ld hl, pal_next
            ld de, pal
            ld bc, 16
            ldir
            nextreg $43, $10        ; Layer 2's first palette
            nextreg $40, 0
            ld hl, pal
            ld b, 16
spl_entry:
            push hl
            ld a, (hl)
            and $0F
            add a, a
            ld e, a
            ld d, 0
            ld hl, rgb16
            add hl, de
            ld a, (hl)
            nextreg $44, a
            inc hl
            ld a, (hl)
            nextreg $44, a
            pop hl
            inc hl
            djnz spl_entry
            ret

; ------------------------------------------------------------------ what changed

; column DE (pixels) of the back page has changed (since the last present)
mark_col:
            ld a, d                 ; off the screen: nothing
            or a
            jp z, mc_on
            ld a, e
            cp 320 - 256
            ret nc
mc_on:
            ld hl, (dirty_lo)
            or a
            sbc hl, de
            jp c, mc_hi
            ld (dirty_lo), de
mc_hi:
            ld hl, (dirty_hi)
            or a
            sbc hl, de
            ret nc
            ld (dirty_hi), de
            ret

; columns up to DE (pixels, kept to the screen) have: with mark_col, a run
mark_last:
            ld hl, 319
            or a
            sbc hl, de
            jp nc, mark_col
            ld de, 319
            jp mark_col

; every column has
mark_all:
            ld hl, 0
            ld (dirty_lo), hl
            ld hl, 319
            ld (dirty_hi), hl
            ret

; nothing has
mark_none:
            ld hl, 320
            ld (dirty_lo), hl
            ld hl, 0
            ld (dirty_hi), hl
            ret

; 9902: the retrace, then the back page to the screen (the columns that changed)
present:
            ld a, (retraces)        ; a retrace since the last (the drawing took that long): at once
            ld hl, pr_retrace
            cp (hl)
            call z, retrace
            ld a, (retraces)
            ld (pr_retrace), a
            call copy_back
            ld a, (pal_late)        ; a palette waiting for this picture
            or a
            jp z, frame_done
            xor a
            ld (pal_late), a
            call set_palette
            jp frame_done

; the changed columns of the back page to the screen: each 8K page's run of
; them at once (a column is 256 bytes, 32 to a page), by the DMA from slot 0
; (the back page's page) to slot 7 (the screen's)
copy_back:
            ld hl, (dirty_hi)
            ld de, (dirty_lo)
            or a
            sbc hl, de
            jp c, bl_done           ; nothing changed (slot 0: the ROM again)
            ld (cb_col), de
cb_run:
            ld hl, (cb_col)         ; the page: column / 32; the run to the page's last, or dirty_hi
            ld a, l
            or $1F
            ld e, a
            ld d, h
            ld hl, (dirty_hi)
            or a
            sbc hl, de
            jp nc, cb_last
            ld de, (dirty_hi)
cb_last:
            ld (cb_end), de
            ld hl, (cb_col)
            call cb_pages
            ld hl, (cb_end)         ; the length: (end - col + 1) * 256
            ld de, (cb_col)
            or a
            sbc hl, de
            inc l
            ld b, l
            ld c, 0
            ld a, e                 ; the offset: (col & 31) * 256
            and $1F
            ld h, a
            ld l, 0
            ld d, a
            ld a, d
            or WINDOW >> 8
            ld d, a
            ld e, 0
            call dma_run
            ld hl, (cb_end)
            inc hl
            ld (cb_col), hl
            ld de, (dirty_hi)
            ex de, hl
            or a
            sbc hl, de
            jp nc, cb_run
            call mark_none
            jp bl_done

; slots 0 and 7 onto the back page's and the screen's pages for column HL
cb_pages:
            ld a, l
            rlca
            rlca
            rlca
            and 7
            ld c, a
            ld a, h
            add a, a
            add a, a
            add a, a
            or c
            push af
            add a, BACK_PAGE
            call spr_map
            pop af
            add a, SCREEN_PAGE
            jp win_map

; 994A: the retrace, then lines 100-199 of the back page to the screen (in the
; columns that changed; they stay changed, for the next present's lines 0-99)
present_bottom:
            ld a, (retraces)        ; (as present: at once if the drawing took a retrace)
            ld hl, pr_retrace
            cp (hl)
            call z, retrace
            ld a, (retraces)
            ld (pr_retrace), a
            ld hl, (dirty_hi)
            ld de, (dirty_lo)
            or a
            sbc hl, de
            jp c, pb_done
            ld (cb_col), de
            ld hl, 100              ; each column's lines 100-199
            ld (dma_copy + 4), hl
pb_pages:
            ld hl, (cb_col)         ; (the pages of these 32 columns)
            call cb_pages
pb_column:
            ld a, (cb_col)
            and $1F
            ld h, a
            ld l, TOP + 100
            ld (dma_copy + 2), hl
            or WINDOW >> 8
            ld h, a
            ld (dma_copy + 11), hl
            call dma_go
            ld hl, (cb_col)
            inc hl
            ld (cb_col), hl
            ld de, (dirty_hi)
            ex de, hl
            or a
            sbc hl, de
            jp c, pb_done
            ld a, (cb_col)
            and $1F
            jp z, pb_pages
            jp pb_column
pb_done:
            call bl_done
            jp frame_done

; the DMA: BC bytes from HL to DE
dma_run:
            ld (dma_copy + 2), hl
            ld (dma_copy + 4), bc
            ld (dma_copy + 11), de
            ld hl, dma_copy
            ld bc, DMA_COPY_LEN * 256 + DMA_PORT
            otir
            ret

; the DMA's program as it is (its addresses and length set) sent
dma_go:
            ld hl, dma_copy
            ld bc, DMA_COPY_LEN * 256 + DMA_PORT
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            outi
            ret

; a new screen is up (the test's model records it here)
frame_done:
            ret

DMA_PORT    EQU $6B
dma_copy:
            db $83                  ; disable the DMA
            db $7D                  ; WR0: A to B, port A's address and the length follow
            dw $0000                ;   port A
            dw $2000                ;   the length
            db $54, $02             ; WR1: port A memory, incrementing; cycle length 2
            db $50, $02             ; WR2: port B memory, incrementing; cycle length 2
            db $AD                  ; WR4: continuous, port B's address follows
            dw WINDOW               ;   port B
            db $82                  ; WR5: stop at the end
            db $CF                  ; WR6: load
            db $87                  ; WR6: enable
DMA_COPY_LEN EQU 16

; ------------------------------------------------------------------ the game's sprite calls

; 8495: item A of file C at HL (4-pixel units), E, put whole
put_sprite:
            add hl, hl
            add hl, hl
            ld b, OP_COPY
            jp sprite

; 82D2: XORed in
xor_sprite:
            add hl, hl
            add hl, hl
            ld b, OP_XOR
            jp sprite

; 83E2: territory shape A (BR item) at HL (4-pixel units), E: XORed in (its
; colour is in its pixels: set_region_colour)
xor_mask:
            ld c, PORTRAITS_PAGE
            jp xor_sprite

; 9208: item A of file C at HL (pixels), E, masked (the slot sprites)
slot_sprite:
            ld b, OP_MASKED
            jp sprite

; 8223: XOR the back page's rectangle rc_x, rc_y, rc_w, rc_h with the Tandy
; program's colour (the word's low byte: its high nibble on even pixels, its
; low nibble on odd ones)
xor_rect3:
            ld a, (rc_colour)
            jp xor_rect

; AC 943B: territory shape A (BR item) in colour word HL: its pixels that are
; not 0 become Dh XOR the colour's high byte's nibble (even rows; the low
; byte's on odd rows), the nibble by the pixel's column (high even, low odd)
set_region_colour:
            ld (rg_colour), hl
            ld (bl_item), a
            ld a, PORTRAITS_PAGE
            ld (bl_file), a
            call find_item
            jp z, bl_done
            inc hl                  ; past kind, flags
            inc hl
            ld e, (hl)
            inc hl
            ld d, (hl)
            inc hl
            ld (bl_w), de
            ld a, (hl)
            ld (bl_h), a
            inc hl
            inc hl                  ; past adv: the columns
            ld bc, 0                ; the column
rg_column:
            push hl
            ld hl, (bl_w)
            or a
            sbc hl, bc
            pop hl
            jp z, bl_done
            ld a, (rg_colour + 1)   ; the even rows' value and the odd rows'
            bit 0, c
            jp nz, rg_hi_low
            rrca
            rrca
            rrca
            rrca
rg_hi_low:
            and $0F
            xor $0D
            ld d, a
            ld a, (rg_colour)
            bit 0, c
            jp nz, rg_lo_low
            rrca
            rrca
            rrca
            rrca
rg_lo_low:
            and $0F
            xor $0D
            ld e, a
            ld a, (bl_h)
            push bc
            ld b, a
            ld c, 0                 ; the row
rg_row:
            ld a, (hl)
            or a
            jp z, rg_next
            ld a, d
            bit 0, c
            jp z, rg_put
            ld a, e
rg_put:
            ld (hl), a
rg_next:
            inc hl
            inc c
            djnz rg_row
            pop bc
            inc bc
            jp rg_column
