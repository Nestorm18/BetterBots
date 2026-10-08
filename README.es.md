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

### Empezar una partida
1. Abre Rising Storm 2 desde Steam con la opción de lanzamiento `-useunpublished` puesta (ver *Instalación*).
2. Espera al **menú principal**. No hace falta crear partida desde los menús.
3. Abre la **consola**:
   - Pulsa **`º`**, la tecla debajo de `Esc` y a la izquierda del `1` en un teclado español.
   - En teclados ingleses es **`~`**.
   - Aparece una barra de texto abajo.
4. Escribe la línea del mapa que quieras y pulsa **Intro**:
   ```
   open VNTE-CuChi?MinPlayers=64?mutator=BetterBots.BBMutator
   ```
   - `VNTE-CuChi` es el mapa. Abajo tienes todos.
   - `MinPlayers=64` rellena con bots hasta 64 jugadores, 32 por bando. Pon menos para menos bots. Sin esto, también son 64.
   - `mutator=BetterBots.BBMutator` carga BetterBots. **Sin esto juegas con los bots normales.**
5. Cuando cargue el mapa, elige **bando**:
   - **South (Sur):** EE. UU. / Australia / ARVN, el bando con helicópteros.
   - **North (Norte):** NVA / Viet Cong.
6. Elige **rol** y aparece.
   - Para pilotar, coge rol de piloto. Los de combate pilotan el Cobra y el Loach; los de transporte, el Huey y el Bushranger.
   - Si no, coge cualquier rol y deja que los bots te lleven.

### Cambiar de mapa o salir
- **Otro mapa:** vuelve a abrir la consola y escribe otra línea `open ...`; no hace falta volver al menú.
- **Volver al menú principal:** escribe `disconnect`.
- **Reiniciar el mismo mapa:** vuelve a escribir la misma línea `open ...`.

### ¿Está funcionando?
- En mapas con helicópteros, unos 15 s después de aparecer los bots se suben a los helicópteros y despegan.
- También puedes escribir `BBHeliInfo` en la consola. Si BetterBots está cargado, lista los helicópteros.
- Todo lo que hace BetterBots queda en `Documentos\My Games\Rising Storm 2\ROGame\Logs\Launch.log`, en las líneas que empiezan por `[BetterBots]`.

### Mapas: comandos de consola

Copia la línea del mapa que quieras, pégala en la consola con **Ctrl+V** y pulsa **Intro**. Cambia `64` para jugar con menos bots.

| Mapa | Comando de consola |
|---|---|
| An Lao Valley | `open VNTE-AnLaoValley?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Apache Snow | `open VNTE-ApacheSnow?MinPlayers=64?mutator=BetterBots.BBMutator` |
| A Shau | `open VNTE-ASau?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Border Watch | `open VNTE-BorderWatch?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Compound | `open VNTE-Compound?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Cua Viet | `open VNTE-CuaViet?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Cu Chi | `open VNTE-CuChi?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Da Nang Air Base | `open VNTE-DaNangAirBase?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Demilitarized Zone | `open VNTE-DemilitarizedZone?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Dong Ha | `open VNTE-DongHa?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Firebase | `open VNTE-Firebase?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Firebase Georgina | `open VNTE-FirebaseGeorgina?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Highway 14 | `open VNTE-Highway14?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Hill 937 | `open VNTE-Hill937?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Hue City | `open VNTE-HueCity?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Khe Sanh | `open VNTE-KheSanh?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Long Tan | `open VNTE-LongTan?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Mekong | `open VNTE-Mekong?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Ninh Phu | `open VNTE-NinhPhu?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Operation Forrest | `open VNTE-OperationForrest?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Quang Tri | `open VNTE-QuangTri?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Resort | `open VNTE-Resort?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Rung Sac | `open VNTE-RungSac?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Saigon | `open VNTE-Saigon?MinPlayers=64?mutator=BetterBots.BBMutator` |
| Song Be | `open VNTE-SongBe?MinPlayers=64?mutator=BetterBots.BBMutator` |

**Otros modos:** el mismo final `?MinPlayers=64?mutator=BetterBots.BBMutator` sirve con cualquier nombre de mapa del juego, también las versiones de Supremacía y Escaramuza. Solo pon el nombre de ese mapa después de `open`.

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

[MIT](LICENSE) © Nestorm18. Rising Storm 2: Vietnam pertenece a Tripwire Interactive y Antimatter Games; esto es un mod no oficial hecho por fans.
