# BetterBots v0.9.0 (beta)

First public release of BetterBots, an offline bot AI overhaul for **Rising Storm 2: Vietnam**.

## Highlights
- **Bots that play the objective:**
  - Defenders hold and retake their points.
  - Attackers push and reinforce captures in progress.
  - They spread over the objectives instead of re-rolling every few seconds.
- **Role personalities:** marksman overwatch, machine gunners on the enemy edge, flankers, the radioman escorting the commander, and US squad leaders as spawn points.
- **Combat behaviour:** suppression, morale, suppressive fire, fireteam bounding and smoke.
- **Defenders use cover:** walls, rocks, trees and roofs instead of open ground, waiting crouched in ambush.
- **Bot commanders on both sides call in their abilities:**
  - Artillery, napalm, gunship or bombing run on visible enemy groups.
  - NVA anti-air, ambush and Ho Chi Minh Trail at the right moments.
  - The NVA commander used no abilities at all in the stock game.
- **Helicopters (US):**
  - Bots fly the Cobra, Loach, Bushranger and transport Huey.
  - They carry door gunners and passengers.
  - They rearm at base, dodge danger and dive under enemy anti-air.
  - They keep clear of each other and of mountains.
- **You keep priority** for pilot roles and helicopters. Bots give them up for you, and join you as gunners or passengers.
- **Squad leader orders now work.** The stock game ignored attack and defend; follow me now uses an open formation.
- **Supremacy, Skirmish and Campaign** support.
- **Fixed machine guns (DShK / M2)** manned by nearby defenders.
- **Up to 64 players** in any offline match: `?MinPlayers=64`.
- **Fixes to the stock AI:**
  - The objective midpoint bug.
  - Stuck bots recover.
  - No more endless teleporting of bots that are off the navmesh.

## Install
1. Copy `Mod/BetterBots.u` to `Documents\My Games\Rising Storm 2\ROGame\Unpublished\CookedPC\Script\`.
2. Add `-useunpublished` to the game's Steam launch options.
3. In game, open the console (`~`, or `º` on Spanish keyboards) and run `open VNTE-CuChi?MinPlayers=64?mutator=BetterBots.BBMutator`.

Full instructions and the map list are in the [README](https://github.com/Nestorm18/BetterBots#readme).

## Known limitations
- **Offline only.**
- **Not compatible** with other bot AI mods (for example GOM).
- **Helicopter AI is new and still being tuned.** Bot pilots can occasionally crash on unusual terrain or struggle to find a landing zone on some maps. Please report the map and attach `Launch.log`.
- **`BBHeliDebug` lines** may not be drawn in the retail game. The text output still works.

---

# BetterBots v0.9.0 (beta) — Español

Primera versión pública de BetterBots, una mejora de la IA de los bots offline para **Rising Storm 2: Vietnam**.

## Novedades
- **Bots que juegan al objetivo:**
  - Los defensores guardan y recuperan sus puntos.
  - Los atacantes empujan y refuerzan las capturas en curso.
  - Se reparten entre los objetivos en lugar de cambiar cada pocos segundos.
- **Personalidad por rol:** tiradores vigilando de lejos, ametralladores en el borde enemigo, flanqueadores, el radioperador escoltando al comandante, y líderes de escuadra americanos como punto de aparición.
- **Comportamiento en combate:** supresión, moral, fuego de supresión, avance por saltos y humo.
- **Los defensores buscan cobertura:** muros, rocas, árboles y techos en vez de terreno abierto, y esperan agachados en emboscada.
- **Comandantes bot de ambos bandos usan sus habilidades:**
  - Artillería, napalm, cañonero o bombardeo sobre grupos de enemigos vistos.
  - Antiaéreo, emboscada y Ruta Ho Chi Minh norvietnamitas en el momento adecuado.
  - En el juego original el comandante norvietnamita no usaba ninguna.
- **Helicópteros (EE. UU.):**
  - Los bots pilotan el Cobra, el Loach, el Bushranger y el Huey de transporte.
  - Llevan artilleros de puerta y pasajeros.
  - Recargan en base, esquivan el peligro y bajan ante el antiaéreo enemigo.
  - Se separan entre ellos y evitan las montañas.
- **Tú mantienes la prioridad** en roles de piloto y helicópteros. Los bots te los ceden y se unen como artilleros o pasajeros.
- **Las órdenes del líder de escuadra funcionan.** El juego original ignoraba atacar y defender; seguidme ahora va en formación abierta.
- **Soporte de Supremacía, Escaramuza y Campaña.**
- **Ametralladoras fijas (DShK / M2)** usadas por los defensores cercanos.
- **Hasta 64 jugadores** en cualquier partida offline: `?MinPlayers=64`.
- **Arreglos de la IA original:**
  - El fallo del punto medio al buscar el objetivo.
  - Los bots atascados se recuperan.
  - Se acabó el teletransporte en bucle de los bots fuera de la malla de navegación.

## Instalación
1. Copia `Mod/BetterBots.u` en `Documentos\My Games\Rising Storm 2\ROGame\Unpublished\CookedPC\Script\`.
2. Añade `-useunpublished` a las opciones de lanzamiento del juego en Steam.
3. En el juego, abre la consola (`º` en teclado español, `~` en inglés) y escribe `open VNTE-CuChi?MinPlayers=64?mutator=BetterBots.BBMutator`.

Instrucciones completas y lista de mapas en el [README en español](https://github.com/Nestorm18/BetterBots/blob/master/README.es.md).

## Limitaciones conocidas
- **Solo offline.**
- **No es compatible** con otros mods de IA de bots (por ejemplo GOM).
- **La IA de helicópteros es nueva y se sigue ajustando.** Algún piloto bot puede estrellarse en terreno raro o tener problemas para encontrar zona de aterrizaje en algunos mapas. Indica el mapa y adjunta `Launch.log`.
- **Las líneas de `BBHeliDebug`** pueden no dibujarse en el juego normal. El texto sí funciona.
