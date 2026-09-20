# Changelog

Fixes and balance raise the last number, new features and floors the middle one.

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
  (a track per floor) – no asset files at all, and 380 lines of C# next to some 12,000 of PowerShell.
* **Around the game:** saved games, demos (and demos as animated GIFs), speedrun clock, options with free key
  bindings, game pad, mods as data files, a level editor, a level generator and a headless self-test.
