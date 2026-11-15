# Defender of the Crown (PC): the game logic

Read from the booter's EGA program (`AB.ASM`; addresses are AB's) with `tools/dec.py`. The CGA and Tandy programs run the same code at other addresses (`AC_vs_AB.txt`); DOC.EXE, the 1987 DOS version, is not compared yet. Started 15 Nov 2026; corrected while porting to the remake. Covered: the **strategic game** (the data, the setup, the month, income, events, buying, conquest, the computer lords), **Seek Conquest with the player's battles and sieges**, **raids and the sword fight**, **tournaments and jousting**, **the ladies** (kidnapping, rescue, romance), **the random numbers**, and **the opening, the options menu and the end of the game**. Every routine of AB is now named (`disassembler/ab_names.txt`); the drawing is outlined in *The screens* at the end, the animation data only in outline.

Checked in DOSBox so far: the first month's status panel (Wilfred of Ivanhoe: Leadership Good, Jousting Good, Swordplay Average; no men in the campaign army; treasure 12 = 9 + his home's income of 3; October 1149), in two runs that dealt him different homes (Cumbria, then Clwyd), the Buy Home Army screen (costs 1, 8, 15, 20; 10 soldiers in the home army), and Hold Tournament in the first month ("There is no land to joust for, so you must joust for fame": the player owns no territory without a castle yet), the opening (every credit box in order, the cast for about 6 seconds and the introduction for about 10, then the reel-two prompt; a key on the title skips the credits), the choice of character and its keypad moves, Sherwood with the flickering fire, and the options menu (its five lines, and the music line toggling to "Music is OFF"), and a joust (the knights riding in, the charge and an unhorsing, frame by frame; *Tournaments*). Everything else is read from the code and not yet checked against the running game.

## The data (all in BH, the data segment; names as in `tools/ds_names.txt`)

### Sides (`side`, DS:009F, 24 bytes each, sides 1-6)
Side 1 is always the player (`player`, DS:0051), 2 and 3 the other Saxons, 4-6 the Normans. A territory's owner is a side number (-1 = nobody).

| Offset | Field | |
|---|---|---|
| +0, +2 | name, padding string | from the lord's record |
| +4 | portrait | |
| +6 | lady | the lady the side holds or has married (-1 none) |
| +8 | home | the home castle's territory |
| +10 | at | where the campaign army is |
| +12 | spend | the computer's spending: it puts spend/10 of its gold into men each time it buys |
| +14 | joust | jousting |
| +16 | lead | leadership |
| +18 | sword | swordplay |
| +20 | income | gold a month: the sum of its territories' incomes (side_income 23AC) |
| +22 | gold | treasure |

### The ten characters (`lord`, DS:04E7, 16 bytes)
The first four are the Saxons the player can be, then Robin, then the five Normans. Ratings shown: 0-3 Weak, 4-6 Average, 7-8 Good, 9-10 Strong (the table `rating`, DS:37B1).

| Character | Leadership | Jousting | Swordplay | Spend | Gold |
|---|---|---|---|---|---|
| Wilfred of Ivanhoe | 7 | 8 | 6 | 5 | 9 |
| Geoffrey Longsword | 6 | 6 | 9 | 5 | 10 |
| Cedric of Rotherwood | 10 | 7 | 3 | 6 | 8 |
| Wolfric the Wild | 5 | 10 | 5 | 8 | 8 |
| Robin of Locksley | 8 | 3 | 10 | -1 | 0 |
| Brian de Bois-Gilbert | 8 | 10 | 8 | 8 | 18 |
| Philip Malvoisin | 7 | 8 | 6 | 10 | 21 |
| Reginald Front-de-Boeuf | 5 | 7 | 10 | 6 | 20 |
| Edmund the Grim | 10 | 5 | 8 | 8 | 19 |
| Roger Falconbridge | 8 | 8 | 9 | 7 | 18 |

### Territories (`terr`, DS:0695, 15 bytes)
+0 name, +2 padding string, +4 owner (byte), +5 castle (0 none, 30 at the start, 35 when bought; only tested for 0 by the rules, the value chooses how the castle is drawn on the map), +6 vassals, +7 income, +8 up to 7 neighbours (0-ended). Territory 0, Sherwood Forest, is not a real territory (no income, no neighbours; the computer never targets it).

| # | Territory | Income | Vassals | Castle at start | Neighbours |
|---|---|---|---|---|---|
| 0 | Sherwood Forest | 0 | 0 |  |  |
| 1 | Cumbria | 3 | 0 | yes | Yorkshire, Lancashire |
| 2 | Yorkshire | 2 | 6 |  | Cumbria, Lancashire, Nottingham, Lincolnshire |
| 3 | Gwynedd | 2 | 4 |  | Lancashire, Glamorgan, Clwyd |
| 4 | Lancashire | 4 | 6 |  | Cumbria, Yorkshire, Gwynedd, Nottingham, Clwyd, Leicester |
| 5 | Nottingham | 2 | 0 | yes | Yorkshire, Lancashire, Lincolnshire, Leicester |
| 6 | Lincolnshire | 3 | 6 |  | Yorkshire, Nottingham, Leicester, Cambridge, Norfolk |
| 7 | Glamorgan | 1 | 4 |  | Gwynedd, Clwyd, Gloucester |
| 8 | Clwyd | 3 | 0 | yes | Gwynedd, Lancashire, Glamorgan, Leicester, Gloucester |
| 9 | Leicester | 2 | 5 |  | Lancashire, Nottingham, Lincolnshire, Clwyd, Cambridge, Gloucester, Buckingham |
| 10 | Cambridge | 5 | 6 |  | Lincolnshire, Leicester, Norfolk, Buckingham, Essex |
| 11 | Norfolk | 6 | 0 | yes | Lincolnshire, Cambridge, Essex |
| 12 | Gloucester | 7 | 12 |  | Glamorgan, Clwyd, Leicester, Buckingham, Dorset, Hampshire |
| 13 | Buckingham | 8 | 0 | yes | Leicester, Cambridge, Gloucester, Essex, Hampshire |
| 14 | Essex | 6 | 8 |  | Cambridge, Norfolk, Buckingham, Hampshire, Sussex |
| 15 | Cornwall | 8 | 0 | yes | Dorset |
| 16 | Dorset | 4 | 6 |  | Gloucester, Cornwall, Hampshire |
| 17 | Hampshire | 3 | 8 |  | Gloucester, Buckingham, Essex, Dorset, Sussex |
| 18 | Sussex | 7 | 8 |  | Essex, Hampshire |

The map cursor moves between territories with the keypad through `nav` (DS:0B56: for each territory, the territory reached in each of 8 directions; choose_territory 4142).

### Armies (`army`, DS:0147, 10 bytes)
Records 0-6 are the sides' campaign armies, record 7 + *t* is the garrison (home army) of territory *t*. +0 at (where it is), +2 base (where it goes back to), +4 soldiers, +6 knights, +8 catapults. Strength (army_strength 26EF) = 4 x knights + soldiers; catapults do not count.

### Others
- `lady` (DS:0478, 8 bytes, 4 ladies: Rebecca of York, Katharine of Nottingham, Anne of Lancashire, Rosalind of Bedford): +0 name, +2 side, +4 territory, +6 flag.
- `enmity` (DS:0416): 7 x 7 words, how hostile side *a* is to side *b*, -10..10; enmity_add 25E5 changes both directions at once. A computer side never attacks a side it has 0 enmity with.
- `price` (DS:0A90): soldier 1, knight 8, catapult 15, castle 20 gold.
- The date: `month_no` DS:0045 (0 = January), `year` DS:0047; the game starts with 8 (September) and 1149, and the first month shown is October 1149.

## The setup (new_game 10B2)
After the title, the credits, the introduction and the choice of character (*The opening*, below), the variables are reset (month count 0, September 1149, morale 30, Robin's pledges 0, every computer side's last order -1) and:
- **Sides** (setup_sides 21CC): the three Saxon home castles Cumbria, Nottingham and Clwyd are dealt at random to sides 1-3; the Normans are at Norfolk (4), Buckingham (5) and Cornwall (6). The player's character becomes side 1; two of the other three Saxons, at random, become sides 2 and 3; three of the five Normans, at random, become sides 4-6. A side's campaign army starts at home, and its income is its home's.
- **Castles** (place_castles 3CAF): each home is given to its side with a castle of 30; the other territories start with no owner.
- **Ladies** (setup_ladies 243B): shuffled; two are placed with sides 2 and 3.
- **Garrisons** (setup_garrisons 1FB3): each territory's garrison is its vassals (soldiers).
- **Armies** (setup_armies 1F11): every campaign army has 15 soldiers, except the player's, which has none; the home garrisons have 5 soldiers, the player's 10.
- **Enmity** (setup_enmity 2556): Saxons and Normans 2, sides of the same faction 0; then each Norman +3 against the player (5).
- **Events**: the first comes in 5 + random(8) months (next_event_in 2EEC).
- **Morale** (DS:0049) = 30. It only chooses the player's portrait: over 29 the first picture, 20-29 the second, 19 or less the third (month_status sets DS:009D, added to the portrait number). A won battle adds 3, a lost one or a retreat takes 3, both armies wiped out takes 1 (morale_add 9464, kept within 1-50); the romance sets it to 50, the disgrace at a tournament to 19.

## The month (month 1B44, called by main until the game is over)
For each side 1-6 in turn:
- **The player** (side 1): side_income; the month count goes up; monthly_event; month_status (the status panel, then the treasure goes up by the income less any income lost to an event this month, counted up 5 or 1 at a time with a beep; the date moves on); rescue_offer (a kidnapped lady, if any); then orders_menu until an order is given.
- **A computer side**: ai_turn (below).

After each side's turn (not once a month) the end checks:
- If the three Norman castles (Norfolk, Buckingham, Cornwall) all have the same owner and it is a Saxon, the game is over: the player has won if it is the player (speaker tune 9Eh), otherwise lost (9Dh).
- If the player no longer owns their home castle, the game is lost.
- While Norfolk's owner plus **twice Buckingham's** owner add up to less than 12, the other Saxons (sides 2 and 3) grow more hostile to the player: +2 enmity each, and the checks run after **every side's turn**, so six times a month (to at most 10). The code (1E6C) adds territory 13 twice and never looks at Cornwall (15): the sum starts at 4 + 5 + 5 = 14, falls below 12 when Buckingham goes to any Saxon or Norfolk goes to the player, and Cornwall's fall alone changes nothing. A quirk to keep (the remake's `--fix=hostility` adds Norfolk's, Buckingham's and Cornwall's owners).
- After a won or lost game (not after Start a New Game or End Present Game): "Would you like to play again?" Yes / No; No quits.

## Events (monthly_event 2F4E)
When the event counter runs out, one of eight events (random(10) + 1; 9 and 10 do nothing), then the counter is set again to 5 + random(8):

| # | Event | Effect |
|---|---|---|
| 1 | Viking raid | A third of the soldiers of the garrison of territory *player* are lost: the code indexes the garrisons with the player's side number (1, so always Cumbria's garrison) instead of the player's home. That is the player's home army only when the player's home is Cumbria: an original quirk (AB 2F89; the remake's `--fix=viking` strikes the home's garrison) |
| 2 | Danes invade | The player loses a territory: the highest-numbered one that is not their home (side_last_territory 2F14); armies there go home |
| 3 | Norman plotters, vassals revolt | The same |
| 4 | Sheriff ambushed | Half of this month's income is lost |
| 5 | Catapult sabotaged | The player's campaign army loses a catapult (if it has one) |
| 6 | Robin raids a Norman stronghold | Each Saxon side gets 25 gold |
| 7 | Three knights from Germany | The player's campaign army gets 3 knights |
| 8 | Norman vassals revolt | The first Norman (4-6) that has a territory other than its home loses its highest-numbered one to the player |

## The player's orders (orders_menu 1A91)
"Your Orders?": 1 Hold Tournament (tournament 62BC), 2 Seek Conquest (seek_conquest 35E0), 3 Go Raiding (go_raiding 45AC), 4 Buy Home Army (buy_army 39C7), 5 Read Map (read_map 4084: territory_info shows a territory's income, vassals and owner), 6 Pass ("Lord *name* Passes"), 7 Options (options_menu 1957). The month goes on when an order returns non-zero.

- **Buy Home Army**: soldiers 1, knights 8, catapults 15 gold, bought into the home garrison; a castle (20 gold) is built in a territory the player owns that has none: castle 35 and 10 more soldiers in its garrison. In the menu Right buys one of the line chosen and Left sells one back, but only what was bought in this visit (the counts start from the garrison's); Enter does nothing except on Castles, where it buys (as Right), and on Continue. Too little gold, or nothing to sell back, is a short click (speaker_tone 250 until the menu is drawn again). Castles: choose_territory (4142) from where the campaign army is: a cursor on the map (the territory flashes), moved with the keypad or the arrows through DS:0B56 (8 a territory: up, down, right, left, up-right, down-left, up-left, down-right), Enter chooses; "You do not own that territory!" or "That territory already has a Castle!" otherwise. The order ends the month only if more was bought than sold back; otherwise the orders menu comes again. The table's spaces are drawn with the font's '>' (the font's pointer for 20h is replaced by 3Eh's while the menu is up; also in the battle's army table).
- **Seek Conquest** (seek_conquest 35E0): a menu that stays open until a move ends the order:
  - **Send forth Campaign Army** (needs soldiers or knights in the campaign army): choose a territory on the map (choose_destination 3585): it must be a neighbour of where the army is (is_neighbour 3D82); choosing Sherwood Forest asks Robin (below). Then send_army 3135 moves the army there and attacks. Moving into one of your own territories (result 1), being refused a siege for want of a catapult (3) or passing through a friendly Saxon's land (8) keeps the menu open, so **the army can march any distance through your own land in one month**; any other result ends the order.
  - **Transfer Forces** (transfer_forces 3721): only in a territory you own: soldiers, knights and catapults move one at a time between the campaign army and that territory's garrison ("Home", "Garrison" with a castle, "Territory" without), with no limits: Right moves one from the garrison to the army, Left back (a click when there is none).
  - **Read Map**, **See Robin**, **Continue**.
- **Robin** (see_robin 2E37): three pledges in a game (DS:004B counts them). Asking sets DS:004D, and the next attack gets Robin's men (robin_men 2E84): 1.5 x the defenders' soldiers (garrison plus the owner's campaign army if it is there) less your soldiers, at least 2 and at most 50, added to your campaign army. After the attack half of them are taken away again (so the other half stay), and if that leaves fewer than 5 soldiers the army is given 5: even an army wiped out in the attack comes back with 5 (an original quirk).
- **Safe passage** (ask_passage 331C): when the player enters a territory of one of the other two Saxons (sides 2, 3) and that Saxon's enmity to the player is 0 or less, he asks "Do you seek safe passage through my land?". Accept: the army passes (result 8). Attack: both Saxons' enmity with the player +5, and the attack goes on.

## Conquest (attack 31D5 and apply_result 33E5)
attack(attacker, defender, territory) returns a result code, which apply_result carries out:

| Code | When | Result |
|---|---|---|
| 1 | the territory is the attacker's | nothing |
| 2 | nobody owns it | the attacker takes it ("No Defense") |
| 3 | the player besieges without a catapult | the army settles (army_settle) |
| 4 | the defenders are wiped out | enmity between the two +6 (both ways); the attacker takes the territory (unless it is the player's home); if it was the defender's home, the defender falls (side_falls 2406) and its campaign army is disbanded; the garrison loses its catapults; other armies there go home |
| 5 | the attackers are wiped out | enmity +6; the attacker loses its catapults and its army goes home; a defending campaign army that had joined the garrison leaves it again |
| 6 | the attacking army is empty | it settles |
| 7 | both are wiped out | enmity +6; both lose their catapults, armies there go home, and the territory is left with no owner unless it is the defender's home |
| 8 | the player asked for safe passage | nothing |

Before a battle, a defending campaign army in the territory joins the garrison. It joins before the siege looks for the attacker's catapult, so after a refused siege (result 3 or 6) it stays merged into the garrison: a quirk to keep (the remake's `--fix=siege-merge` merges it only when the siege goes ahead). A territory with a castle is besieged (siege 74B5: the player's siege 763E or a siege of the player 78A9), otherwise there is a field battle (battle 5781): shown with tactics when the player is involved (battle_shown 57BB), otherwise fought out at once (battle_auto 600C).

**Battle rounds** (battle_round 60EB; battle_auto always uses tactic 2, Stand and Fight, until one side is empty): each side's damage is soldiers / 32 + knights / *k* (army_damage 6202), where by tactic *k* is 4 (1 Ferocious Attack), 8 (2 Stand and Fight), 4 (3 Bombard, plus random(catapults + 1)), 8 (4 Outflank), and for 5 (Retreat) soldiers / 48 + knights / 16. Leadership adds lead x damage / 10 (rounded) to each side's damage; with Outflank instead each side's damage is reduced by the other side's leadership share. Then each side adds random(3); the attacker's damage is reduced by a percentage (the attack's 4th argument; 0 in the open field). Each point of damage kills one soldier, or a knight when no soldiers are left (take_losses 6290).

## The player's field battle (battle_shown 57BB)
Fought when the player attacks a territory without a castle, is attacked in one, or as the last part of a siege (below). If the defenders have no soldiers or knights: "There are no men defending this territory. You capture it without casualty" (result 4). Otherwise the screen shows both armies, and round after round battle_round runs with the tactic chosen in the menu (Ferocious Attack, Stand and Fight, Bombard, Outflank, Retreat!; Up and Down move the cursor, Enter makes its line the tactic; it starts on Stand and Fight). A round is fought at once and then shown for 28 timer ticks (about 1.5 seconds): each tick one of three groups of men is animated (the BN items 160-163 and 170-173 picked with random(4) each, so **the animation uses the game's random numbers**: 56 calls a round), the soldiers shown in groups by the count left (more than 50, 25, 0) and the knights in two (more than 10, 0), at the positions DS:0B34-0B4B. A tactic chosen during a round is used from the next round: Retreat ends the battle when the round is over, so a Retreat round (tactic 5) is never fought. The army table under the battle is redrawn after every round. Retreat is offered when attacking, or when defending with the campaign army in a territory that is not the home; at home or with only the garrison there is no retreat.
- The battle ends when one side or both have no soldiers or knights left (an army left with none also loses its catapults): 4 (the attacker won), 5 (the defender won) or 7 (both gone); morale +3 for a win, -3 for a loss, -1 for both gone.
- **Retreat**: attacking, the army goes back (result 6); defending your own territory, the garrison joins the campaign army, it leaves, and the attacker takes the territory (result 4). Morale -3.

## Sieges (siege 74B5)
Every attack on a territory with a castle is a siege; the attacker needs a catapult in its campaign army (otherwise the player is told "Sorry Sir, you have no catapult. You are forced to retreat", result 3; a computer side gets result 6).

**The player's siege** (siege_by_player 763E): up to 6 days of bombardment (DS:0A88), one shot a day, then the battle. Each day choose the ammunition (choose_ammo 7505): Greek Fire (2 shots, DS:0A8C), Disease (1, DS:0A86), Boulders (6, DS:0A82) or Cease Fire (ends the bombardment). Then aim (catapult_aim 7168): Enter starts drawing the arm back, Enter again releases; the shot's height is (tension - 140) / 2, 0-7, where tension rises by one a frame (60 a second: the delay_ticks(1) between the steps end at once, as their first tick change counts at once) from 136 to at most 159, about 0.4 seconds from the start to the end of the pull; Enter (or keypad +, F1) both starts and releases. So heights 1-6 need a release 6 to 17 frames into the pull (0.1 to 0.28 seconds), and a hit on the wall at its first height 6 needs 16 or 17. Shots of height 0 or 7 miss. The wall starts at height 6 (DS:0A8A):
- **Greek Fire** over the wall (height above the wall's): the garrison loses soldiers / (random(25) + 6).
- **Disease** over the wall: the garrison loses soldiers x days left / 15 (40% on the first day, less later).
- **Boulders** that hit the wall at its height: the wall is one lower, and the defenders' protection drops by 15.
- The garrison never goes below 1 soldier.
Then the field battle, with the attacker's damage reduced by the protection: 90% less 15 for each boulder hit.

**A computer side's siege** (siege_of_player 78A9, also used between computer sides): protection 90 - (random(3) + 3) x 15 (45, 30 or 15%), the garrison loses soldiers / (random(7) + 2) (at least 1, never below 1), then the battle (shown if the player is involved). When the player defends, "Suddenly your home castle is attacked!" (at home) or "Your garrison is under siege in the territory ..." and then "Your castle strength is ... percent. ... men were killed during the siege."; the battle then skips its own "The Defense" message (DS:003F).

When a computer side attacks the player in the open, the battle is shown only if the player's campaign army is there; a garrison alone fights it out unseen (the territory just changes colour). The battle's "Saxon blood taints the green fields of ..." takes the territory with the defender's side number (AB 58D1), so it names territory 1 for the player: a quirk to keep (the remake's `--fix=battle-text` names the territory attacked).

## Raids (go_raiding 45AC, raid 45EC)
**Go Raiding**: choose a territory on the map (choose_raid_target 4538): it must be another side's home castle that the side still holds (choosing your own home cancels the order; Sherwood Forest asks Robin). Then:
- The castle's owner's enmity with the player +1.
- The player's sword strength (DS:0B10) is swordplay x 4, or 50 if Robin's help was asked for (that uses the help up).
- **The Attack** (raid_attack 5449): a sword fight against the guards, whose strength (DS:0B1A) is 20, with other fighters animated around (sword_fight mode 1).
- **The Defense** (raid_defense 5571): if the attack was won, a second sword fight against the castle's lord, whose strength is his swordplay x 4. The bars on line 192 show both strengths, 2 pixels a point (the player's from 50, the enemy's from 40 down; the guards start at 20). The 1987 DOS version (DOC.EXE) has no bar sprites: its RAID.LIB pictures have the bars drawn in, filled to its own ends (the player's to x 153, the guards' to 242, already at 20, the lord's to 282), and it shortens them from there with the same routine (050E:08F7), a point for each below 50 (40 for the lord), one more than the booter's count for the player (050E:10F5, 11FF, 1236). So its player's bar ends 3 pixels short of the booter's.
- **Success** (both won): with a kidnapped lady to rescue, the romance (below); otherwise "The Enemy's Gold": half of the lord's gold is taken, leadership +1, morale +1.
- **Captured** (the player's strength runs out): leadership -1, morale -1, and half of the player's gold goes to the lord as ransom.
- **The Retreat** (backing out of the fight, past the left edge): leadership -10 (that is, to 0) and morale -2.

**The sword fight** (sword_fight 4F24): the two fighters stand at x positions (the player DS:0B08, the enemy DS:0B12); each loses one point of strength per hit, and the fight ends when either reaches 0 or the player retreats past the left limit. The player's keys (the keypad; a table at 5263): Enter thrusts; 8 raises the sword, 2 parries; 7, 4 and 1 step back (sword raised, middle stance, parrying), 9, 6 and 3 step forward the same way (only while more than 5 apart). A thrust hits when the two are less than 7 apart and the enemy is not parrying. The enemy acts every other frame: more than 6 apart, steps in with chance 1/2; less than 6 apart (and not at his limit), steps back parrying; otherwise attacks or parries, even chances; his attack hits when less than 7 apart and the player is not parrying. A frame is one screen refresh (60 a second: the loop waits only in present); a key is read only when the player is neither stepping (the legs' 3 frames) nor finishing a thrust (a thrust is resolved in the frame after Enter, the sword then back in the middle), and the keys waiting are thrown away each frame, so holding a key does not queue moves. The enemy's attack takes two of his turns: he raises the sword (170), then strikes (172), so a parry (2, or 1, 3) in between stops it; the arrows work as the keypad's 8, 2, 4 and 6. In The Attack two more fighters behind (DS:0B1C, 0B26) only change stance and step at random (random(9) a frame: the fight uses the game's random numbers). Between The Attack and The Defense the last frame stays up about two seconds (39 wait_ticks(1) in a row: each waits for the tick the one before ended on) while the hall is drawn behind.

**A computer raid** (ai_raid 4428, a Norman's order 3): it picks one of the three Saxon sides at random (choose_raid_victim 43F6; nothing if that side's home has fallen); that side's enmity +1. If the victim holds a lady, the player has none and more than 10 months have passed, the lady is kidnapped to the Norman's home (DS:0053); otherwise the Norman takes half of the victim's gold ("A cunning Norman lord raids your castle in the middle of the night... You lose half your gold"), without a fight.

## The ladies (kidnapping, rescue, romance)
At the start two of the four ladies are placed, as wards, with the other two Saxons (sides 2 and 3). When a Norman kidnaps one (above), at the start of the player's next month (rescue_offer 4316): "*Lady* has been kidnapped... Her ward promises to grant you her hand, and the joining of your two kingdoms should you succeed in a rescue attempt. Do you want to rescue her?"
- **Yes**: a raid on the kidnapper's castle (this uses the month); leadership +2 whatever happens. If it succeeds: the romance (romance 48EB, Saxon lady pictures; morale set to 50), the lady becomes the player's (and no more ladies can be kidnapped from then on, since the player now holds one), and **all the ward's territories become the player's** (side_falls).
- **No**: leadership -2.
Either way the offer is gone (the lady stays where she is).

## Tournaments (tournament 62BC)
Held by the player (Hold Tournament) or by a Saxon computer side (its order 1); the player jousts in either case.
- Refused if the player has been banned (DS:003D, "you have been banned from Ashby"), in the month of the last tournament or the one after it ("The Lords have just returned from the last tournament!"), or if the holder has less than 5 gold. Otherwise the holder pays 5 gold and every side's enmity towards the holder drops by 1.
- All the other sides are in the tournament. Up to three rounds, each against a lord still in it, until the player loses one:
  - **Stakes** (joust_round 6475): Land is possible only if a lord still in the tournament owns a territory without a castle, and the player owns one without a castle (the player's highest-numbered such territory is the one at stake); otherwise "There is no land to joust for, so you must joust for fame". For Fame the player chooses the opponent (choose_opponent 7094); for Land, the territory to win (its owner is the opponent).
  - **Win**: morale +1; Fame: leadership +1; Land: the territory is the player's (an army of the loser there goes home).
  - **Loss**: morale -1; Fame: leadership -1; Land: the opponent takes the player's territory at stake (the player's army there goes home).
  - **Disgrace** (the lance hit the horse): banned from tournaments for good, morale 19, all territories but the home lost, the army sent home.
- Three wins: "The Champion".
- **Whose jousting counts** (AB 64B8): the joust is judged with the jousting of the side in `di`, which joust_round sets while looking for land at stake: the owner of the highest-numbered territory without a castle of a lord still in the tournament, or, if there is none, the owner of territory 1 (whoever it is: the player, nobody, anyone). It is not the opponent chosen (DS:0D10), whose portrait and name are shown and who takes or loses the land. A land won also sends home `di`'s army (if it stands in the territory won), not the opponent's. A quirk to keep: so jousting for fame in the first months is often judged against the player's own jousting (when he owns Cumbria) or another lord's. The remake's `--fix=joust-opponent` uses the opponent's.

**The joust** (joust 6EC2): the jousting lane (CI); the opponent comes closer through BK items 3-19 (one item every 3 steps of the lance, 51 steps; its place on the screen DS:0C8C/0C8E, x and y, by item); meanwhile the keypad moves the lance's point (x DS:0D0C, 20-50; y DS:0D14, 120-180; it also bobs up and down with the gallop: lance_step 6B09). Each step the key moves the point by the table DS:0CDC (keypad 7/8/9: x -2/0/+2, y -4; 4/6: x -2/+2; 1/2/3: x -2/0/+2, y +4; no key or another key: nothing), x is kept within 20-50, then y moves by the bob (DS:0063, ±2, reversed every 6 steps, and sooner when y hits 120 or 180) and is kept within 120-180. The gallop is a speaker beep whose divisor (DS:005F) falls by 500 a step from 30000, back to 30000 below 28500. At the meeting:
- **Hit**: the point within the target, x 26 ± (1 if the player's jousting is higher than the opponent's, else 0) and y 138 ± (player's jousting + 2 - opponent's, at least 1): the opponent is unhorsed (win).
- **The horse**: x below 30 and y above 170: disgrace.
- **Otherwise**: random(opponent's jousting) of 2 or more, the player is unhorsed (loss); else "A Near Miss" and they joust again. The fourth pass is always a loss, whatever happens in it.
- **Unsigned** (EGA only): AB compares these numbers unsigned. When the opponent's jousting is 3 or more above the player's, the margin (player + 2 - opponent) is negative, is not raised to 1, and no y can lie within 138 + margin .. 138 - margin: the opponent cannot be unhorsed. The CGA and Tandy programs compare signed, so there the margin becomes 1. The remake follows the EGA program (`--fix=joust-margin`: as the CGA and Tandy ones).
- **Timing** (checked in DOSBox, EGA): the 51 lance steps are 51 consecutive frames (60 a second, under a second for the charge: lance_step's beep(…, 1) ends at once), the outcome's 41 frames likewise; the approach's knights move every 2 ticks (wait_ticks(3)), then every tick or so. The remake's approach, charge (no keys) and unhorsing (result 2) were compared with a DOSBox recording frame by frame: pixel-identical.
- The CGA program (AA) also writes a CRT controller register each lance step (crtc_write 8457) to bob the picture with the gallop, but only when GameSYS's configuration word DS:0000 is 2.

## The computer lords (ai_turn 2995)
A computer side whose home castle has fallen does nothing. Otherwise: gold += income; it may move soldiers from its campaign army into the garrison where the army is (ai_reinforce_garrison 2C60: up to half of the army's soldiers at home, a fifth elsewhere, when the garrison has fewer); then it chooses an order (ai_choose_order 2D84, using the random generator's last value):
- the army is away from home: 1 in 4, go home (9);
- else, unless the last order was to buy: 1 in 4, buy (4);
- else 7 in 8: conquest (2) if it finds a target, otherwise buy (4) or pass (6), even chances;
- else (1 in 8): a Norman raids (3); a Saxon holds a tournament (1) after 1149, before that buys (4).

**Buying** (ai_buy 2A9E): if it has no catapult (in its campaign army or the garrison of the territory with its side's number, not its home's: AB 2AD1, a quirk to keep; the remake's `--fix=catapult` looks in its home's) it buys one (15) into the home garrison, and if it cannot afford one it buys nothing at all this month; then spend x gold / 10 is spent on men, half of it on knights (8 each) and the rest on soldiers; then castles (20 each) in its owned territories with the highest income and no castle, while it has 20 gold; then 80% of the soldiers and of the knights of the garrison where its campaign army stands join the army ((n << 3) / 10 in 32 bits: long_shl 9E77, long_div 9DF8; rounded down), and all of that garrison's catapults.

**Choosing a target** (ai_find_target 2803, ai_search 28B8, target_value 2704): a search from the campaign army's territory through the side's own territories (up to 4 steps); each neighbour not owned by the side gets a value:
- unowned: 1000 - steps;
- owned by a side it has 0 enmity with: never;
- with a castle: only with a catapult in the campaign army, (defenders / 2 + (own strength - defenders) + enmity) x 3;
- without: own strength - defenders + enmity,

where the defenders are the garrison plus the owner's campaign army if it is there (strengths as above). The best value wins (the first one found, on a tie); the army moves straight into the target and attacks it (army_move_to: the territory it came from is kept as its base, where army_settle sends it back after a refused siege). The path to the target is worked out (DS:0069) but never used.

**A quirk to keep:** the values are compared unsigned (`jbe`), so a negative value (an attack on a much stronger enemy) beats every positive one except -1, which is excluded. The remake's first games show it: in the first months the Saxons, with 8 soldiers, march on Norman territories held by 13 to 20 (values -3 to -12) and lose their armies. The remake's `--fix=targets` compares them signed: a lord then only attacks where the value is above 0.

## Notes
- **A side whose home falls** (result 4 against its home, or a rescue for the ward): all its territories go to the winner (side_falls 2406), its campaign army is disbanded, and it does nothing more (ai_turn skips a side without its home).
- Routine 44F4 (a share of a side's gold: 15, or 40% above 38) is never called.

## The random numbers (random_next 9D96)
A 16-bit Galois LFSR at DS:005B: shift right; if a 1 fell out, xor 0B400h. random(n) (9CFC; 0 when n is 0) takes the new value v, (v x 7FFFh) & FFFFh, shifted right by 8 when n < 256, then modulo n. seed_random (9DB3, at the start of every game) seeds it with the low word of the BIOS tick count (never 0) and then steps it a tick-dependent number of times; every 65535 calls (counter DS:0025) it is reseeded the same way. ai_choose_order uses the generator's last value directly (see *The computer lords*). The remake can use the same generator, seeded from the clock.

## The opening (new_game 10B2)
On the first game only (DS:002F; "play again" goes straight to the choice of character):
- The blank scroll (CA) with "Jack M. Zufelt and American Equity Resource in association with", the title tune (97h) starts, then "Cinemaware, Inc. presents a C I N E M A W A R E Interactive Movie, Copyright 1986, 1987".
- The title (CB): sparkles (title_twinkle 179A: 44 pixels around a point turn white in 11 rounds of 4 and back again) at (55, 67), (274, 41), (117, 98), (223, 97), (122, 156) and (247, 141), each followed by a pause of 9 or 18 ticks. The CGA program's put_pixel ORs the colour 0Fh into the byte, so it also lights the pixel to the left, and a few such pixels stay on its title. A key here skips the rest of the credits and stops the tune.
- The scroll again with the credits, one box at a time: Computography by David Todd, Fantasy Research, additional computography by Dave Farquharson; Art Direction and Special Effects by Curt Toumanian; based upon original artwork by James Sachs; Original Score composed by Jim Cuomo, IBM PC Soundtrack by Dave Farquharson; Executive Producers Robert and Phyllis Jacob; Produced by John Cutter; Written and Directed by Kellyn Beeck.
- The cast (CC) for 108 ticks (6 seconds), the introduction picture (CD) for 180 ticks (10 seconds).
- "Please insert reel two and press any key to continue..." until GameSYS reports disk 2 (ask_reel_two 9898).

Then, every game: with enough memory (DS:0004, in 64K blocks, from GameSYS) BJ and BK (6 or more), BN, BO and Bd (8 or more) are kept in memory; the map (CK) is unpacked once, its palette kept as palette slot 0 and its planes put at A000:6000 (redraw_map copies them from there); the portraits (BL) go to 3000:0 and the sprites BE to 2000:0.

**Choosing a character** (CE, when the title tune has ended): four panels, character 1 Wilfred of Ivanhoe top left, 2 Geoffrey Longsword bottom left, 3 Cedric of Rotherwood top right, 4 Wolfric the Wild bottom right. A blue box over the name (BE item 7 + character, XORed at DS:08F2/08FC) marks the character; the keypad moves it through the table DS:0906 (8 bytes a character: the neighbour for 8, 9, 6, 3, 2, 1, 4, 7, that is clockwise from up, or 0 for none: from 1, 6 goes to 3 and 2 to 2; from 3, 2 goes to 4; from 4, 4 goes to 2; from 2, 8 goes to 1); Enter (or the joystick's button) chooses. The first marked is character 1. (Checked in DOSBox.)

**Sherwood** (CF): the intro tune (98h) plays twice, each time with a box of the story ("SHERWOOD FOREST: Here you visit your old friend Robin of Locksley...", then "...Normans are assembling armies, and Saxons will fight them... Robin tells you the struggle ahead is a task for younger men."), the campfire flickering (fire_flicker 18C9) until the tune ends; then 125 more frames of fire. Then the setup above; at its end every owned territory is coloured on the map with its owner's colour (DS:0C7E).

## The options menu (options_menu 1957, from the orders)
A box of five: the joystick (ON / OFF), the music (ON / OFF), Start a New Game, End Present Game, Continue. The joystick line toggles it, and turning it on reads the stick's centre (the dead zone is a third either side: DS:08D3-08D9); the music line toggles DS:0033, and with music off the tunes still run, silently, so the game's timing is the same (play flags A000h / E000h instead of 8000h / C000h). Start a New Game ends this one with no question; End Present Game quits to DOS; Continue goes back. The other lines return to the menu.

## The end of the game (month 1B44)
- **Won** (the three Norman castles the player's): the victory tune (9Eh), "--- Final Victory --- Defeating the last enemy lord, you restore...", then "The Crown has been found. Robin has it!...", then the land view (CL) with "THE END" (BO item 6) at (100, 30).
- **Another Saxon won**: tune 9Dh, "Another Saxon has defeated the foul Norman oppressors...", "THE END" (BO item 6) at (100, 116).
- **The home castle lost**: tune 9Dh, "--- The Last Battle --- Your men fought bravely, but luck was not...", then "--- continued --- Moments later, you follow them to freedom...", "THE END" (BO item 6) at (100, 127).
- Then "Would you like to play again?" (above).

## The screens (the EGA build)
- **Pages**: everything is drawn on a back page at A000:2000 and copied to the screen at A000:0000 at the vertical retrace (present 9902; present_bottom 994A copies only lines 100-199, for the joust and the fire). A000:4000 keeps the castle during a siege (save_back / restore_back), A000:6000 the map. x is counted in 4-pixel units (the CGA build's bytes) by most routines, in pixels by the sprite slots and the glyphs.
- **Pictures**: show_picture 98C3: the C picture's palette becomes the current palette (CS:0103), its LZW data is unpacked to 3000:8000 and the planes copied to the back page; set_ega_palette 9CA1 shows the palette. Palettes can be kept in 16-byte slots (CS:E700; slot 0 = the map).
- **Sprite slots** (12, DS:1210-12B7: save area, active, x, y, image, image segment, width trim): sprites_draw 88CF saves what lies under each active slot (11 down to 0) and draws its masked sprite; sprites_erase 8816 puts the background back (0 up to 11). An image is 4 pointers to pre-shifted copies (chosen by x & 6): byte rows, byte bytes a row, word plane size, the mask (1 = transparent), the planes. The fire's two flames are in the program itself (CS:015C, CS:08B8).
- **Boxes** (dialog 7A80): a 12-byte description passed by value (struct_arg 9EB1): x, y, number of lines, width, icon (-2 text only, -3 a filled box without its frame, otherwise a framed box), ..., word +9 = the table of line pointers; `AB.ASM` and `tools/dec.py` show each box's text where it is used. A box with a menu returns the line chosen.
- **Territory colours** (set_region_colour, each program its own table): the EGA program sets the shape's set/reset colour word (DS:0C7E: the planes enabled in the high byte, so the XOR leaves the others to the shape's bits); the CGA program XORs a 2-bit pattern (DS:0C62, alternate rows from the word's two bytes) into the shape's pixels, cumulatively (set_owner XORs the old owner's out first); the Tandy program sets the shape's pixels to Dh XOR a nibble (DS:0C70).
- **Other drawing**: fill_rect, xor_rect (menu highlights), xor_sprite (cursors, sights), xor_mask (a territory's shape on the map, flash_territory), put_sprite (portraits, the ladies), draw_glyph (the font, ANDed: dark letters), put_pixel / get_pixel (the title's sparkles, the strength bars).
- **The CGA build** (AA) draws into a back buffer at 3000:8000 in the CGA's layout and copies it to B800 (two banks); GameSYS's video type 3 gets its own copies in a four-bank layout. **The Tandy build** (AC) uses a linear 4-bit back buffer (see `README.md`). Their own routines are named in `disassembler/aa_names.txt` and `ac_names.txt`; the rest match AB (`AA_vs_AB.txt`, `AC_vs_AB.txt`).

## The scenes' animation
The sprites are drawn in `../Graphics/Booter_EGA/sprites/` (one sheet a file, numbered by item; `extract_graphics.py`). Positions below are x in 4-pixel units and y in lines, as the code has them.

**The sword fight** (sword_fight 4F24; BN items, the bars and sparks in BO). The fighters' record (DS:0B08, words): player x, y, legs item, body item, strength; enemy x, y, legs item, body item, strength. A fighter is two sprites: the body at (x, y) and the legs at (x, y + 24) (the enemy's legs at x + 8).
- Player bodies: 160 sword raised (keys 7, 8, 9), 161 middle (4, 6), 162 thrust (Enter; back to 161 the next frame, when the hit is judged), 163 parry (1, 2, 3); legs 164 standing, 165-166 a step (two frames during which no key is read, then 164 again). 168 and 169 (the player falling and lying) are not used here.
- Enemy bodies: 171 on guard, 170 drawing back, 172 thrust (the frame after 170; the hit is judged then), 173 parry; legs 174 standing, 175-176 a step; when beaten, 178 (falling) and two ticks later 179 (lying, 32 lines lower).
- A hit flashes a spark (BO item 9 at the enemy, x + 7, y + 17; BO item 10 at the player, x - 1, y + 16) and shortens the loser's bar by 2 pixels (bar_shorten; bars BO items 7 "You" and 8 "Enemy" at (8, 192) and (43, 192), their ends at x 154 and 280 pixels). At the start the player's bar is shortened 49 - strength times; in the Attack the guards' bar 20 times (so it shows 30 points for a strength of 20, and still 10 when they fall); in the Defense the lord's bar 39 - strength times. Quirks to keep.
- The Attack (raid_attack, CN, tune 9Bh looping): player at 32, enemy at 54 (y 141); the player may retreat to x 30 ("The Retreat" if he goes below), the enemy back to 51. Two more fighters fight in the background (DS:0B1C: x 7 and 13, y 139), changing bodies at random (random(9): 1-4 the right one's 170-173, 5-8 the left one's 160-163, 0 the pair steps 1 left or right, even chances, kept within 4-10 (11 becomes 9, 3 becomes 5), the legs stepping with it; not while one of them is thrusting).
- The Defense (raid_defense, CO, 40 ticks of the picture first): player at 6, enemy at 23; retreat limit 4, the enemy's 20.

**The joust's approach** (joust_approach 6850, over the tournament from above, CH): BJ items 2-22 a knight riding in (x 41 up to 61, y 76, 3 ticks a frame), 23-24 turning at 60, then 25-29 riding back (x 60 down) while the other knight (items 30-34, then 35; y 88, x 15 up) comes in (1 and 2 ticks a frame); then the opponent's portrait at (9, 3) and the player's at (53, 3), each with its name, and "An expectant hush falls over the gallery as the Marshall gives the signal and the gallant knights spur their horses into action. Begin when ready".

**The joust's outcome** (joust_outcome 6C59, over the stands, CJ): script BJ item 37 + result (37 near miss, 38 opponent unhorsed, 39 player unhorsed, 40 the horse), 41 frames each of the two knights crossing: 4 bytes a knight (BJ item - 20, rows to draw, the rest cut off behind the barrier, x, y; a y of 0 removes the knight, an x over 80 ends the script). The white knight (items 41-47) is the player, the dark one (48-61) the opponent; in 38 the opponent falls (49-54) and his horse runs on (55). Each frame comes with two gallop beeps (divisor DS:0065, falling by 500 from 30000). `tools/joust_scripts.py` lists them.

**The battle** (battle_shown 57BB): no picture, a black screen with the two armies' figures (show_armies), the tactics menu at (49, 123) and the fighters (BN is unpacked to 2000:0, over BE, which is only needed for the choice of character). The player's side is on the left in red (bodies 160-163, legs 165, fallen 169, knight 180), the other on the right in green (170-173, 175, 179, knight 181). Each round shows 28 frames, one a timer tick, cycling through three rows (2, 1, 0). Soldiers: rows 2, 1, 0 are shown while the side has more than 50, 25, 0 soldiers, at (42, 6), (18, 6), (31, 74) on the left and (48, 6), (24, 6), (37, 74) on the right (DS:0B40/0B46), body random(4) + 160 or + 170 every frame, legs at y + 24; a row whose men are gone shows a fallen man (169 or 179) at y + 32. Knights: rows 1 and 0 while more than 10 and 0 knights, at (0, 0) and (0, 61) on the left and (62, 0) and (62, 61) on the right (DS:0B34/0B3A), put opaque, XORed away when lost.

**The siege** (siege_by_player 763E; Bd items over CQ for a Saxon castle, CP for a Norman one). The catapult: base item 8 at (39, 146), arm 9 at (39, 125); the loaded arm (10 Greek Fire, 24 Disease, 38 Boulders) moves down from line 136 as the tension rises (to 159), with the flame (52) XORed on it for Greek Fire; on release it springs back (11, 25, 39 at line 132) and the shot rises (12/26/40 to line 112, 13/27/41 to 100). The flight (show_shot 739D): 30 frames, one a screen refresh (its wait_ticks(1) end at once), x 41 (the code would move it to 42 at frame 10, but tests the frame count only at frames 2, 5, 8 ...: it never moves), y from the table DS:0992 (30 bytes for each height 0-7), the item changing every 3 frames as the shot shrinks with distance (ammunition x 14 + frame / 3: 14-23, 28-37, 42-51). Each boulder hit at the wall's height puts the next hole on the wall: Bd 3, 4, ... 7 at (39, 75). The Tandy program puts the catapult, its flame, the holes and the flight one unit (4 pixels) to the left (38, 40: AC 62C2, 64B6), where the EGA program's whole bytes put them too; the CGA program uses AB's numbers. Only after a boulder's hit is the catapult's sprite slot cleared: after any other last shot it is still set when the battle starts, so it is drawn (and taken off again) over the battle's first frames until slot 0 is used for the enemy's men (the remake's `--fix=siege-sprite` clears it).

## Not read in detail yet
- DOC.EXE (the 1987 DOS version) against the booter.
