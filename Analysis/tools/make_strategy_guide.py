#!/usr/bin/env python3
"""Writes DOTC_PC_Strategy_Guide.pdf (needs reportlab and the DejaVu fonts):
    python3 Analysis/tools/make_strategy_guide.py [OUT.pdf]
Every number in it comes from the game's code, as written up in Analysis/GAME_LOGIC.md."""
import sys, os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Table,
                                TableStyle, KeepTogether, PageBreak)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

FONT_DIRS = ["/usr/share/fonts/truetype/dejavu", "/Library/Fonts", os.path.expanduser("~/Library/Fonts")]
def font(name):
    for d in FONT_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p): return p
    sys.exit("missing font " + name)
pdfmetrics.registerFont(TTFont("Sans", font("DejaVuSans.ttf")))
pdfmetrics.registerFont(TTFont("Sans-Bold", font("DejaVuSans-Bold.ttf")))
pdfmetrics.registerFont(TTFont("Sans-Oblique", font("DejaVuSans-Oblique.ttf")))
pdfmetrics.registerFont(TTFont("Mono", font("DejaVuSansMono.ttf")))
pdfmetrics.registerFontFamily("Sans", normal="Sans", bold="Sans-Bold", italic="Sans-Oblique", boldItalic="Sans-Bold")

INK = colors.HexColor("#1F2933")
ACCENT = colors.HexColor("#8A3B12")
GREY = colors.HexColor("#616E7C")
HEAD_BG = colors.HexColor("#F6F1EA")
TIP_BG = colors.HexColor("#FBF7F0")
RULE = colors.HexColor("#D9CBB8")

body = ParagraphStyle("body", fontName="Sans", fontSize=8.8, leading=12.4, textColor=INK, spaceAfter=5)
small = ParagraphStyle("small", parent=body, fontSize=7.8, leading=10.5)
cell = ParagraphStyle("cell", parent=body, fontSize=8, leading=10.6, spaceAfter=0)
cellb = ParagraphStyle("cellb", parent=cell, fontName="Sans-Bold")
title = ParagraphStyle("title", fontName="Sans-Bold", fontSize=22, leading=27, textColor=ACCENT, spaceBefore=4, spaceAfter=2)
subtitle = ParagraphStyle("subtitle", fontName="Sans", fontSize=10, leading=14, textColor=GREY, spaceAfter=6)
h1 = ParagraphStyle("h1", fontName="Sans-Bold", fontSize=13.5, leading=17, textColor=ACCENT, spaceBefore=10, spaceAfter=5, keepWithNext=1)
h2 = ParagraphStyle("h2", fontName="Sans-Bold", fontSize=9.6, leading=12.5, textColor=INK, spaceBefore=6, spaceAfter=3, keepWithNext=1)
bullet = ParagraphStyle("bullet", parent=body, leftIndent=11, bulletIndent=2, spaceAfter=3)
tipst = ParagraphStyle("tip", parent=body, fontSize=8.6, leading=12, spaceAfter=0)

def P(t, st=body): return Paragraph(t, st)
def B(items): return [Paragraph(t, bullet, bulletText="•") for t in items]

def tip(text):
    t = Table([[P("<b>Tip.</b> " + text, tipst)]], colWidths=[174 * mm])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), TIP_BG), ("LINEBEFORE", (0, 0), (0, -1), 2.2, ACCENT),
                           ("LEFTPADDING", (0, 0), (-1, -1), 7), ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                           ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    return [t, Spacer(1, 6)]

def table(head, rows, widths, center_from=None):
    data = [[P(h, cellb) for h in head]] + [[P(str(x), cell) for x in r] for r in rows]
    t = Table(data, colWidths=[w * mm for w in widths], repeatRows=1)
    st = [("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -1), 0.5, RULE),
          ("BACKGROUND", (0, 0), (-1, 0), HEAD_BG), ("LINEBELOW", (0, 0), (-1, 0), 0.8, RULE),
          ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 4), ("LEFTPADDING", (0, 0), (-1, -1), 5)]
    t.setStyle(TableStyle(st))
    return [t, Spacer(1, 7)]

def footer(canv, doc):
    canv.saveState()
    canv.setStrokeColor(INK); canv.setLineWidth(0.6)
    canv.line(18 * mm, A4[1] - 14 * mm, A4[0] - 18 * mm, A4[1] - 14 * mm)
    canv.setFont("Sans", 7); canv.setFillColor(GREY)
    canv.drawString(18 * mm, 12 * mm, "Defender of the Crown (PC) — Strategy Guide")
    canv.drawRightString(A4[0] - 18 * mm, 12 * mm, "Page %d" % doc.page)
    canv.restoreState()

s = []
s.append(P("Defender of the Crown — Strategy Guide", title))
s.append(P("The IBM PC version (1987): how the game really works, read from its code", subtitle))
s.append(P("The printed manual was written for the Amiga original and is vague, and in places wrong, about the PC game. "
           "Everything in this guide comes from the PC program itself, disassembled and read routine by routine "
           "(<i>Analysis/GAME_LOGIC.md</i> has the details). It describes the booter version (CGA, EGA and Tandy), which the remake plays "
           "by default; where the 1987 DOS version (DOC.EXE, the remake’s <font face='Mono'>--rules=dos</font>) differs, it says so. "
           "Some of the original’s flaws are noted as <b>quirks</b>; the remake keeps them unless told to fix them (<font face='Mono'>--fix=</font>)."))

# ---------------------------------------------------------------- winning
s.append(P("Winning and losing", h1))
s += B(["<b>You win</b> when you own all three Norman castles: Norfolk, Buckingham and Cornwall.",
        "<b>You lose</b> when your home castle falls, or when <b>another Saxon</b> owns all three Norman castles. "
        "(The manual says you could still take them from him; on the PC the game ends at once.)",
        "The checks are made after every lord’s turn, not just once a month."])
s.append(P("The month", h2))
s.append(P("Each month you go first: your income is added, perhaps an event, then your orders. Then each of the five computer lords "
           "takes his turn. <b>Hold Tournament, Go Raiding, Buy Home Army</b> (if you bought more than you sold back), <b>Pass</b> and "
           "<b>an attack</b> end your month. Read Map, Transfer Forces and moving through your own land do not: "
           "<b>your army can march any distance through your own territories in one month</b> before it attacks."))

# ---------------------------------------------------------------- characters
s.append(P("The lords", h1))
s.append(P("Lead, Joust and Sword are the leadership, jousting and swordplay ratings, Gold the gold at the start. Ratings run 0 to 10; the game shows 0-3 as Weak, 4-6 Average, 7-8 Good and 9-10 Strong. "
           "The three Saxon homes (Cumbria, Nottingham, Clwyd) are dealt at random; the other two Saxons and three of the five Normans are "
           "chosen at random too, so check Read Map at the start of each game."))
s += table(["Lord", "Lead", "Joust", "Sword", "Gold", "Best at"], [
    ["Wilfred of Ivanhoe", 7, 8, 6, 9, "An all-rounder; the manual’s choice for a first game"],
    ["Geoffrey Longsword", 6, 6, 9, 10, "Raids: a sword strength of 36"],
    ["Cedric of Rotherwood", "<b>10</b>", 7, 3, 8, "Battles: leadership 10 makes Outflank crushing (below); raids are hopeless without Robin"],
    ["Wolfric the Wild", 5, "<b>10</b>", 5, 8, "Tournaments: a wide target and the best odds"],
], [38, 13, 13, 15, 13, 82])
s += table(["Norman (three of five)", "Leadership", "Jousting", "Swordplay", "Gold at start"], [
    ["Brian de Bois-Gilbert", 8, 10, 8, 18],
    ["Philip Malvoisin", 7, 8, 6, 21],
    ["Reginald Front-de-Boeuf", 5, 7, 10, 20],
    ["Edmund the Grim", 10, 5, 8, 19],
    ["Roger Falconbridge", 8, 8, 9, 18],
], [52, 22, 22, 22, 22])

# ---------------------------------------------------------------- the land
s.append(P("The land", h1))
s.append(P("A territory’s income is added to its owner’s treasury every month. Its <b>vassals</b> are only the soldiers holding it "
           "when the game starts: unlike the manual’s vassals they never join your army or desert. The six castle territories are the lords’ "
           "homes. The other twelve start with no owner, defended by their vassals."))
TERR = [
    (1, "Cumbria", 3, "castle", "Yorkshire, Lancashire"),
    (2, "Yorkshire", 2, 6, "Cumbria, Lancashire, Nottingham, Lincolnshire"),
    (3, "Gwynedd", 2, 4, "Lancashire, Glamorgan, Clwyd"),
    (4, "Lancashire", 4, 6, "Cumbria, Yorkshire, Gwynedd, Nottingham, Clwyd, Leicester"),
    (5, "Nottingham", 2, "castle", "Yorkshire, Lancashire, Lincolnshire, Leicester"),
    (6, "Lincolnshire", 3, 6, "Yorkshire, Nottingham, Leicester, Cambridge, Norfolk"),
    (7, "Glamorgan", 1, 4, "Gwynedd, Clwyd, Gloucester"),
    (8, "Clwyd", 3, "castle", "Gwynedd, Lancashire, Glamorgan, Leicester, Gloucester"),
    (9, "Leicester", 2, 5, "Lancashire, Nottingham, Lincolnshire, Clwyd, Cambridge, Gloucester, Buckingham"),
    (10, "Cambridge", 5, 6, "Lincolnshire, Leicester, Norfolk, Buckingham, Essex"),
    (11, "Norfolk", 6, "Norman castle", "Lincolnshire, Cambridge, Essex"),
    (12, "Gloucester", 7, 12, "Glamorgan, Clwyd, Leicester, Buckingham, Dorset, Hampshire"),
    (13, "Buckingham", 8, "Norman castle", "Leicester, Cambridge, Gloucester, Essex, Hampshire"),
    (14, "Essex", 6, 8, "Cambridge, Norfolk, Buckingham, Hampshire, Sussex"),
    (15, "Cornwall", 8, "Norman castle", "Dorset"),
    (16, "Dorset", 4, 6, "Gloucester, Cornwall, Hampshire"),
    (17, "Hampshire", 3, 8, "Gloucester, Buckingham, Essex, Dorset, Sussex"),
    (18, "Sussex", 7, 8, "Essex, Hampshire"),
]
s += table(["#", "Territory", "Gold / month", "Vassals", "Neighbours"],
           [[n, nm, g, v, nb] for n, nm, g, v, nb in TERR], [8, 26, 20, 24, 96])
s += tip("The rich land is in the south: Gloucester and Sussex bring 7 a month, Cambridge 5, Essex 6. Gloucester has the most vassals (12) "
         "and borders both Clwyd and Buckingham. Cornwall can only be reached through Dorset. "
         "The territory numbers matter: events and tournaments take your <b>highest-numbered</b> land first, so southern holdings are the first to go.")

# ---------------------------------------------------------------- start
s.append(P("The start", h1))
s += B(["You have the gold shown above, your home’s income (Cumbria 3, Nottingham 2, Clwyd 3) and <b>10 soldiers in your home garrison. "
        "Your campaign army is empty</b>: transfer men into it (Seek Conquest, Transfer Forces) or buy some before you can march.",
        "Every computer lord starts with 15 soldiers in his campaign army and 5 at home.",
        "The other two Saxons start friendly (enmity 0): a lord <b>never attacks a lord whose enmity towards him is 0</b>. "
        "The Normans start at 5 against you.",
        "The first event comes 5 to 12 months in."])
s += tip("The neighbouring unowned lands are held only by their vassals (4 to 12 soldiers), and the Normans are slow at first. "
         "Take two or three of them in the first months: each adds its income for the rest of the game.")

# ---------------------------------------------------------------- money
s.append(P("Gold and buying", h1))
s += table(["Item", "Cost", "Notes"], [
    ["Soldier", "1", "The army’s body: losses are taken from soldiers first"],
    ["Knight", "8", "Strikes 4 or 8 times as hard as a soldier, depending on the tactic"],
    ["Catapult", "15", "Needed in your campaign army to attack any castle"],
    ["Castle", "20", "Built in a territory you own without one, <b>with 10 soldiers in its garrison</b>"],
], [26, 14, 134])
s.append(P("Buying puts everything in your home garrison; move it to the campaign army with Transfer Forces. In the Buy menu Right buys one and "
           "Left sells back one bought on this visit."))
s += tip("A castle is 10 soldiers for 2 gold each <i>and</i> a wall. A computer lord only attacks a castle when he carries a catapult, and then "
         "his damage is cut by 15 to 45% (below). Castles on your borders keep the Normans busy elsewhere.")

# ---------------------------------------------------------------- battles
s.append(P("Battles", h1))
s.append(P("A battle is fought in rounds until one side has no soldiers or knights left. In each round each side deals"))
s.append(P("<b>damage = soldiers ÷ 32 + knights ÷ <i>k</i></b> &nbsp;(each division rounded down), plus the leader’s share, plus random 0-2",
           ParagraphStyle("f", parent=body, alignment=1, spaceBefore=2, spaceAfter=6)))
s.append(P("and every point of damage kills one enemy: a soldier, or a knight once no soldiers are left. Your tactic is used by <b>both</b> armies."))
s += table(["Tactic", "Knights ÷ k", "Leadership", "Notes"], [
    ["Ferocious Attack", "÷ 4", "Each side adds its own leader’s share", "Knights count double, for both sides: bloody"],
    ["Stand and Fight", "÷ 8", "Each side adds its own leader’s share", "The default; computer lords always fight this way among themselves"],
    ["Bombard", "÷ 4", "Each side adds its own leader’s share", "Each side also adds random(catapults + 1)"],
    ["Outflank", "÷ 8", "Each side’s damage is <b>cut</b> by the <b>other</b> leader’s share", "Favours the better leader enormously"],
    ["Retreat!", "", "", "Ends the battle after the round: the army withdraws, morale −3"],
], [30, 20, 52, 72])
s.append(P("<b>The leader’s share</b> is leadership × damage ÷ 10: every point of leadership is 10% (the manual’s “50% for a strong leader” is wrong). "
           "Under Outflank a leadership of 10 cuts the enemy’s damage by 100%: he does only his random 0-2 a round."))
s += tip("<b>Small armies fight with luck alone.</b> With fewer than 32 soldiers and fewer than 4 knights (Ferocious) or 8 (Stand, Outflank) an army deals "
         "nothing but its random 0-2 a round, and the leader’s share of 0 is 0. Early battles are therefore won by the side with more men to lose, and every "
         "soldier (1 gold) is as good as a knight (8 gold). Knights pay once you have 4 or more of them: in Ferocious Attack every 4 knights add a sure point "
         "a round.")
s += tip("<b>Outflank when you lead better.</b> Cedric (10) against Reginald (5): Cedric’s damage is cut by half (Reginald’s 5), Reginald’s by all of it "
         "(Cedric’s 10), so Reginald deals only his random 0-2 a round. Against a better leader Outflank hurts you: use Stand and Fight or Ferocious Attack.")
s.append(P("A battle won is morale +3, lost or retreated −3. Morale only chooses your portrait on the status screen."))

# ---------------------------------------------------------------- conquest
s.append(P("Conquest", h1))
s += B(["Send forth your campaign army to a neighbouring territory. Your own land costs nothing to cross; the move ends at the first territory that "
        "isn’t yours. Unowned land is captured if its vassals are beaten (or at once if it has none).",
        "<b>Safe passage:</b> entering the land of another Saxon whose enmity to you is 0 or less, he offers safe passage. Accept and you pass; "
        "attack and both other Saxons’ enmity rises by 5.",
        "Any battle between two lords raises their enmity by 6, both ways.",
        "Taking a lord’s <b>home</b> castle gives you all his territories and ends him."])
s.append(P("Robin of Locksley", h2))
s.append(P("Choose Sherwood Forest (in Send forth, or as the castle to raid) to ask Robin’s help, <b>three times a game</b>. For an attack, his men are "
           "1.5 × the defenders’ soldiers less your soldiers (at least 2, at most 50), added to your army for the attack. <b>Afterwards only half of them "
           "leave: the other half stay in your army.</b> And if your army is left with fewer than 5 soldiers it is given 5, even if it was wiped out (a quirk)."))
s += tip("Robin gives more the fewer soldiers you bring, so lead knights against a strong garrison with Robin’s help: up to 50 of his men fight for "
         "you and 25 of them stay. Three pledges can recruit 75 free soldiers.")

# ---------------------------------------------------------------- sieges
s.append(P("Sieges", h1))
s.append(P("Every attack on a castle is a siege, and needs a catapult in your campaign army (otherwise you must retreat). You have <b>6 days</b>, one shot a "
           "day, with 6 boulders, 2 Greek Fire and 1 Disease; then the battle. <b>The castle’s wall cuts your damage in that battle by 90%</b>, and each boulder "
           "that hits takes 15 off that: after six hits your men fight at full strength."))
s += table(["Ammunition", "Hits when", "Effect"], [
    ["Boulders (6)", "The shot’s height equals the wall’s height", "The wall is one lower; your damage in the battle +15 points of 100"],
    ["Disease (1)", "The shot goes over the wall (higher than it)", "The garrison loses soldiers × days left ÷ 15 (33% on day 2, 7% on the last day)"],
    ["Greek Fire (2)", "Over the wall", "The garrison loses 1/6 to 1/30 of its soldiers"],
], [28, 60, 86])
s.append(P("<b>Aiming.</b> Enter starts pulling the arm back, Enter again lets go. The shot’s height is 1 to 6 (0 and 7 miss). The wall starts at height 6, "
           "the highest shot that lands, so <b>nothing gets over it until a boulder has knocked it lower</b>. The height rises one for every two steps of the pull: "
           "height <i>h</i> needs a release at step 4 + 2<i>h</i> or 5 + 2<i>h</i>, so the first boulder (height 6) needs steps 16-17. At the remake’s default "
           "(<font face='Mono'>catapult_pull = 2</font>, a step every two refreshes) that is a little over half a second after the first Enter; each lower wall comes "
           "1/15 of a second sooner."))
s += tip("Your damage is only 10% behind a whole wall, so boulders win sieges. A good plan: a boulder on day 1; Disease on day 2 over the lowered wall (a third "
         "of the garrison); boulders after that. Greek Fire is worth a shot only when a boulder would miss anyway. Cease Fire goes straight to the battle.")
s.append(P("When a computer lord besieges <i>your</i> castle, it protects you by 45, 30 or 15% and the siege kills 1/2 to 1/8 of your garrison’s soldiers before "
           "the battle. Your campaign army, if it is there, joins the defence; at home there is no retreat."))

# ---------------------------------------------------------------- raids
s.append(P("Raids", h1))
s.append(P("Go Raiding chooses another lord’s home castle. His enmity to you rises by 1. You fight with a strength of your <b>swordplay × 4</b> "
           "(50 with Robin’s help): first the guards (strength 20), then, with whatever strength you have left, the lord himself (his swordplay × 4). "
           "Each hit costs one point."))
s.append(KeepTogether(table(["Outcome", "Result"], [
    ["Success", "Half of the lord’s gold is yours; leadership +1. (With a kidnapped lady there, the rescue instead.)"],
    ["Captured (your strength runs out)", "Half of <b>your</b> gold goes to him as ransom; leadership −1"],
    ["Retreat (back out past the left edge)", "<b>Leadership falls to 0</b>; morale −2"],
], [56, 118])))
s.append(P("<b>The sword fight.</b> Enter thrusts; Up raises your sword, Down parries; Left and Right step (7/1 and 9/3 step with the sword raised or parrying). "
           "A thrust hits when you are close (less than 7 apart) and he isn’t parrying. He acts every other frame: from further than 6 he steps in, "
           "from closer than 6 he steps back parrying, at 6 he attacks or parries. His attack takes two turns, the sword raised, then the blow: "
           "<b>when you see it raised, thrust</b> (he isn’t parrying), or parry before it falls."))
s += tip("Never back out of a raid: losing all your leadership costs every battle you fight afterwards. Being captured is cheaper unless you are rich. "
         "Count the strength you need: the guards (20) plus the lord (up to 40 for Reginald) is more than Cedric (12) or even Wilfred (24) can survive "
         "without Robin.")

# ---------------------------------------------------------------- tournaments
s.append(P("Tournaments", h1))
s += B(["Holding one costs the holder 5 gold, and every lord’s enmity towards the holder <b>falls by 1</b>. Not allowed in the month of the last "
        "tournament or the month after, nor after you have been banned.",
        "You joust up to three rounds, until you lose one. For <b>Fame</b> you choose the opponent; win and your leadership rises by 1, lose and it falls "
        "by 1. For <b>Land</b> (only if both of you own land without a castle) you choose the territory: win it, or lose your highest-numbered "
        "castle-less territory.",
        "Hit the horse and you are disgraced: banned from tournaments for good, and stripped of every territory but your home."])
s.append(P("The joust", h2))
s.append(P("The lance’s point starts at x 40, y 125 (x 20-50, y 120-180). Each lance step the keypad moves it (7/8/9 up-left, up, up-right by 2 across and 4 up; "
           "4/6 by 2 across; 1/2/3 down), and the gallop bobs it 2 a step, turning every 6 steps. At the meeting:"))
s += B(["<b>A hit</b> unhorses him: the point at x exactly <b>26</b> (25-27 if your jousting is higher than his) and y within <b>138 ± (your jousting + 2 − his)</b>, "
        "at least ±1.",
        "<b>The horse</b> (disgrace): x below 30 and y above 170, the point low and to the left (y grows downwards).",
        "<b>Otherwise</b> you are unhorsed if a random number below his jousting is 2 or more; else “A Near Miss” and you go again. The fourth pass is "
        "always a loss."])
s += tip("x moves in steps of 2 from 40, so <b>press left exactly seven times</b> (4, or 7 and 1 diagonals) and leave it. Then keep the point level with "
         "the cross in his shield against the bob, staying well above the bottom: x 26 is inside the horse’s area if y goes over 170. "
         "Joust against weaker jousters: against a lord 3 or more better than you the EGA program can never unhorse him (a quirk: "
         "<font face='Mono'>--fix=joust-margin</font>; the DOS rules don’t have it). Another quirk judges the joust with the wrong lord’s rating "
         "(<font face='Mono'>--fix=joust-opponent</font>): in the first months often your own.")
s += tip("<b>Tournaments and enmity.</b> Each one lowers the enmity between the holder and every lord by 1. A lord never attacks a lord he has "
         "<b>exactly 0</b> enmity with, but in the booter a negative enmity counts as an enemy again (the DOS version treats 0 or less as peace). "
         "So your first tournament takes the other two Saxons from 0 to −1, which lets them attack you, while the Normans (5) need five to reach 0.")

# ---------------------------------------------------------------- AI
s.append(P("The computer lords", h1))
s.append(P("Each turn a lord collects his income, may leave some soldiers in the garrison where his army stands, and chooses:"))
s += B(["army away from home: 1 in 4, it goes home;",
        "otherwise 1 in 4 (unless he bought last time), he buys: a catapult if he has none (if he can’t afford one, nothing at all), then men with "
        "part of his gold (half on knights), then castles in his richest castle-less lands; and 80% of the garrison’s men join his army;",
        "otherwise 7 in 8, conquest if he finds a target (else buy or pass); 1 in 8, a Norman raids a Saxon and a Saxon holds a tournament.",
        "Targets: unowned land first (the nearest), then lands of lords whose enmity towards him isn’t 0, valued by his strength (4 × knights + soldiers) less the "
        "defenders’ plus enmity; castles only with a catapult. He searches up to 4 territories through his own land."])
s += tip("<b>The suicidal Saxons</b> (a quirk): the targets are compared unsigned, so a hopeless attack beats every sensible one, and in the first months the other "
         "Saxons throw their armies at Norman land and lose them. That leaves the north to you. The DOS version and <font face='Mono'>--fix=targets</font> "
         "make them sensible.")
s.append(P("<b>Norman raids.</b> A Norman raid takes half the gold of a Saxon picked at random, without a fight; after 10 months, if that Saxon keeps a "
           "lady and you have none, he kidnaps her instead."))
s.append(P("<b>The other Saxons turn on you</b> (a quirk): while Buckingham belongs to a Saxon, or Norfolk to you, both other Saxons’ enmity to you rises by 2 "
           "after <b>every</b> lord’s turn (up to 10). Cornwall’s fall alone changes nothing (the code checks Buckingham twice). "
           "<font face='Mono'>--fix=hostility</font> counts all three castles."))
s += tip("Take Cornwall (through Dorset) and the southern lands before Buckingham or Norfolk. Once you hold Buckingham, expect the other Saxons to come for you "
         "within a month or two; have your castles and garrisons ready.")

# ---------------------------------------------------------------- events, ladies
s.append(P("Events", h1))
s.append(P("Every 5 to 12 months one of these (or nothing, 2 times in 10):"))
s += table(["Event", "Effect"], [
    ["Viking raid", "A third of the soldiers of <b>Cumbria’s</b> garrison are lost, whoever you are (a quirk: it means your home; "
     "<font face='Mono'>--fix=viking</font>)"],
    ["Danes invade; Norman plotters", "You lose your highest-numbered territory other than your home"],
    ["Sheriff ambushed", "Half of this month’s income is lost"],
    ["Catapult sabotaged", "Your campaign army loses a catapult"],
    ["Robin raids a Norman stronghold", "Every Saxon gets 25 gold"],
    ["Three knights from Germany", "Your campaign army gains 3 knights"],
    ["Norman vassals revolt", "The first Norman with land besides his home gives you his highest-numbered territory"],
], [52, 122])
s.append(P("The ladies", h1))
s.append(P("Two ladies live as wards of the other two Saxons. When a Norman kidnaps one, you are offered the rescue: <b>accepting raises your leadership by 2 "
           "whatever happens</b> (refusing lowers it by 2), and the rescue is a raid on the kidnapper’s castle. Succeed and the lady is yours, "
           "<b>with all her ward’s territories</b>, and no lady will be kidnapped again."))
s += tip("Always accept a rescue: +2 leadership even if you fail, and success hands you a whole Saxon realm.")

# ---------------------------------------------------------------- summary
s.append(P("A plan for a first game", h1))
s += B(["Read Map: note the Normans’ jousting and swordplay, and which neighbours are unowned.",
        "Month 1: move most of your home garrison into the campaign army (keep a few at home) and take the weakest unowned neighbour; take more each month.",
        "Buy soldiers while armies are small; add knights once you can field 4 or more; buy a catapult before you reach a castle.",
        "Joust for Fame against weaker jousters when the other Saxons hold tournaments (you attend for free); think twice before holding your own (enmity, above).",
        "Use Robin’s three pledges on big attacks with few soldiers of your own; keep one for a raid if you are a swordsman.",
        "Build castles on the borders facing the Normans. Take the south and Cornwall before Buckingham and Norfolk.",
        "Raid only with strength to spare; never back out of one."])

out = sys.argv[1] if len(sys.argv) > 1 else "DOTC_PC_Strategy_Guide.pdf"
doc = BaseDocTemplate(out, pagesize=A4, leftMargin=18 * mm, rightMargin=18 * mm, topMargin=18 * mm, bottomMargin=20 * mm,
                      title="Defender of the Crown (PC) — Strategy Guide", subject="How the PC game works, from its code",
                      author="Brett Hallen")
doc.addPageTemplates([PageTemplate(id="p", frames=[Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="f")], onPage=footer)])
doc.build(s)
print("wrote", out)
