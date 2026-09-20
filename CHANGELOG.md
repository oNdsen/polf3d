# Changelog

Fixes and balance raise the last number, new features and floors the middle one.

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
