#!/usr/bin/env python3
"""Writes DOTC_Remake_Quick_Reference.pdf (needs reportlab and the DejaVu fonts):
    python3 tools/make_quick_reference.py [OUT.pdf]
The same layout as The Ancient Art of War remake's quick reference."""
import sys, os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Table,
                                TableStyle, Preformatted, KeepTogether)
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
CODE_BG = colors.HexColor("#F3F4F6")
HEAD_BG = colors.HexColor("#F6F1EA")
RULE = colors.HexColor("#D9CBB8")

body = ParagraphStyle("body", fontName="Sans", fontSize=8.6, leading=12, textColor=INK, spaceAfter=5)
small = ParagraphStyle("small", parent=body, fontSize=7.8, leading=10.5)
cell = ParagraphStyle("cell", parent=body, fontSize=8, leading=10.8, spaceAfter=0)
cellb = ParagraphStyle("cellb", parent=cell, fontName="Sans-Bold")
title = ParagraphStyle("title", fontName="Sans-Bold", fontSize=20, leading=25, textColor=ACCENT, spaceBefore=4, spaceAfter=2)
subtitle = ParagraphStyle("subtitle", fontName="Sans", fontSize=9.5, leading=13, textColor=GREY, spaceAfter=4)
h1 = ParagraphStyle("h1", fontName="Sans-Bold", fontSize=12.5, leading=16, textColor=ACCENT, spaceBefore=9, spaceAfter=5, keepWithNext=1)
h2 = ParagraphStyle("h2", fontName="Sans-Bold", fontSize=9, leading=12, textColor=INK, spaceBefore=4, spaceAfter=3, keepWithNext=1)
code = ParagraphStyle("code", fontName="Mono", fontSize=7.6, leading=10, textColor=INK)

def c(t): return '<font face="Mono">%s</font>' % t
def P(t, st=body): return Paragraph(t, st)

def codeblock(text):
    t = Table([[Preformatted(text, code)]], colWidths=[174 * mm])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), CODE_BG),
                           ("LEFTPADDING", (0, 0), (-1, -1), 6), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                           ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]))
    return [t, Spacer(1, 5)]

def table(head, rows, widths, mono_first=False, plain=False):
    data = []
    if head: data.append([P(h, cellb) for h in head])
    for r in rows:
        data.append([P(c(x) if (mono_first and i == 0) else x, cell) for i, x in enumerate(r)])
    t = Table(data, colWidths=[w * mm for w in widths], repeatRows=1 if head else 0)
    st = [("VALIGN", (0, 0), (-1, -1), "TOP"),
          ("LINEBELOW", (0, 0), (-1, -1), 0.5, RULE),
          ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
          ("LEFTPADDING", (0, 0), (-1, -1), 5)]
    if head: st += [("BACKGROUND", (0, 0), (-1, 0), HEAD_BG), ("LINEBELOW", (0, 0), (-1, 0), 0.8, RULE)]
    else: st += [("LINEABOVE", (0, 0), (-1, 0), 0.5, RULE)]
    t.setStyle(TableStyle(st))
    return [t, Spacer(1, 6)]

def footer(canv, doc):
    canv.saveState()
    canv.setStrokeColor(INK)
    canv.setLineWidth(0.6)
    canv.line(18 * mm, A4[1] - 14 * mm, A4[0] - 18 * mm, A4[1] - 14 * mm)
    canv.setFont("Sans", 7)
    canv.setFillColor(GREY)
    canv.drawString(18 * mm, 12 * mm, "Defender of the Crown (1986) remake — Quick Reference")
    canv.drawRightString(A4[0] - 18 * mm, 12 * mm, "Page %d" % doc.page)
    canv.restoreState()

APP = "build/DefenderOfTheCrown.app/Contents/MacOS/DefenderOfTheCrown"
s = []
s.append(P("Defender of the Crown — Remake", title))
s.append(P("Quick Reference Guide: building, running, settings and command-line options", subtitle))
s.append(P("The remake is written in C with SDL3 and built with CMake. It runs on macOS, and also builds on Windows "
           "and Linux. It is a port of the booter version’s EGA program, and shows the game as each PC version did: "
           "the 1987 DOS version’s CGA, the booter’s CGA, EGA and Tandy 1000. No original game files are included: "
           "the remake loads its pictures, sprites, music and data from <b>your own copy</b> of the original game at run time."))

s.append(P("What you need", h1))
s += table(None, [
    ["Tools", "CMake 3.16 or later, a C11 compiler (Clang, GCC or MSVC) and SDL3. On macOS: " + c("brew install cmake sdl3") +
     ' (<font color="#8A3B12">Homebrew</font>).'],
    ["Game files", c("GAME.DAT") + " from the booter version (the CGA, EGA and Tandy modes, the music and the game’s data). "
     "For the CGA (1987) mode, add the 1987 DOS version’s " + c("DOC.EXE") + ", " + c("TITLE.LIB") + ", " + c("RAID.LIB") + ", " +
     c("JOUST1.LIB") + ", " + c("JOUST2.LIB") + ", " + c("DOCCHARS.LIB") + ", " + c("SIEGE.LIB") + ", " + c("LOVE1.LIB") + " and " +
     c("LOVE2.LIB") + ". They can be in one folder, or in its " + c("ega/") + " and " + c("cga/") + " subfolders (as in the "
     "repository’s " + c("Original/") + "). Upper or lower case doesn’t matter."],
], [30, 144])

s.append(P("Compiling", h1))
s.append(P("macOS", h2))
s += codeblock("cd Remake\ncmake -S . -B build -DCMAKE_BUILD_TYPE=Release\ncmake --build build")
s.append(P("This makes " + c("build/DefenderOfTheCrown.app") + ". The app icon (the title picture on the stone wall) is drawn during "
           "the build from your game files, found in " + c("../Original") + ". If they are elsewhere, add " +
           c("-DDOTC_GAME_DIR=/path/to/your/game") + " to the first cmake command. Without them the app still builds; it just has no "
           "icon in Finder. If Finder shows an old icon, run " + c("touch build/DefenderOfTheCrown.app") + "."))
s.append(P("Windows and Linux", h2))
s.append(P("The same two cmake commands, with SDL3 installed where CMake can find it (if it can’t, add " +
           c("-DCMAKE_PREFIX_PATH=/path/to/SDL3") + "). With Visual Studio, build with " + c("cmake --build build --config Release") +
           ". The result is the " + c("DefenderOfTheCrown") + " program in " + c("build") + " (in " + c("build/Release") + " for Visual Studio)."))
s.append(P("Tests (optional)", h2))
s.append(P("The test programs are in " + c("Remake/test") + ". Build one with " + c("./build.sh NAME") + " (with AddressSanitizer and "
           "UBSan; " + c("SDL3_DIR=/path") + " if SDL3 isn’t found) and run it without a window by setting " +
           c("SDL_AUDIODRIVER=dummy") + ". The remake’s README lists each one and its arguments."))

s.append(P("Running", h1))
s += codeblock("open build/DefenderOfTheCrown.app                 # macOS, from Finder or the terminal\n" + APP + " ../Original")
s.append(P("The app looks for your game files in the folder given on the command line, then the one it remembers, then " +
           c("game/") + " or " + c("../Original") + " next to the app, then the current folder. If it finds none it asks for the "
           "folder (press <b>O</b> to choose it again) and remembers it in the settings file. Command-line options need the "
           "program inside the app bundle (" + c("…/Contents/MacOS/DefenderOfTheCrown") + ")."))

s.append(P("Command-line options", h1))
s += codeblock("DefenderOfTheCrown [--video=MODE] [--rules=booter|dos] [--fix=NAME,...|all]\n"
               "                   [--catapult-pull=N] [--sword-pace=N] [--log | --log=verbose | --log=off]\n"
               "                   [game-folder]")
s += table(["Option", "What it does"], [
    ["game-folder", "The folder with your original game files. Any argument that doesn’t start with - is taken as the folder."],
    ["--video=MODE", "The video mode to start in (EGA if not given). MODE is one of the names in the next table. Tab changes the mode while playing."],
    ["--rules=booter<br/>--rules=dos", "Whose rules and timing to play by: the booter version’s (the default), or the 1987 DOS version’s "
     "(DOC.EXE): its random numbers, the computer lords’ odds, its signed comparisons and its slower, clock-paced scenes. "
     "Works in any video mode."],
    ["--fix=NAME,...<br/>--fix=all", "Fix some of the original’s flaws (none by default: the game as it was). The names are in the <i>Fixes</i> table below."],
    ["--catapult-pull=N", "Screen refreshes for each step of the catapult’s arm as you draw it back, 1 to 8 (2 if not given). "
     "1 is the original on a fast PC: 0.4 seconds for a full pull."],
    ["--sword-pace=N", "Screen refreshes for each frame of the sword fight in a raid, 1 to 8 (3 if not given: 20 frames a second). "
     "1 is the original on a fast PC: 60 frames a second."],
    ["--log<br/>--log=verbose<br/>--log=off", "Write a log of each game played: the settings, the setup, your orders, the computer lords’ "
     "decisions (with the random draws behind them), battles, jousts, raids and events. Verbose adds every territory weighed and every hit."],
], [42, 132], mono_first=True)

s.append(P("Video modes (--video=MODE)", h1))
s += table(["MODE", "Mode", "What you see"], [
    ["cga1", "CGA (1987)", "The 1987 DOS version (DOC.EXE): its pictures, font, boxes, map and sprites, in the CGA’s green, red and brown *"],
    ["cga2", "CGA", "The booter’s CGA program: its own redrawn CGA pictures and sprites"],
    ["ega", "EGA (default)", "The booter’s EGA program, 16 colours"],
    ["tandy", "Tandy 1000", "The booter’s Tandy program, 16 colours, with the Tandy’s three-voice music"],
], [22, 30, 122], mono_first=True)
s.append(P("* Needs the 1987 version’s files (above). Tab goes through the modes in the order of this table. "
           "The video mode only changes the look and the sound; the rules are set with " + c("--rules") + ".", small))

s.append(P("The settings file", h1))
s.append(P("Every option can also be set in " + c("DefenderOfTheCrown.ini") + ", so you don’t have to give it each time. The remake "
           "writes it with the defaults and a comment for each setting the first time it starts, and adds any settings introduced "
           "by a later version. An option on the command line wins for that run only; delete the file to get the defaults back."))
s += table(["Section", "Setting", "Command line", "Values (default)"], [
    ["[game]", c("folder"), "the folder argument", "your game files’ folder (empty: look for it, else ask)"],
    ["[display]", c("video"), c("--video="), c("cga1") + ", " + c("cga2") + ", " + c("ega") + " or " + c("tandy") + " (" + c("ega") + ")"],
    ["[play]", c("rules"), c("--rules="), c("booter") + " or " + c("dos") + " (" + c("booter") + ")"],
    ["[play]", c("fix"), c("--fix="), "flaw names separated by commas, or " + c("all") + " (empty: none)"],
    ["[play]", c("catapult_pull"), c("--catapult-pull="), "1 to 8 (2)"],
    ["[play]", c("sword_pace"), c("--sword-pace="), "1 to 8 (3)"],
    ["[debug]", c("log"), c("--log"), c("off") + ", " + c("normal") + " or " + c("verbose") + " (" + c("off") + ")"],
], [22, 30, 38, 84], mono_first=True)

s.append(P("Examples", h1))
s += codeblock("APP=" + APP + "   # macOS\n"
               "$APP --video=cga1                      # start in the 1987 DOS version's CGA\n"
               "$APP --rules=dos --video=cga1          # the 1987 DOS version, rules and all\n"
               "$APP --fix=all                         # the original's flaws fixed\n"
               "$APP --sword-pace=4 --catapult-pull=3  # slower sword fights and catapult\n"
               "$APP --log=verbose ~/Games/DotC        # a detailed log; game files in ~/Games/DotC")

s.append(P("Keys that work everywhere", h1))
s += table(["Key", "Action"], [
    ["Tab", "Next video mode: CGA (1987), CGA, EGA, Tandy"],
    ["F2", "The original monitor’s 4:3 shape, or square pixels"],
    ["⌘Enter or Alt+Enter", "Full screen"],
    ["⌘Q", "Quit"],
    ["Enter (the opening)", "Skip to the choice of character; in Sherwood, skip to the game"],
    ["O (no game files found)", "Choose the folder with your game files"],
], [48, 126])

s.append(P("Playing", h1))
s.append(P("The original’s keys: the arrows or the keypad, and Enter (keypad + and F1 are Enter too). Without a keypad, "
           "Home, Page Up, End and Page Down (fn + the arrows on a Mac laptop) are the keypad’s 7, 9, 1 and 3."))
s += table(["Where", "Keys"], [
    ["Menus", "Up and Down choose, Enter selects. Buying: Right buys one, Left sells back one bought this time."],
    ["The map", "The keypad or the arrows move between territories; Enter chooses."],
    ["Siege (catapult)", "Choose the ammunition, then Enter to start drawing the arm back and Enter again to let go: the longer the pull, the higher the shot."],
    ["Sword fight (raid)", "Enter thrusts; 8 (Up) raises the sword, 2 (Down) parries; 4/6 (Left/Right) step back or forward; "
     "7/1 and 9/3 step with the sword raised or parrying. Parry when the enemy raises his sword."],
    ["Joust", "A key starts each pass. Aim the lance’s point at the opponent’s shield: 7/8/9 up, 1/2/3 down, 4/6 sideways (the gallop bobs it)."],
], [36, 138])

s.append(P("Fixes (--fix=NAME)", h1))
s += table(["Name", "The original", "Fixed"], [
    ["viking", "The Viking raid strikes the garrison of the territory with your side’s number", "Your home’s garrison"],
    ["hostility", "The check that turns the other Saxons against you counts Buckingham twice and never Cornwall", "Norfolk, Buckingham and Cornwall"],
    ["targets", "The computer lords compare targets unsigned, so a hopeless attack beats every sensible one", "Compared signed"],
    ["catapult", "A buying lord looks for a catapult in the wrong garrison, and may buy one he has", "His home’s garrison"],
    ["siege-merge", "A defending army stays merged into the garrison after a siege refused for want of a catapult", "Merged only when the siege goes ahead"],
    ["joust-opponent", "The joust is judged by the wrong lord’s jousting", "The opponent’s"],
    ["joust-margin", "In the EGA program you can never unhorse an opponent jousting 3 or more above you", "At least 1 line either side, as CGA and Tandy"],
    ["battle-text", "“Saxon blood taints the green fields of …” names the wrong territory", "The territory attacked"],
    ["siege-sprite", "The catapult can flicker over the battle’s first frames after a siege", "Cleared before the battle"],
], [28, 92, 54], mono_first=True)

s.append(P("Where the remake keeps its files", h1))
s.append(P("macOS: " + c("~/Library/Application Support/DefenderOfTheCrown/Remake/") + " (on Windows and Linux, SDL’s per-user data "
           "folder for the app)."))
s += table(["File or folder", "Contents"], [
    ["DefenderOfTheCrown.ini", "The settings (above), including the game folder you chose"],
    ["Logs/", "The " + c("--log") + " files, one per game, named by the date, time and the lord you chose"],
], [48, 126], mono_first=True)
s.append(P("The game itself has no saved games, as in the original. Full details: the remake’s " + c("README.md") + "; the game’s "
           "rules as read from the code: " + c("Analysis/GAME_LOGIC.md") + "; the two versions compared: " + c("Analysis/DOC_vs_AB.md") + ".", small))

out = sys.argv[1] if len(sys.argv) > 1 else "DOTC_Remake_Quick_Reference.pdf"
doc = BaseDocTemplate(out, pagesize=A4, leftMargin=18 * mm, rightMargin=18 * mm, topMargin=18 * mm, bottomMargin=20 * mm,
                      title="Defender of the Crown Remake — Quick Reference",
                      subject="Building, running, settings and command-line options", author="Brett Hallen")
doc.addPageTemplates([PageTemplate(id="p", frames=[Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="f")], onPage=footer)])
doc.build(s)
print("wrote", out)
