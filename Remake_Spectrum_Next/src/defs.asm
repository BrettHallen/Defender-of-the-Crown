; Defender of the Crown (1986) - Spectrum Next remake
; Nov 2026 using Claude Opus 5.5
; "Guided" by Brett Hallen
; Original game by Cinemaware (Kellyn Beeck, Jim Sachs, ...)
;
; defs.asm: the constants the program (main.asm) and its overlays (ov_*.asm)
; share: the memory map, the ports, and the original's data segment's names
; (as the Mac remake's game.h has them).

; ------------------------------------------------------------------ the Next

DSEG          EQU $4000           ; the data segment
WINDOW      EQU $E000           ; slot 7
DS_PAGE     EQU 12
BG_PAGE     EQU 16
FONT_PAGE   EQU 20
CHARS_PAGE  EQU 22
PORTRAITS_PAGE EQU 24
SCREEN_BANK EQU 20              ; Layer 2's two buffers (16K banks)
BACK_BANK   EQU 25
SCREEN_PAGE EQU SCREEN_BANK * 2
BACK_PAGE   EQU BACK_BANK * 2
CACHE_PAGE  EQU 60
MAP_PAGE    EQU 84              ; the map, a byte a pixel (map_keep)
SPARE_PAGE  EQU 92              ; the pictures not kept
SWORD_PAGE  EQU 6               ; Ba, the sword fight and the battle's men (pages 6-9)
SLOTPOOL_PAGE EQU 37            ; what the sprite slots cover (pages 37-39)
END_PAGE    EQU 15              ; Bb: THE END, the strength bars, the sparks
SCENE_PAGE  EQU 60              ; after the opening: the scenes' sprites (load_sprites), the saved back page
SIEGE_PAGE  EQU SCENE_PAGE      ; Be (3 pages)
TOURN_PAGE  EQU SCENE_PAGE      ; BX (7)
LANE_PAGE   EQU SCENE_PAGE + 7  ; BY (12)
SAVE_PAGE   EQU SCENE_PAGE + 3  ; the back page saved (gfx_copy_page(PAGE_SAVE, ...)): 8 pages
NUM_SLOTS   EQU 12              ; the sprite slots (gfx.asm): 8 bytes each
SLOT_SIZE   EQU 8
SAVED_SIZE  EQU 9               ; what a slot covers: x (word), y, w (word), rows, the pool's page, offset (word)
OV_SETUP    EQU 2               ; the overlays' pages (ov_*.asm: 8K each, run at 2000h)
OV_WAR      EQU 3
OV_CONQ     EQU 4
OV_SIEGE    EQU 19
OV_TOURN    EQU 23
HI_TAB      EQU DSEG + $5C00    ; 256 bytes: each byte's high nibble (picture_to)
STACK_TOP   EQU $DE00
TOP         EQU 28              ; the picture's first row in Layer 2's 256
SCREEN_H    EQU 200

REG_SELECT  EQU $243B           ; Next register select / access ports
AY_SELECT   EQU $FFFD           ; AY register select (and Turbosound chip select)
AY_DATA     EQU $BFFD
LAYER2_PORT EQU $123B
CTC0        EQU $183B           ; CTC channel 0
CTC_TC      EQU 64              ; its time constant (with the 256 prescaler)
F_OPEN      EQU $9A             ; esxDOS calls (RST 08h, then the code)
F_CLOSE     EQU $9B
F_READ      EQU $9D

OP_COPY     EQU 0               ; blit's ways
OP_XOR      EQU 1
OP_MASKED   EQU 2
IT_GLYPH    EQU 4               ; a sprite item that is a letter
save_buf    EQU DSEG + $5000    ; what the fire covers (64 * 47 bytes, past BH)

KEY_ENTER   EQU $1C             ; the PC's scan codes the game reads
KEY_S       EQU $1F
KEY_SPACE   EQU $39
KEY_UP      EQU $48
KEY_LEFT    EQU $4B
KEY_RIGHT   EQU $4D
KEY_DOWN    EQU $50

; ------------------------------------------------------------------ the data segment (game.h)

D_FIRST_GAME EQU $002F
D_TUNE_ONCE  EQU $0035
D_TUNE_STOP  EQU $0039
D_PLAYER     EQU $0051

PIC_SCROLL   EQU 0
PIC_TITLE    EQU 1
PIC_CAST     EQU 2
PIC_INTRO    EQU 3
PIC_CHOOSE   EQU 4
PIC_SHERWOOD EQU 5
D_RANDOM_N   EQU $0025
D_QUIT       EQU $0029
D_GAME_OVER  EQU $002D
D_SOUND_ON   EQU $0033
D_TUNE_LOOP  EQU $0037
D_MONTH      EQU $0043
D_MONTH_NO   EQU $0045
D_YEAR       EQU $0047
D_MORALE     EQU $0049
D_KIDNAPPED  EQU $0053
D_EVENT_IN   EQU $0055
D_RANDOM     EQU $005B
D_MAP_SHOWN  EQU $0067
D_LEFTRIGHT  EQU $0A9C
D_INCOME_LOST EQU $0D2E

S_NAME       EQU 0
S_PORTRAIT   EQU 4
S_LADY       EQU 6
S_HOME       EQU 8
S_AT         EQU 10
S_JOUST      EQU 14
S_LEAD       EQU 16
S_SWORD      EQU 18
S_INCOME     EQU 20
S_GOLD       EQU 22
T_NAME       EQU 0
T_OWNER      EQU 4
T_CASTLE     EQU 5
T_VASSALS    EQU 6
T_INCOME     EQU 7
L_SIDE       EQU 2
L_TERR       EQU 4
L_FLAG       EQU 6
A_AT         EQU 0
A_BASE       EQU 2
A_SOLDIERS   EQU 4
A_KNIGHTS    EQU 6
A_CATAPULTS  EQU 8

PIC_MAP      EQU 10
PIC_LAND     EQU 11
PIC_PLOTTERS EQU 12
M_GETDATE    EQU $8E            ; esxDOS: the real-time clock
