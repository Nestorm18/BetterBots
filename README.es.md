# BetterBots para Rising Storm 2: Vietnam

**Bots offline más inteligentes para Rising Storm 2: Vietnam.** Los bots defienden, atacan y flanquean de verdad. Pilotan y tripulan todos los helicópteros, y los comandantes bot de ambos bandos usan sus habilidades. Hasta 64 jugadores en cualquier partida offline.

🇬🇧 **[Read in English](README.md)**

> Solo offline (un jugador / práctica). No se carga en servidores online.

---

## Características

### Infantería
- **Elección de objetivos de verdad.** En el juego original los defensores se van a atacar el 80 % de las veces y los bots cambian de objetivo cada pocos segundos. Con BetterBots puntúan los objetivos:
  - Los defensores guardan sus puntos y acuden a los que les están capturando.
  - Los atacantes empujan sobre los puntos enemigos y refuerzan las capturas en curso.
  - Se reparten entre los objetivos y mantienen su elección.
- **Roles con personalidad:**
  - El tirador vigila desde lejos.
  - El ametrallador cubre el lado enemigo del objetivo.
  - Los flanqueadores atacan por los lados, o emboscan desde los laterales cuando defienden.
  - El radioperador escolta al comandante.
  - El líder de escuadra americano se queda justo detrás del objetivo como punto de aparición.
- **Los defensores buscan cobertura.** Eligen sitios detrás de muros, rocas, árboles o techos en vez de terreno abierto, y esperan agachados en emboscada.
- **Comportamiento en combate:**
  - **Supresión:** si están muy suprimidos se tumban, apuntan y reaccionan peor, y los más miedosos retroceden.
  - **Moral:** baja cuando mueren compañeros cerca o se pierde un punto. Sube con bajas, capturas y su líder de escuadra vivo cerca.
  - **Fuego de supresión:** los ametralladores y algunos fusileros disparan ráfagas donde vieron u oyeron al enemigo.
  - **Avance por saltos:** las escuadras en contacto se dividen en dos equipos; uno avanza mientras el otro cubre.
  - **Humo:** los atacantes lanzan humo antes de cruzar terreno abierto.
- **Los combates atraen bots.** Los objetivos en disputa reciben refuerzos de ambos bandos.
- **Ametralladoras fijas (DShK / M2).** Los defensores cercanos las usan contra infantería y helicópteros, a ráfagas y adelantando el blanco. La dejan:
  - si les flanquean o cae el punto;
  - si te acercas tú;
  - tras un minuto sin blancos.
- **Bots atascados:**
  - **Atascados en el sitio:** replanifican la ruta, dan un paso lateral o se desatascan.
  - **Fuera de la malla de navegación:** el juego original los teletransporta a un punto de aparición al azar, a menudo en bucle sin fin. BetterBots los lleva al punto de aparición más cercano que sí esté en la malla, como mucho una vez cada 20 s.

### Comandante (ambos bandos)
En el juego original el comandante norvietnamita nunca usaba sus habilidades. Tenía que ir a una radio primero, y su bando no tiene. Ahora el comandante decide solo:
- **Artillería, napalm, cañonero o bombardeo:** sobre grupos de enemigos que algún aliado está viendo, cerca de un objetivo en juego y lejos de sus tropas.
- **Norvietnamita:**
  - Antiaéreo solo con helicópteros enemigos en vuelo.
  - Emboscada cuando hay muchos esperando para reaparecer.
  - Ruta Ho Chi Minh al atacar o tras perder un punto.
- **Americano:** necesita a su radioperador al lado o una radio cerca, como un jugador.

### Helicópteros (bando EE. UU.)
Los bots pilotan, tripulan y usan todos los helicópteros, de forma automática:

| Helicóptero | Qué hacen los bots |
|---|---|
| **AH-1 Cobra** | Espera alto y lejos, y hace pasadas de cohetes y cañón o tiros lejanos. Mantiene la táctica que le da bajas. Si sobran plazas de piloto, lleva un bot artillero. |
| **OH-6 Loach** | Da vueltas sobre el combate, marca enemigos en el mapa y hace pasadas cortas con la minigun. |
| **Bushranger** | Gira alrededor del combate con los ametralladores de puerta disparando. |
| **UH-1 Huey (transporte)** | Recoge soldados en base, aterriza a 150-300 m del objetivo, los deja y vuelve. Elige una zona más lejana si esa zona ha estado caliente, y fuerza el aterrizaje si sigue recibiendo fuego. |

Todos los pilotos bot:
- **Vuelven a base** a recargar y reparar si les falta munición, el helicóptero está dañado o la tripulación está herida.
- **Recuerdan el peligro** unos 3 minutos y rodean los sitios donde les dispararon.
- **Leen el terreno** unos 8 segundos por delante y frenan ante montañas empinadas. El agua cuenta como suelo.
- **Se separan entre ellos** en el aire, y esperan a que la pista esté libre para despegar.
- **Bajan por debajo de 50 m** en cuanto el antiaéreo enemigo está activo o viene un misil. El misil solo fija por encima de 75 m.
- **Planean hacia la base** si se queda sin motor.
- **Se apoyan entre ellos:** si disparan a un helicóptero, el Loach marca al tirador y el Cobra o el Bushranger va a por él.
- **Llevan pasajeros:** los bots muertos pueden reaparecer dentro de un Huey que espera pasajeros o que va de camino a su zona de aterrizaje. Pasa sobre todo cuando la base es el único punto de aparición; si hay puntos avanzados, solo lo hace un 10 %.

Los norvietnamitas se defienden. Los de cohetes y los ametralladores disparan a los helicópteros, y el resto se pone a cubierto.

**Tú siempre tienes prioridad:**
- **Elegir plaza de piloto:** tienes 15 s desde que apareces para elegir rol de piloto antes de que los bots cojan los helicópteros.
- **Una plaza de piloto ocupada por bots:** elige ese rol y un bot en tierra te la cede al momento. Si todos vuelan, uno vuelve a base para dejártela.
- **Un helicóptero de bot aterrizado:** acércate a menos de 15 m con rol de piloto y el bot se baja.
- **Tu tripulación:**
  - Si subes a un helicóptero de ataque, se te une un bot artillero. Si cambias de helicóptero, tu artillero te sigue.
  - Si pilotas un Huey o un Bushranger, los bots suben en base. Se bajan cuando aterrizas cerca de un objetivo.
- **En la base de helicópteros:** los helicópteros de bot esperan en tierra (hasta 30 s) mientras sigues eligiendo.

### Modos de juego y escuadras
- **Supremacía:** un 30 % de los bots defiende tus puntos y el resto ataca; todos acuden si capturan uno.
- **Escaramuza:** menos flanqueadores, así que las escuadras van juntas.
- **Campaña:** usa mapas de Territorios y Supremacía, así que se aplica lo anterior.
- **Tus órdenes como líder de escuadra funcionan.** El juego original guarda las órdenes de atacar y defender, pero no hace nada con ellas.
  - **Atacar:** tus bots van hasta capturar el punto.
  - **Defender:** se quedan hasta que des otra orden.
  - **Seguidme:** formación abierta, y cuando paras vigilan hacia fuera.
- **Las escuadras con líder bot van juntas** a su objetivo.

---

## Instalación

1. Descarga **`BetterBots-vX.Y.Z.zip`** de la página de [Releases](../../releases).
2. Copia `Mod/BetterBots.u` del zip en:
   ```
   Documentos\My Games\Rising Storm 2\ROGame\Unpublished\CookedPC\Script\
   ```
   Si las carpetas `Unpublished\CookedPC\Script` no existen, créalas. La carpeta `My Games\Rising Storm 2` aparece tras abrir el juego una vez.
3. En Steam: clic derecho en **Rising Storm 2: Vietnam** > **Propiedades** > **Opciones de lanzamiento**, y añade:
   ```
   -useunpublished
   ```

## Cómo jugar

Abre el juego, pulsa **`~`** para la consola y escribe, por ejemplo:

```
open VNTE-CuChi?mutator=BetterBots.BBMutator
```

Por defecto rellena hasta **64 jugadores**. Usa `MinPlayers` para otro número:

```
open VNTE-CuChi?MinPlayers=40?mutator=BetterBots.BBMutator
```

<details>
<summary><b>Todos los mapas de Territorios (copiar y pegar)</b></summary>

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

### Comandos de consola

| Comando | Qué hace |
|---|---|
| `JoinSquad 0` | Unirte a la escuadra 0 (1, 2…) aunque esté llena; un bot se cambia a otra. |
| `BBLeader` | Ser líder de tu escuadra (el bot líder pasa a fusilero). |
| `BBHeliInfo` | Lista los helicópteros, su piloto y lo que hacen. |
| `BBHeliDebug` | Activa/desactiva la depuración de helicópteros: dibuja rutas, zonas de aterrizaje, peligro, blancos y marcas, y lista cada 5 s lo que hace cada piloto bot. |
| `BBHeliTest [s]` | Un bot coge un Cobra/Loach libre, se mantiene 30 s (o *s*) en el aire y aterriza. |
| `BBHeliGoto [n]` | El bot que vuela viene hasta ti (o al objetivo *n*: 1 = A, 2 = B…), espera 20 s y vuelve. |
| `BBHeliHome` | Ordena volver a base al helicóptero de prueba. |

Lo que hacen los bots queda en `Documentos\My Games\Rising Storm 2\ROGame\Logs\Launch.log`, en las líneas que empiezan por `[BetterBots]`.

---

## Notas

- **Solo offline.** No se carga en servidores online.
- **Sin otros mods de bots:** no lo uses junto con otros mods de IA de bots (por ejemplo GOM), porque chocarían.
- **Desinstalar:** borra `BetterBots.u` y quita `-useunpublished` de las opciones de lanzamiento.
- **Mapas con helicópteros:** las funciones de helicópteros necesitan un mapa con helicópteros para el bando americano, como Hill 937, Resort o A Shau.

## Compilar desde el código

Requisitos: Rising Storm 2: Vietnam con el **SDK** instalado (Steam > Biblioteca > Herramientas).

1. Clona este repositorio.
2. Cambia la ruta del SDK al principio de `build.ps1` si tu juego no está en `D:\SteamLibrary\...`.
3. Ejecuta:
   ```powershell
   powershell -ExecutionPolicy Bypass -File build.ps1
   ```
   El script copia `Src/BetterBots` al SDK, compila en segundo plano, y genera `Mod/BetterBots.u` y el zip de la release en `dist/`.

## Licencia

Aún no hay archivo de licencia. Pregunta al autor antes de redistribuir versiones modificadas.
