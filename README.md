<h1 align="center">POLF 3D &nbsp;<code>&gt;_</code></h1>

<p align="center"><b>A 90s-style ray casting shooter – written in PowerShell.</b><br>
<i>Five floors and a secret one, eleven kinds of enemies, nine weapons, co-op and duels over the network,<br>
procedurally generated graphics, sound and music – and about 150 lines of C#.</i></p>

<p align="center"><img src="media/banner.png" alt="POLF 3D - the war machine opens fire" width="900"></p>

```powershell
git clone https://github.com/oNdsen/polf3d.git
cd polf3d
./Start-Polf3D.ps1
```

Requirements: **Windows** and **PowerShell 7.2+**. Nothing else – no modules, no asset files, no installation.
On first start the two small C# files ([src/Scaler.cs](src/Scaler.cs), [src/Gamepad.cs](src/Gamepad.cs)) are compiled
once into `bin/`, and each piece of music is composed and cached there the first time it is needed.

---

## Contents

- [What is this?](#what-is-this)
- [Screenshots](#screenshots)
- [Controls](#controls)
- [The campaign](#the-campaign)
- [Enemies, weapons, items](#enemies-weapons-items)
- [Stealth](#stealth)
- [Level machinery](#level-machinery)
- [Two players: co-op and duel](#two-players-co-op-and-duel)
- [Saved games, demos, speedruns](#saved-games-demos-speedruns)
- [Music](#music)
- [Cheats](#cheats)
- [Command line](#command-line)
- [How it works](#how-it-works)
- [Building your own levels](#building-your-own-levels)
- [Tests](#tests)
- [Origin and scope](#origin-and-scope)
- [License](#license)

## What is this?

POLF 3D is a complete first-person shooter with a textured ray caster (walls, floors, ceilings, windows, distance fog),
sliding doors, keys, levers, traps, teleporters, secret push-walls, enemy AI, bosses, saved games, demos, a level
editor and a two-player network mode – and almost all of it is **plain PowerShell**: game logic, AI, ray casting,
map format, HUD, menus, music, network protocol.

* **No asset files.** All wall and floor textures, about 300 sprite images, 40 sound effects and the whole soundtrack
  are generated procedurally (GDI+ primitives, a tiny square/saw/noise synthesiser and a chiptune composer).
* **As little C# as possible:** the innermost pixel loops (scale one wall strip, draw one sprite, fill one floor row)
  and one P/Invoke declaration for the game pad. PowerShell cannot push 64,000 pixels per frame – but it handles the
  320 rays per frame with ease.
* **50–60 fps** in a 960×720 window on an ordinary office laptop.

## Screenshots

| | |
|---|---|
| ![Title screen](media/title.png) | ![The hub hall on floor 1](media/hub.png) |
| Title screen with difficulty levels and high scores | Floor 1: the hub hall – patrols, banners with the `>_` coat of arms |
| ![Fire fight](media/firefight.png) | ![Co-op](media/coop.png) |
| A guard takes aim (seen through the door frame) | Co-op over the network: your partner runs ahead |
| ![Catacombs](media/catacombs.png) | ![Lab Zero](media/lab.png) |
| Floor 3: mutants between the pillars of the catacombs | Floor 4: an elite patrol in the ring corridor of Lab Zero |
| ![Citadel](media/citadel.png) | ![Automap](media/automap.png) |
| Floor 5: the great hall of the citadel | Automap (hold `M`) – shows only what you have already seen |
| ![Kennels](media/kennels.png) | ![War machine](media/warmachine.png) |
| The kennels | Pipeline Cannon versus the war machine and its escort |

<p align="center"><img src="media/cast.png" alt="The cast" width="900"></p>

## Controls

| Key | Action |
|---|---|
| `W` / `S`, arrow up/down | forward / back |
| arrow left/right | turn |
| `A` / `D` | strafe |
| `Shift` | run (enemies find you harder to hit – but hear you from further away) |
| `C` | sneak (slow and silent) |
| `Ctrl`, left mouse button | fire |
| `Space`, `E`, right mouse button | door, lever, lift switch, secret wall |
| `1`–`9` | weapons (see below) |
| `M` (hold) / `N` | automap / radar minimap on and off |
| `F2` / `F3` / `F4` | mouse look / fps display / music on and off |
| `F5` / `F9` | quick save / quick load |
| `F12` | record a demo (press again to stop and save) |
| `P`, `Esc` | pause: `1`–`3` save to a slot, `L` load, `Q` main menu |

**Game pad (XInput):** left stick move and strafe, right stick turn, `RT` fire, `LT` run, `A` use, `B` sneak,
`LB`/`RB` previous/next weapon, `Y` minimap, `Back` automap, `Start` pause. D-pad and `A` work in the menus.

The status bar shows floor, score, lives, health, ammunition for the weapon in hand, the weapons you own and your
keys. Above it: floor progress (kills, secrets, treasures), a three-step **noise meter**, `?` and `!` above enemies
who have noticed something or are coming for you, and the radar with alerted enemies as red dots.

## The campaign

Five floors that keep getting harder, plus a secret one. The lift takes you to the next floor; you keep your weapons,
ammunition and health, but not your keys. If you die you restart the floor with a pistol and 8 rounds. Every floor
ends with a tally (kills, secrets, treasures, a bonus for beating the par time).

| # | Floor | Enemies / total HP* | Character |
|---|---|---|---|
| 1 | Shellstein Dungeon | 33 / ~2800 | A gentle start: guards, dogs, the first elites and mutants, generous secret rooms, a commander at the end |
| 2 | The Barracks | 37 / ~3100 | A long corridor with counter-rotating patrols, dormitories (some of them really are asleep), shield bearers in the mess hall – and a lift that goes somewhere it should not |
| – | *The Treasury* | 12 / ~500 | The secret floor: gold everywhere, kamikaze bots between the chests |
| 3 | The Catacombs | 43 / ~3400 | Caves without doors – noise carries far. Dogs in the fog, mutants lying in ambush behind every pillar |
| 4 | Lab Zero | 37 / ~5800 | A ring corridor with elite patrols around the reactor hall, windows to shoot (and be shot) through, snipers, **the first war machine** |
| 5 | The Citadel | 40 / ~6500 | The finale: a great hall with three patrols, two commanders, and a throne hall with a war machine and its escort |

\* on *root*, where everybody shows up.

**The difficulty really matters.** It changes how many enemies are on the floor, how tough they are, how well and how
quickly they shoot, how far your gunfire carries and what a clip is worth:

| | Intern (-WhatIf) | Sysadmin | Senior Engineer | root (-Force -Confirm:$false) |
|---|---|---|---|---|
| damage you take | ×0.2 | ×0.33 | ×0.6 | ×1 |
| enemies' chance to hit | ×0.55 | ×0.7 | ×0.85 | ×1 |
| enemies' reaction time | ×2.5 | ×1.6 | ×1 | ×0.7 |
| rank and file on the floor | about 65 % | about 80 % | about 90 % | all, plus reinforcements (also on Senior Engineer) |
| enemy hit points | about 55 % | about 80 % | 100 % | 100 %, bosses more |
| gunfire wakes enemies within | 10 tiles | 13 tiles | 18 tiles | the whole connected area |
| rounds per clip / at the start | 16 / 16 | 12 / 12 | 8 / 8 | 8 / 8 |

The numbers are not guesses: `./Start-Polf3D.ps1 -BalanceTest <floor>` lets a bot play the floor on every difficulty –
a careless bot that never takes cover, never retreats and fights every boss in the open. On *Intern* it practically
never dies, on *Sysadmin* it beats every boss, on *Senior Engineer* it needs luck, and on *root* it has no chance at
all: there you need cover, the special weapons and a plan.

## Enemies, weapons, items

**Enemies**

| Enemy | HP | Trait |
|---|---|---|
| Guard | 15–25 | the standard opponent, one shot per attack |
| Dog | 1 | fast, cannot open doors, leaps at you |
| Officer | 30–50 | reacts almost instantly and aims very briefly |
| Elite | 55–100 | three-round bursts, better aim, drops a machine gun |
| Mutant | 30–65 | never shouts an alarm, two shots per attack – loves an ambush |
| Sniper | 15–30 | slow and fragile, takes his time – and then hits hard at **any** distance. Only running helps |
| Shield bearer | 45–80 | bullets and blades glance off the shield: get behind him, wait until he lowers it to shoot – or use something that does not care |
| Kamikaze bot | 10–20 | rolls at you at speed and blows itself up; shooting it has the same effect (mind who stands next to it) |
| Commander | 350–1200 | boss with twin machine guns: three rounds per salvo, then a pause – that is your moment. Drops the gold key |
| War machine | 550–1800 | super boss: gun bursts and salvos of three rockets (real projectiles with splash damage – pillars give cover) |
| Pilot | 140–500 | phase 2: climbs out of the war machine's wreck – few hit points, but very fast |

The AI works on the tile grid: enemies patrol along waypoints, open doors, chase you in a zig-zag and have a reaction
time. Hits throw blood or sparks, a heavy hit shakes the camera, explosions shake it more.

**Weapons**

| # | Weapon | |
|---|---|---|
| 1 | Knife | silent, costs nothing |
| 2 | Pistol | one shot per key press |
| 3 | Machine gun | automatic fire |
| 4 | Chain gun | automatic fire at twice the rate |
| 5 | **Pipeline Cannon** | "`\|` passes everything along": the beam pierces **every** enemy in the line of fire (4 rounds per beam) |
| 6 | **Force Blaster** | `Remove-Item -Recurse -Force` for your whole field of view – fed by rare Force charges |
| 7 | **Rocket launcher** | a real projectile with splash damage: brings down cracked walls, sets off barrels, ignores shields – and hurts you too |
| 8 | **Flamethrower** | short range, wide cone, burns everybody in it; flames lick around shields |
| 9 | **Throwing knives** | silent like the knife, but at a distance – deadly against anyone who has not noticed you |

The guns share one kind of ammunition (99 rounds at most); rockets, knives and Force charges are counted separately.
When a weapon runs dry you automatically draw the best one that still works.

**Items:** dog food (+4), food (+10), first aid kit (+25), clips, rockets, gold and silver keys, treasures
(coins 100, goblet 500, chest 1000, crown 5000 points), extra lives, Force charges and the **SUDO** power-up
(20 seconds of double damage dealt and half damage taken). Every 40,000 points earn an extra life.
**Explosive barrels** (the red ones) go up when shot and set each other off.

## Stealth

Anyone who has not noticed you yet takes **double damage**. What they notice:

* **Gunfire** alerts every room that is connected to yours through a door that is open at that moment (or a window).
* **Footsteps and doors** are heard within a few tiles – further when you run, not at all when you sneak (`C`).
* **Sight:** enemies only see what is in front of them. Sneaking, you can get right behind them.
* The knife and throwing knives are silent. Shield bearers are best dealt with exactly this way.

## Level machinery

* **Doors** slide into the wall and close again by themselves; gold and silver locks need the matching key.
* **Lever doors** cannot be opened by hand: somewhere there is a wall lever with the same number.
* **Secret push-walls** slide back two tiles when you press against them. **Cracked walls** only give way to explosions.
* **Windows** can be seen, heard and shot through – by both sides.
* **Spikes and crushers** cycle on a timer; neighbours are out of phase, so a row of them is a timing puzzle.
  Crushers do not care who is underneath.
* **Teleporter pads** come in numbered pairs.
* A second, hidden **lift switch** on floor 2 leads to the secret floor.

## Two players: co-op and duel

```powershell
./Start-Polf3D.ps1 -HostGame Coop          # or: -HostGame Duel
./Start-Polf3D.ps1 -JoinGame 192.168.1.20  # on the other computer: name or address of the host
```

The title screen shows the state of the connection; once the guest has joined, the host picks the difficulty and
presses Enter. The port is 27500/TCP (`-Port` changes it) – the host's firewall has to let it in.

* **Co-op:** the whole campaign together. Enemies go for whoever is nearer, keys are shared, either player can call
  the lift, and the partner shows up as a blue dot on the radar. No lives: whoever dies is back at the start of the
  floor a moment later with the basic kit, and the floor goes on. Friendly bullets do nothing – friendly rockets do.
* **Duel:** the same floors without monsters. Everybody starts with a machine gun, weapons and items come back
  after 25 seconds, the dead respawn far away from their opponent, frags are counted; the lift switch ends the round.

Both computers need the same maps (the game warns if they differ). Saving, loading and demos are switched off in a
network game, and the pause menu does not stop the world.

## Saved games, demos, speedruns

* **Saved games:** quick save (`F5`/`F9`), three slots from the pause menu, and an **autosave** whenever the lift
  arrives on a new floor. `L` on the title screen lists them all.
* **Demos:** `F12` records your input from a fresh start of the floor; played back, the same numbers go into the same
  simulation. Leave the title screen alone for a while and the attract demo starts – recorded by a little bot.
* **Speedruns:** `-Speedrun` (or `T` on the title screen) shows the clock – floor time, par and total run – and keeps
  the best times per floor and for complete runs in `saves/speedrun.json`.

## Music

Every track is composed in code and rendered once: a solemn **anthem** that plays only on the title screen, then
one style per floor – **rock** for the dungeon, a **march** for the barracks, a **creepy drone with far-away bells**
for the catacombs, **techno** for the lab, a **galloping finale** in harmonic minor for the citadel and a carefree
ditty for the treasury. Further floors you add cycle through the styles, transposed. `F4` or `-NoMusic` turns it off.

## Cheats

| Key | Code word (type it while playing) | Parameter | Effect |
|---|---|---|---|
| `F6` | `GIVEALL` | `-AllWeapons` | all weapons, full ammunition, Force charges, both keys, full health |
| `F7` | `NOLIMIT` | `-InfiniteAmmo` | shooting costs nothing |
| `F8` | `ROOT` | `-GodMode` | no damage |
| `F11` | `ONEHIT` | `-OneHitKill` | every hit kills – **the enemies and you** (unless god mode is on) |

`F7`, `F8` and `F11` are toggles; active cheats are shown at the bottom left of the view. Cheaters get a "(cheat)" tag
in the high score list and no speedrun records. No cheating in a duel.

## Command line

```powershell
./Start-Polf3D.ps1 -Scale 4        # window size: 2..5 times 320x240 (default 3)
./Start-Polf3D.ps1 -Columns 160    # half the number of rays, for slow machines
./Start-Polf3D.ps1 -FlatFloors     # plain floors and ceilings (the 1992 look, a little faster)
./Start-Polf3D.ps1 -Difficulty 4   # preselect the difficulty (1..4)
./Start-Polf3D.ps1 -Level 4        # start the campaign on floor 4
./Start-Polf3D.ps1 -Map ./maps/mine.map   # play just this one map
./Start-Polf3D.ps1 -Speedrun       # show the speedrun clock
./Start-Polf3D.ps1 -NoSound -NoMusic -NoGamepad
./Start-Polf3D.ps1 -HostGame Coop  # network game, see above (-JoinGame <host>, -Port <n>)
```

`Get-Help ./Start-Polf3D.ps1 -Full` lists everything.

## How it works

| File | Purpose |
|---|---|
| [Start-Polf3D.ps1](Start-Polf3D.ps1) | parameters, loading the modules, compiling the C# (DLL cache in `bin/`), start |
| [src/Defs.ps1](src/Defs.ps1) | constants, the classes `Actor`/`Door`/`Static`, tables for enemies, states, weapons, items |
| [src/Assets.Gfx.ps1](src/Assets.Gfx.ps1) | procedural textures, flats and sprites |
| [src/Assets.Sfx.ps1](src/Assets.Sfx.ps1) | sound synthesis, playback on one channel with priorities |
| [src/Music.ps1](src/Music.ps1) | the composer: styles, melodies written as text, wave patterns, SIMD mixing, WAV cache |
| [src/Map.ps1](src/Map.ps1) | loads the text map, finds rooms ("areas") by flood fill, places things |
| [src/Doors.ps1](src/Doors.ps1) | doors, levers, the area graph for sound and sight, push-walls |
| [src/Mechanics.ps1](src/Mechanics.ps1) | traps and teleporters |
| [src/Actors.ps1](src/Actors.ps1) | line of sight, perception, grid movement, think/action routines, projectiles, explosions, damage |
| [src/Player.ps1](src/Player.ps1) | movement with wall sliding, use, weapons, items, cheats |
| [src/Render.ps1](src/Render.ps1) | ray caster, floor casting, fog, windows, sprite projection, HUD, overlays, automap, radar |
| [src/Game.ps1](src/Game.ps1) | window, keyboard/mouse/game pad, game modes, main loop, screens |
| [src/SaveGame.ps1](src/SaveGame.ps1) | saved games as JSON, speedrun records, high score list |
| [src/Demo.ps1](src/Demo.ps1) | demo recording and playback, the bot that records the attract demo |
| [src/Network.ps1](src/Network.ps1) | the two-player mode: connection, protocol, snapshots, the "peer context" |
| [src/Scaler.cs](src/Scaler.cs), [src/Gamepad.cs](src/Gamepad.cs) | **the only C#**: the pixel loops, and the XInput declaration |
| [src/SelfTest.ps1](src/SelfTest.ps1) | headless tests and the screenshots for this README |

A few details for the curious:

* **Time** runs in tics (1/70 s). Every movement and every counter is scaled by the tics that have passed since the
  last frame – the game plays at the same speed at 20 fps as at 60.
* **Ray caster:** one ray per screen column is walked through the tile grid (DDA). The wall height comes from the
  distance *along the view direction* (no fish-eye). Doors are thin leaves in the middle of their tile and slide
  sideways into the wall, neighbouring walls show a door frame, push-walls are a ray-against-box test. For a window
  the ray simply goes on, and the window strip is blended in later. One of the two wall axes uses a darker copy of
  the texture – lighting for free; fog fades everything towards the floor's haze colour. The distance is remembered
  per column so sprites disappear cleanly behind walls.
* **Enemies** are a data-driven state machine `{Sprite, Rot, Tics, Think, Action, Next}`: *Think* runs every frame,
  *Action* once when the state runs out. The chains (stand, patrol, chase, shoot, pain, die) are generated from a
  short definition per enemy type.
* **Sound propagation:** the map falls into areas (rooms between doors) automatically. Only areas connected to yours
  through currently open doors hear gunfire – and only there do enemies think at all. That is gameplay and
  optimisation in one.
* **Determinism:** the game's random numbers are seeded per floor, cosmetic randomness has its own generator. That is
  what makes demos possible – a demo is just the seed plus the input of every frame.
* **Network:** the host owns the world and sends the guest what has changed, twenty times a second, as lines of text
  over TCP; the guest simulates only its own player and *asks* the host for everything else ("I hit actor 17 for 23",
  "use the tile in front of me"). For the enemies to fight two players, the host swaps the remote player in as
  "the player" for the duration of one actor's update – all the existing AI code then simply means the other one.
* **Music:** a note is one short wave pattern copied over and over with `Buffer.BlockCopy`; the six channels are added
  up with `System.Numerics.Vector`, sixteen samples at a time. Half a minute of music renders in under a second.
* **Presentation:** `int[]` frame buffer → bitmap → `BufferedGraphics`. Its GDI blit is about six times faster than
  drawing a GDI+ bitmap straight to the window – the difference between 30 and 55 fps.
* **Approved verbs:** every function, including every internal helper, uses a verb from `Get-Verb`;
  [tools/Test-Verbs.ps1](tools/Test-Verbs.ps1) checks that via the AST.

## Building your own levels

```powershell
./tools/Edit-Level.ps1 ./maps/level1.map   # the point-and-click editor: paint, validate, play
```

Every `maps/level<N>.map` is a text file; the campaign simply consists of all of them in numerical order – a
`level6.map` automatically becomes floor 6, and `bonus<N>.map` is where the secret lift switch of floor N leads.
After the header the grid follows `@map`, **every cell two characters wide**.

Header: `@name`, `@par <seconds>`, `@ceiling <RRGGBB>`, `@floor <RRGGBB>`, optionally `@floortex` / `@ceiltex`
(`flat_stone flat_wood flat_moss flat_tech flat_carpet` / `ceil_plain ceil_rock ceil_tech`), `@fog <RRGGBB> <tiles>`
and any number of `@spawn <min. difficulty> <x> <y> <enemy code>` reinforcements.

| Code | Meaning |
|---|---|
| `SS Sb Sp` `BB Bc` `WW Wp Ws` `RR Rb` `MM` | walls: stone, blue stone, wood, brick, steel (+ decorated variants) |
| `GG Gv` `TT Tl` | mossy rock (+ vines), tech panels (+ console) |
| `MX` / `MY` | lift switch (the exit) / secret lift switch (to the bonus floor) |
| `?S ?s ?B ?b ?W ?w ?R ?r ?M ?G ?g ?T ?t` | secret push-wall (upper case plain, lower case decorated) |
| `!S !B !W !R !M !G !T` | cracked wall – only an explosion brings it down |
| `=S =B =W =R =M =G =T` | window |
| `DD DG DS DL` | door: normal / gold lock / silver lock / lift door – the orientation is detected from the neighbouring walls |
| `D1`–`D9`, `X1`–`X9` | lever door and the wall lever that opens it |
| `..` | floor |
| `P^ P> Pv P<` | player start and view direction |
| `g d e o m s h k b u` + direction | guard, dog, elite, officer, mutant, sniper, shield bearer, kamikaze bot, commander, war machine |
| direction `^ > v <` / `n e s w` / `N E S W` | standing / standing and "deaf" (ambush, reacts to sight only) / patrolling |
| `:^ :> :v :<` | waypoint: patrols turn here |
| `~s ~c` | trap: spikes, crusher |
| `@1`–`@9` | teleporter pad (two pads with the same number form a pair) |
| `+d +f +h` `+a +o +z` `+m +c +p +r +l +t +j` `+g +s` `+1 +2 +3 +4` `+u +q` | dog food, food, first aid · clip, rockets, Force charge · machine gun, chain gun, Pipeline Cannon, Force Blaster, rocket launcher, flamethrower, throwing knives · keys · treasures · extra life, SUDO |
| `*l *h *L *t *b *p *a *c *f *x *v *s *u *k *B *m *g` `*e` | decoration: ceiling lamp, chandelier, floor lamp, table, barrel, plant, suit of armour, column, flag, crates, vat, bones, puddle, dead guard, bed, console, stalagmite · **explosive barrel** |

The bundled maps are generated by [tools/New-Levels.ps1](tools/New-Levels.ps1) from room lists – rooms are rectangles
carved out of solid rock; where they touch they merge into corridors and caves. The game only ever reads the `.map`
files, though, so you can just as well edit them by hand or in the editor. Validate and play:

```powershell
./tools/Test-Level.ps1 -Map ./maps/mine.map    # border closed? everything reachable? keys, levers, teleporter pairs? patrol routes clear?
./Start-Polf3D.ps1 -Map ./maps/mine.map
```

## Tests

```powershell
./Start-Polf3D.ps1 -SelfTest   # headless: renders PNGs into ./selftest and tests combat, stealth, weapons, machinery,
                               # bosses, saved games, demo determinism, the network protocol (both sides, over
                               # loopback) and the music - plus a soak test of every floor that fights every boss
./tools/Test-Level.ps1         # validates all maps and prints an overview of each
./tools/Test-Verbs.ps1         # every function uses an approved verb
./Start-Polf3D.ps1 -BalanceTest 1   # a bot plays floor 1 on every difficulty and duels its bosses: who wins how often?
```

## Origin and scope

POLF 3D is **neither a clone nor a port**. The source code of the 1992 grandfather of the genre, later released by
id Software, was first analysed and described *in our own words* – how the code is structured and how levels, enemies,
weapons, items and doors work. Only from that description was the game written anew. What was adopted are concepts and
game mechanics; **nothing** of the original is contained in this repository: own code, own levels, own names, own
procedurally generated graphics, sounds and music – and the `>_` prompt as a coat of arms.

## License

Copyright © 2026 oNdsen. Released under the [MIT License](LICENSE) – code, maps and the procedurally generated
graphics, sounds and music. Use it, change it and pass it on, as long as the copyright notice stays in place.
