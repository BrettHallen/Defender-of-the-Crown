# The manual against the PC code

What the printed manual and the reference cards say, checked against the PC game as read from its code (`GAME_LOGIC.md`; the booter's EGA program, and DOC.EXE where it differs). The manual is the one booklet shipped with every computer version (1986, written for the Amiga original); each version added its own reference card. No scan of the IBM PC card has been found, so the two cards in `../Documentation` are other versions':

- `Defender_of_the_Crown_Manual_C64.pdf`: the booklet (14 pages, scanned without a text layer; read here by OCR), with the **Commodore 64** reference card (©1987, "Special thanks to Palace Software", who did that port) at its end.
- `Defender_of_the_Crown_Reference_Card_Apple.pdf`: the **Apple IIGS** reference card (©1988, "Programmed by Ivan Manley of Manley & Associates"), with its own Questions & Answers.

The cards describe their own ports, which differ from the PC's in places (the C64's battle strengths, the IIGS's Spy option and seven-day siege); where they disagree with the PC code, that is not a flaw in either.

## Agreed

| The manual or a card | The PC code |
|---|---|
| Six lords; the three Norman castles in the south; capture every Norman fortress to win | The game is won when Norfolk, Buckingham and Cornwall all belong to the player |
| Hold Tournament, Go Raiding, Buy Army, Pass and an attack end your turn; the other actions are unlimited (C64 card) | The same; Buy Home Army ends the month only if more was bought than sold back |
| Holding a tournament costs 5 gold; at other lords' tournaments you joust for free (both cards) | The holder needs and pays 5 gold |
| Joust for Fame to raise your leadership, for Land to win territory; you need spare land to joust for it (cards) | Fame: leadership ±1; Land only if both sides own a territory without a castle |
| A strong jousting rating means your aim needn't be as good; a weak one, dead centre (Q&A) | The target is 138 ± (your jousting + 2 − his), at least 1 (in the EGA program it can close completely: `--fix=joust-margin`) |
| Your opponent may miss, especially with a low jousting rating (cards) | You are unhorsed only if random(his jousting) is 2 or more; otherwise "A Near Miss" and you joust again |
| Aim at a horse and the tournament will be your last | Hitting the horse bans you from tournaments for good (and costs you every territory but your home, and morale) |
| Robin pledged his aid three times | Three pledges a game (DS:004B) |
| Seek Robin before a raid: his men are renowned with the blade | Asking Robin before a raid sets your sword strength to 50 |
| Thrust when the enemy's sword points up, when he is most vulnerable (cards) | The enemy attacks in two turns, raising his sword (170) then striking (172); raised, he isn't parrying |
| Raiding steals his gold (cards: right after he attacks you) | A successful raid takes half of the lord's gold |
| You can always get out the way you came in | Backing out past the left edge ends the raid ("The Retreat": leadership to 0, morale −2) |
| Each soldier figure is 25 men, each horseman 10 knights (C64 card) | The battle shows soldiers in groups by more than 50, 25 and 0, knights by more than 10 and 0 |
| Your tactic decides how both armies fight (cards) | battle_round uses the one tactic for both sides' damage |
| Ferocious Attack: a better chance against a stronger army, far greater casualties | Knights count double (knights / 4 against / 8) for both sides |
| Knights are the striking power; soldiers protect them; avoid losing knights | Knights do 4 or 8 times a soldier's damage; losses take soldiers first, knights only when no soldiers are left |
| You need a catapult in your campaign army to attack a castle (cards) | "Sorry Sir, you have no catapult. You are forced to retreat" |
| Knock a hole in the wall with a boulder before Disease or Greek Fire (cards) | They work only above the wall's height; the wall starts at 6, the highest shot that lands, so a boulder must lower it first |
| Six boulder hits bring the wall down (IIGS card) | The wall's height 6 drops by one a hit |
| Disease works better early in the siege (cards) | The garrison loses soldiers × days left / 15 |
| Build castles to defend your lands | Castles cost 20 gold and come with 10 soldiers in the territory's garrison |
| A territory worth seven gold a month is worth taking even for a few months (Q&A) | Gloucester and Sussex bring 7, Buckingham and Cornwall 8 |
| Read Map shows the lords' leadership, jousting and swordfighting (Q&A) | territory_info shows them as Weak, Average, Good or Strong |

## Different on the PC

| The manual or a card | The PC code |
|---|---|
| **Vassals** from your lands join your campaign army when you set out, desert as battles go on, and are replenished over time | No such levy or desertion. A territory's vassals (`Territories.ini`) are only the soldiers holding it at the start; afterwards it holds whatever garrison was transferred into it |
| An undamaged castle **nearly doubles** the defenders' effectiveness, less with each hit to the wall (both cards) | The attacker's damage is cut by 90% at a whole wall, by 15 points less for each boulder hit (to 0 after six) |
| The siege's battle begins after **7 days** (IIGS card) | 6 days (DS:0A88) |
| Leadership: a strong leader adds **50%**, a weak one nothing; Outflank **doubles** its effect (C64 card) | Each side adds leadership × damage / 10 (10% a point, so up to 100%, and something even for a weak one); with Outflank each side's damage is instead reduced by the other's leadership share |
| Strengths: soldiers 1; knights 8 (Ferocious Attack) or 6; catapults 16 in Bombard (C64 card) | Knights are 8 soldiers in Ferocious Attack and Bombard (/ 4 against / 32) and 4 in Stand and Fight and Outflank (/ 8); Bombard adds random(catapults + 1) |
| If the Saxons hold all three Norman castles, you must still capture them to win, even from Saxons (Q&A) | If one other Saxon holds all three, the game ends and you lose; only while they are split between owners does it go on |
| The captain inside must be forced to the top of the stairs before he dies (C64 Q&A) | The Defense ends when either strength reaches 0, wherever he stands |
| In the joust, press the button when he comes close; too early sounds a buzzer, too late misses (both cards) | No button: the outcome is judged where the lance's point is at the meeting |
| To practise jousting play Cedric (C64 Q&A) or Wolfric (IIGS Q&A) | Wolfric has the best jousting (10); Cedric's is 7 and his leadership 10 |
| The IIGS's Spy option; refunds on a Buying/Refunding bar | Not in the PC game; Buy Home Army's Left sells back only what was bought in this visit |
