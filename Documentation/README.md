# Documentation

Scans of the original printed documentation. No scan of the IBM PC's own reference card (loading and controls) has been found; the booklet was the same for every version.

| File | What it is |
|---|---|
| `Defender_of_the_Crown_Manual_C64.pdf` | The manual (Master Designer Software, 1986: the story, the map, army building, conquest, tournaments, raiding, the historical essays, Designer's Notes, Questions & Answers), with the Commodore 64 reference card (1987) at the end. 14 pages, scanned images without a text layer. From the Internet Archive (`Defender_of_the_Crown_1987_Cinemaware`) |
| `Defender_of_the_Crown_Reference_Card_Apple.pdf` | The Apple IIGS reference card (Cinemaware, 1988), with its own Questions & Answers and hard disk notes. 5 pages. From the Internet Archive (`Defender_of_the_Crown_Reference_Card`) |

What they say, checked against the PC game's code: `../Analysis/MANUAL_vs_CODE.md`.

`DOTC_PC_Strategy_Guide.pdf` is a strategy guide for the PC version written from its code rather than the manual: winning and losing, the lords and the land (with the game's map, its territories numbered; the script needs Pillow and `../Graphics/Booter_EGA/CK.png`), gold, battles (the damage formula and the tactics), conquest and Robin, sieges and aiming the catapult, raids and the sword fight, tournaments and the joust, the computer lords, events and the ladies, with the original's quirks. `python3 ../Analysis/tools/make_strategy_guide.py DOTC_PC_Strategy_Guide.pdf` writes it again.
