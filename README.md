# BetterBots for Rising Storm 2: Vietnam

**Smarter offline bots for Rising Storm 2: Vietnam.** Bots defend, attack and flank properly. They fly and crew every helicopter, and the bot commanders on both sides call in their abilities. Up to 64 players in any offline match.

🇪🇸 **[Leer en español](README.es.md)**

> Offline only (single player / practice). It does not load on online servers.

---

## Features

### Infantry
- **Real objective choice.** In the stock game, defenders go off to attack 80 % of the time and bots re-roll their objective every few seconds. With BetterBots they score objectives:
  - Defenders hold their points and rush to any point being captured.
  - Attackers push enemy points and back up captures in progress.
  - Bots spread over the objectives and keep their choice.
- **Roles with a personality:**
  - Marksmen take long overwatch positions.
  - Machine gunners cover the enemy side of the objective.
  - Flankers attack from the sides, or ambush from the sides when defending.
  - The radioman escorts the commander.
  - US squad leaders stay just behind the objective as a spawn point.
- **Defenders use cover.** They pick spots behind walls, rocks, trees or roofs instead of open ground, and wait crouched in ambush.
- **Combat behaviour:**
  - **Suppression:** heavily suppressed bots go prone, aim and react worse, and the timid ones fall back.
  - **Morale:** it drops when nearby friends die or a point is lost. It rises with kills, captures and a living squad leader nearby.
  - **Suppressive fire:** machine gunners and some riflemen fire bursts at where an enemy was last seen or heard.
  - **Bounding:** squads in contact split into two fireteams; one moves while the other covers.
  - **Smoke:** attackers throw smoke before crossing open ground.
- **Fights draw bots in.** Objectives under attack pull reinforcements from both teams.
- **Fixed machine guns (DShK / M2).** Nearby defenders man them against infantry and helicopters, firing bursts and leading their target. They leave the gun when:
  - they are flanked or the point falls;
  - you walk up to the gun;
  - they have had no targets for a minute.
- **Stuck bots recover:**
  - **Bots stuck in place:** they re-plan their route, sidestep or nudge free.
  - **Bots off the navmesh:** the stock game teleports them to a random spawn, often in an endless loop. Instead, BetterBots moves them to the nearest spawn that is on the navmesh, at most once every 20 s.

### Commander (both sides)
In the stock game the North Vietnamese commander never used his abilities. The bot had to walk to a radio first, and the NVA have none. Now the commander decides on its own:
- **Artillery, napalm, gunship or bombing run:** on groups of enemies that a teammate can see near an objective in play, away from friendly troops.
- **NVA:**
  - Anti-air only while enemy helicopters are flying.
  - Ambush respawn when many soldiers are waiting to respawn.
  - Ho Chi Minh Trail when attacking or after losing a point.
- **US:** needs his radioman next to him or a radio nearby, like a player.

### Helicopters (US side)
Bots fly, crew and use every helicopter, automatically:

| Helicopter | What the bots do |
|---|---|
| **AH-1 Cobra** | Waits high and far away, then makes rocket and cannon passes or long-range shots. It keeps using whichever tactic scores kills. A bot gunner joins when pilot slots are spare. |
| **OH-6 Loach** | Circles the fight, marks enemies on the map and makes short minigun passes. |
| **Bushranger** | Orbits the fight with its door gunners firing. |
| **UH-1 Huey (transport)** | Picks up soldiers at base, lands 150–300 m from the objective, drops them and flies back. It picks a landing zone further away if that area has been hot, and forces the landing if it keeps taking fire. |

All bot pilots:
- **Return to base** to rearm and repair when ammo is low, the helicopter is damaged or the crew is wounded.
- **Remember danger** for about 3 minutes and fly around the spots where they were shot at.
- **Read the terrain** about 8 seconds ahead and slow down for steep mountains. Water counts as ground.
- **Keep clear of each other** in the air, and wait for the pad to be free before taking off.
- **Dive below 50 m** as soon as enemy anti-air is active or a missile is incoming. The SAM only locks on above 75 m.
- **Glide toward base** if the engine dies.
- **Support each other:** when a helicopter takes fire, the Loach marks the shooter and the Cobra or Bushranger goes after him.
- **Take passengers:** dead bots can respawn inside a Huey that is waiting for passengers or flying out to its landing zone. This mostly happens when the base is the only spawn; with forward spawns only about 10 % do.

The NVA fight back. Rocket soldiers and machine gunners shoot at helicopters, and the rest take cover.

**You always have priority:**
- **Picking a pilot slot:** you get 15 s after spawning to choose a pilot role before the bots take the helicopters.
- **A pilot slot held by bots:** choose that role and a bot on the ground gives it up at once. If they are all flying, one returns to base for you.
- **A landed bot helicopter:** walk up to it (within 15 m) with a pilot role and the bot gets out.
- **Your crew:**
  - Board an attack helicopter and a bot joins as your gunner. If you switch helicopters, your gunner follows you.
  - Fly a Huey or Bushranger and bots board at base. They get out when you land near an objective.
- **At the heli base:** bot helicopters wait on the ground (up to 30 s) while you are still choosing.

### Game modes and squads
- **Supremacy:** about 30 % of the bots hold your points and the rest attack; everyone answers a point being captured.
- **Skirmish:** fewer flankers, so squads move together.
- **Campaign:** uses Territories and Supremacy maps, so the rules above apply.
- **Your orders as squad leader now work.** The stock game stores attack and defend orders but never acts on them.
  - **Attack:** your bots go until the point is captured.
  - **Defend:** they hold until you give another order.
  - **Follow me:** they move in an open formation and watch outward when you stop.
- **Bot squads stick together** on their leader's objective.

---

## Installation

1. Download **`BetterBots-vX.Y.Z.zip`** from the [Releases](../../releases) page.
2. Copy `Mod/BetterBots.u` from the zip to:
   ```
   Documents\My Games\Rising Storm 2\ROGame\Unpublished\CookedPC\Script\
   ```
   Create the `Unpublished\CookedPC\Script` folders if they don't exist. The `My Games\Rising Storm 2` folder appears after you start the game once.
3. In Steam, right-click **Rising Storm 2: Vietnam** > **Properties** > **Launch Options**, and add:
   ```
   -useunpublished
   ```

## How to play

Start the game, open the console with **`~`** and type, for example:

```
open VNTE-CuChi?mutator=BetterBots.BBMutator
```

By default the match is filled up to **64 players**. Use `MinPlayers` for a different number:

```
open VNTE-CuChi?MinPlayers=40?mutator=BetterBots.BBMutator
```

<details>
<summary><b>All Territories maps (copy &amp; paste)</b></summary>

```
open VNTE-AnLaoValley?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-ApacheSnow?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-ASau?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-BorderWatch?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-Compound?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-CuaViet?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-CuChi?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-DaNangAirBase?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-DemilitarizedZone?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-DongHa?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-Firebase?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-FirebaseGeorgina?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-Highway14?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-Hill937?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-HueCity?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-KheSanh?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-LongTan?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-Mekong?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-NinhPhu?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-OperationForrest?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-QuangTri?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-Resort?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-RungSac?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-Saigon?MinPlayers=64?mutator=BetterBots.BBMutator
open VNTE-SongBe?MinPlayers=64?mutator=BetterBots.BBMutator
```
</details>

### Console commands

| Command | What it does |
|---|---|
| `JoinSquad 0` | Join squad 0 (1, 2…) even if it is full; a bot moves to another squad. |
| `BBLeader` | Become your squad's leader (the bot leader becomes a rifleman). |
| `BBHeliInfo` | List the helicopters, their pilots and what they are doing. |
| `BBHeliDebug` | Toggle helicopter debug: draws routes, landing zones, danger, targets and marks, and lists what each bot pilot is doing every 5 s. |
| `BBHeliTest [s]` | A bot takes a free Cobra/Loach, hovers for 30 s (or *s*) and lands. |
| `BBHeliGoto [n]` | The flying bot comes to you (or to objective *n*: 1 = A, 2 = B…), waits 20 s and goes back. |
| `BBHeliHome` | Orders the test helicopter home. |

The bot logs what it is doing to `Documents\My Games\Rising Storm 2\ROGame\Logs\Launch.log`. Look for lines starting with `[BetterBots]`.

---

## Notes

- **Offline only.** It does not load on online servers.
- **No other bot mods:** don't use it together with other bot AI mods (for example GOM), because they would conflict.
- **Uninstall:** delete `BetterBots.u` and remove `-useunpublished` from the launch options.
- **Helicopter maps:** helicopter features need a map with helicopters for the US side, such as Hill 937, Resort or A Shau.

## Building from source

Requirements: Rising Storm 2: Vietnam with the **SDK** installed (Steam > Library > Tools).

1. Clone this repository.
2. Edit the SDK path at the top of `build.ps1` if your game is not in `D:\SteamLibrary\...`.
3. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File build.ps1
   ```
   The script copies `Src/BetterBots` into the SDK, compiles it in the background, and writes `Mod/BetterBots.u` and the release zip to `dist/`.

### Source layout

| File | Purpose |
|---|---|
| `BBMutator.uc` | Entry point: swaps in the BetterBots controllers, fills the match to 64 players and starts the helicopter manager. |
| `BBAIController.uc` | Infantry: objectives, roles, morale, suppression, bounding, smoke, cover and stuck recovery. |
| `BBSquadAI.uc` | Commander abilities and fixed machine guns. |
| `BBHeliAI.uc` | Helicopter autopilot, missions, weapons, gunners and passengers. |
| `BBHeliManager.uc` | Helicopter crews, human priority, landing zones, danger memory, and where dead bots respawn. |
| `BBPlayerController.uc` | Console commands and requesting a pilot role held by bots. |

## License

No license file yet. Ask the author before redistributing modified versions.
