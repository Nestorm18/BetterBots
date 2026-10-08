BetterBots - smarter offline bots for Rising Storm 2: Vietnam
=============================================================
(Spanish instructions: LEEME.txt)

INSTALL
-------
1. Copy "BetterBots.u" (in the "Mod" folder of this zip) to:

   Documents\My Games\Rising Storm 2\ROGame\Unpublished\CookedPC\Script\

   Create the "Unpublished\CookedPC\Script" folders if they don't exist.
   ("My Games\Rising Storm 2" appears after starting the game once.)

2. In Steam: right-click Rising Storm 2 > Properties > Launch Options
   and add:

   -useunpublished


PLAY
----
1. Start the game (with -useunpublished) and wait for the main menu.
2. Open the console: the key under Esc, left of 1 (~ on English
   keyboards, º on Spanish ones).
3. Type, for example, and press Enter:

   open VNTE-CuChi?mutator=BetterBots.BBMutator

The match is filled up to 64 players. For another number:

   open VNTE-CuChi?MinPlayers=40?mutator=BetterBots.BBMutator

Pick a team (South = US with helicopters, North = NVA), a role, and
spawn. Another map: type another "open ..." line. Back to the menu:
type "disconnect".

Works on every Territories map (VNTE-...), plus Supremacy, Skirmish and
Campaign. Helicopter features need a map with US helicopters (Hill937,
Resort, ASau...).


WHAT IT DOES
------------
- Bots choose objectives properly: defenders hold and retake their
  points, attackers push and reinforce captures.
- Roles: marksman overwatch, MGs on the enemy edge, flankers, radioman
  escorting the commander, US squad leader as a spawn point.
- Suppression, morale, suppressive fire, bounding and smoke.
- Defenders take cover (walls, rocks, trees, roofs) and wait in ambush.
- Bot commanders on both sides call artillery, napalm, gunships, NVA
  anti-air, ambush and Ho Chi Minh Trail.
- Bots fly the Cobra, Loach, Bushranger and transport Huey (US): door
  gunners, passengers, rearming, danger avoidance, diving under enemy
  anti-air. You keep priority for pilot roles and helicopters.
- Your squad leader orders (attack / defend / follow me) work.
- Fixed MGs (DShK / M2) manned by nearby defenders.
- Stuck and off-navmesh bots recover.


CONSOLE COMMANDS
----------------
   JoinSquad 0     Join squad 0 (1, 2...) even if it is full.
   BBLeader        Become your squad's leader.
   BBHeliInfo      List helicopters, pilots and what they are doing.
   BBHeliDebug     Toggle helicopter debug output.
   BBHeliTest      A bot takes a free Cobra/Loach, hovers 30 s, lands.
   BBHeliGoto [n]  The flying bot comes to you (or objective n), returns.
   BBHeliHome      Orders the test helicopter home.


NOTES
-----
- Offline only. It does not load on online servers.
- Don't use it together with other bot mods (e.g. GOM).
- The "Source" folder has the source code (not needed to play).
- Uninstall: delete BetterBots.u and remove -useunpublished.
