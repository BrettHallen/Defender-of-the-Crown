# Defender of the Crown (PC): the game logic

Read from the booter's EGA program (`AB.ASM`; addresses are AB's) with `tools/dec.py`. The CGA and Tandy programs run the same code at other addresses (`AC_vs_AB.txt`); DOC.EXE, the 1987 DOS version, is not compared yet. Started 15 Nov 2026. Covered: the **strategic game** (the data, the setup, the month, income, events, buying, conquest, the computer lords), **Seek Conquest with the player's battles and sieges**, **raids and the sword fight**, **tournaments and jousting**, and **the ladies** (kidnapping, rescue, romance). The scenes' drawing and animation are not described here, only their rules.

Checked in DOSBox so far: the first month's status panel (Wilfred of Ivanhoe: Leadership Good, Jousting Good, Swordplay Average; no men in the campaign army; treasure 12 = 9 + his home's income of 3; October 1149), in two runs that dealt him different homes (Cumbria, then Clwyd), the Buy Home Army screen (costs 1, 8, 15, 20; 10 soldiers in the home army), and Hold Tournament in the first month ("There is no land to joust for, so you must joust for fame": the player owns no territory without a castle yet). Everything else is read from the code and not yet checked against the running game.

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
After the title, the credits, the introduction and the choice of character:
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

Then the end checks:
- If the three Norman castles (Norfolk, Buckingham, Cornwall) all have the same owner and it is a Saxon, the game is over: the player has won if it is the player (speaker tune 9Eh), otherwise lost (9Dh).
- If the player no longer owns their home castle, the game is lost.
- While the Norman castles' owners add up to less than 12 (that is, at least one has fallen to a Saxon), the other Saxons (sides 2 and 3) grow more hostile to the player (+2 enmity a month).

## Events (monthly_event 2F4E)
When the event counter runs out, one of eight events (random(10) + 1; 9 and 10 do nothing), then the counter is set again to 5 + random(8):

| # | Event | Effect |
|---|---|---|
| 1 | Viking raid | A third of the soldiers of the garrison of territory *player* are lost: the code indexes the garrisons with the player's side number (1, so always Cumbria's garrison) instead of the player's home. That is the player's home army only when the player's home is Cumbria: an original quirk (AB 2F89) |
| 2 | Danes invade | The player loses a territory: the highest-numbered one that is not their home (side_last_territory 2F14); armies there go home |
| 3 | Norman plotters, vassals revolt | The same |
| 4 | Sheriff ambushed | Half of this month's income is lost |
| 5 | Catapult sabotaged | The player's campaign army loses a catapult (if it has one) |
| 6 | Robin raids a Norman stronghold | Each Saxon side gets 25 gold |
| 7 | Three knights from Germany | The player's campaign army gets 3 knights |
| 8 | Norman vassals revolt | The first Norman (4-6) that has a territory other than its home loses its highest-numbered one to the player |

## The player's orders (orders_menu 1A91)
"Your Orders?": 1 Hold Tournament (tournament 62BC), 2 Seek Conquest (seek_conquest 35E0), 3 Go Raiding (go_raiding 45AC), 4 Buy Home Army (buy_army 39C7), 5 Read Map (read_map 4084: territory_info shows a territory's income, vassals and owner), 6 Pass ("Lord *name* Passes"), 7 Options (options_menu 1957). The month goes on when an order returns non-zero.

- **Buy Home Army**: soldiers 1, knights 8, catapults 15 gold, bought into the home garrison; a castle (20 gold) is built in a territory the player owns that has none: castle 35 and 10 more soldiers in its garrison.
- **Seek Conquest** (seek_conquest 35E0): a menu that stays open until a move ends the order:
  - **Send forth Campaign Army** (needs soldiers or knights in the campaign army): choose a territory on the map (choose_destination 3585): it must be a neighbour of where the army is (is_neighbour 3D82); choosing Sherwood Forest asks Robin (below). Then send_army 3135 moves the army there and attacks. Moving into one of your own territories (result 1), being refused a siege for want of a catapult (3) or passing through a friendly Saxon's land (8) keeps the menu open, so **the army can march any distance through your own land in one month**; any other result ends the order.
  - **Transfer Forces** (transfer_forces 3721): only in a territory you own: soldiers, knights and catapults move one at a time between the campaign army and that territory's garrison ("Home", "Garrison" with a castle, "Territory" without), with no limits.
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

Before a battle, a defending campaign army in the territory joins the garrison. A territory with a castle is besieged (siege 74B5: the player's siege 763E or a siege of the player 78A9), otherwise there is a field battle (battle 5781): shown with tactics when the player is involved (battle_shown 57BB), otherwise fought out at once (battle_auto 600C).

**Battle rounds** (battle_round 60EB; battle_auto always uses tactic 2, Stand and Fight, until one side is empty): each side's damage is soldiers / 32 + knights / *k* (army_damage 6202), where by tactic *k* is 4 (1 Ferocious Attack), 8 (2 Stand and Fight), 4 (3 Bombard, plus random(catapults + 1)), 8 (4 Outflank), and for 5 (Retreat) soldiers / 48 + knights / 16. Leadership adds lead x damage / 10 (rounded) to each side's damage; with Outflank instead each side's damage is reduced by the other side's leadership share. Then each side adds random(3); the attacker's damage is reduced by a percentage (the attack's 4th argument; 0 in the open field). Each point of damage kills one soldier, or a knight when no soldiers are left (take_losses 6290).

## The player's field battle (battle_shown 57BB)
Fought when the player attacks a territory without a castle, is attacked in one, or as the last part of a siege (below). If the defenders have no soldiers or knights: "There are no men defending this territory. You capture it without casualty" (result 4). Otherwise the screen shows both armies, and round after round battle_round runs with the tactic chosen in the menu (Ferocious Attack, Stand and Fight, Bombard, Outflank, Retreat!; the cursor moves with the up and down keys while a round is shown, about 28 frames). Retreat is offered when attacking, or when defending with the campaign army in a territory that is not the home; at home or with only the garrison there is no retreat.
- The battle ends when one side or both have no soldiers or knights left (an army left with none also loses its catapults): 4 (the attacker won), 5 (the defender won) or 7 (both gone); morale +3 for a win, -3 for a loss, -1 for both gone.
- **Retreat**: attacking, the army goes back (result 6); defending your own territory, the garrison joins the campaign army, it leaves, and the attacker takes the territory (result 4). Morale -3.

## Sieges (siege 74B5)
Every attack on a territory with a castle is a siege; the attacker needs a catapult in its campaign army (otherwise the player is told "Sorry Sir, you have no catapult. You are forced to retreat", result 3; a computer side gets result 6).

**The player's siege** (siege_by_player 763E): up to 6 days of bombardment (DS:0A88), one shot a day, then the battle. Each day choose the ammunition (choose_ammo 7505): Greek Fire (2 shots, DS:0A8C), Disease (1, DS:0A86), Boulders (6, DS:0A82) or Cease Fire (ends the bombardment). Then aim (catapult_aim 7168): Enter starts drawing the arm back, Enter again releases; the shot's height is (tension - 140) / 2, 0-7, where tension rises by one a tick from 136 to at most 159. Shots of height 0 or 7 miss. The wall starts at height 6 (DS:0A8A):
- **Greek Fire** over the wall (height above the wall's): the garrison loses soldiers / (random(25) + 6).
- **Disease** over the wall: the garrison loses soldiers x days left / 15 (40% on the first day, less later).
- **Boulders** that hit the wall at its height: the wall is one lower, and the defenders' protection drops by 15.
- The garrison never goes below 1 soldier.
Then the field battle, with the attacker's damage reduced by the protection: 90% less 15 for each boulder hit.

**A computer side's siege** (siege_of_player 78A9, also used between computer sides): protection 90 - (random(3) + 3) x 15 (45, 30 or 15%), the garrison loses soldiers / (random(7) + 2) (at least 1, never below 1), then the battle (shown if the player is involved).

## Raids (go_raiding 45AC, raid 45EC)
**Go Raiding**: choose a territory on the map (choose_raid_target 4538): it must be another side's home castle that the side still holds (choosing your own home cancels the order; Sherwood Forest asks Robin). Then:
- The castle's owner's enmity with the player +1.
- The player's sword strength (DS:0B10) is swordplay x 4, or 50 if Robin's help was asked for (that uses the help up).
- **The Attack** (raid_attack 5449): a sword fight against the guards, whose strength (DS:0B1A) is 20, with other fighters animated around (sword_fight mode 1).
- **The Defense** (raid_defense 5571): if the attack was won, a second sword fight against the castle's lord, whose strength is his swordplay x 4.
- **Success** (both won): with a kidnapped lady to rescue, the romance (below); otherwise "The Enemy's Gold": half of the lord's gold is taken, leadership +1, morale +1.
- **Captured** (the player's strength runs out): leadership -1, morale -1, and half of the player's gold goes to the lord as ransom.
- **The Retreat** (backing out of the fight, past the left edge): leadership -10 (that is, to 0) and morale -2.

**The sword fight** (sword_fight 4F24): the two fighters stand at x positions (the player DS:0B08, the enemy DS:0B12); each loses one point of strength per hit, and the fight ends when either reaches 0 or the player retreats past the left limit. The player's keys (the keypad; a table at 5263): Enter thrusts; 8 raises the sword, 2 parries; 7, 4 and 1 step back (sword raised, middle stance, parrying), 9, 6 and 3 step forward the same way (only while more than 5 apart). A thrust hits when the two are less than 7 apart and the enemy is not parrying. The enemy acts every other frame: more than 6 apart, steps in with chance 1/2; less than 6 apart (and not at his limit), steps back parrying; otherwise attacks or parries, even chances; his attack hits when less than 7 apart and the player is not parrying.

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

**The joust** (joust 6EC2): the knights charge (20 steps); meanwhile the keypad moves the lance's point (x DS:0D0C, 20-50; y DS:0D14, 120-180; it also bobs up and down with the gallop: lance_step 6B09). At the meeting:
- **Hit**: the point within the target, x 26 ± (1 if the player's jousting is higher than the opponent's, else 0) and y 138 ± (player's jousting + 2 - opponent's, at least 1): the opponent is unhorsed (win).
- **The horse**: x below 30 and y above 170: disgrace.
- **Otherwise**: random(opponent's jousting) of 2 or more, the player is unhorsed (loss); else "A Near Miss" and they joust again. The fourth pass is always a loss, whatever happens in it.

## The computer lords (ai_turn 2995)
A computer side whose home castle has fallen does nothing. Otherwise: gold += income; it may move soldiers from its campaign army into the garrison where the army is (ai_reinforce_garrison 2C60: up to half of the army's soldiers at home, a fifth elsewhere, when the garrison has fewer); then it chooses an order (ai_choose_order 2D84, using the random generator's last value):
- the army is away from home: 1 in 4, go home (9);
- else, unless the last order was to buy: 1 in 4, buy (4);
- else 7 in 8: conquest (2) if it finds a target, otherwise buy (4) or pass (6), even chances;
- else (1 in 8): a Norman raids (3); a Saxon holds a tournament (1) after 1149, before that buys (4).

**Buying** (ai_buy 2A9E): if it has no catapult (in its campaign army or home garrison) it buys one (15) into the home garrison, and if it cannot afford one it buys nothing at all this month; then spend x gold / 10 is spent on men, half of it on knights (8 each) and the rest on soldiers; then castles (20 each) in its owned territories with the highest income and no castle, while it has 20 gold; then part of the soldiers and knights of the garrison where its campaign army stands join the army (the share is worked out with long arithmetic, 9E77/9DF8: not read yet), and all of that garrison's catapults.

**Choosing a target** (ai_find_target 2803, ai_search 28B8, target_value 2704): a search from the campaign army's territory through the side's own territories (up to 4 steps); each neighbour not owned by the side gets a value:
- unowned: 1000 - steps;
- owned by a side it has 0 enmity with: never;
- with a castle: only with a catapult in the campaign army, (defenders / 2 + (own strength - defenders) + enmity) x 3;
- without: own strength - defenders + enmity,

where the defenders are the garrison plus the owner's campaign army if it is there (strengths as above). The best value wins; the army moves to the target's neighbour along the path and attacks.

**A quirk to keep:** the values are compared unsigned (`jbe`), so a negative value (an attack on a much stronger enemy) beats every positive one except -1, which is excluded. This needs checking in the running game before the remake relies on it.

## Notes
- **A side whose home falls** (result 4 against its home, or a rescue for the ward): all its territories go to the winner (side_falls 2406), its campaign army is disbanded, and it does nothing more (ai_turn skips a side without its home).
- Routine 44F4 (a share of a side's gold: 15, or 40% above 38) is never called.

## Not read yet
- The drawing of the scenes (the battle and siege screens, the sword fight's and the joust's animation tables, the lance's movement table DS:0CDC).
- The computer's transfer from a garrison to its campaign army (the long arithmetic in ai_buy).
- The title, the introduction, the choice of character, the options menu, the end screens (they are the same pictures and texts as in the files).
