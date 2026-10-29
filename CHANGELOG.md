# Changelog

Fixes and balance raise the last number, new features and floors the middle one.

## 1.3.3 - 2026-10-29

The game fetches this one itself: `[U]` on the title screen. Or download `polf3d.zip` below, unpack it and start
`Play.cmd` (Windows, PowerShell 7.2 or newer – nothing else).

Fixed:

* **The console sandbox is sealed.** Constrained language mode still let `[xml]` through, and with it the console could
  read and write any file the player may touch, from a typed line or from `saves/profile.ps1`. Every line is now
  checked before it runs, statement by statement: types only from a short list of harmless ones, and none of the ways
  that turn text into code. A profile with one refused line still defines the rest.
* **A doctored demo no longer verifies.** One frame with negative time took minutes off a dungeon time and still came
  out VALID, and one huge frame hung the verifier. Every value of a demo is now checked against what the game itself
  can record before it is played.
* **The game starts from any folder.** An apostrophe, brackets, an `&` or a `^` in the path of the game folder kept it
  from starting, from caching its helpers or from restarting after an update, and a folder nobody may write to (one
  under Program Files) stopped it at once. The caches move to the temp folder when they have to.
* Closing the window while the game was loading left it running without a window. It ends now.
* An empty `achievements.json` or `dungeon.json` crashed the next floor completed, and a hand-edited `settings.json`
  could keep the game from starting.

Changed:

* Every push is tested on GitHub: the self-test, the map validator, the verb check and the attract demo, with the
  newest PowerShell and with 7.2.

## 1.3.2 - 2026-10-14

The game fetches this one itself: `[U]` on the title screen. Or download `polf3d.zip` below, unpack it and start
`Play.cmd` (Windows, PowerShell 7.2 or newer – nothing else).

Fixed:

* **A guest can no longer crash a network game.** One malformed line from a guest, a coordinate of `NaN` for example,
  ended the game for everybody. The host now checks what guests send: positions have to be real numbers on the map,
  and hits, frags, door use and pickups have to be within reach and in sight. By Ben Richards
  ([@The-Running-Dev](https://github.com/The-Running-Dev)), thank you. The checks leave half a tile of room for lag,
  so that a real network does not make a guest miss what loopback lets them hit.
* **Co-op with one guest** put that guest inside the top wall of the map. Two or three guests were fine.
* **`-NoSound` and `-NoMusic` work again.** Since 1.3.1 they did nothing, and the self-test and the other modes without
  a window played the whole game out loud.
* **A lockdown cut rooms off.** It closed doors that were already closed, and from then on the rooms behind such a door
  stayed apart even with the door open: enemies there neither saw nor heard anything, and nobody could shoot through.
  A door kicked in with `-Force` had the same effect once it shut again. Floors 7 to 10 have lockdowns.
* `Receive-Job` with the drone in view ended the game.
* A guest printed `True` about twenty times a second into the PowerShell window.

## 1.3.1 - 2026-09-27

The game fetches this one itself: `[U]` on the title screen. Or download `polf3d.zip` below, unpack it and start
`Play.cmd` (Windows, PowerShell 7.2 or newer – nothing else).

Changed:

* **The weapons are drawn in perspective.** Each one is a small model of boxes in metres from the eye, projected with
  the game's own lens: the barrel runs towards the crosshair, the top shows as a narrow lit strip, round parts are
  shaded, and the recoil is the model moving back. No more weapons aimed at the ceiling that hide half the view.
* **The game runs without a console window.** `Play.cmd` starts it under a headless console host and is gone at once;
  should the game not start, the reason comes up in a dialog. `-Terminal` keeps its console, it plays there.
* **The window comes first** and shows the start-up: every step with a percentage of its own and a bar with the total.
  Only the modules the window needs load before it, so it is up after half a second instead of two.
* A crossed-out speaker under the noise bars and on the title screen says when the music (F4) or the sound is off.
  A track that fails to start says why in the game and is tried again, instead of silencing the music for good.
* The noise bars moved to the top left, under the policy label, out of the weapon's way.

Fixed:

* A rocket that hit a wall lost half its explosion to the wall behind it; explosions and sparks stay whole now, and
  the flamethrower no longer burns behind a wall it is pointed at.
* A locked door is locked for the enemies too: nobody opens the silver door from the far side any more. A thrown
  knife goes through the bars of a window, as a bullet does.
* After an update the old builds of the C# helpers and the music of an older composer stayed in `bin/`; every start
  sweeps them once the current ones are loaded, and the restart waits for the old game to close first.

## 1.3.0 - 2026-09-25

**Download `polf3d.zip` below, unpack it and start `Play.cmd`** (Windows, PowerShell 7.2 or newer – nothing else).
This is the last version you have to fetch by hand: from now on the game updates itself.

New:

* **The game updates itself.** Once a day the title screen asks GitHub for a newer release – one request, in the
  background, and the options menu or `-NoUpdateCheck` turns it off. When there is one, a line on the title screen says
  so, `U` shows what is new, and Enter downloads `polf3d.zip`, checks its SHA256 against the release notes, keeps the
  files it replaces in `polf3d-backup-<version>.zip` next to the game, installs and restarts. Saved games, settings and
  your own mods stay. `./Start-Polf3D.ps1 -Update` does the same from the command line, and `Update-Module polf3d`
  asks the console.
* **`Play.cmd`** is now a launcher that is gone the moment the game runs, so that an update may replace it too. Should
  the game not start, PowerShell keeps the window and the reason on the screen.
* The keys of the title menu stand in brackets: `[Enter]`, `[G]`, `[U]` ...
* The story of the project, and what it is really about: [HOW-IT-WAS-BUILT.md](HOW-IT-WAS-BUILT.md).

Fixed – the first three by Ben Richards ([@The-Running-Dev](https://github.com/The-Running-Dev)), thank you:

* A map row with an odd number of characters is rejected instead of silently losing its last one.
* A mod whose later section is malformed no longer leaves its earlier sections half installed.
* A saved game is checked in full before a single thing of the running game is replaced: a damaged or foreign file is
  refused and the game goes on.
* The pause menu let you save in the arena and in the onboarding; such a game could never be loaded. There is no
  saving there now.
* Demos and dungeon records name the version that made them. A demo from an older version is reported as such –
  "recorded with POLF 3D 1.2.0, this is 1.3.0" – instead of as doctored.
* A machine managed by an organisation gets a plain answer: the start script checks PowerShell's language mode
  (AppLocker, WDAC) and says what that means, and `Play.cmd` explains an execution policy set by Group Policy.
* A guest takes the host's bonus map as a name, never as a path.

## 1.2.0 - 2026-09-21

**Download `polf3d.zip` below, unpack it and start `Play.cmd`** (Windows, PowerShell 7.2 or newer – nothing else).

All three points come from a first player's feedback – thank you.

New:

* **The onboarding** (`N` on the title screen, or `-Tutorial`): a floor of ten rooms, each explaining one mechanism and
  offering what it takes to try it – from doors and sneaking to the powers, the console, sentry guns, darkness and
  loot. The explaining is done by hints, which any map can use: `@hint <x> <y> <width> <height> <text>`.
* **Tab completion in the console:** commands, aliases and parameters – and what only the game can know: the kinds of
  enemies on the floor, the files of the terminal, the properties of whatever comes down the pipeline. Tab again takes
  the next candidate. Tab therefore no longer closes the console; `Esc` does.
* **The commands people type by instinct:** `Get-Door | Set-Door -Open $true` and `Get-Process | Stop-Process` now do
  what one would guess.

## 1.1.1 - 2026-09-21

**Download `polf3d.zip` below, unpack it and start `Play.cmd`** (Windows, PowerShell 7.2 or newer – nothing else).

Fixed:

* The window could go "not responding" while a floor was loading (reported on r/PowerShell – thank you). The music of
  a floor used to be composed when the lift arrived, which takes seconds on a slower machine. The whole soundtrack is
  now composed in the background as soon as the game is up, and loading a floor shows what it is doing and keeps the
  window responsive.

## 1.1.0 - 2026-09-20

**Download `polf3d.zip` below, unpack it and start `Play.cmd`** (Windows, PowerShell 7.2 or newer – nothing else).

New:

* **Three enemies.** The **bug** – small, quick, leaps at you; blow it up and two smaller ones crawl out ("fix one,
  get two"). The **engineer** – takes hacked sentry guns back, repairs destroyed sentry guns and cameras, patches up
  whoever stands near him. The **auditor** – unarmed, runs for the nearest terminal, and if he gets there his report
  raises the building's execution policy by a level.
* **Two weapons.** The **taser** (`0`): silent, short of reach, stuns people and switches machines off for good; its
  battery recharges. **Mines** (`Q`): put one down, press again – or `Invoke-Command` in the console – to set it off.
* **Loot.** Loot tables per enemy, **armour** (takes half of every hit), **keycards** (open a locked door for good),
  scrap, rare **signed drops** that import a module for the rest of the floor, and the **silent streak**: unnoticed
  kills in a row make them leave more behind.
* **A new title screen:** left-aligned, the menu as a command line, the controls in three columns showing the keys as
  they are bound, the achievements with a bar.

Fixed:

* The commander dropped a gold key on floors that have no gold door (floor 2) or where he stands behind it (floor 3).
  He now only drops it where it opens something – otherwise his strongbox.

Balance:

* Floors 3 and 5 were too hard on the two easier difficulties: a less crowded entrance to the citadel, an armoured
  vest at the start of both, fewer ambushers in the pillar crypt.
* The arena's waves can bring bugs and engineers; its supply drops include vests, mines and a taser.

Saved games of 1.0.0 still load. Demos recorded with 1.0.0 do not replay: the floors and their loot have changed.

## 1.0.0 - 2026-09-20

The first release: the whole game.

**Download `polf3d.zip` below, unpack it and start `Play.cmd`.** Windows and PowerShell 7.2 or newer are all it needs –
no modules, no asset files, no installation. (`Play.cmd` starts the game with `-ExecutionPolicy Bypass` for that one
process, because Windows marks scripts from a downloaded ZIP as "from the internet". With `git clone` you can start
`./Start-Polf3D.ps1` directly.)

What is in it:

* **A campaign of ten floors** and a secret one, four difficulties that really differ, a dozen kinds of enemies
  plus security cameras and sentry guns, three bosses, nine weapons – and an ending that is worth playing for.
* **PowerShell is the theme, not just the language:** a real, sandboxed PowerShell console in the game with
  pipelines, a `$PROFILE`, hotkeys and background jobs (a drone); `-WhatIf`, `-Confirm`, `-Verbose`, `-Force` and
  Undo as powers; files to read on the terminals of every floor; an execution policy for the whole building;
  `Install-Module` in the lift; a Pester report at the end of every floor.
* **Stealth, light and time:** noise and sight matter, dark rooms and a flashlight, lockdowns, power failures and
  Patch Tuesday on the floors' schedules.
* **More ways to play:** the daily dungeon with runs that can be verified, the arena with endless waves (alone or
  in co-op), co-op and deathmatch for up to four over the network with an admin panel for the host, a terminal mode
  that draws the game with half-block characters.
* **Everything is generated:** textures, about 400 sprites, 47 sounds, the enemies' spoken lines and the music
  (a track per floor) – no asset files at all. As much PowerShell as possible, as little C# as necessary.
* **Around the game:** saved games, demos (and demos as animated GIFs), speedrun clock, options with free key
  bindings, game pad, mods as data files, a level editor, a level generator and a headless self-test.
