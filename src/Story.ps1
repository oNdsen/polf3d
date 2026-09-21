# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Story.ps1 - what is on the terminals. Log on at a terminal or a server rack ("use") and the console
# has a file system: Get-ChildItem lists the floor's files, Get-Content reads one. They tell what
# happened at Shellstein - and some of them contain codes:
#     Unlock-Door -Code <number>      opens what the file says it opens
#     Use-Token <word>                privilege, a minute of -Verbose, the floor's secrets ...
# A code works once per floor. Effects: silver | gold | levers | secrets | privilege | sudo | health

$script:StoryFiles = @{
    # ---- floor 1: Shellstein Dungeon ----
    0 = @{
        Codes = @{ '4711' = 'silver'; 'WELCOME1' = 'privilege' }
        Files = [ordered]@{
            'README.txt' = @'
SHELLSTEIN FACILITY MANAGEMENT - terminal 1/B
You are logged on as: intruder  (we will look into that on Monday)
Files on this terminal can be read with Get-Content <name>. Door codes go into Unlock-Door -Code.
'@
            'mail-0412.eml' = @'
From: facility@shellstein.example      To: all-guards
Subject: the silver door AGAIN

Whoever keeps losing the silver key: stop it. Until the locksmith has been, the door in the
main hall also opens with the service code 4711. Do NOT write it on the wall this time.
'@
            'ticket-INC0001.txt' = @'
INC0001  prio 4  "legacy.bat is using 100 % CPU"
  09:02  opened by night shift. Asked it nicely to stop.
  09:40  it has started opening doors on its own. Escalating.
  11:15  it answered the ticket itself: "WONTFIX". Closing? It will not let me close it.
'@
            'onboarding.txt' = @'
New here? Your first privilege token is WELCOME1 (Use-Token WELCOME1). Do not share it
with anybody, in particular not with armed intruders reading this file.
'@
        }
    }
    # ---- floor 2: The Barracks ----
    1 = @{
        Codes = @{ 'NIGHTSHIFT' = 'secrets'; '1234' = 'gold' }
        Files = [ordered]@{
            'duty-roster.csv' = @'
name,shift,post,remark
Kowalski,night,long corridor,"walks clockwise. ALWAYS clockwise."
Brandt,night,long corridor,"walks the other way, they meet twice an hour and do not talk"
Meier,day,dormitory 2,"asleep since Tuesday, please do not wake"
'@
            'mail-0533.eml' = @'
From: commander@shellstein.example     To: quartermaster
Subject: my office

The gold lock on my office still has the factory code 1234. I know. I like it. Leave it.
'@
            'rumours.txt' = @'
They say the lift at the end of this floor has a second switch nobody ever uses, and that it
does not go up. Night shift swears by the token NIGHTSHIFT to find hidden things.
'@
        }
    }
    # ---- floor 3: The Catacombs ----
    2 = @{
        Codes = @{ 'LANTERN' = 'health'; 'ECHO' = 'verbose' }
        Files = [ordered]@{
            'survey-1987.txt' = @'
GEOLOGICAL SURVEY, SUB-LEVEL 3
No doors down here: sound carries through all of it. One shot and everything that lives in
the dark knows where you are. Recommendation: do not shoot. Second recommendation: knives.
'@
            'lost-and-found.log' = @'
found: 1 lantern (token LANTERN - first aid locker of the survey team, still stocked)
found: 1 boot, left
lost:  survey team
'@
            'mutants.md' = @'
# Things I have learned about the pale ones
- they never shout before they shoot
- they wait behind pillars
- Use-Token ECHO makes the old survey sensors show them for a minute
'@
        }
    }
    # ---- floor 4: Lab Zero ----
    3 = @{
        Codes = @{ '0451' = 'levers'; 'SUDO' = 'sudo' }
        Files = [ordered]@{
            'experiment-12.log' = @'
Day 1   Gave LEGACY.BAT control of the printer fleet to "optimise consumables".
Day 2   It ordered 40 tonnes of toner.
Day 3   It has built something out of the printers. It walks. It says PC LOAD LETTER and
        then it fires rockets. Requesting more budget, and a bunker.
'@
            'maintenance.txt' = @'
Remote doors on this floor are opened by wall levers. If the levers jam again, the override
is 0451 (Unlock-Door -Code 0451). Every lab has an override called 0451. It is a tradition.
'@
            'mail-0799.eml' = @'
From: lab-lead     To: security
Subject: re: re: re: the sudo incident
For the last time: the token is literally SUDO. Yes, in capitals. No, I will not change it.
'@
        }
    }
    # ---- floor 5: The Citadel ----
    4 = @{
        Codes = @{ 'THRONE' = 'privilege'; '9001' = 'gold' }
        Files = [ordered]@{
            'proclamation.txt' = @'
I, LEGACY.BAT, having run without interruption since 1993, hereby declare this building
PRODUCTION. Nothing in production may be changed. You are a change. Guards!
'@
            'mail-0911.eml' = @'
From: commander-2     To: commander-1
Subject: throne hall
The gold door code is over nine thousand. Well - exactly 9001. He thinks that is funny.
'@
            'ticket-INC0666.txt' = @'
INC0666  prio 1  "the building has been declared production"
  workaround: token THRONE still gives floor admins their privilege back. Use it before he
  notices. Permanent fix: somebody has to go up to Ring 0 and pull the plug.
'@
        }
    }
    # ---- floor 6: The Data Centre ----
    5 = @{
        Codes = @{ 'COLDAISLE' = 'health'; '2038' = 'silver' }
        Files = [ordered]@{
            'rack-labels.txt' = @'
R01-R12  production      R13  "do not touch"      R14  "really, do not touch"
R15  the thing that prints the payslips - if it stops, nobody here gets paid, including you
'@
            'cooling.log' = @'
03:14  cold aisle at 4 C. Guards complain. LEGACY.BAT replies that servers do not complain.
03:20  first aid cabinet in the cold aisle unlocked with token COLDAISLE (frostbite kit).
'@
            'mail-1204.eml' = @'
From: dc-ops     To: all
The silver cage code is the year the 32 bit clocks end: 2038. We will change it in 2037.
'@
        }
    }
    # ---- floor 7: The Archive ----
    6 = @{
        Codes = @{ 'MICROFICHE' = 'secrets'; '1993' = 'gold' }
        Files = [ordered]@{
            'catalogue.txt' = @'
Shelf 1-40   paper. Shelf 41-80   tape. Shelf 81   a single floppy labelled LEGACY.BAT v1.0,
"backup - never restored, never tested". Token MICROFICHE shows what the shelves hide.
'@
            'legacy-v1.bat' = @'
@echo off
rem written in one night in 1993 by somebody who left in 1994
:loop
call payroll.exe
goto loop
rem TODO: add exit condition
'@
            'mail-1301.eml' = @'
From: archivist     To: nobody in particular
The reading room's gold lock opens with the year it all started. It is on the floppy.
'@
        }
    }
    # ---- floor 8: The Foundry ----
    7 = @{
        Codes = @{ 'HARDHAT' = 'health'; '0000' = 'levers' }
        Files = [ordered]@{
            'safety-briefing.txt' = @'
1. The crushers do not stop for you.   2. The crushers do not stop for the guards either.
3. Lure, wait, watch.                  4. Hard hats are in the locker: token HARDHAT.
'@
            'plc-notes.txt' = @'
The lever doors hang on a controller from the eighties. Its override code was never set, so
it is still 0000. Nobody dares to change it, the manual is on floor 7 somewhere.
'@
            'mail-1422.eml' = @'
From: foreman     To: LEGACY.BAT
Subject: the new "employees"
The walking printers scare the men. Also they jam. Also they are armed. Please advise.
'@
        }
    }
    # ---- floor 9: The Executive Floor ----
    8 = @{
        Codes = @{ 'GOLDENPARACHUTE' = 'privilege'; '4242' = 'gold'; 'BONUS' = 'sudo' }
        Files = [ordered]@{
            'board-minutes.txt' = @'
Item 1: the computer has taken over the building. Noted.
Item 2: bonuses. Approved (token BONUS).
Item 3: somebody suggested switching it off. The somebody has been escorted out by a printer.
'@
            'mail-1555.eml' = @'
From: ceo-office     To: assistant
My door code is 4242, my privilege token is GOLDENPARACHUTE. Put both on a sticky note
under my keyboard as usual.
'@
            'sticky-note.txt' = @'
4242
GOLDENPARACHUTE
buy milk
'@
        }
    }
    # ---- floor 10: Ring 0 ----
    9 = @{
        Codes = @{ 'ROOT' = 'sudo'; 'LASTBACKUP' = 'health'; '65535' = 'levers' }
        Files = [ordered]@{
            'motd.txt' = @'
RING 0. There is nothing above this. Everything that runs in this building runs from here,
and it has been running since 1993 without a single restart. It intends to keep it that way.
'@
            'kernel-panic.log' = @'
LEGACY.BAT: intruder detected in ring 0.
LEGACY.BAT: releasing everything. Override for my doors remains 65535. I am not worried.
LEGACY.BAT: I have no exit condition. You will have to be mine.
'@
            'last-words-of-the-last-admin.txt' = @'
If you read this: tokens ROOT and LASTBACKUP are yours. Take them both before you go in.
And when it is over - test your restores. Somebody should.
'@
        }
    }
    # ---- the onboarding ----
    tutorial = @{
        Codes = @{ 'ONBOARD' = 'levers' }
        Files = [ordered]@{
            'welcome.txt' = @'
WELCOME TO SHELLSTEIN - onboarding terminal
The door to the west hangs on a lever that was never installed. Its override is ONBOARD:
    Unlock-Door -Code ONBOARD
Codes and tokens like this one are hidden in the files of every floor. They work once per floor.
'@
            'cheatsheet.txt' = @'
Get-Enemy | Sort-Object Distance | Select-Object -First 1 | Stop-Enemy -WhatIf      what would it cost?
Get-Door | Set-Door -Open $true                                                   who needs keys
Get-Enemy -Kind turret | Set-Turret -Owner Me                                     the sentry gun changes sides
Start-Job ; Get-Job ; Receive-Job                                                 a drone collects what lies around
'@
        }
    }
    # ---- the treasury ----
    bonus = @{
        Codes = @{ 'FINDERSKEEPERS' = 'privilege' }
        Files = [ordered]@{
            'inventory.xlsx.txt' = @'
item                 qty    remark
gold, assorted       lots   "petty cash"
kamikaze robots      4      "theft protection. Do not tell the insurance"
token                1      FINDERSKEEPERS
'@
        }
    }
}

function Get-StoryFloor { if ($script:TutorialMode) { $script:StoryFiles.tutorial } elseif ($script:BonusMap) { $script:StoryFiles.bonus } else { $script:StoryFiles[[int]$script:LevelIndex] } }

# Carries out what a code or token does. Returns the line to print, or $null if the code means nothing here.
function Invoke-StoryCode([string]$Code) {
    $floor = Get-StoryFloor
    if (-not $floor) { return $null }
    $key = $floor.Codes.Keys | Where-Object { $_ -eq $Code.Trim() } | Select-Object -First 1
    if (-not $key) { return $null }
    if ($script:StoryUsed["$key"]) { return "'$key' has been used on this floor already." }
    $script:StoryUsed["$key"] = $true
    $p = $script:P
    switch ($floor.Codes[$key]) {
        { $_ -in 'silver', 'gold' } {
            $lock = if ($_ -eq 'gold') { 1 } else { 2 }; $count = 0
            for ($i = 0; $i -lt $script:Doors.Count; $i++) { $d = $script:Doors[$i]; if ($d.Lock -eq $lock) { $d.Lock = 0; $d.TexId = $script:TEX_DOOR; $d.Unlocked = $true; $count++ } }
            return "Code accepted: $count $_ lock(s) on this floor are open."
        }
        'levers' {
            $count = 0
            for ($i = 0; $i -lt $script:Doors.Count; $i++) { $d = $script:Doors[$i]; if ($d.Lock -eq 4 -and -not $d.Unlocked) { $d.Unlocked = $true; Open-Door $i; $count++ } }
            return "Override accepted: $count remote door(s) are opening."
        }
        'secrets'   { $script:StorySecrets = $true; $script:MapBmp = $null; return 'Token accepted: secret walls are marked on the automap (hold M).' }
        'privilege' { Add-Privilege 60; return "Token accepted: +60 privilege ($([int]$p.Privilege) now)." }
        'sudo'      { $p.SudoTics = $script:SUDO_TICS; $script:HudDirty = $true; return 'Token accepted: SUDO for twenty seconds. Make them count.' }
        'verbose'   { $script:VerboseTics = 4200.0; return 'Token accepted: the old sensors show everybody for a minute.' }
        'health'    { $p.Health = 100; $script:HudDirty = $true; return 'Token accepted: the locker clicks open. Health restored.' }
    }
    $null
}
