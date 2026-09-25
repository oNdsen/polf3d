<h1 align="center">POLF 3D &nbsp;<code>&gt;_</code></h1>

<p align="center"><b>A 90s-style ray casting shooter – written in PowerShell.</b><br>
<i>A real PowerShell console inside the game, <code>-WhatIf</code>, <code>-Confirm</code> and <code>-Force</code> as powers, a daily dungeon with
verifiable runs,<br>ten floors, a secret one and an ending worth playing for, fifteen kinds of enemies plus cameras and sentry guns, ten weapons and a mine, an arena with endless waves, co-op and deathmatch for up to four over the network, a terminal
mode –<br>procedurally generated graphics, sound, speech and music – as much PowerShell as possible, as little C# as necessary.</i></p>

<p align="center">
<a href="https://github.com/oNdsen/polf3d/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/oNdsen/polf3d?label=release&color=2C54C4"></a>
<a href="https://github.com/oNdsen/polf3d/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/oNdsen/polf3d/total?label=downloads&color=2C54C4"></a>
<a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/github/license/oNdsen/polf3d?color=2C54C4"></a>
<img alt="PowerShell 7.2+" src="https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?logo=powershell&logoColor=white">
<img alt="Platform: Windows" src="https://img.shields.io/badge/platform-Windows-0078D6">
<img alt="Asset files: 0" src="https://img.shields.io/badge/asset%20files-0-40C060">
<a href="https://github.com/oNdsen/polf3d/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/oNdsen/polf3d?color=506080"></a>
<a href="https://github.com/oNdsen/polf3d/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/oNdsen/polf3d?style=flat&color=F0D040"></a>
</p>

<p align="center"><img src="media/banner.png" alt="POLF 3D - the war machine opens fire" width="900"></p>

<p align="center"><img src="media/gameplay.gif" alt="Ten seconds of the attract demo: the hub hall of floor 1" width="640"><br>
<sub>Ten seconds of the demo that plays on the title screen – exported by the game itself: <code>./Start-Polf3D.ps1 -ExportGif demos/attract.json</code></sub></p>

**[Download polf3d.zip](https://github.com/oNdsen/polf3d/releases/latest/download/polf3d.zip)**, unpack it and start
`Play.cmd` – or clone the repository:

```powershell
git clone https://github.com/oNdsen/polf3d.git
cd polf3d
./Start-Polf3D.ps1
```

Requirements: **Windows** and **PowerShell 7.2+** (`winget install Microsoft.PowerShell`). Nothing else – no modules,
no asset files, no installation. Windows marks scripts that come out of a downloaded ZIP as "from the internet", and
PowerShell may then refuse them; `Play.cmd` starts the game with `-ExecutionPolicy Bypass` for that one process and
changes nothing on the machine (`Get-ChildItem -Recurse | Unblock-File` is the other way). On a machine managed by an
organisation two things can still stop it, and the game says which: an execution policy set by Group Policy, which
`Play.cmd` cannot lift, and an application control policy (AppLocker, WDAC) that puts PowerShell into constrained
language mode, where the C# helpers cannot be built. What changed from release to release is in the
[changelog](CHANGELOG.md) - and **the game updates itself**: once a day the title screen asks GitHub for a newer
release (one request, and the options menu or `-NoUpdateCheck` turns it off), a line says when there is one, `U` shows
what is new, and Enter downloads `polf3d.zip`, checks its SHA256 against the release notes, keeps the old files in
`polf3d-backup-<version>.zip` next to the game, installs and restarts. Saved games, settings and your own mods stay.
`./Start-Polf3D.ps1 -Update` does the same from the command line.
On first start the four small C# files ([src/Scaler.cs](src/Scaler.cs), [src/Mixer.cs](src/Mixer.cs),
[src/Gamepad.cs](src/Gamepad.cs), [src/Terminal.cs](src/Terminal.cs)) are compiled once into `bin/` - every later start
just loads the DLLs, until a source file changes; the music and the enemies' spoken lines are
composed, spoken and cached there the first time they are needed.

---

## Contents

- [What is this?](#what-is-this)
- [Screenshots](#screenshots)
- [Controls](#controls)
- [The onboarding](#the-onboarding)
- [The campaign](#the-campaign)
- [Enemies, weapons, items](#enemies-weapons-items)
- [PowerShell is the point](#powershell-is-the-point)
- [The daily dungeon](#the-daily-dungeon)
- [The arena](#the-arena)
- [Terminal mode](#terminal-mode)
- [Stealth](#stealth)
- [Level machinery](#level-machinery)
- [Up to four players: co-op and deathmatch](#up-to-four-players-co-op-and-deathmatch)
- [Saved games, demos, speedruns](#saved-games-demos-speedruns)
- [Music](#music)
- [Mods](#mods)
- [Cheats](#cheats)
- [Command line](#command-line)
- [How it works](#how-it-works)
- [Building your own levels](#building-your-own-levels)
- [Tests](#tests)
- [Origin and scope](#origin-and-scope)
- [License](#license)

## What is this?

POLF 3D is a complete first-person shooter with a textured ray caster (walls, floors, ceilings, windows, distance fog),
sliding doors, keys, levers, traps, teleporters, secret push-walls, dark rooms, enemy AI, bosses, saved games, demos,
a level editor and a network mode for up to four – and almost all of it is **plain PowerShell**: game logic, AI, ray
casting, map format, HUD, menus, music, network protocol, even the GIF at the top of this page.

* **PowerShell is not just the language, it is the theme.** A sandboxed but real PowerShell console is part of the
  game (with a `$PROFILE`, background jobs and hotkeys), the special powers are PowerShell's common parameters, the
  building has an execution policy, the lift installs modules, the walls are full of consoles and error screens, the
  bosses are a batch file, a printer and a blue screen, and every floor ends with a transcript and a Pester report.
* **No asset files.** All wall and floor textures, about 480 sprite images, 50 sound effects and the whole soundtrack
  are generated procedurally (GDI+ primitives, a 3×5 pixel font, a tiny square/saw/noise synthesiser and a chiptune
  composer); the enemies' lines are spoken by Windows' own speech synthesiser. That is also why a [mod](#mods) can add
  an enemy with ten lines of data.
* **As much PowerShell as possible, as little C# as necessary.** Everything that can reasonably be done in PowerShell
  is PowerShell. C# is only used where PowerShell cannot keep up: the innermost pixel loops (scale one wall strip, draw one sprite, fill one floor row, turn a frame into terminal characters), the audio callback that
  mixes the sounds, and two P/Invoke declarations (game pad, keyboard state). PowerShell cannot push 64,000 pixels
  per frame or feed a sound card every few milliseconds – but it handles the 320 rays per frame with ease.
* **45–60 fps** in a 960×720 window on an ordinary office laptop.

## Screenshots

| | |
|---|---|
| ![Title screen](media/title.png) | ![The hub hall on floor 1](media/hub.png) |
| Title screen with difficulty levels and high scores | Floor 1: the hub hall – patrols, banners with the `>_` coat of arms |
| ![Fire fight](media/firefight.png) | ![Co-op](media/coop.png) |
| A guard takes aim (seen through the door frame) | Co-op over the network: two partners run ahead, each in the colour of his slot |
| ![Catacombs](media/catacombs.png) | ![Lab Zero](media/lab.png) |
| Floor 3: mutants between the pillars of the catacombs | Floor 4: an elite patrol in the ring corridor of Lab Zero |
| ![Citadel](media/citadel.png) | ![Automap](media/automap.png) |
| Floor 5: the great hall of the citadel | Automap (hold `M`) – shows only what you have already seen |
| ![Kennels](media/kennels.png) | ![War machine](media/warmachine.png) |
| The kennels | Pipeline Cannon versus the war machine and its escort |
| ![-WhatIf](media/whatif.png) | ![The console](media/console.png) |
| `-WhatIf`: time stands still, ghosts show where everybody will be in two seconds – the red ones will open fire | The console: real pipelines, real `-WhatIf`, no way out of the sandbox |
| ![Terminal mode](media/terminal.png) | ![The daily dungeon](media/dungeon.png) |
| `-Terminal`: the same game as half-block characters | The plan of a generated dungeon: the lift behind the gold door, the key with the boss |
| ![The Data Centre](media/datacentre.png) | ![Ring 0](media/ring0.png) |
| Floor 6: a cold aisle of the data centre – there is a sniper at the far end of every one | Floor 10: the core of Ring 0 – dark, and something in there is glowing blue |
| ![The arena](media/arena.png) | ![A floor's tests](media/tests.png) |
| The arena: wave three comes through the gates – the radar shows where from | Every floor is a test suite, and Pester reports: a pacifist run through the catacombs |
| ![The player list](media/players.png) | ![The onboarding](media/tutorial.png) |
| `F1` in a network game: on the host it is an admin panel – `K` kicks, `B` bans, `U` lifts a ban | The onboarding (`N` on the title screen): one room per mechanism, and the floor explains itself |

<p align="center"><img src="media/faces.png" alt="The face in the status bar" width="880"></p>

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
| `1`–`9`, `0` | weapons (see below) – `0` is the taser |
| `Q` | put a mine down – and, pressed again, set off what lies out there |
| `Z` `X` `V` `F` `R` | the powers: `-WhatIf`, `-Confirm`, `-Verbose`, `-Force`, Undo (see [below](#powershell-is-the-point)) |
| `T`, `Tab` | the PowerShell console (`Esc` leaves it, `Tab` completes in there) – or "use" a terminal or a server rack |
| `G` `H` `B` `Y` | the four console hotkeys: whatever command line you put on them with `Set-Hotkey` |
| `L` | flashlight (dark rooms) |
| `M` (hold) / `N` | automap / radar minimap on and off |
| `F2` / `F3` / `F4` | mouse look / fps display / music on and off |
| `F5` / `F9` | quick save / quick load |
| `F12` | record a demo (press again to stop and save) |
| `P`, `Esc` | pause: `1`–`3` save to a slot, `L` load, `Q` main menu |
| `N` (title screen) | **new here? the onboarding** – a floor that explains every mechanism, one room at a time |
| `G` / `H` (title screen) | today's dungeon / the arena (horde mode) |
| `O` (title screen, pause) | options: mouse sensitivity, volumes, radar, fps, floors, window size – **and every key above** |
| `F1` (network games) | the player list – on the host with kick and ban |

**Game pad (XInput):** left stick move and strafe, right stick turn, `RT` fire, `LT` run, `A` use, `B` sneak,
`LB`/`RB` previous/next weapon, `X` `-Confirm`, `Y` minimap, `Back` automap, `Start` pause. D-pad and `A` work in the menus.

The status bar shows floor, score, lives, health, ammunition for the weapon in hand, the weapons you own and your
keys – and **the admin on call**: he collects a new layer of damage every 20 health, winces at every hit and then
looks towards whoever fired, grins over a new weapon, grits his teeth while you hold the trigger, squints when
sneaking and wears shades during SUDO. Above it: floor progress (kills, secrets, treasures), a three-step **noise meter**, `?` and `!` above enemies
who have noticed something or are coming for you, and the radar with alerted enemies as red dots – each with a nose
that shows where it is looking. In the top left corner: the building's [execution policy](#stealth) and, below it,
whatever the floor has [scheduled](#level-machinery) (or, in the arena, the wave).

## The onboarding

`N` on the title screen (or `./Start-Polf3D.ps1 -Tutorial`) is the place to start: ten rooms, and each of them explains
one thing and has what it takes to try it – moving and doors, shooting somebody who has not noticed you, sneaking and
blades, keys and a hollow wall, the five powers (with a gold door that only `-Force` opens – well, almost only), the
console with a terminal, a file and a code, a camera, a sentry gun and the taser, a dark room with bugs, mines and
your flashlight, loot – and a lift that goes back to the title screen. The difficulty is *Intern* in there whatever
you chose, privilege comes back five times as fast, and nothing is rated.

The explaining is done by **hints**, which any map can use: `@hint <x> <y> <width> <height> <text>` shows the text at
the top of the view the first time the player stands inside that rectangle.

## The campaign

Ten floors that keep getting harder, plus a secret one. The lift takes you to the next floor; you keep your weapons,
ammunition and health, but not your keys. If you die you restart the floor with a pistol and 8 rounds. Every floor
ends with a tally (kills, secrets, treasures, a bonus for beating the par time).

| # | Floor | Enemies / total HP* | Character |
|---|---|---|---|
| 1 | Shellstein Dungeon | 33 / ~2800 | A gentle start: guards, dogs, the first elites and mutants, generous secret rooms, a commander at the end |
| 2 | The Barracks | 37 / ~3100 | A long corridor with counter-rotating patrols, dormitories (some of them really are asleep), shield bearers in the mess hall – and a lift that goes somewhere it should not |
| – | *The Treasury* | 12 / ~500 | The secret floor: gold everywhere, kamikaze bots between the chests |
| 3 | The Catacombs | 43 / ~3400 | Caves without doors – noise carries far. Dogs in the fog, mutants lying in ambush behind every pillar |
| 4 | Lab Zero | 37 / ~5800 | A ring corridor with elite patrols around the reactor hall, windows to shoot (and be shot) through, snipers, **the first war machine** |
| 5 | The Citadel | 40 / ~6500 | The end of the first half: a great hall with three patrols, two commanders, and a throne hall with a war machine and its escort |
| 6 | The Data Centre | 44 / ~4200 | Six cold aisles between two cross corridors: snipers at the far ends, windows in the rack rows, a commander in the silver cage |
| 7 | The Archive | 45 / ~3700 | Two halls of shelves to get lost in, with things waiting between them. Four secrets – the microfiche knows them all |
| 8 | The Foundry | 35 / ~5600 | A production line: a conveyor with three crushers and a gate, three levers – and THE PRINTER in the assembly hall |
| 9 | The Executive Floor | 46 / ~5500 | Carpet and plants. A gallery of offices, the board (a commander chairing his officers) behind the silver door, and a CEO who keeps a printer |
| 10 | Ring 0 | 47 / ~10000 | Two rings around the core. Patrols outside, levers for the gates, and in the dark of the core two printers, **BLUE SCREEN** – and the lift in the middle of it |

**Every floor is a test suite.** When you throw the lift switch the run is put through ten tests and the result is
printed the way Pester prints it – `[+] beats the par time 24ms`, `[-] fires no gun (blades are fine) 19ms` – on the
completion screen, in terminal mode and in the transcript. Reaching the lift, par time, all kills, all secrets, all
treasure, noticed by nobody, no guns, never below 50 health, no powers and no console, no cheats: what has been passed
once stays passed (`saves/achievements.json`), and the title screen counts them – there are a hundred to get.

**`Install-Module`.** The lift has a repository: after every floor it offers three modules, and one of them – `1`, `2`
or `3` – can be installed for the rest of the run. `Get-Module` in the console lists what you have.

| Module | What it does |
|---|---|
| `PSReadLine` | the powers cost a quarter less privilege |
| `ThreadJob` | the drone costs 15, carries ten things and flies half as fast again |
| `SecretManagement` | secret and cracked walls are marked on the automap of every floor |
| `Pester` | whoever has not noticed you takes triple instead of double damage |
| `PSScriptAnalyzer` | `-Verbose` is free and lasts twice as long |
| `PowerShellGet` | every clip holds a quarter more rounds |
| `Microsoft.PowerShell.Archive` | food and first aid heal half as much again |
| `PSWindowsUpdate` | privilege comes back half as fast again |

**It is worth finishing.** Whoever throws the last switch on floor 10 gets a proper ending, with a piece of music
written for it. There is no picture of it here, on purpose: it has to be earned.

\* on *root*, where everybody shows up. Cameras and sentry guns (floors 6–10) are equipment, not staff: they are not
counted here and they are not kills.

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
| Bug | 8–16 | small, quick, zig-zags and leaps at you. Fix it with a blade, a bullet or fire and it is gone – **blow it up and two smaller ones crawl out** ("fix one, get two") |
| Engineer | 25–45 | a poor shot, but he keeps the house running: takes hacked sentry guns back, puts destroyed sentry guns and cameras on their feet again and patches up whoever stands near him. Always the first target |
| Auditor | 20–40 | unarmed. When he sees you he **runs for the nearest terminal** – and if he gets there, his report raises the [execution policy](#stealth) by a whole level. Always carries a keycard |
| Kamikaze bot | 10–20 | rolls at you at speed and blows itself up; shooting it has the same effect (mind who stands next to it) |
| Security camera | 8–12 | hangs from the ceiling and sweeps a quarter turn to either side. Harmless – but every second it sees you heats the [execution policy](#stealth) by eight points. Not a kill; `Get-Enemy -Kind camera \| Stop-Enemy` switches it off quietly |
| Sentry gun | 35–65 | never moves, fires bursts, explodes when destroyed. `Get-Enemy -Kind turret \| Set-Turret -Owner Me` (25 privilege) makes it change sides: from then on it shoots whoever else comes within ten tiles |
| Commander – *LEGACY.BAT* | 350–1200 | "runs as SYSTEM, nobody dares to touch it". Twin machine guns: three rounds per salvo, then a pause – that is your moment. Drops the gold key |
| War machine – *THE PRINTER* | 550–1800 | "PC LOAD LETTER". Super boss: gun bursts and salvos of three rockets (real projectiles with splash damage – pillars give cover). After every second salvo it has a **paper jam**: four seconds of helpless blinking and triple damage – but the first three times it also finishes two print jobs, and they come rolling at you |
| *BLUE SCREEN* | 700–2200 | ":( your admin ran into a problem". The last one, in the core of Ring 0: a monitor riding on a tangle of cables. Bursts, a rocket – and **the crash**: the picture tears and your controls hang for most of a second (Undo still works). When it dies the system halts: everybody left stands still for twenty seconds |
| Pilot – *THE PRINTER DRIVER* | 140–500 | "unsigned". Phase 2: climbs out of the war machine's wreck – few hit points, but very fast |

The AI works on the tile grid: enemies patrol along waypoints, open doors, chase you in a zig-zag and have a reaction
time. Hits throw blood or sparks, a heavy hit shakes the camera, explosions shake it more. Bosses show their name
and a health bar once they are after you. And **they talk**: "Access denied!", "Who approved this change?", "Execution
policy: restricted!" – and now and then a last "Null reference!" (`-NoVoices` makes them beep again).

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
| 0 | **Taser** | `Stop-Process`: silent, two and a half tiles of reach. Stuns whoever it touches for five seconds (and he still has not noticed you), makes bosses flinch and switches machines – sentry guns, cameras, kamikaze bots – off for good. The battery recharges by itself; no gun as far as the pacifist achievement is concerned |
| `Q` | **Mine** | `Invoke-Command`, the remote kind: `Q` puts one down, `Q` again – or `Invoke-Command` in the console, or anything that hits it – sets off whatever lies out there. They come in pairs |

The guns share one kind of ammunition (99 rounds at most); rockets, knives and Force charges are counted separately.
When a weapon runs dry you automatically draw the best one that still works.

**Loot.** Every kind of enemy has its own loot table, rolled with the floor's random numbers. Officers may carry
**keycards** – a locked door without its key eats one and stays open for good. Elites and shield bearers leave shards
of **armour**, the commander a whole vest: armour takes half of every hit until it is gone. Machines leave **scrap**
that turns into privilege. Rarely there is a **signed drop**, a module that is imported for the rest of the floor –
`Overclock` (the guns cycle half as fast again), `ArmorPiercing` (bullets hit harder and go through shields) or
`Compress-Archive` (every second round is free). And there is the **silent streak**: kill enemies who never noticed
you, one after another without anybody noticing in between, and from the third on they leave more behind; the fifth
brings a signed drop for certain. Being seen ends it. The commander, by the way, only drops a gold key where there is
a gold lock to open – otherwise his strongbox.

**Items:** dog food (+4), food (+10), first aid kit (+25), clips, rockets, gold and silver keys, treasures
(coins 100, goblet 500, chest 1000, crown 5000 points), extra lives, Force charges and the **SUDO** power-up
(20 seconds of double damage dealt and half damage taken). Every 40,000 points earn an extra life.
**Explosive barrels** (the red ones) go up when shot and set each other off.

## PowerShell is the point

**Powers named after the common parameters.** They cost *privilege* (the blue gauge), which trickles back by itself
and comes in chunks with every kill.

| Key | Power | Cost | |
|---|---|---|---|
| `Z` | `-WhatIf` | 25 | Time stands still for four seconds and everybody's next two seconds appear as ghosts – cyan for where they will walk, **red for those who will open fire**. It is a real forecast: the game copies the world, runs the actual simulation ahead and puts the world back |
| `X` | `-Confirm` | 30 | "Are you sure?" The world drops to a third of its speed for five seconds. You do not |
| `V` | `-Verbose` | 15 | Ten seconds of `VERBOSE: guard 25` over everybody within 14 tiles – through walls |
| `F` | `-Force` | 35 | Kicks in the door in front of you (locked or not), brings down cracked walls, shoves secret walls and hurts whoever stands close |
| `R` | Undo | 60 | `Restore-Checkpoint`: the last five seconds never happened – including the rocket you just ate |

**The console** (`T` or `Tab`). The world stops and you get a PowerShell prompt – a real one: pipelines,
`Where-Object`, `Sort-Object`, script blocks, `Get-Member`. The game's cmdlets cost privilege when they *do* something:

```powershell
Get-Enemy | Sort-Object Distance | Select-Object -First 1 | Stop-Enemy -WhatIf   # what would it cost?
Get-Enemy | Where-Object State -eq 'attacking' | Suspend-Enemy                   # freeze them for eight seconds
Get-Door  | Where-Object Lock -ne '-' | Open-Door                                # who needs keys
Get-Door  | Sort-Object Distance | Select-Object -First 1 | Lock-Door            # jam the door behind you
Get-Enemy -Kind turret | Set-Turret -Owner Me                                    # the sentry gun changes sides
Get-Door | Set-Door -Open $true ;  Get-Process | Stop-Process                    # ... or the way you would have guessed
Get-Trap | Disable-Trap ;  Get-Loot -Name key* ;  Get-Secret ;  Get-Player ;  Get-Help
```

**Tab completes** – commands, aliases and parameters, but also what only the game can know: the kinds of enemies on
this floor after `-Kind`, the files of the terminal after `cat`, and the properties of whatever comes down the pipeline
(`Get-Door | ? Lo` + Tab gives `Lock`). Tab again takes the next candidate. `Tab` also opens the console, `Esc` leaves it.

Logging on at one of the terminals or server racks in the levels ("use") opens the same console and grants 30
privilege once. **Those terminals have files** – `Get-ChildItem`, `Get-Content mail-0412.eml` – and the files tell
what happened at Shellstein, floor by floor: tickets nobody could close, a duty roster, the minutes of the board. Some
of them give things away: `Unlock-Door -Code 4711` opens what the mail says it opens, `Use-Token NIGHTSHIFT` marks the
floor's secrets on the automap. A code works once per floor.

**It has background jobs.** `Start-Job` (30 privilege) sends out a drone – a small blue quadcopter that flies through
the ventilation to whatever lies around in the rooms that are open to you, nearest first, and picks it up: ammunition,
first aid, treasure, keys. Six things or thirty seconds later it comes back and hovers next to you. `Get-Job` shows how
it is doing, `Receive-Job` drops its load at your feet, `Stop-Job` calls it back early. Undo undoes it, too.

**It has a `$PROFILE`.** Define a function or an alias in the console and `Save-Profile` writes it to
`saves/profile.ps1`, which is run – inside the sandbox, like everything else – whenever the console starts. And
`Set-Hotkey 1 'kn'` puts a command line on a key, to be run in the middle of the game without opening the console:

```powershell
function kn { Get-Enemy | Sort-Object Distance | Select-Object -First 1 | Stop-Enemy }
Set-Hotkey 1 'kn'          # G - the four keys are G H B Y, Get-Hotkey shows them, the options menu rebinds them
Save-Profile               # Get-Content $PROFILE shows it, Clear-Content $PROFILE empties it
```
 It is safe to type anything: the console runs in a second runspace whose session state starts
*empty* – no providers (so no file system), no external programs, a dozen harmless cmdlets added back,
`ConstrainedLanguage`, and two seconds per line. `Remove-Item C:\ -Recurse -Force` gets a polite answer.

**Everywhere you look.** Consoles on the walls (each wall type has its own one-liner; the one in the caves is long
dead and overgrown), red `ACCESS DENIED` screens, `Get-Help` posters ("Verb-Noun. Always."), neon `>_` panels,
graffiti, server racks, desks with CRTs. The level generator spreads them over every floor.

**The transcript.** Every floor writes a `Start-Transcript`-style log into `saves/transcripts` – what you killed with
what (and whether the victim had noticed anything), what you found, which powers and console lines you used – and
ends with a one-line verdict that also appears on the floor-completed screen ("Completed with 12 % of the staff still
employed. A remarkably quiet change window.").

## The daily dungeon

`G` on the title screen (or `-Daily`) builds a floor from today's date, so **everybody gets the same dungeon today**;
`-Dungeon 4711` plays any other number. Rooms are joined into a tree by corridors plus a loop or two, the lift is
behind a gold door in the farthest dead end, the key is with *LEGACY.BAT* in another, and everything in between is
populated by its distance from the start. One life, a fresh kit, no saving, no console.

Every run is recorded – and since a demo is nothing but the seed plus the input of every frame, **a time can be
checked**:

```powershell
./Start-Polf3D.ps1 -VerifyDemo ./saves/dungeon-20260918-d2-3m12s4-174501.json
# VALID: ... on 'Dungeon #20260918', difficulty 2, 6745 frames - reached the lift after 3:12.4 with 31 kills
```

The verifier rebuilds the dungeon, plays the input back without a window and compares where it ends. A doctored file
does not end where it claims to. Best times are kept per seed and difficulty.

## The arena

`H` on the title screen (or `./Start-Polf3D.ps1 -Horde`, `-HordeNumber 4711` for a particular one): one life, one hall
with eight pillars, and wave after wave coming out of four gates. Every wave has more to spend than the one before –
first guards and dogs, later elites, snipers, shield bearers and kamikaze bots; every fifth wave is led by a
commander, every tenth by a war machine. Between the waves supplies drop in the middle of the hall, and now and then a
new weapon. The waves are made from the horde's number – today's date by default – so everybody fights the same ones,
and `saves/horde.json` keeps your best for every number and difficulty. The lift in the corner is the way out: taking
it ends the run with what you have. The console works in there. So does the drone.

**Together:** the host of a co-op game can open the arena as well – `H` on the title screen once the guests are
there, or `./Start-Polf3D.ps1 -HostGame Coop -Horde`, where Enter opens it. The waves grow with the number of players,
nobody runs out of lives (whoever falls is back a moment later with the basic kit), and the run is not rated. The
guests need nothing special: they load the arena the way they load a secret floor.

## Terminal mode

```powershell
./Start-Polf3D.ps1 -Terminal
```

No window: the frame buffer goes into the terminal as half-block characters with 24 bit colours (two pixels per
character cell – the bigger the terminal window, the finer the picture), status bar and menus are text, and the
PowerShell console simply *is* the terminal. Wants a terminal that understands ANSI sequences, such as Windows
Terminal. Over SSH the keyboard state of the remote machine is of no use, so there (or with `-TerminalKeys`) the key
presses of the terminal are used, and `J` fires.

## Stealth

Anyone who has not noticed you yet takes **double damage**. What they notice:

* **Gunfire** alerts every room that is connected to yours through a door that is open at that moment (or a window).
* **Footsteps and doors** are heard within a few tiles – further when you run, not at all when you sneak (`C`).
* **Sight:** enemies only see what is in front of them. Sneaking, you can get right behind them.
* The knife and throwing knives are silent. Shield bearers are best dealt with exactly this way.

**The building has an execution policy** – how nervous the whole floor is, shown in the top left corner. Being seen
and making noise heat it up, keeping quiet lets it cool down again:

| Policy | The house | What it means |
|---|---|---|
| `Restricted` | suspects nothing | nobody watches the logs: your privilege comes back 30 % faster |
| `AllSigned` | has been told to look twice | enemies react 20 % quicker, gunfire carries a quarter further |
| `RemoteSigned` | is on edge | 40 % quicker, gunfire carries 60 % further |
| `Unrestricted` | **sounds the alarm** | everybody who can reach you comes running, and every shot is heard everywhere |

In the console `Get-ExecutionPolicy` tells you where you stand and `Set-ExecutionPolicy Restricted` calms the house
down again, for 15 privilege a step. (Setting it to `Unrestricted` is free. You will pay for it in other ways.)

## Level machinery

* **Dark rooms** (floors 6–10 each have one – on floor 10 it is the core). The haze closes in and turns black; every
  shot lights the room up for a moment. `L` switches on a flashlight that opens a cone of light in the middle of the
  picture. It cuts both ways: in the dark nobody sees further than three and a half tiles – unless you carry a light
  around. A map marks them with `@dark <x> <y>`.
* **The floor has a schedule** (floors 6–10; `@event <kind> <seconds>` in a map). A **lockdown** slams every plain
  door shut and seals it for fifteen seconds – only your own hand still opens them, so nobody can follow you, or come
  to help. A **power failure** turns the whole floor into a dark room for twenty-five seconds. And **Patch Tuesday**
  has a countdown in the corner of the screen: when it runs out, every enemy still alive is as good as new and the
  execution policy heats up by thirty. It pays to be quick.
* **Doors** slide into the wall and close again by themselves; gold and silver locks need the matching key.
* **Lever doors** cannot be opened by hand: somewhere there is a wall lever with the same number.
* **Secret push-walls** slide back two tiles when you press against them. **Cracked walls** only give way to explosions.
* **Windows** can be seen, heard and shot through – by both sides.
* **Spikes and crushers** cycle on a timer; neighbours are out of phase, so a row of them is a timing puzzle.
  Crushers do not care who is underneath.
* **Teleporter pads** come in numbered pairs.
* A second, hidden **lift switch** on floor 2 leads to the secret floor.

## Up to four players: co-op and deathmatch

```powershell
./Start-Polf3D.ps1 -HostGame Coop -PlayerName Boss           # or: -HostGame Deathmatch   (-MaxPlayers 2..4)
./Start-Polf3D.ps1 -JoinGame 192.168.1.20 -PlayerName Anna   # on the other computers: name or address of the host
```

Guests gather on the host's title screen, which lists who has joined; the host picks the difficulty and presses
Enter. The port is 27500/TCP (`-Port` changes it) – the host's firewall has to let it in. Whoever connects while a
floor is being played waits in the lobby and is in from the next floor. Every player wears the colour of their slot:
orange (the host), green, purple, yellow.

* **Co-op:** the whole campaign together. Enemies go for whoever is nearest, keys are shared, anybody can call the
  lift, partners are blue dots on the radar and their health is shown in the view. No lives: whoever dies is back at
  the start of the floor a moment later with the basic kit, and the floor goes on. Friendly bullets do nothing –
  friendly rockets do.
* **Deathmatch** (`Duel` is the same thing for two): the same floors without monsters. Everybody starts with a machine
  gun, weapons and items come back after 25 seconds, the dead respawn as far from everybody else as possible, the
  host keeps the frag count and everybody sees it; the lift switch ends the round.

**The host is the admin.** `F1` opens the player list – slot, name, address, state, frags. `K` kicks the selected
player, `B` bans them: they are thrown out and their address is turned away from then on (the list is kept in
`saves/banned.json`), `U` lifts a ban. A guest who was kicked, banned or found the game full is told why and does not
keep knocking. Guests see the same list without the buttons. If a guest leaves or loses the connection the floor
simply goes on without them; if the host leaves, everybody is back at the title screen.

All computers need the same maps (the game warns if they differ). Saving, loading, demos, the console (and with it
hotkeys, drone and hacked sentry guns), the modules in the lift and the time-bending powers are switched off in a
network game (`-Verbose` works), and menus do not stop the world. The dungeon is a solo affair; [the arena](#the-arena) is not.

## Saved games, demos, speedruns

* **Saved games:** quick save (`F5`/`F9`), three slots from the pause menu, and an **autosave** whenever the lift
  arrives on a new floor. `L` on the title screen lists them all.
* **Demos:** `F12` records your input from a fresh start of the floor; played back, the same numbers go into the same
  simulation. Leave the title screen alone for a while and the attract demo starts – recorded by a little bot.
* **Speedruns:** `-Speedrun` (or `T` on the title screen) shows the clock – floor time, par and total run – and keeps
  the best times per floor and for complete runs in `saves/speedrun.json`.

**Demos as GIFs.** `./Start-Polf3D.ps1 -ExportGif <demo.json>` plays a demo back without a window and saves it as an
animated GIF – `-GifStart` and `-GifSeconds` choose the part (default: the first twelve seconds), `-GifScale 2` doubles
the pixels, `-GifPath` says where. Windows reduces the colours (one palette for the whole clip, so nothing flickers),
PowerShell stitches the frames together. The clip at the top of this page was made that way.

## Music

Every track is composed in code and rendered once: a solemn **anthem** that plays only on the title screen, then
one style per floor – **rock** for the dungeon, a **march** for the barracks, a **creepy drone with far-away bells**
for the catacombs, **techno** for the lab, a **galloping finale** in harmonic minor for the citadel and a carefree
ditty for the treasury. The second half picks what suits it – techno for the data centre, the drone for the archive,
rock for the foundry, the march for the executive floor, the finale for Ring 0 – transposed and with melodies of
their own. And there is one more piece, which you will only hear once you have finished the game.
`F4` or `-NoMusic` turns it off.

Sound and music go through a small software mixer on `waveOut` ([src/Mixer.cs](src/Mixer.cs)): many sounds at once,
each placed left or right of you and quieter with distance, and music that loops without a gap. The volumes are in
the options menu.

## Mods

Every `mods/*.psd1` is read with `Import-PowerShellDataFile` – which cannot run code – and merged into the game's
tables before anything is painted, spoken or composed. Because all art is generated, **a new enemy needs no picture,
only a palette**:

```powershell
@{
    Name     = 'Purple interns'
    Enemies  = @{ intern = @{ BasedOn = 'guard'; HP = 8, 10, 12, 12; Points = 50; Code = 'i'; Replaces = 'guard'; Share = 0.33 } }
    Palettes = @{ intern = @{ Uniform = '7A3AA8'; UniformDark = '5A2A80'; Hair = 'D8B040'; HatStyle = 'none' } }
    Voices   = @{ intern = 'It works on my machine!', 'Is this production?'; 'intern.die' = 'I will put it in a ticket.' }
    Weapons  = @{ pistol = @{ Name = 'Service pistol' } }
}
```

That is [mods/examples/purple-interns.psd1](mods/examples/purple-interns.psd1): copy it one folder up and a third of
all guards turn into chatty interns in purple hoodies. Mods can also change any field of the existing enemies, the
difficulty table and the music styles (tempo, key, scale, chords); see [src/Mods.ps1](src/Mods.ps1). Demos remember
the mods they were recorded with, and `-VerifyDemo` insists on the same ones. `-NoMods` ignores the folder.

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
./Start-Polf3D.ps1 -Scale 4        # window size: 2..5 times 320x240 (default: what the options menu says, 3 at first)
./Start-Polf3D.ps1 -Columns 160    # half the number of rays, for slow machines
./Start-Polf3D.ps1 -FlatFloors     # plain floors and ceilings (the 1992 look, a little faster)
./Start-Polf3D.ps1 -Difficulty 4   # preselect the difficulty (1..4)
./Start-Polf3D.ps1 -Level 4        # start the campaign on floor 4
./Start-Polf3D.ps1 -Map ./maps/mine.map   # play just this one map
./Start-Polf3D.ps1 -Speedrun       # show the speedrun clock
./Start-Polf3D.ps1 -NoSound -NoMusic -NoVoices -NoGamepad -NoMods
./Start-Polf3D.ps1 -HostGame Coop  # network game, see above (-JoinGame <host>, -Port, -MaxPlayers, -PlayerName)
./Start-Polf3D.ps1 -Daily          # today's dungeon (-Dungeon <number> for any other)
./Start-Polf3D.ps1 -Tutorial       # the onboarding: every mechanism explained, one room at a time
./Start-Polf3D.ps1 -Horde          # the arena with today's waves (-HordeNumber <number> for any other)
./Start-Polf3D.ps1 -ExportGif <file>    # a demo as an animated GIF (-GifPath, -GifStart, -GifSeconds, -GifScale)
./Start-Polf3D.ps1 -VerifyDemo <file>   # is this demo genuine, and how long did the run take?
./Start-Polf3D.ps1 -Terminal       # no window: play in the terminal (-TerminalKeys over SSH)
./Start-Polf3D.ps1 -Version        # which version is this?
./Start-Polf3D.ps1 -Update         # fetch and install the latest release (-NoUpdateCheck: never ask GitHub)
```

`Get-Help ./Start-Polf3D.ps1 -Full` lists everything.

## How it works

| File | Purpose |
|---|---|
| [Start-Polf3D.ps1](Start-Polf3D.ps1) | parameters, loading the modules, compiling the C# (DLL cache in `bin/`), start |
| [src/Defs.ps1](src/Defs.ps1) | constants, the classes `Actor`/`Door`/`Static`, tables for enemies, states, weapons, items |
| [src/Assets.Gfx.ps1](src/Assets.Gfx.ps1) | procedural textures, flats and sprites |
| [src/Assets.Sfx.ps1](src/Assets.Sfx.ps1) | sound synthesis; playing a sound at a place in the world |
| [src/Voices.ps1](src/Voices.ps1) | the enemies' lines, spoken once by Windows' speech synthesiser (SAPI through COM) and cached |
| [src/Music.ps1](src/Music.ps1) | the composer: styles, melodies written as text, wave patterns, SIMD mixing, WAV cache |
| [src/Map.ps1](src/Map.ps1) | loads the text map, finds rooms ("areas") by flood fill, places things |
| [src/Doors.ps1](src/Doors.ps1) | doors, levers, the area graph for sound and sight, push-walls |
| [src/Mechanics.ps1](src/Mechanics.ps1) | traps and teleporters |
| [src/Actors.ps1](src/Actors.ps1) | line of sight, perception, grid movement, think/action routines, projectiles, explosions, damage |
| [src/Player.ps1](src/Player.ps1) | movement with wall sliding, use, weapons, items, cheats |
| [src/Render.ps1](src/Render.ps1) | ray caster, floor casting, fog, windows, sprite projection, HUD, overlays, automap, radar |
| [src/Game.ps1](src/Game.ps1) | window, keyboard/mouse/game pad, game modes, main loop, screens |
| [src/Mods.ps1](src/Mods.ps1) | merges `mods/*.psd1` into the tables |
| [src/SaveGame.ps1](src/SaveGame.ps1) | saved games as JSON, speedrun records, high score list |
| [src/Transcript.ps1](src/Transcript.ps1) | the transcript of a floor and its verdict |
| [src/Achievements.ps1](src/Achievements.ps1) | every floor as a test suite: the ten tests, what has been passed, the Pester-style report |
| [src/Settings.ps1](src/Settings.ps1) | the options menu, the key bindings, `saves/settings.json` |
| [src/GifExport.ps1](src/GifExport.ps1) | a demo as an animated GIF |
| [src/Demo.ps1](src/Demo.ps1) | demo recording and playback, the bot that records the attract demo |
| [src/Tutorial.ps1](src/Tutorial.ps1) | the onboarding floor, and the hints any map can use |
| [src/Horde.ps1](src/Horde.ps1) | the arena: waves from a number, supplies, the list of runs |
| [src/Dungeon.ps1](src/Dungeon.ps1) | the dungeon generator, its records, and the demo verifier |
| [src/Network.ps1](src/Network.ps1) | network games: connections, protocol, relay, snapshots, the "peer context", the host's admin panel and ban list |
| [src/Events.ps1](src/Events.ps1) | what a floor has scheduled: lockdown, power failure, Patch Tuesday |
| [src/Policy.ps1](src/Policy.ps1) | the building's execution policy: the alarm level of a floor |
| [src/Loot.ps1](src/Loot.ps1) | loot tables, armour, keycards, scrap, signed drops, the silent streak |
| [src/Perks.ps1](src/Perks.ps1) | `Install-Module`: the perks offered between the floors |
| [src/Abilities.ps1](src/Abilities.ps1) | privilege, the five powers, in-memory world snapshots, the `-WhatIf` forecast |
| [src/Story.ps1](src/Story.ps1) | the files on the terminals, and what their codes and tokens do |
| [src/Console.ps1](src/Console.ps1) | the sandboxed runspace, the game's cmdlets, pricing and carrying out requests, the profile and the hotkeys |
| [src/Ending.ps1](src/Ending.ps1) | what happens after the last floor (spoilers) |
| [src/Terminal.ps1](src/Terminal.ps1) | terminal mode: keys, text screens, presenting a frame |
| [src/Scaler.cs](src/Scaler.cs), [src/Mixer.cs](src/Mixer.cs), [src/Gamepad.cs](src/Gamepad.cs), [src/Terminal.cs](src/Terminal.cs) | **the only C#**: the pixel loops (screen and terminal), the audio callback, XInput and keyboard state declarations. Compiled once, then loaded from `bin/` |
| [src/SelfTest.ps1](src/SelfTest.ps1) | headless tests and the screenshots for this README |
| [tools/New-Release.ps1](tools/New-Release.ps1) | builds `polf3d.zip` from the committed state and, with `-Publish`, the GitHub release |

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
* **Snapshots and the forecast:** saved games go through JSON, which is far too slow to do twice a second. Undo and
  `-WhatIf` use a second kind of snapshot: arrays are cloned, living actors copied field by field, the dead shared.
  That costs a few milliseconds. The forecast swaps in a throw-away random generator, mutes sound, messages and damage,
  runs doors and actors ahead for two seconds, notes where everybody went and who reached a firing state, and restores.
* **The console's sandbox:** the cmdlets inside cannot touch the game at all. `Get-Enemy` returns copies made when the
  line is run; `Stop-Enemy` merely *outputs* a request object. The game picks requests out of the pipeline's output,
  prices them and carries them out – which is also how `-WhatIf` on them comes for free.
* **Sprite order:** `[Array]::Sort(keys, items)` called from PowerShell sorts the keys and leaves an `object[]` of items
  alone – for a long time every enemy was drawn over every column. The sprites are now sorted through an index array,
  and a self-test puts a guard behind a column to make sure.
* **Network:** a star. The host owns the world and sends every guest what has changed, twenty times a second, as
  lines of text over TCP; a guest simulates only its own player and *asks* the host for everything else ("I hit actor
  17 for 23", "use the tile in front of me", "I hit player 2"), and the host passes on what the others need to know.
  For the enemies to fight several players, the host swaps one remote player in as "the player" for the duration of
  one actor's update – all the existing AI code then simply means that guest.
* **Music:** a note is one short wave pattern copied over and over with `Buffer.BlockCopy`; the six channels are added
  up with `System.Numerics.Vector`, sixteen samples at a time. Half a minute of music renders in under a second.
* **Presentation:** `int[]` frame buffer → bitmap → `BufferedGraphics`. Its GDI blit is about six times faster than
  drawing a GDI+ bitmap straight to the window – the difference between 30 and 55 fps.
* **One place for the state of a floor:** the execution policy's heat, which scheduled events have fired, how long the
  power stays out, how long the controls hang, what a wave still has to send, what the drone carries – all of it lives
  in the floor's statistics table, as numbers or as arrays that are replaced rather than changed. That table is what
  saved games write and what Undo and the `-WhatIf` forecast copy, so every new mechanism is undone, forecast and
  saved correctly without knowing about any of them.
* **Darkness is fog.** A dark room multiplies the distance haze and pulls its colour to black; a shot takes most of it
  away for a few frames. The flashlight is an array with one factor per screen column – a bell curve around the
  middle – that the wall, sprite and floor code multiply into their fog value.
* **The GIF encoder** lets Windows do the two expensive things – a median cut palette over a sheet of frames from all
  over the clip, and LZW – by encoding every frame as a GIF of its own, and then does what Windows cannot: it cuts the
  frame out of each of those files and writes them one after the other, with a loop block in front and a delay
  before each.
* **Approved verbs:** every function, including every internal helper, uses a verb from `Get-Verb`;
  [tools/Test-Verbs.ps1](tools/Test-Verbs.ps1) checks that via the AST.

## Building your own levels

```powershell
./tools/Edit-Level.ps1 ./maps/level1.map   # the point-and-click editor: paint, validate, play
```

Every `maps/level<N>.map` is a text file; the campaign simply consists of all of them in numerical order – a
`level11.map` automatically becomes floor 11 (and the ending moves there with it), `bonus<N>.map` is where the secret
lift switch of floor N leads, `arena.map` is the arena and `tutorial.map` the onboarding.
After the header the grid follows `@map`, **every cell two characters wide**.

Header: `@name`, `@par <seconds>`, `@ceiling <RRGGBB>`, `@floor <RRGGBB>`, optionally `@floortex` / `@ceiltex`
(`flat_stone flat_wood flat_moss flat_tech flat_carpet` / `ceil_plain ceil_rock ceil_tech`), `@fog <RRGGBB> <tiles>`
and any number of these:

| Header line | Meaning |
|---|---|
| `@spawn <min. difficulty> <x> <y> <enemy code>` | reinforcements that only show up from that difficulty on |
| `@dark <x> <y>` | the room this tile is in has no light |
| `@event lockdown\|powerfail\|patch <seconds>` | something the floor has scheduled |
| `@horde <x> <y>` | a tile the waves of the arena come from |
| `@hint <x> <y> <width> <height> <text>` | an explanation, shown when the player first stands in that rectangle |

The editor keeps these lines as they are; they are edited as text.

| Code | Meaning |
|---|---|
| `SS Sb Sp` `BB Bc` `WW Wp Ws` `RR Rb` `MM` | walls: stone, blue stone, wood, brick, steel (+ decorated variants) |
| `GG Gv` `TT Tl` | mossy rock (+ vines), tech panels (+ console) |
| `St Bt Wt Rt Mt Gt Tt` · `Sh Wh Rh` · `Me Te` · `Mn Tn` · `Sg Rg` | PowerShell on the wall: console · `Get-Help` poster · error screen · neon `>_` · graffiti (first letter = wall type) |
| `MX` / `MY` | lift switch (the exit) / secret lift switch (to the bonus floor) |
| `?S ?s ?B ?b ?W ?w ?R ?r ?M ?G ?g ?T ?t` | secret push-wall (upper case plain, lower case decorated) |
| `!S !B !W !R !M !G !T` | cracked wall – only an explosion brings it down |
| `=S =B =W =R =M =G =T` | window |
| `DD DG DS DL` | door: normal / gold lock / silver lock / lift door – the orientation is detected from the neighbouring walls |
| `D1`–`D9`, `X1`–`X9` | lever door and the wall lever that opens it |
| `..` | floor |
| `P^ P> Pv P<` | player start and view direction |
| `g d e o m s h k b u` + direction | guard, dog, elite, officer, mutant, sniper, shield bearer, kamikaze bot, commander, war machine |
| `y n a` + direction | bug, engineer, auditor |
| `x` + direction | BLUE SCREEN |
| `c t` + `n e s w` | security camera, sentry gun (they only ever see, so always the "deaf" letters; floors 6–10 have them) |
| direction `^ > v <` / `n e s w` / `N E S W` | standing / standing and "deaf" (ambush, reacts to sight only) / patrolling |
| `:^ :> :v :<` | waypoint: patrols turn here |
| `~s ~c` | trap: spikes, crusher |
| `@1`–`@9` | teleporter pad (two pads with the same number form a pair) |
| `+d +f +h` `+a +o +z` `+m +c +p +r +l +t +j` `+g +s` `+1 +2 +3 +4` `+u +q` `+v +i +b +k` | dog food, food, first aid · clip, rockets, Force charge · machine gun, chain gun, Pipeline Cannon, Force Blaster, rocket launcher, flamethrower, throwing knives · keys · treasures · extra life, SUDO · taser, mines, armoured vest, keycard |
| `*l *h *L *t *b *p *a *c *f *x *v *s *u *k *B *m *g` `*e` | decoration: ceiling lamp, chandelier, floor lamp, table, barrel, plant, suit of armour, column, flag, crates, vat, bones, puddle, dead guard, bed, console, stalagmite · **explosive barrel** |
| `*r *T` | server rack and desk with a CRT (both open the console when "used") |

The bundled maps – ten floors, the treasury and the arena – are generated by [tools/New-Levels.ps1](tools/New-Levels.ps1)
from room lists: rooms are rectangles carved out of solid rock; where they touch they merge into corridors and caves.
Shelves and the free-standing lift shaft of Ring 0 are blocks put back into a room. They are decorated with PowerShell
scenery by position, so they come out the same every time. The game only ever reads the `.map`
files, though, so you can just as well edit them by hand or in [the editor](tools/Edit-Level.ps1). Validate
([tools/Test-Level.ps1](tools/Test-Level.ps1)) and play:

```powershell
./tools/Test-Level.ps1 -Map ./maps/mine.map    # border closed? everything reachable? keys, levers, teleporter pairs? patrol routes clear?
./Start-Polf3D.ps1 -Map ./maps/mine.map
```

## Tests

```powershell
./Start-Polf3D.ps1 -SelfTest   # headless: renders PNGs into ./selftest and tests combat, stealth, weapons, machinery,
                               # bosses, saved games, demo determinism, the network protocol (a host with two
                               # guests, relay, kick and ban; a guest among three players - over loopback), sprite order, the face, snapshots and every power, the console (which
                               # tries three ways to delete a canary file), dungeons (valid, reproducible, a run
                               # verifies, a doctored one does not), terminal frames, transcripts, the example mod,
                               # the mixer and the music, the options, the files on the terminals, the console's
                               # profile and hotkeys (with a canary of its own), the execution policy, cameras and
                               # sentry guns, the drone, the modules, darkness and the flashlight, the paper jam and
                               # BLUE SCREEN, the floors' schedules, the arena, loot and the commander's key, the
                               # bug, the engineer and the auditor, taser and mine, the floor tests, the ending and the
                               # GIF encoder (read back by GDI+) - plus a soak test of every floor that fights every boss
./tools/Test-Level.ps1         # validates all maps and prints an overview of each
./tools/Test-Verbs.ps1         # every function uses an approved verb
./Start-Polf3D.ps1 -BalanceTest 1   # a bot plays floor 1 on every difficulty and duels its bosses: who wins how often?
```

## Origin and scope

POLF 3D is **neither a clone nor a port**. The source code of the 1992 grandfather of the genre, later released by
id Software, was first analysed and described *in our own words* – how the code is structured and how levels, enemies,
weapons, items and doors work. Only from that description was the game written anew. What was adopted are concepts and
game mechanics; **nothing** of the original is contained in this repository: own code, own levels, own names, own
procedurally generated graphics, sounds, speech and music – and the `>_` prompt as a coat of arms.

It is a fun project, and the question behind it is how far PowerShell can be pushed. How it came about and why it grew
the way it did is written down in [HOW-IT-WAS-BUILT.md](HOW-IT-WAS-BUILT.md).

## License

Copyright © 2026 oNdsen. Released under the [MIT License](LICENSE) – code, maps and the procedurally generated
graphics, sounds and music. Use it, change it and pass it on, as long as the copyright notice stays in place.
