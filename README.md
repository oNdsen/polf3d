<h1 align="center">POLF 3D &nbsp;<code>&gt;_</code></h1>

<p align="center"><b>A 90s-style ray casting shooter – written in PowerShell.</b><br>
<i>Five floors, eight kinds of enemies, six weapons, procedurally generated graphics and sound –<br>
and roughly 50 lines of C#.</i></p>

<p align="center"><img src="media/warmachine.png" alt="Pipeline Cannon versus the war machine" width="720"></p>

```powershell
git clone https://github.com/oNdsen/polf3d.git
cd polf3d
./Start-Polf3D.ps1
```

Requirements: **Windows** and **PowerShell 7.2+**. Nothing else – no modules, no asset files, no installation.
On first start the ~50 lines of C# ([src/Scaler.cs](src/Scaler.cs)) are compiled once into `bin/`.

---

## Contents

- [What is this?](#what-is-this)
- [Screenshots](#screenshots)
- [Controls](#controls)
- [The campaign](#the-campaign)
- [Enemies, weapons, items](#enemies-weapons-items)
- [Cheats](#cheats)
- [Command line](#command-line)
- [How it works](#how-it-works)
- [Building your own levels](#building-your-own-levels)
- [Tests](#tests)
- [Origin and scope](#origin-and-scope)
- [License](#license)

## What is this?

POLF 3D is a complete first-person shooter with a textured ray caster, sliding doors, keys, secret push-walls,
enemy AI, bosses, saved games and a high score list – and almost all of it is **plain PowerShell**:
game logic, AI, ray casting, map format, HUD, menus.

* **No asset files.** All wall textures, about 250 sprite images and 40 sound effects are generated procedurally at
  start-up in a little over two seconds (GDI+ primitives and a tiny square/saw/noise synthesiser).
* **As little C# as possible:** exactly two pixel loops (scale one wall strip, draw one sprite).
  PowerShell cannot push 64,000 pixels per frame – but it handles the 320 rays per frame with ease.
* **50–60 fps** in a 960×720 window on an ordinary office laptop.

## Screenshots

| | |
|---|---|
| ![Title screen](media/title.png) | ![The hub hall on floor 1](media/hub.png) |
| Title screen with difficulty levels and high scores | Floor 1: the hub hall – patrols, banners with the `>_` coat of arms |
| ![Fire fight](media/firefight.png) | ![Kennels](media/kennels.png) |
| A guard takes aim (seen through the door frame) | The kennels |
| ![Catacombs](media/catacombs.png) | ![Lab Zero](media/lab.png) |
| Floor 3: mutants between the pillars of the catacombs | Floor 4: an elite patrol in the ring corridor of Lab Zero |
| ![Citadel](media/citadel.png) | ![Automap](media/automap.png) |
| Floor 5: the great hall of the citadel | Automap (hold `M`) – shows only what you have already seen |

<p align="center"><img src="media/cast.png" alt="The cast" width="900"></p>

## Controls

| Key | Action |
|---|---|
| `W` / `S`, arrow up/down | forward / back |
| arrow left/right | turn |
| `A` / `D` | strafe |
| `Shift` | run (enemies find you harder to hit) |
| `Ctrl`, left mouse button | fire |
| `Space`, `E`, right mouse button | door, lift switch, secret wall |
| `1`–`4` | knife, pistol, machine gun, chain gun |
| `5` / `6` | Pipeline Cannon / Force Blaster (find them first!) |
| `M` (hold) | automap |
| `F2` | mouse look on/off |
| `F3` | fps display |
| `F5` / `F9` | quick save / quick load (`saves/quicksave.json`); on the title screen `L` loads |
| `P`, `Esc` | pause |

## The campaign

Five floors that keep getting harder. The lift takes you to the next one; you keep your weapons, ammunition and
health, but not your keys. If you die you restart the floor with a pistol and 8 rounds. Every floor ends with a tally
(kills, secrets, treasures, a bonus for beating the par time).

| # | Floor | Enemies / total HP | Character |
|---|---|---|---|
| 1 | Shellstein Dungeon | 30 / ~2300 | A gentle start: guards, dogs, the first elites and mutants, generous secret rooms, a commander at the end |
| 2 | The Barracks | 33 / ~2450 | A long corridor with counter-rotating patrols, dormitories (some of them really are asleep), a mess hall full of guards |
| 3 | The Catacombs | 33 / ~2700 | Caves without doors – noise carries far. Dogs in the dark, mutants lying in ambush behind every pillar |
| 4 | Lab Zero | 31 / ~4600 | A ring corridor with elite patrols around the reactor hall, a commander in the server room, **the first war machine** |
| 5 | The Citadel | 30 / ~5150 | The finale: a great hall with three patrols, two commanders, and a throne hall with a war machine and its escort |

Four difficulty levels – *Intern (-WhatIf)*, *Sysadmin*, *Senior Engineer* and *root (-Force -Confirm:$false)* –
scale the damage you take (×0.25 to ×1.3) and the bosses' hit points.

## Enemies, weapons, items

**Enemies**

| Enemy | HP | Trait |
|---|---|---|
| Guard | 25 | the standard opponent, one shot per attack |
| Dog | 1 | fast, cannot open doors, leaps at you |
| Officer | 50 | reacts almost instantly and aims very briefly |
| Elite | 100 | four-round bursts, better aim, drops a machine gun |
| Mutant | 45–65 | never shouts an alarm, two shots per attack – loves an ambush |
| Commander | 850–1200 | boss with twin machine guns, drops the gold key |
| War machine | 1100–1800 | super boss: gun bursts and salvos of three rockets (real projectiles with splash damage – pillars give cover) |
| Pilot | 250–500 | phase 2: climbs out of the war machine's wreck – few hit points, but very fast |

The AI works on the tile grid: enemies patrol along waypoints, open doors, chase you in a zig-zag and have a reaction
time. **Stealth pays off:** anyone who has not noticed you yet takes double damage, and gunfire only alerts rooms that
are connected to yours through a door that is open at that moment. The knife is silent.

**Weapons**

| # | Weapon | |
|---|---|---|
| 1 | Knife | silent, costs nothing |
| 2 | Pistol | one shot per key press |
| 3 | Machine gun | automatic fire |
| 4 | Chain gun | automatic fire at twice the rate |
| 5 | **Pipeline Cannon** | "`\|` passes everything along": the beam pierces **every** enemy in the line of fire (4 rounds per beam) |
| 6 | **Force Blaster** | `Remove-Item -Recurse -Force` for your whole field of view – fed by rare Force charges |

All guns share one kind of ammunition (99 rounds at most). When it runs out you automatically draw the knife.

**Items:** dog food (+4), food (+10), first aid kit (+25), clips, gold and silver keys, treasures
(coins 100, goblet 500, chest 1000, crown 5000 points), extra lives, Force charges and the **SUDO** power-up
(20 seconds of double damage dealt and half damage taken). Every 40,000 points earn an extra life.

## Cheats

| Key | Code word (type it while playing) | Parameter | Effect |
|---|---|---|---|
| `F6` | `GIVEALL` | `-AllWeapons` | all weapons, 99 rounds, Force charges, both keys, full health |
| `F7` | `NOLIMIT` | `-InfiniteAmmo` | shooting costs nothing (Pipeline Cannon and Force Blaster included) |
| `F8` | `ROOT` | `-GodMode` | no damage |
| `F11` | `ONEHIT` | `-OneHitKill` | every hit kills – **the enemies and you** (unless god mode is on) |

`F7`, `F8` and `F11` are toggles; active cheats are shown at the bottom left of the view. Cheaters get a "(cheat)" tag
in the high score list.

## Command line

```powershell
./Start-Polf3D.ps1 -Scale 4        # window size: 2..5 times 320x240 (default 3)
./Start-Polf3D.ps1 -Columns 160    # half the number of rays, for slow machines
./Start-Polf3D.ps1 -Difficulty 4   # preselect the difficulty (1..4)
./Start-Polf3D.ps1 -Level 4        # start the campaign on floor 4
./Start-Polf3D.ps1 -Map ./maps/mine.map   # play just this one map
./Start-Polf3D.ps1 -NoSound        # skip sound synthesis (faster start)
```

## How it works

| File | Purpose |
|---|---|
| [Start-Polf3D.ps1](Start-Polf3D.ps1) | parameters, loading the modules, compiling the scaler (DLL cache in `bin/`), start |
| [src/Defs.ps1](src/Defs.ps1) | constants, the classes `Actor`/`Door`/`Static`, tables for enemies, states, weapons, items |
| [src/Assets.Gfx.ps1](src/Assets.Gfx.ps1) | procedural textures and sprites |
| [src/Assets.Sfx.ps1](src/Assets.Sfx.ps1) | sound synthesis, playback on one channel with priorities |
| [src/Map.ps1](src/Map.ps1) | loads the text map, finds rooms ("areas") by flood fill, places things |
| [src/Doors.ps1](src/Doors.ps1) | doors, the area graph for sound and sight, push-walls |
| [src/Actors.ps1](src/Actors.ps1) | line of sight, perception, grid movement, think/action routines, rockets, damage |
| [src/Player.ps1](src/Player.ps1) | movement with wall sliding, use, weapons, items, cheats |
| [src/Render.ps1](src/Render.ps1) | ray caster, sprite projection, HUD, overlays, automap |
| [src/Game.ps1](src/Game.ps1) | window, input, game modes, main loop, screens |
| [src/SaveGame.ps1](src/SaveGame.ps1) | quick save/load as JSON, high score list |
| [src/Scaler.cs](src/Scaler.cs) | **the only C#**: scaling wall strips and sprites pixel by pixel |
| [src/SelfTest.ps1](src/SelfTest.ps1) | headless tests and the screenshots for this README |

A few details for the curious:

* **Time** runs in tics (1/70 s). Every movement and every counter is scaled by the tics that have passed since the
  last frame – the game plays at the same speed at 20 fps as at 60.
* **Ray caster:** one ray per screen column is walked through the tile grid (DDA). The wall height comes from the
  distance *along the view direction* (no fish-eye). Doors are thin leaves in the middle of their tile and slide
  sideways into the wall, neighbouring walls show a door frame, push-walls are a ray-against-box test. One of the
  two wall axes uses a darker copy of the texture – lighting for free. The distance is remembered per column so
  sprites disappear cleanly behind walls.
* **Enemies** are a data-driven state machine `{Sprite, Rot, Tics, Think, Action, Next}`: *Think* runs every frame,
  *Action* once when the state runs out. The chains (stand, patrol, chase, shoot, pain, die) are generated from a
  short definition per enemy type.
* **Sound propagation:** the map falls into areas (rooms between doors) automatically. Only areas connected to yours
  through currently open doors hear gunfire – and only there do enemies think at all. That is gameplay and
  optimisation in one.
* **Presentation:** `int[]` frame buffer → bitmap → `BufferedGraphics`. Its GDI blit is about six times faster than
  drawing a GDI+ bitmap straight to the window – the difference between 30 and 55 fps.
* **Approved verbs:** every function, including every internal helper, uses a verb from `Get-Verb`;
  [tools/Test-Verbs.ps1](tools/Test-Verbs.ps1) checks that via the AST.

## Building your own levels

Every `maps/level<N>.map` is a text file; the campaign simply consists of all of them in numerical order – a
`level6.map` automatically becomes floor 6. After a few header lines (`@name`, `@par`, `@ceiling`, `@floor`) the grid
follows `@map`, **every cell two characters wide**:

| Code | Meaning |
|---|---|
| `SS Sb Sp` `BB Bc` `WW Wp Ws` `RR Rb` `MM` | walls: stone, blue stone, wood, brick, steel (+ decorated variants) |
| `GG Gv` `TT Tl` | mossy rock (+ vines), tech panels (+ console) |
| `MX` | lift switch (the exit) |
| `?S ?s ?B ?b ?W ?w ?R ?r ?M ?G ?g ?T ?t` | secret push-wall (upper case plain, lower case decorated) |
| `DD DG DS DL` | door: normal / gold lock / silver lock / lift door – the orientation is detected from the neighbouring walls |
| `..` | floor |
| `P^ P> Pv P<` | player start and view direction |
| `g d e o m b u` + direction | guard, dog, elite, officer, mutant, commander, war machine |
| direction `^ > v <` / `n e s w` / `N E S W` | standing / standing and "deaf" (ambush, reacts to sight only) / patrolling |
| `:^ :> :v :<` | waypoint: patrols turn here |
| `+d +f +h` `+a` `+m +c +p +r +z` `+g +s` `+1 +2 +3 +4` `+u +q` | dog food, food, first aid · clip · machine gun, chain gun, Pipeline Cannon, Force Blaster, Force charge · keys · treasures · extra life, SUDO |
| `*l *h *L *t *b *p *a *c *f *x *v *s *u *k *B *m *g` | decoration: ceiling lamp, chandelier, floor lamp, table, barrel, plant, suit of armour, column, flag, crates, vat, bones, puddle, dead guard, bed, console, stalagmite |

The bundled maps are generated by [tools/New-Levels.ps1](tools/New-Levels.ps1) from room lists – rooms are rectangles
carved out of solid rock; where they touch they merge into corridors and caves. The game only ever reads the `.map`
files, though, so you can just as well edit them by hand. Validate and play:

```powershell
./tools/Test-Level.ps1 -Map ./maps/mine.map    # border closed? everything reachable? keys present? patrol routes clear?
./Start-Polf3D.ps1 -Map ./maps/mine.map
```

## Tests

```powershell
./Start-Polf3D.ps1 -SelfTest   # headless: renders PNGs into ./selftest; combat, cheat, dog, boss and savegame tests
                               # plus a soak test of every floor that also fights every boss
./tools/Test-Level.ps1         # validates all maps and prints an overview of each
./tools/Test-Verbs.ps1         # every function uses an approved verb
```

## Origin and scope

POLF 3D is **neither a clone nor a port**. The source code of the 1992 grandfather of the genre, later released by
id Software, was first analysed and described *in our own words* – how the code is structured and how levels, enemies,
weapons, items and doors work. Only from that description was the game written anew. What was adopted are concepts and
game mechanics; **nothing** of the original is contained in this repository: own code, own levels, own names, own
procedurally generated graphics and sounds – and the `>_` prompt as a coat of arms.

## License

Copyright © 2026 oNdsen. Released under the [MIT License](LICENSE) – code, maps and the procedurally generated
graphics and sounds. Use it, change it and pass it on, as long as the copyright notice stays in place.
