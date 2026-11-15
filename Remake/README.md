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
- **Go Raiding**: choosing another lord's home castle, The Attack against the guards and The Defense against the lord in his hall, with the sword fight on the keypad or the arrows (Enter thrusts, 8/Up raises the sword, 2/Down parries, 4/6 or Left/Right step, 7/9/1/3 step with the sword raised or parrying), the strength bars, and the endings: the enemy's gold, captured (ransom), or the retreat (backing out to the left). Robin's help makes you stronger. A kidnapped lady's rescue is the same raid, and then **the romance**: the lady's portrait opening and closing her eyes, the bedchamber with the couple drawing together by the flickering hearth, and the couple at the window; she and her ward's land become yours, and your morale is at its best. It follows the EGA program's timing in every mode, with each program's own pictures and sprites (the small differences between them are in `../Analysis/GAME_LOGIC.md`, *The romance*). Not compared with DOSBox yet
- **Tournaments**: Hold Tournament, and the Saxon lords' own from 1150: the trumpeters, the stakes (Fame, or Land when both sides have land without a castle), the opponent, the knights riding in, the joust down the lane (aim the lance's point with the keypad: 7/8/9 up, 1/2/3 down, 4/6 sideways; the gallop bobs it) and its outcome over the stands, near misses and second passes, the champion, and disgrace (hitting the horse). The ride-in, the charge and an unhorsing were compared with DOSBox frame by frame: pixel-identical in EGA
- **Read Map** (also as an order): a territory's income, vassals and owner
- **battles against you**: when a computer lord attacks one of your castles or your campaign army, the siege messages and the battle screen with its tactics (Ferocious Attack, Stand and Fight, Bombard, Outflank, Retreat). Not compared with DOSBox yet
- **sound**: the PC-speaker tunes (they time the opening, as in the CGA and EGA programs), beeps, and the Tandy chip's music in Tandy mode. Tab between the speaker and the Tandy starts the tune being played again from the top on the new sound; the game's timing goes on as it was

Left out on purpose: "Please insert reel two and press any key to continue..." after the opening (both reels are there at once).

**The joust's bobbing picture (CGA modes):** during the charge, both CGA programs bob the whole picture up and down a line or two with the gallop. They do it with the CRT controller, by shortening the frame (its vertical total adjust register) by the bob each lance step, so the monitor shows the picture higher. The 1987 DOS version always does it; the booter's CGA program only on one GameSYS configuration. The remake shows it in both CGA modes (the picture moves up by 0-2 lines, the border colour showing below it); it is not in DOSBox, which doesn't emulate the monitor's timing. The booter's CGA program also takes four lance steps for each picture of the opponent, where its EGA and Tandy programs take three; the remake keeps three (all modes share one game), and four with `--rules=dos`, as DOC.EXE.

The CGA (1987) mode is the DOS version's look: its pictures, and DOC.EXE's own font, boxes, map, castles, army marker, portraits, name plates, sword fighters, joust, siege, THE END, sparks and romance, each at DOC.EXE's own places and drawn its way (`../Analysis/DOC_vs_AB.md`, *The graphics*). Its texts are DOC.EXE's where they differ: the credits ("Master Designer Software"; two credits left blank there, under the crown), Sherwood's story, and the numbers in the tables, which DOC.EXE writes right-aligned or without the booter's space before a single digit. Compared with DOSBox running DOC.EXE, pixel for pixel: the credits with the crown, the title and its sparkles, Sherwood's box, the status panel, the orders menu, Buy Home Army, Transfer Forces, the map, the battle screen, the sword fight, the siege, and the joust's approach, lane (the lance and the opponent) and an unhorsing over the stands. The events and the endings use the same boxes and sprites but were not reached in DOSBox.

`DOTC_Remake_Quick_Reference.pdf` sums up building, running, the settings, the options and the keys on four pages (`python3 tools/make_quick_reference.py` writes it again; it needs reportlab).

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
The app looks for your game files in the folder given on the command line, then the one it remembers (the settings file's `folder`, below), then `game/` or `../Original` next to the app (so the repository's `Original/` folder is found when you run it from `Remake/build`), then the current folder. If it finds none it asks for the folder, and remembers it.
```sh
build/DefenderOfTheCrown.app/Contents/MacOS/DefenderOfTheCrown --video=cga1 ../Original
```

**The settings file:** every option below can also be set in `DefenderOfTheCrown.ini`, so you don't have to give it each time. The remake reads it at every start and writes it with the defaults (and a comment for each setting) if it isn't there: on macOS it is `~/Library/Application Support/DefenderOfTheCrown/Remake/DefenderOfTheCrown.ini`, beside `Logs/`. An option given on the command line wins over the file for that run only; delete the file to get the defaults back. The game folder you choose (or give on the command line) is remembered in it; earlier builds kept it in `gamedir.txt`, which is read once and moved over.

| Section | Setting | Command line | Values (default) |
|---|---|---|---|
| `[game]` | `folder` | the folder argument | your game files' folder (empty: look for it, else ask) |
| `[display]` | `video` | `--video=` | `cga1`, `cga2`, `ega` or `tandy` (`ega`) |
| `[play]` | `rules` | `--rules=` | `booter` or `dos` (`booter`) |
| `[play]` | `fix` | `--fix=` | flaw names separated by commas, or `all` (empty: none) |
| `[play]` | `catapult_pull` | `--catapult-pull=` | 1 to 8 (2) |
| `[play]` | `sword_pace` | `--sword-pace=` | 1 to 8 (3) |
| `[play]` | `joust_pace` | `--joust-pace=` | 1 to 8 (4) |
| `[debug]` | `log` | `--log`, `--log=verbose`, `--log=off` | `off`, `normal` or `verbose` (`off`) |

Comments are lines starting with `;` or `#`. Settings added in later versions of the remake are added to an existing file, with their defaults and comments, the next time it starts.

**Rules:** `--rules=dos` plays the game as DOC.EXE (the 1987 DOS version) does, in any video mode: its random numbers (Aztec C's `ran()`), the computer lords' odds (home 1 in 3, conquest 6 in 7), their targets compared signed, the joust's margin, and its pace: one-tick waits that really wait (the DOS version ran its animations off the 18.2 Hz clock, the booter at the screen's 60 Hz), the slower month's box with its counting beeps, the slower sword fight and catapult pull, and the blinds wipe between pictures. `booter` (the default) plays as the booter version. The differences are listed in `../Analysis/DOC_vs_AB.md`.

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

**The sword fight's pace:** `--sword-pace=N` sets how many screen refreshes each frame of the sword fight (in a raid) takes, 1 to 8. The original draws a frame a refresh, 60 a second, on a fast enough PC (and in DOSBox); the enemy then acts 30 times a second, and his raised sword strikes a thirtieth of a second later, too quick to parry by sight. On the PCs of 1987 each frame took two or three refreshes. The remake takes **3** (20 frames a second) unless told otherwise; `1` is the original at full speed, higher is slower (the DOS version, `--rules=dos`, ran its fight at about 9 frames a second, which this setting does not change). Keys pressed during a frame are read at the next.

**The joust's pace:** `--joust-pace=N` sets how many screen refreshes each step of the joust's charge takes, 1 to 8. The original takes a step a refresh on a fast enough PC (and in DOSBox): 51 steps, 0.85 seconds down the lane, over before you can aim. The 1987 DOS version waits a clock tick a step (68 steps, 3.7 seconds). The remake takes **4** (3.4 seconds) unless told otherwise; `1` is the original at full speed (`--rules=dos` keeps DOC.EXE's own pace). Keys pressed during a step are read at the next.

**Keys:** the original's: the arrows or the keypad (its 1-9 for the diagonals), Enter (keypad + and F1 are Enter too, as in the original). The remake's own: **S** skips: during the opening to the choice of character, in Sherwood to the game, and in a tournament the trumpeters' fanfare and the knights riding in (to the two lords' portraits). S rather than Enter, so the key that skips can't also choose in the box that follows; **Tab** the video mode, **F2** 4:3 or square pixels, **Alt+Enter** or **Cmd+Enter** full screen, **Cmd+Q** quit.

**Game log (debugging):** `--log` writes a log of each game played:
```sh
build/DefenderOfTheCrown.app/Contents/MacOS/DefenderOfTheCrown --log            # decisions and events
build/DefenderOfTheCrown.app/Contents/MacOS/DefenderOfTheCrown --log=verbose    # and more
```
Each game opens a new text file in `Logs/` in the remake's folder (`~/Library/Application Support/DefenderOfTheCrown/Remake/Logs/` on macOS), named with the date, time and the lord you chose, such as `2026-11-15 08-46-01 Wilfred of Ivanhoe.log`. It starts with the settings in effect (each with where it came from: the settings file, the command line or the default) and the video mode, then the game as it was set up: the date, morale, the next event, the random generator's state, every side (lord, home, where its army is, gold, income, leadership, jousting, swordplay, its lady), the campaign armies, the 18 territories (owner, castle, vassals, income, neighbours, garrison), the ladies, and the enmity between the sides. Then one line for each decision or event, after the date in the game:
```
[October   1149, month  1] STATUS your income 3 (less any lost this month), treasure 9; morale 30; army at Cumbria (1): 0 soldiers, ...
[October   1149, month  1] YOU order: Pass
```
Switching the video mode (Tab) or the pixel shape (F2) during a game adds a `SETTING` line.
- **STATUS**: the month's status panel. **YOU**: your orders, purchases, transfers, marches and tactics. **ROBIN**, **PASSAGE**: Robin's men, a Saxon's offer of safe passage. **TOURNAMENT**, **JOUST**: who holds one, the stakes and opponent (and whose jousting the joust is judged by), each pass with the lance's point and the target, and the result. **RAID**: your raids, the fighters' strengths and how each fight ended (with verbose, every hit). **EVENT**: the month's event. **AI**: each computer lord's turn: its gold, the men it moves into a garrison, the order it chose and why (the random draws), what it buys, the target it marches on with its value and way; with verbose, every territory it looked at and its value. **BATTLE**, **SIEGE**, **RESULT**, **OWNER**, **FALLS**: the fighting and who holds what afterwards (with verbose, **ROUND**: each round of a battle you do not see). **ENMITY** (verbose): the Saxons growing hostile. **END**: how the game ended. **REMAKE**: something not ported yet.

The log only reads the game: it never calls the random numbers, so a logged game plays as one not logged.

## How it works
- `src/game.c`, `src/month.c`, `src/ai.c` (the computer lords), `src/war.c` (armies, conquest, battles, sieges): the game, ported from AB with the original's data where the original kept it: the data file BH is the data segment, and the game reads and writes it at the same offsets with 16-bit words, signed or unsigned as each comparison was, so its quirks stay (`../Analysis/GAME_LOGIC.md`).
- The game runs on its own thread, one routine calling the next and waiting for keys and timer ticks as the original did (`src/sys.c`: the BIOS clock at 18.2 ticks a second, the keyboard as scan codes, the vertical retrace at 60 a second).
- `src/gfx.c`: every picture is drawn into all four modes at once, each with its own pictures, sprites and the way its program drew them (the EGA program puts sprites on whole bytes of 8 pixels, the CGA one on 4; the territories' colours each from their own table ...), so Tab can switch at any moment.
- `src/assets.c`, `src/dat.c`: GAME.DAT (two floppy images, LZW) and the .LIB files, decoded as in `../Analysis/DOTC_file_reference.md`.
- `src/sound.c`: the speaker tunes (AB 968A) and AC's Tandy music driver.
- `src/main.c`, `src/ini.c`: the window, the keys, the command line and the settings file (`DefenderOfTheCrown.ini`: read, written with the defaults when missing, and the game folder set in it without touching the rest of the file).
- `src/icon.c`, `tools/make_icon.c`: the app icon from the player's own copy of the game: the title picture in its 4:3 shape on a rounded square; `make_icon` writes the macOS `.iconset` at build time and `iconutil` turns it into `AppIcon.icns` (as in The Ancient Art of War remake).

## Tests
`test/build.sh NAME` builds `test/NAME.c` with the remake's sources (ASan and UBSan; SDL3 from pkg-config or `SDL3_DIR`). Run headless with `SDL_AUDIODRIVER=dummy`.
- `run_script GAME OUTDIR SPEED t:key ... t:shot:NAME`: plays the game at SPEED times its pace, pressing keys (scan codes in hex) and writing the screen of all four modes as BMPs at given times (game seconds). Set `DOTC_LOG=folder/` for a verbose log. `DOTC_FIX=list` as `--fix=list`, `DOTC_RULES=dos` as `--rules=dos` (also for `battle_test` and `joust_test`).
- `t:w:ADDR:VALUE` in a script waits until the word at DS:ADDR (hex) is VALUE, e.g. `100:w:43:5` until month 5; the times after it count from there.
- `battle_test GAME OUTDIR`: a Norman lord besieges your home with a large army; the battle screen of the four modes every quarter second. `FIELD=s,k,s,k`: a field battle instead, your soldiers and knights against his. `battle_test GAME OUTDIR siege t:key ...`: you besiege a Saxon castle instead, with a key script as `run_script`'s (`PASSAGE=1`: that Saxon offers safe passage first; `PULL=N` as `--catapult-pull=N`). `battle_test GAME OUTDIR raid t:key ...`: you raid a Norman's home (`ROMANCE=0`-`3`: only the romance with that lady, over the hall; `SWORD=N` as `--sword-pace=N`). `DOTC_LOG=folder/` writes a log of these too.
- `joust_test GAME OUTDIR approach|lane|0-3`: the knights riding in, a pass down the lane with no keys, or an outcome (0 near miss, 1 opponent unhorsed, 2 player unhorsed, 3 the horse; `JMODE=` the mode to write; a step a frame, or `JPACE=N` as `--joust-pace=N`), every frame written as a BMP (to compare with a DOSBox recording).
- `dump_assets GAME OUTDIR`: every picture and sprite of the four modes as BMPs.
