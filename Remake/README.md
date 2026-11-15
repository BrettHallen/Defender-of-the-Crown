# Defender of the Crown - Remake
A modern version of Defender of the Crown (Cinemaware) as it was on the IBM PC, for macOS, written in C with [SDL3](https://www.libsdl.org/). It should also build on Windows and Linux.

The remake is a port of the booter version's EGA program (`AB` in GAME.DAT, `../Analysis/AB.ASM`), routine by routine, and shows the game as each of the PC versions did. **Tab** goes through them at any moment:

| Mode | `--video=` | What it shows |
|---|---|---|
| CGA (1987) | `cga1` | the 1987 DOS version's pictures (DOC.EXE's .LIB files): red map, brown title bricks |
| CGA | `cga2` | the booter's CGA program (AA): its own CGA pictures and sprites |
| EGA | `ega` | the booter's EGA program (AB) |
| Tandy | `tandy` | the booter's Tandy 1000 program (AC), with its three-voice music |

**No original game files are included.** The remake loads everything from your own copy: `GAME.DAT` (the booter version), plus the 1987 version's `TITLE.LIB`, `RAID.LIB`, `JOUST1.LIB`, `JOUST2.LIB`, `DOCCHARS.LIB`, `SIEGE.LIB`, `LOVE1.LIB` and `LOVE2.LIB` for the CGA (1987) pictures. They can be in one folder, or in its `ega/` and `cga/` subfolders (as in the repository's `Original/`).

## Status
Ported and checked against DOSBox (pixel for pixel in EGA where noted):
- **the opening**: the credits (pixel-identical in EGA), the title with its sparkles (a key there skips the rest), the cast, the introduction, the choice of character with the keypad (pixel-identical in CGA), Sherwood with the campfire (pixel-identical in EGA but for the flames, which flicker), and the setup of a new game
- **the month**: the status panel (income counted into the treasure, the date), the map with the territories in their owners' colours and the castles, the orders menu, **Pass**, **Options** (music on/off: the tunes still keep time, silently; Start a New Game; End Present Game), "War rages throughout the land", the end checks (the three Norman castles, the home castle lost, "Would you like to play again?"), the **monthly events** (Vikings, Danes, Norman plotters, Robin's gold, the German knights ...)
- **Buy Home Army**: soldiers, knights and catapults with Right (Left sells back what you bought this time), castles in a territory you choose on the map
- **the computer lords' turns**: income, reinforcing garrisons, the choice of order, buying, castles, conquest (the search for a target, battles and sieges between them, territories changing hands, a lord falling with his home), the Normans' raids (gold taken, ladies kidnapped), armies going home
- **Seek Conquest**: sending your campaign army to a neighbouring territory (on through your own land in the same month), Transfer Forces, Read Map, See Robin (his men join your next attack, three times in a game), a Saxon's offer of safe passage, and **your sieges**: six days of Greek Fire, Disease or Boulders with the catapult (Enter to draw the arm back, Enter to let go), then the battle against the castle's garrison
- **Go Raiding**: choosing another lord's home castle, The Attack against the guards and The Defense against the lord in his hall, with the sword fight on the keypad or the arrows (Enter thrusts, 8/Up raises the sword, 2/Down parries, 4/6 or Left/Right step, 7/9/1/3 step with the sword raised or parrying), the strength bars, and the endings: the enemy's gold, captured (ransom), or the retreat (backing out to the left). Robin's help makes you stronger. A kidnapped lady's rescue is the same raid; her romance scene is not ported yet (its first and last words are shown, and she and her ward's land become yours)
- **Tournaments**: Hold Tournament, and the Saxon lords' own from 1150: the trumpeters, the stakes (Fame, or Land when both sides have land without a castle), the opponent, the knights riding in, the joust down the lane (aim the lance's point with the keypad: 7/8/9 up, 1/2/3 down, 4/6 sideways; the gallop bobs it) and its outcome over the stands, near misses and second passes, the champion, and disgrace (hitting the horse). The ride-in, the charge and an unhorsing were compared with DOSBox frame by frame: pixel-identical in EGA
- **Read Map** (also as an order): a territory's income, vassals and owner
- **battles against you**: when a computer lord attacks one of your castles or your campaign army, the siege messages and the battle screen with its tactics (Ferocious Attack, Stand and Fight, Bombard, Outflank, Retreat). Not compared with DOSBox yet
- **sound**: the PC-speaker tunes (they time the opening, as in the CGA and EGA programs), beeps, and the Tandy chip's music in Tandy mode. Tab between the speaker and the Tandy starts the tune being played again from the top on the new sound; the game's timing goes on as it was

Left out on purpose: "Please insert reel two and press any key to continue..." after the opening (both reels are there at once).

Not ported yet: the romance scene (a rescue shows its first and last words). The CGA program's picture bobbing with the joust's gallop (a CRT controller trick it uses on one GameSYS configuration only) is left out.

The CGA (1987) mode has the DOS version's pictures, with the booter's CGA sprites, font and boxes over them for now (DOC.EXE's own are decoded in `../Graphics/CGA_DOS` but not placed yet). Where its pictures have something drawn in that the booter adds as a sprite, the mode follows DOC.EXE: so far the raid's strength bars.

## Building on macOS
Install the tools with [Homebrew](https://brew.sh):
```sh
brew install cmake sdl3
```
Then build:
```sh
cd Remake
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```
This makes `build/DefenderOfTheCrown.app`.

The app's icon is the title picture ("Defender of the Crown" on the stone wall, from the EGA program), drawn during the build from your own game files, so no original artwork is kept in the repository. CMake finds them in `../Original`; if they are somewhere else, add `-DDOTC_GAME_DIR=/path/to/your/game` to the first `cmake` command. Without them the app builds with no icon in Finder, and the program still shows the icon in the Dock once it has loaded your files. If Finder keeps showing an old icon, run `touch build/DefenderOfTheCrown.app`.

## Running
```sh
open build/DefenderOfTheCrown.app
```
The app looks for your game files in the folder given on the command line, then the one it remembers, then `game/` or `../Original` next to the app (so the repository's `Original/` folder is found when you run it from `Remake/build`), then the current folder. If it finds none it asks for the folder, and remembers it.
```sh
build/DefenderOfTheCrown.app/Contents/MacOS/DefenderOfTheCrown --video=cga1 ../Original
```

**Video:** `--video=cga1|cga2|ega|tandy` chooses the mode to start in (EGA if not given). Tab goes through them in the game: CGA (1987) → CGA → EGA → Tandy.

**Fixing the original's flaws:** the remake plays the game as it was, flaws included. `--fix=` with a list of names, separated by commas (or `--fix=all`), fixes those you choose:
```sh
build/DefenderOfTheCrown.app/Contents/MacOS/DefenderOfTheCrown --fix=targets,joust-opponent,joust-margin
```

| `--fix=` | The original | Fixed |
|---|---|---|
| `viking` | The Viking raid strikes the garrison of the territory with your side's number (Cumbria), not your home's | Your home's garrison |
| `hostility` | The check that turns the other Saxons against you adds Buckingham's owner twice and never looks at Cornwall | Norfolk's, Buckingham's and Cornwall's owners |
| `targets` | The computer lords compare their targets' values unsigned, so a hopeless attack on a much stronger enemy (a negative value) beats every sensible one | Compared signed: a lord attacks only where the value is above 0 |
| `catapult` | A buying lord looks for a catapult in the garrison of the territory with his side's number, not his home's, and so may buy one he has | His home's garrison |
| `siege-merge` | A defending army joins the castle's garrison before the siege looks for the attacker's catapult, and stays joined when there is none | It joins only when the siege goes ahead |
| `joust-opponent` | The joust is judged by the jousting of whichever lord the search for land at stake stopped at (often you, or territory 1's owner), and a land won sends that lord's army home | The opponent's jousting, and his army |
| `joust-margin` | In the EGA program you can never unhorse an opponent whose jousting is 3 or more above yours (an unsigned comparison) | As the CGA and Tandy programs: the target is at least 1 line either side |
| `battle-text` | "Saxon blood taints the green fields of ..." names the territory with the attacked side's number | The territory attacked |
| `siege-sprite` | After a siege whose last shot was not a boulder hitting the wall, the catapult flickers over the battle's first frames | Cleared before the battle |

Each is described in `../Analysis/GAME_LOGIC.md` where it happens. The game log says which fixes are on.

**The catapult's pull:** `--catapult-pull=N` sets how many screen refreshes each step of the catapult's arm takes while you draw it back, 1 to 8. The original moves it one step a refresh, so a full pull takes 0.4 seconds, but only on a PC fast enough to copy the whole picture every refresh, as in DOSBox; on the PCs of 1987 that copy took two or three refreshes, and the pull was that much slower. The remake takes **2** (0.8 seconds) unless told otherwise; `--catapult-pull=1` is the original at full speed, `3` slower still. Enter is read every refresh, so letting go is as quick at any setting.

**Keys:** the original's: the arrows or the keypad (its 1-9 for the diagonals), Enter (keypad + and F1 are Enter too, as in the original). The remake's own: **Enter** during the opening skips to the choice of character, and in Sherwood skips to the game; **Tab** the video mode, **F2** 4:3 or square pixels, **Alt+Enter** or **Cmd+Enter** full screen, **Cmd+Q** quit.

**Game log (debugging):** `--log` writes a log of each game played:
```sh
build/DefenderOfTheCrown.app/Contents/MacOS/DefenderOfTheCrown --log            # decisions and events
build/DefenderOfTheCrown.app/Contents/MacOS/DefenderOfTheCrown --log=verbose    # and more
```
Each game opens a new text file in `Logs/` in the remake's folder (`~/Library/Application Support/DefenderOfTheCrown/Remake/Logs/` on macOS), named with the date, time and the lord you chose, such as `2026-11-15 08-46-01 Wilfred of Ivanhoe.log`. It starts with the game as it was set up: the date, morale, the next event, the random generator's state, every side (lord, home, where its army is, gold, income, leadership, jousting, swordplay, its lady), the campaign armies, the 18 territories (owner, castle, vassals, income, neighbours, garrison), the ladies, and the enmity between the sides. Then one line for each decision or event, after the date in the game:
```
[October   1149, month  1] STATUS your income 3 (less any lost this month), treasure 9; morale 30; army at Cumbria (1): 0 soldiers, ...
[October   1149, month  1] YOU order: Pass
```
- **STATUS**: the month's status panel. **YOU**: your orders, purchases, transfers, marches and tactics. **ROBIN**, **PASSAGE**: Robin's men, a Saxon's offer of safe passage. **TOURNAMENT**, **JOUST**: who holds one, the stakes and opponent (and whose jousting the joust is judged by), each pass with the lance's point and the target, and the result. **RAID**: your raids, the fighters' strengths and how each fight ended (with verbose, every hit). **EVENT**: the month's event. **AI**: each computer lord's turn: its gold, the men it moves into a garrison, the order it chose and why (the random draws), what it buys, the target it marches on with its value and way; with verbose, every territory it looked at and its value. **BATTLE**, **SIEGE**, **RESULT**, **OWNER**, **FALLS**: the fighting and who holds what afterwards (with verbose, **ROUND**: each round of a battle you do not see). **ENMITY** (verbose): the Saxons growing hostile. **END**: how the game ended. **REMAKE**: something not ported yet.

The log only reads the game: it never calls the random numbers, so a logged game plays as one not logged.

## How it works
- `src/game.c`, `src/month.c`, `src/ai.c` (the computer lords), `src/war.c` (armies, conquest, battles, sieges): the game, ported from AB with the original's data where the original kept it: the data file BH is the data segment, and the game reads and writes it at the same offsets with 16-bit words, signed or unsigned as each comparison was, so its quirks stay (`../Analysis/GAME_LOGIC.md`).
- The game runs on its own thread, one routine calling the next and waiting for keys and timer ticks as the original did (`src/sys.c`: the BIOS clock at 18.2 ticks a second, the keyboard as scan codes, the vertical retrace at 60 a second).
- `src/gfx.c`: every picture is drawn into all four modes at once, each with its own pictures, sprites and the way its program drew them (the EGA program puts sprites on whole bytes of 8 pixels, the CGA one on 4; the territories' colours each from their own table ...), so Tab can switch at any moment.
- `src/assets.c`, `src/dat.c`: GAME.DAT (two floppy images, LZW) and the .LIB files, decoded as in `../Analysis/DOTC_file_reference.md`.
- `src/sound.c`: the speaker tunes (AB 968A) and AC's Tandy music driver.
- `src/icon.c`, `tools/make_icon.c`: the app icon from the player's own copy of the game: the title picture in its 4:3 shape on a rounded square; `make_icon` writes the macOS `.iconset` at build time and `iconutil` turns it into `AppIcon.icns` (as in The Ancient Art of War remake).

## Tests
`test/build.sh NAME` builds `test/NAME.c` with the remake's sources (ASan and UBSan; SDL3 from pkg-config or `SDL3_DIR`). Run headless with `SDL_AUDIODRIVER=dummy`.
- `run_script GAME OUTDIR SPEED t:key ... t:shot:NAME`: plays the game at SPEED times its pace, pressing keys (scan codes in hex) and writing the screen of all four modes as BMPs at given times (game seconds). Set `DOTC_LOG=folder/` for a verbose log. `DOTC_FIX=list` as `--fix=list`.
- `t:w:ADDR:VALUE` in a script waits until the word at DS:ADDR (hex) is VALUE, e.g. `100:w:43:5` until month 5; the times after it count from there.
- `battle_test GAME OUTDIR`: a Norman lord besieges your home with a large army; the battle screen of the four modes every quarter second. `battle_test GAME OUTDIR siege t:key ...`: you besiege a Saxon castle instead, with a key script as `run_script`'s (`PASSAGE=1`: that Saxon offers safe passage first; `PULL=N` as `--catapult-pull=N`). `battle_test GAME OUTDIR raid t:key ...`: you raid a Norman's home. `DOTC_LOG=folder/` writes a log of these too.
- `joust_test GAME OUTDIR approach|lane|0-3`: the knights riding in, a pass down the lane with no keys, or an outcome (0 near miss, 1 opponent unhorsed, 2 player unhorsed, 3 the horse), every frame written as a BMP (to compare with a DOSBox recording).
- `dump_assets GAME OUTDIR`: every picture and sprite of the four modes as BMPs.
