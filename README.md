<h1 align="center">POLF 3D &nbsp;<code>&gt;_</code></h1>

<p align="center"><b>A 90s-style ray casting shooter – written in PowerShell.</b><br>
<i>A real PowerShell console inside the game, <code>-WhatIf</code>, <code>-Confirm</code> and <code>-Force</code> as powers, a daily dungeon with
verifiable runs,<br>ten floors, a secret one and an ending worth playing for, eleven kinds of enemies, nine weapons, co-op and deathmatch for up to four over the network, a terminal
mode –<br>procedurally generated graphics, sound, speech and music, and under 400 lines of C#.</i></p>

<p align="center"><img src="media/banner.png" alt="POLF 3D - the war machine opens fire" width="900"></p>

```powershell
git clone https://github.com/oNdsen/polf3d.git
cd polf3d
./Start-Polf3D.ps1
```

Requirements: **Windows** and **PowerShell 7.2+**. Nothing else – no modules, no asset files, no installation.
On first start the four small C# files ([src/Scaler.cs](src/Scaler.cs), [src/Mixer.cs](src/Mixer.cs),
[src/Gamepad.cs](src/Gamepad.cs), [src/Terminal.cs](src/Terminal.cs)) are compiled once into `bin/` - every later start
just loads the DLLs, until a source file changes; the music and the enemies' spoken lines are
composed, spoken and cached there the first time they are needed.

---

## Contents

- [What is this?](#what-is-this)
- [Screenshots](#screenshots)
- [Controls](#controls)
- [The campaign](#the-campaign)
- [Enemies, weapons, items](#enemies-weapons-items)
- [PowerShell is the point](#powershell-is-the-point)
- [The daily dungeon](#the-daily-dungeon)
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
sliding doors, keys, levers, traps, teleporters, secret push-walls, enemy AI, bosses, saved games, demos, a level
editor and a two-player network mode – and almost all of it is **plain PowerShell**: game logic, AI, ray casting,
map format, HUD, menus, music, network protocol.

* **PowerShell is not just the language, it is the theme.** A sandboxed but real PowerShell console is part of the
  game, the special powers are PowerShell's common parameters, the walls are full of consoles and error screens, the
  final boss is a printer, and every floor ends with a transcript.
* **No asset files.** All wall and floor textures, about 380 sprite images, 40 sound effects and the whole soundtrack
  are generated procedurally (GDI+ primitives, a 3×5 pixel font, a tiny square/saw/noise synthesiser and a chiptune
  composer); the enemies' lines are spoken by Windows' own speech synthesiser. That is also why a [mod](#mods) can add
  an enemy with ten lines of data.
* **As little C# as possible:** the innermost pixel loops (scale one wall strip, draw one sprite, fill one floor row,
  turn a frame into terminal characters) and two P/Invoke declarations (game pad, keyboard state). PowerShell cannot
  push 64,000 pixels per frame – but it handles the 320 rays per frame with ease.
* **50–60 fps** in a 960×720 window on an ordinary office laptop.

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
| Floor 6: a cold aisle of the data centre – there is a sniper at the far end of every one | Floor 10: the core of Ring 0. The last commander is expecting you |
| ![A floor's tests](media/tests.png) | ![The player list](media/players.png) |
| Every floor is a test suite, and Pester reports: a pacifist run through the catacombs | `F1` in a network game: on the host it is an admin panel – `K` kicks, `B` bans, `U` lifts a ban |

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
| `1`–`9` | weapons (see below) |
| `Z` `X` `V` `F` `R` | the powers: `-WhatIf`, `-Confirm`, `-Verbose`, `-Force`, Undo (see [below](#powershell-is-the-point)) |
| `T`, `Tab` | the PowerShell console – or "use" a terminal or a server rack |
| `G` `H` `B` `Y` | the four console hotkeys: whatever command line you put on them with `Set-Hotkey` |
| `M` (hold) / `N` | automap / radar minimap on and off |
| `F2` / `F3` / `F4` | mouse look / fps display / music on and off |
| `F5` / `F9` | quick save / quick load |
| `F12` | record a demo (press again to stop and save) |
| `P`, `Esc` | pause: `1`–`3` save to a slot, `L` load, `Q` main menu |
| `G` (title screen) | today's dungeon |
| `O` (title screen, pause) | options: mouse sensitivity, volumes, radar, fps, floors, window size – **and every key above** |
| `F1` (network games) | the player list – on the host with kick and ban |

**Game pad (XInput):** left stick move and strafe, right stick turn, `RT` fire, `LT` run, `A` use, `B` sneak,
`LB`/`RB` previous/next weapon, `X` `-Confirm`, `Y` minimap, `Back` automap, `Start` pause. D-pad and `A` work in the menus.

The status bar shows floor, score, lives, health, ammunition for the weapon in hand, the weapons you own and your
keys – and **the admin on call**: he collects a new layer of damage every 20 health, winces at every hit and then
looks towards whoever fired, grins over a new weapon, grits his teeth while you hold the trigger, squints when
sneaking and wears shades during SUDO. Above it: floor progress (kills, secrets, treasures), a three-step **noise meter**, `?` and `!` above enemies
who have noticed something or are coming for you, and the radar with alerted enemies as red dots.

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
| 6 | The Data Centre | 44 / ~4100 | Six cold aisles between two cross corridors: snipers at the far ends, windows in the rack rows, a commander in the silver cage |
| 7 | The Archive | 46 / ~3700 | Two halls of shelves to get lost in, with things waiting between them. Four secrets – the microfiche knows them all |
| 8 | The Foundry | 35 / ~5500 | A production line: a conveyor with three crushers and a gate, three levers – and THE PRINTER in the assembly hall |
| 9 | The Executive Floor | 46 / ~7000 | Carpet and plants. A gallery of offices, the board (two commanders) behind the silver door, and a CEO who keeps a printer |
| 10 | Ring 0 | 47 / ~8800 | Two rings around the core. Patrols outside, levers for the gates, and in the core two printers, the last commander – and the lift in the middle of it |

**Every floor is a test suite.** When you throw the lift switch the run is put through ten tests and the result is
printed the way Pester prints it – `[+] beats the par time 24ms`, `[-] fires no gun (blades are fine) 19ms` – on the
completion screen, in terminal mode and in the transcript. Reaching the lift, par time, all kills, all secrets, all
treasure, noticed by nobody, no guns, never below 50 health, no powers and no console, no cheats: what has been passed
once stays passed (`saves/achievements.json`), and the title screen counts them – there are a hundred to get.

**It is worth finishing.** Whoever throws the last switch on floor 10 gets a proper ending, with a piece of music
written for it. There is no picture of it here, on purpose: it has to be earned.

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
| Commander – *LEGACY.BAT* | 350–1200 | "runs as SYSTEM, nobody dares to touch it". Twin machine guns: three rounds per salvo, then a pause – that is your moment. Drops the gold key |
| War machine – *THE PRINTER* | 550–1800 | "PC LOAD LETTER". Super boss: gun bursts and salvos of three rockets (real projectiles with splash damage – pillars give cover) |
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

The guns share one kind of ammunition (99 rounds at most); rockets, knives and Force charges are counted separately.
When a weapon runs dry you automatically draw the best one that still works.

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
Get-Trap | Disable-Trap ;  Get-Loot -Name key* ;  Get-Secret ;  Get-Player ;  Get-Help
```

Logging on at one of the terminals or server racks in the levels ("use") opens the same console and grants 30
privilege once. **Those terminals have files** – `Get-ChildItem`, `Get-Content mail-0412.eml` – and the files tell
what happened at Shellstein, floor by floor: tickets nobody could close, a duty roster, the minutes of the board. Some
of them give things away: `Unlock-Door -Code 4711` opens what the mail says it opens, `Use-Token NIGHTSHIFT` marks the
floor's secrets on the automap. A code works once per floor.

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

**The building has an execution policy** – how nervous the whole floor is, shown next to the noise meter. Being seen
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
floor is being played waits in the lobby and is in from the next floor. Every player wears the colour of his slot:
orange (the host), green, purple, yellow.

* **Co-op:** the whole campaign together. Enemies go for whoever is nearest, keys are shared, anybody can call the
  lift, partners are blue dots on the radar and their health is shown in the view. No lives: whoever dies is back at
  the start of the floor a moment later with the basic kit, and the floor goes on. Friendly bullets do nothing –
  friendly rockets do.
* **Deathmatch** (`Duel` is the same thing for two): the same floors without monsters. Everybody starts with a machine
  gun, weapons and items come back after 25 seconds, the dead respawn as far from everybody else as possible, the
  host keeps the frag count and everybody sees it; the lift switch ends the round.

**The host is the admin.** `F1` opens the player list – slot, name, address, state, frags. `K` kicks the selected
player, `B` bans him: he is thrown out and his address is turned away from then on (the list is kept in
`saves/banned.json`), `U` lifts a ban. A guest who was kicked, banned or found the game full is told why and does not
keep knocking. Guests see the same list without the buttons. If a guest leaves or loses the connection the floor
simply goes on without him; if the host leaves, everybody is back at the title screen.

All computers need the same maps (the game warns if they differ). Saving, loading, demos, the console and the
time-bending powers are switched off in a network game (`-Verbose` works), and menus do not stop the world.

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
./Start-Polf3D.ps1 -Scale 4        # window size: 2..5 times 320x240 (default 3)
./Start-Polf3D.ps1 -Columns 160    # half the number of rays, for slow machines
./Start-Polf3D.ps1 -FlatFloors     # plain floors and ceilings (the 1992 look, a little faster)
./Start-Polf3D.ps1 -Difficulty 4   # preselect the difficulty (1..4)
./Start-Polf3D.ps1 -Level 4        # start the campaign on floor 4
./Start-Polf3D.ps1 -Map ./maps/mine.map   # play just this one map
./Start-Polf3D.ps1 -Speedrun       # show the speedrun clock
./Start-Polf3D.ps1 -NoSound -NoMusic -NoVoices -NoGamepad -NoMods
./Start-Polf3D.ps1 -HostGame Coop  # network game, see above (-JoinGame <host>, -Port, -MaxPlayers, -PlayerName)
./Start-Polf3D.ps1 -Daily          # today's dungeon (-Dungeon <number> for any other)
./Start-Polf3D.ps1 -VerifyDemo <file>   # is this demo genuine, and how long did the run take?
./Start-Polf3D.ps1 -Terminal       # no window: play in the terminal (-TerminalKeys over SSH)
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
| [src/Demo.ps1](src/Demo.ps1) | demo recording and playback, the bot that records the attract demo |
| [src/Dungeon.ps1](src/Dungeon.ps1) | the dungeon generator, its records, and the demo verifier |
| [src/Network.ps1](src/Network.ps1) | network games: connections, protocol, relay, snapshots, the "peer context", the host's admin panel and ban list |
| [src/Policy.ps1](src/Policy.ps1) | the building's execution policy: the alarm level of a floor |
| [src/Abilities.ps1](src/Abilities.ps1) | privilege, the five powers, in-memory world snapshots, the `-WhatIf` forecast |
| [src/Story.ps1](src/Story.ps1) | the files on the terminals, and what their codes and tokens do |
| [src/Console.ps1](src/Console.ps1) | the sandboxed runspace, the game's cmdlets, pricing and carrying out requests, the profile and the hotkeys |
| [src/Ending.ps1](src/Ending.ps1) | what happens after the last floor (spoilers) |
| [src/Terminal.ps1](src/Terminal.ps1) | terminal mode: keys, text screens, presenting a frame |
| [src/Scaler.cs](src/Scaler.cs), [src/Mixer.cs](src/Mixer.cs), [src/Gamepad.cs](src/Gamepad.cs), [src/Terminal.cs](src/Terminal.cs) | **the only C#**: the pixel loops (screen and terminal), the audio callback, XInput and keyboard state declarations. Compiled once, then loaded from `bin/` |
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
| direction `^ > v <` / `n e s w` / `N E S W` | standing / standing and "deaf" (ambush, reacts to sight only) / patrolling |
| `:^ :> :v :<` | waypoint: patrols turn here |
| `~s ~c` | trap: spikes, crusher |
| `@1`–`@9` | teleporter pad (two pads with the same number form a pair) |
| `+d +f +h` `+a +o +z` `+m +c +p +r +l +t +j` `+g +s` `+1 +2 +3 +4` `+u +q` | dog food, food, first aid · clip, rockets, Force charge · machine gun, chain gun, Pipeline Cannon, Force Blaster, rocket launcher, flamethrower, throwing knives · keys · treasures · extra life, SUDO |
| `*l *h *L *t *b *p *a *c *f *x *v *s *u *k *B *m *g` `*e` | decoration: ceiling lamp, chandelier, floor lamp, table, barrel, plant, suit of armour, column, flag, crates, vat, bones, puddle, dead guard, bed, console, stalagmite · **explosive barrel** |
| `*r *T` | server rack and desk with a CRT (both open the console when "used") |

The bundled maps are generated by [tools/New-Levels.ps1](tools/New-Levels.ps1) from room lists – rooms are rectangles
carved out of solid rock; where they touch they merge into corridors and caves – and decorated with PowerShell
scenery by position, so they come out the same every time. The game only ever reads the `.map`
files, though, so you can just as well edit them by hand or in the editor. Validate and play:

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
                               # verifies, a doctored one does not), terminal frames, transcripts, the example mod
                               # and the music - plus a soak test of every floor that fights every boss
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

## License

Copyright © 2026 oNdsen. Released under the [MIT License](LICENSE) – code, maps and the procedurally generated
graphics, sounds and music. Use it, change it and pass it on, as long as the copyright notice stays in place.
