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
            ld a, (bl_file)         ; the item's offset: the word at 2 * item
            call spr_map
            ld a, (bl_item)
            ld l, a
            ld h, 0
            add hl, hl
            ld e, (hl)
            inc hl
            ld d, (hl)
            ld a, d
            or e
            jp z, bl_done
            ld a, d                 ; its page: the file's + offset / 8192
            rlca
            rlca
            rlca
            and 7
            ld hl, bl_file
            add a, (hl)
            call spr_map
            ld a, d
            and $1F
            ld d, a
            ex de, hl               ; HL: the item (kind, flags, w, h, adv, the columns)
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
            ld a, (bl_file)
            call spr_map
            ld a, (bl_item)
            ld l, a
            ld h, 0
            add hl, hl
            ld e, (hl)
            inc hl
            ld d, (hl)
            ld a, d
            or e
            jp z, bl_done
            ld a, d
            rlca
            rlca
            rlca
            and 7
            ld hl, bl_file
            add a, (hl)
            call spr_map
            ld a, d
            and $1F
            ld h, a
            ld l, e
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

; ------------------------------------------------------------------ pictures, palettes, presenting

; 98C3: picture A to the back page (from the cache, loaded first if need be),
; its palette registers to pal_next
show_picture:
            ld (sp_pic), a
            ld l, a
            ld h, 0
            ld de, pic_loaded
            add hl, de
            ld a, (hl)
            or a
            jp nz, sp_have
            ld a, (sp_pic)
            call load_picture
            ret c
            ld a, (sp_pic)
            ld l, a
            ld h, 0
            ld de, pic_loaded
            add hl, de
            ld (hl), 1
sp_have:
            ld a, (sp_pic)
            ld l, a
            ld h, 0
            ld de, pic_page
            add hl, de
            ld a, (hl)
            ld (sp_page), a
            add a, 3                ; the palette registers: the last page, 1F40h
            call spr_map
            ld hl, $1F40
            ld de, pal_next
            ld bc, 16
            ldir
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
            ld b, SCREEN_H
sp_rows:
            ld a, (hl)
            rrca
            rrca
            rrca
            rrca
            and $0F
            ld (de), a
            ld a, (hl)
            and $0F
            inc d
            ld (de), a
            dec d
            inc hl
            inc e
            djnz sp_rows
            ld hl, sp_pair
            inc (hl)
            jp sp_pairs

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
            call retrace
            call copy_back
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
            call retrace
            ld hl, (dirty_hi)
            ld de, (dirty_lo)
            or a
            sbc hl, de
            jp c, pb_done
            ld (cb_col), de
pb_column:
            ld hl, (cb_col)
            call cb_pages
            ld a, (cb_col)          ; the column's lines 100-199
            and $1F
            ld h, a
            ld l, TOP + 100
            or WINDOW >> 8
            ld d, a
            ld e, l
            ld bc, 100
            call dma_run
            ld hl, (cb_col)
            inc hl
            ld (cb_col), hl
            ld de, (dirty_hi)
            ex de, hl
            or a
            sbc hl, de
            jp nc, pb_column
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
