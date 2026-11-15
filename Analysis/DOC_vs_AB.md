# DOC.EXE (the 1987 DOS version) against the booter (AB)

DOC.EXE and the booter's programs were built from much the same C source with different compilers: DOC.EXE with a large-model compiler (far calls, far pointers, an 8087 emulator; its `ran()` is Aztec C's), the booter with a small-model one. They share no code worth comparing instruction by instruction, but the routines line up one to one. This file records how they were paired and what differs.

## Tools
- `tools/docmatch.py DOC.EXE`: pairs DOC's routines with AB's by the message boxes and strings they use, then through the call graph (the calls of two paired routines, in order, between calls already paired). 88 of DOC's 232 routines pair this way; most of the rest are the C library, the 8087 emulator and the drawing primitives.
- `tools/doc_names.txt`: the names given so far (DOC SEG:OFF, AB name), checked by reading. `tools/doc_ds_names.txt`: DOC's data segment.
- `tools/docflat.py` turns `DOC.ASM` into the flat form `tools/dec.py` reads: `python3 docflat.py > /tmp/DOC_flat.ASM; python3 dec.py -f /tmp/DOC_flat.ASM -n doc_ds_names.txt joust` gives DOC's routine as pseudocode, comparable with `python3 dec.py joust` (AB's). dec.py knows both compilers' ways of indexing the records (AB's imul, DOC's shifts and adds).

## The data
The same tables at other offsets, every near pointer made far (DGROUP 0BCE):

| AB (BH) | DOC | Record |
|---|---|---|
| side 009F, 24 bytes | 4444, 28 | name (far), a second far pointer, portrait, lady, home, at, spend, joust, lead, sword, income, gold |
| terr 0695, 15 | 364A, 19 | label (far), owner, castle, vassals, income, 7 neighbours, name (far) |
| army 0147, 10 | 4340, 10 | the same |
| lady 0478, 8 | 33F6, 10 | name (far), side, territory, flag |
| enmity 0416 | 32E4 | the same |
| nav 0B56 | 38B9 | the same |

The initial values of these tables are the same (checked for the territories: owners, castles, vassals, incomes and neighbours byte for byte).

## The game logic
Read side by side for: the setup (setup_sides, place_castles, setup_ladies, setup_garrisons, setup_armies, setup_enmity), the month and its end checks, the monthly events, the computer lords (ai_turn, ai_reinforce_garrison, ai_choose_order, ai_find_target, ai_search, target_value, ai_buy, best_site_for_castle, ai_raid, choose_raid_victim), the armies (army_move_to, army_go_home, army_settle, army_merge, send_others_home, send_home_armies_at), conquest (attack, apply_result, battle, battle_auto, battle_round, army_damage, take_losses, siege, siege_of_player, choose_ammo, ask_passage, choose_destination), raids (raid, choose_raid_target), the joust (joust, joust_round), the ladies (rescue_offer, lady_to_side, romance), Robin (see_robin, robin_men), set_owner, side_income, side_falls, morale_add, leadership_add, enmity_add, next_event_in.

**The same in both**, flaws included: the Viking raid's garrison (`--fix=viking`), the hostility check (`--fix=hostility`), ai_buy's catapult check (`--fix=catapult`), the merged army after a refused siege (`--fix=siege-merge`), the joust judged by the wrong lord (`--fix=joust-opponent`), the battle text's territory (`--fix=battle-text`).

**Different:**
- **The random numbers.** DOC uses Aztec C's `ran()`: a 31-bit seed (DS:40D2, 100001 at the start), seed = seed x 125 mod 2796203, returning seed / 2796203.0. random(n) (070A:000D) is `(int)(ran() * 32767.0)`, shifted right by 8 when n < 256, modulo n (0 when n is 0): the same shape as the booter's random, whose LFSR replaced `ran()`. A new game (the first one only: DS:0014) first calls `ran()` (BIOS ticks & 1FFh) + 1 times. ai_choose_order calls random() where the booter reads its generator's bits directly (below).
- **The computer lords' orders** (ai_choose_order 04BA:0485): go home if the army is away and random(3) is 0 (1 in 3; the booter 1 in 4); buy if the last order was not to buy and random(4) is 0 (1 in 4, the same); else conquest if random(7) is not 0 (6 in 7; the booter 7 in 8), with no target buy or pass on random(2) (even, the same); else a Norman raids, a Saxon holds a tournament after 1149 or buys (the same).
- **The search for a target** (ai_search 0045:024A) compares the values signed: a lord attacks only where his value is above the best so far, from 0 (what `--fix=targets` does; the booter compares unsigned). And target_value refuses an owner whose enmity is 0 **or less** (the booter: only 0).
- **The joust** (joust 02D3:0DF4) compares signed: the target is at least 1 line either side (what `--fix=joust-margin` does, as the booter's CGA and Tandy programs; the EGA program compares unsigned). Before each pass it unpacks the lane picture off the screen (070A:02B1 into the buffer at DS:46EA), waits for a key (070A:0761), then brings it in with the blinds wipe (070A:01B3): the same order as the booter's, which waits for the key before showing the lane. The approach's last wait is 9 ticks.
- **Its timing.** DOC's wait_ticks (070A:08B2) and delay_ticks (070A:08E9) keep the last tick in global variables (DS:41D6 and 41DE), so wait_ticks(1) waits for the next BIOS tick (18.2 a second); the booter's keep it on the stack where other calls' values lie, so its one-tick waits end at once and its animations run at the screen's 60 frames a second. DOC draws straight onto the screen (no back buffer), so its scenes are paced by the clock:
  - the catapult's pull (catapult_aim 0637:0008): two delay_ticks(1) a step, about 0.11 s a step, 2.5 s for the whole pull (the booter: one step a refresh, 0.4 s);
  - the joust's charge (lance_step 02D3:0A16): beep(..., 1) waits a tick each step, about 2.8 s down the lane (the booter: 0.85 s); each step also waits for the vertical retrace and writes the CRT controller's start (the picture bobbing with the gallop, which the booter's CGA program does only on one GameSYS configuration);
  - the sword fight (sword_fight 050E:0ADB): delay_ticks between the two halves of a frame, about 9 frames a second (the booter: 60);
  - the lady's eyes (romance's lady_animate): one a tick (the booter: one a refresh);
  - the month's status box (month_status): waits 18 and 18 ticks, then counts the income up 1 at a time with beep(250,1), beep(500,1) and a 1-tick wait, and waits 54 ticks at the end;
  - the sparks in the sword fight stay 3 ticks (wait_ticks for the enemy's hit, item 9; delay_ticks for the player's, item 10);
  - a new picture comes in as a 4-pass blinds wipe, 2 ticks a pass (070A:01B3), unless DS:46D8 is set.
- **Smaller differences:** ai_turn flashes the territory 14 times; show_shot moves the shot sideways at frame 20; Sherwood's fire flickers with the game's random(4); the romance plays fire_flicker2(350) and shows single figures from step 2.

## The graphics
DOC's sprite files: DOCCHARS.LIB (the booter's font BA, map and portraits BP and sword fight BV in one), TITLE.LIB, JOUST1/JOUST2.LIB, SIEGE.LIB, RAID.LIB, LOVE1/LOVE2.LIB. Item n of a call is LIB entry n-1, as in the booter. Most sprites are drawn as a mask ANDed in then the picture ORed; the box edges with colour 0 transparent; the siege and the joust's outcome with colour 0 transparent and the other colours XOR 1; THE END put whole at (100, 30/116/127). Other positions: the castles (table 3977), the army marker (399D, mask item 37, picture 127), the name plates of the character choice (3214/321E), the joust approach (x+2, y 74/86, turning items 24/25), the lane knights (no +1 on y), the romance window (x 37; the lady at 26,17, her eyes at 34,53).

**Texts and numbers.** The texts are the booter's but for: the credits (DS:0239-0627: "Master Designer Software, Inc. presents"; the Computography and Art Direction credits are blank, shown under the crown, TITLE item 12 put at (112, 10), 021C:0341); "Killing the King" in Sherwood's story (box DS:096A); and the numbers, written with sprintf: right-aligned in four places in the battle's table (0079:0000, "  %4d      Soldiers <@@%4d>"), Buy Home Army ("You have %4d>gold pieces", "  1 >Soldiers <@@%4d>") and Transfer Forces ("%4d   Soldiers <@@%4d>"); elsewhere "%d" where the booter's number routine (94B5) puts a space before a single digit and its labels end a space short (the status panel "<       Men:  %d", the siege's "Days remaining in Siege: %1d", "Your castle strength is %d percent.", "%d men were killed during the siege.", Read Map's "%d gold / month" and "%d vassals"). The font's space (item 20h) is a glyph 3 pixels wide. The battle's chosen tactic is XORed with AAh (0940:000F: colour 2) where the booter's CGA program XORs 55h. The title's sparkles are put in colour 1 (021C:086F through 093C:000F, the pixel's two bits replaced), where the booter ORs 0Fh. The opening shows the scroll again before the second credit (021C:01E3) and puts the cast and the introduction at once, without the blinds (DS:46D8 set at 032D).

**The lane.** The opponent's pictures are put whole and stay (02D3:0AAE): each covers the last, and the distant knight the lane picture starts with; only the lance's background is saved and put back (0977/0971 at y 116, 40 x 84 pixels).

## In the remake
- The CGA (1987) mode draws with DOC's own sprite files and positions when DOC.EXE and its .LIB files are in the game folder (`DOS_MODES` in the source); the other modes keep the booter's.
- `rules = dos` (`--rules=dos`) plays with DOC's random numbers, the computer lords' odds, the signed comparisons and DOC's timing (the waits above, the blinds wipe); `rules = booter` (the default) plays as the booter. The two are independent of the video mode.
