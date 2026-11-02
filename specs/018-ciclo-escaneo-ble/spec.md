# Spec 018 — Ciclo de escaneo BLE
**Estado:** implementada (2026-11-01) · **Fecha:** 2026-10-31
**Origen:** fallo intermitente reportado («a veces no encuentra el dispensador»); auditoría de solo lectura del flujo BLE de la app (specs 005 y 010).

## Contexto y objetivo
El escaneo funciona en el camino feliz, pero su ciclo de vida no está cerrado: la ventana de 15 s no se reinicia ni avisa, el cierre de un escaneo puede detener otro y un cambio del adaptador o del ciclo de vida rompe la búsqueda sin reflejarlo.
Objetivo: ciclo explícito y finito con salida visible; apertura, inicio y detención serializados y con identidad de ciclo; reacción al adaptador y al ciclo de vida; fin de las listas de caché; permisos verificados; aprovisionamiento acotado y estados de pantalla excluyentes con precedencia explícita.

| # | Gravedad | Hallazgo | Evidencia |
| --- | --- | --- | --- |
| 1 | Crítico | Escaneo de un disparo de 15 s sin reinicio ni aviso; spinner indefinido; ventana útil real ~12 s. | `ble_provisioning_service.dart:94-97`, `ble_scan_page.dart:61-91`, `dispenser_bloc.dart:285-286` |
| 2 | Crítico | Inicio y detención se solapan; el `finally` del flujo llama `stopScan()` sin identidad de ciclo; `_scanSubscription` del servicio nunca se asigna. | `dispenser_bloc.dart:276-305`, `ble_provisioning_service.dart:14`, `:164-173` |
| 3 | Crítico | Sin escucha de `adapterState` ni del ciclo de vida: apagar el Bluetooth o volver del segundo plano rompe el escaneo y congela la lista. | `ble_provisioning_service.dart:60-86` |
| 4 | Crítico | Sondeo de 500 ms que no se detiene fuera de escaneo y reemite caché; el estado de escaneo no admite emisión silenciosa. | `ble_provisioning_service.dart:149-158`, `dispenser_bloc.dart:267-274` |
| 5 | Alto | El encendido asistido del adaptador espera hasta 60 s; el timeout de 3 s no lo envuelve. | `ble_provisioning_service.dart:70-82` |
| 6 | Alto | Resultado de permisos ignorado y ubicación fina incoherente con `neverForLocation`. | `ble_provisioning_service.dart:34-40`, `:96`, `AndroidManifest.xml:5-8` |
| 7 | Alto | Solo la conexión tiene timeout; sin listener de conexión, el estado «aprovisionando» queda colgado. | `ble_provisioning_service.dart:176-245` |
| 8 | Alto | La detención del escaneo no emite estado propio (005 RF-02.1 a medias). | `dispenser_bloc.dart:298-305` |
| 9 | Menor | Estado de escaneo compara listas por identidad; detención emitida por triplicado. | `dispenser_state.dart:91-98`, `ble_scan_page.dart:35-42`, `:104-106`, `:123-126` |

## Requisitos funcionales (EARS)
### A. Ciclo de escaneo (RF-01 a RF-05)
- **RF-01:** CUANDO se abra la pantalla o se pida búsqueda, EL SISTEMA abrirá una ventana de 15 s contada desde el escaneo realmente activo (cooldown y retardos no la consumen); MIENTRAS esté abierta y sin dispositivos mostrará progreso y texto de búsqueda, con el primer dispositivo mostrará la lista sin progreso y el texto «Buscando más dispensadores...»; al cerrarse retirará el progreso en ≤2 s sin esperar resultado ni error.
- **RF-02:** SI la tercera ventana consecutiva sin resultados se cierra sin dispositivos, EL SISTEMA mostrará el estado final «No se encontraron dispensadores en modo de configuración», la indicación de comprobar encendido y modo configuración, «Volver a buscar» (ciclo nuevo, contador a cero) y cancelar, sin indicador de progreso.
- **RF-03:** SI la ventana cierra sin resultados, la pantalla sigue visible y el adaptador encendido, EL SISTEMA abrirá automáticamente otra ventana tras la fase de apertura hasta tres consecutivas sin resultados; al completar la tercera pasará al estado final; la apertura nunca cuenta como ventana y un resultado encontrado o una búsqueda manual reinician el contador.
- **RF-04:** CUANDO una ventana reciba dispositivos, EL SISTEMA mostrará nombre, identificador, señal y «Conectar» por dispositivo (detiene el ciclo y abre la configuración WiFi, 005 RF-03); al cerrar la ventana con dispositivos detendrá escaneo y sondeo, no renovará, no dejará temporizadores y pasará a resultados conservados con lista visible y sin texto de búsqueda; ofrecerá «Volver a buscar» como única acción de pantalla; cada dispositivo permanece hasta que se abra una ventana nueva o se reinicie, y la lista nueva parte vacía.
- **RF-05:** MIENTRAS haya apertura, ventana, resultados conservados, estado final o aviso, EL SISTEMA mantendrá cancelar; al cancelar cerrará el ciclo y saldrá en ≤2 s sin esperar cooldown, permisos ni cierre del flujo, y sin consumir ventana ni renovación.

### B. Serialización y deduplicación (RF-06 a RF-10)
- **RF-06:** SI se pide inicio con ventana abierta, EL SISTEMA lo descartará sin reiniciar tiempo ni abrir ciclos paralelos; SI la petición es manual durante la apertura de una renovación automática, la cancelará y abrirá un ciclo nuevo con contador a cero; SI repite una apertura que el usuario ya pidió, la descartará; SI hay resultados conservados, la petición manual siempre abrirá ciclo nuevo con lista vacía y contador a cero; durante una detención rige RF-09.
- **RF-07:** EL SISTEMA dará a cada ciclo un identificador propio y al cerrarlo liberará solo sus recursos, de modo que un cierre tardío no detenga el escaneo, la suscripción ni el estado de un ciclo posterior.
- **RF-08:** CUANDO se pida detener, EL SISTEMA lo hará una sola vez aunque llegue repetido desde conexión, cancelación o salida, sin error si no hay ciclo ni apertura, sin repetir cooldown, y emitirá el estado «escaneo detenido» sin progreso, que es el punto de cesión de RF-24.
- **RF-09:** CUANDO se pida búsqueda mientras se resuelve una detención anterior, EL SISTEMA esperará a que termine y solo entonces abrirá el ciclo nuevo, sin solapar apertura y cierre y sin descartar la petición.
- **RF-10:** EL SISTEMA no emitirá un estado de escaneo si la lista es equivalente a la última emitida (mismos identificadores en el mismo orden, con independencia de la señal); mostrará el último RSSI conocido del ciclo sin forzar emisión, y comparará listas por contenido.

### C. Adaptador y ciclo de vida (RF-11 a RF-14)
- **RF-11:** SI el adaptador informa `off` durante el ciclo, su apertura o antes de abrirlo, EL SISTEMA cerrará el ciclo, detendrá el sondeo, limpiará la lista y mostrará dentro de la pantalla, en la zona de la lista, «El Bluetooth está desactivado» con «Abrir ajustes» y «Reintentar», sin modal, sin bloquear navegación, sin progreso ni lista previa y sin intentar encender; `unavailable` y `unauthorized` rigen por RF-25 y `turningOn`/`turningOff` no producen aviso.
- **RF-12:** CUANDO el adaptador vuelva a `on` con la pantalla visible, EL SISTEMA reemplazará el aviso de RF-11 o RF-25 por un ciclo nuevo tras la fase de apertura, con lista vacía y contador a cero, sin exigir reiniciar la app, reentrar ni pulsar «Reintentar».
- **RF-13:** EL SISTEMA cerrará el ciclo y liberará el escaneo con `paused`, `hidden` o destrucción de pantalla; `inactive` y `resumed` transitorios no lo cerrarán (diálogos, permisos, ajustes, centro de control); al volver a `resumed` con la pantalla visible reabrirá tras la fase de apertura con lista vacía y contador a cero, salvo permisos denegados, adaptador apagado o ubicación faltante, casos que muestran su aviso sin abrir ciclo.
- **RF-14:** EL SISTEMA no pedirá ni intentará el encendido del adaptador por iniciativa propia (ni al abrirlo, ni al volver del segundo plano, ni en la pantalla de búsqueda) ni invocará el diálogo asistido del sistema; el encendido solo ocurre en los ajustes abiertos con «Abrir ajustes», cuya apertura esperará ≤3 s sin bloquear los avisos ni la reanudación de RF-12.

### D. Fin de la caché (RF-15 y RF-16)
- **RF-15:** EL SISTEMA mantendrá el sondeo solo mientras haya una ventana abierta; al cerrarse, con o sin resultados, lo cancelará en ≤500 ms y no emitirá listas después; con resultados, la cancelación ocurre junto a la del escaneo de RF-04 y no queda temporizador en resultados conservados.
- **RF-16:** EL SISTEMA no completará ni sustituirá el resultado con la caché del adaptador, ni al abrir ni durante la ventana; solo mostrará lo recibido en la ventana abierta y un ciclo nuevo nunca reutilizará la lista anterior.

### E. Permisos (RF-17 y RF-18)
- **RF-17:** CUANDO se pida escanear o aprovisionar, EL SISTEMA comprobará el resultado de los permisos de escaneo y conexión; SI quedan denegados no iniciará la operación, retirará el progreso y mostrará un mensaje en español; SI la denegación es permanente o no reaparece el diálogo ofrecerá «Abrir ajustes» y, si no es permanente, además «Reintentar»; en el aprovisionamiento dejará el botón habilitado y sin estado «aprovisionando».
- **RF-18:** EL SISTEMA configurará el escaneo de forma coherente con `neverForLocation`; SI la versión de Android exige ubicación activada y está desactivada, no iniciará el ciclo y mostrará un mensaje con «Abrir ajustes de ubicación»; en las que no la exigen no solicitará ni exigirá ubicación.

### F. Aprovisionamiento (RF-19 a RF-22)
- **RF-19:** EL SISTEMA limitará conexión a 15 s, descubrimiento a 10 s, escritura de cada credencial a 10 s y desconexión a 5 s; SI se supera, abortará, intentará la desconexión sin exceder su límite y devolverá un resultado tipado con el código de etapa (catálogo abajo), que la presentación traduce al mensaje en español, nunca un texto de la excepción.
- **RF-20:** EL SISTEMA garantizará un estado terminal de éxito o de error tipado dentro de un presupuesto de 60 s, con `presupuesto_agotado` al vencer; al terminar habilitará el botón y permitirá reintentar sin salir ni reiniciar.
- **RF-21:** SI se pierde la conexión durante descubrimiento, escritura o espera, EL SISTEMA abortará con el código `conexion_perdida`, mostrará el mensaje del catálogo y ofrecerá reintentar, sin reconexión automática.
- **RF-22:** MIENTRAS el aprovisionamiento esté en curso o hasta salir de su pantalla, EL SISTEMA descartará resultados y errores de escaneo para no pisar sus estados y no abrirá ciclos.

### G. Estados de la pantalla (RF-23 a RF-25)
- **RF-23:** CUANDO se pida abrir un ciclo, EL SISTEMA mostrará una fase de apertura con estado propio, texto «Preparando la búsqueda de dispensadores...» y cancelar, que comprende detención previa, cooldown de 1,2 s y comprobación de permisos, adaptador y ubicación, sin progreso ni lista y sin consumir ventana ni renovación; SI no puede escanear, pasará al aviso correspondiente sin contar intento (así no se muestra progreso sin ventana abierta).
- **RF-24:** EL SISTEMA resolverá la pantalla con precedencia única: aprovisionamiento > aviso de adaptador > permisos y ubicación > estados del ciclo (apertura, ventana abierta, resultados conservados, estado final, detenido; excluyentes) > lista de dispensadores; SI llega una petición de lista con un estado de mayor precedencia la descartará, salvo que el estado vigente sea «escaneo detenido», único punto de cesión, transitorio y sustituido por la lista, emitido siempre antes de esa petición; ninguna lista pisará apertura, ventana, resultados conservados, estado final, avisos, permisos, ubicación ni aprovisionamiento.
- **RF-25:** SI el adaptador informa `unavailable` o no hay soporte BLE, EL SISTEMA mostrará en la zona de la lista «El Bluetooth no está disponible en este teléfono»; SI informa `unauthorized`, mostrará «La aplicación no tiene autorización para usar el Bluetooth. Revisa los permisos en los ajustes.» con «Abrir ajustes»; en ambos casos sin ciclo, sin progreso, sin encender ni solicitar de nuevo, y con `on` aplicará RF-12.

## Requisitos no funcionales
- **RNF-01:** Lógica de ciclo, identidad, timeouts y permisos en datos y estado, nunca en vistas; sin textos visibles derivados de excepciones (solo resultados tipados y catálogo).
- **RNF-02:** Escaneo y aprovisionamiento son locales y no alteran el comportamiento sin conexión ni la lectura local; ningún fallo de red impide abrir, cerrar o reintentar un ciclo.
- **RNF-03:** Estados nuevos con paleta, tipografía, radios y escala globales, en claro y oscuro, sin colores literales.
- **RNF-04:** Textos en español, sin emojis, accionables; pantallas sin desbordamiento en móvil.
- **RNF-05:** Cada RF con al menos una prueba automatizada; las pruebas simulan los siete estados del adaptador, permisos, ciclo de vida, reloj y resultados, con temporizadores controlados.
- **RNF-06:** Sin temporizadores ni suscripciones al cerrar ventana, cerrar ciclo, salir de pantalla o detener la app; resultados conservados no mantiene sondeo.
- **RNF-07:** Sin dependencias, capas, gestor de estado ni enrutador nuevos; tipos internos, catálogo de etapas y frontera del adaptador no cuentan como cambio de arquitectura.
- **RNF-08:** No se tocan firmware, API, contrato GATT, filtro `PDAM-Config-` ni credenciales seguras; de `AndroidManifest.xml` solo el bloque de permisos Bluetooth y ubicación (RF-18).
- **RNF-09:** Trazabilidad RF/RNF/caso límite a prueba, y regresión de las specs 005 y 010.

Catálogo de etapas del aprovisionamiento: `conexion` («No se pudo conectar con el dispensador. Acércalo al teléfono y vuelve a intentarlo.»), `descubrimiento` («El dispensador no respondió al iniciar la configuración. Vuelve a intentarlo.»), `escritura` («No se pudieron enviar las credenciales al dispensador. Vuelve a intentarlo.»), `desconexion` («La configuración se envió, pero el dispensador no confirmó el cierre de la conexión. Vuelve a intentarlo.»), `conexion_perdida` («Se perdió la conexión con el dispensador. Acércalo al teléfono y vuelve a intentarlo.»), `presupuesto_agotado` («La configuración tardó demasiado y se canceló. Vuelve a intentarlo.»). Sin UUID, códigos ni trazas.

## Casos de prueba
| CP | Qué valida | RF |
| --- | --- | --- |
| CP-01 | Ventana de 15 s no consumida por la apertura; retiro del progreso; exactamente tres ventanas automáticas con estado final y contador reiniciado. | RF-01, RF-02, RF-03, RF-23 |
| CP-02 | Lista persistente al cerrar la ventana, escaneo y sondeo detenidos sin temporizadores, dispositivo visible aunque deje de anunciarse, «Conectar» navega. | RF-01, RF-04, RF-15, RF-16 |
| CP-03 | Cancelar en apertura y en ventana, en ≤2 s, sin consumir ventana ni dejar temporizadores. | RF-05, RF-08, RF-23 |
| CP-04 | Inicio descartado con ventana abierta; manual cancela renovación; «Volver a buscar» desde resultados conservados; inicio tras detención. | RF-06, RF-07, RF-09 |
| CP-05 | Cierre tardío no detiene el ciclo nuevo; doble detención idempotente con estado que cede a la lista; listas equivalentes emiten un solo estado aunque cambie el RSSI. | RF-07, RF-08, RF-09, RF-10, RF-24 |
| CP-06 | `off` cierra el ciclo y muestra el aviso en pantalla con «Abrir ajustes»/«Reintentar», sin auto-encendido; «Reintentar» con adaptador apagado deja el aviso. | RF-11, RF-12, RF-14 |
| CP-07 | `paused`/`hidden` cierran e `inactive` no; `resumed` reabre salvo permisos, adaptador apagado o ubicación; avisos sin ciclo. | RF-13, RF-16, RF-17, RF-25 |
| CP-08 | Sondeo cancelado al cerrar la ventana, con o sin resultados; ninguna lista de caché. | RF-15, RF-16 |
| CP-09 | Permisos denegados y permanentemente denegados al escanear y al aprovisionar, con ajustes, reintento y botón habilitado; permiso concedido con Bluetooth apagado prevalece el aviso. | RF-11, RF-17 |
| CP-10 | Ubicación exigida y desactivada: mensaje y ajustes; donde no se exige, no se pide. | RF-18 |
| CP-11 | Timeouts de 15/10/10/5 s, presupuesto de 60 s y pérdida de conexión: código de etapa, mensaje del catálogo, sin reintento automático y botón habilitado. | RF-19, RF-20, RF-21 |
| CP-12 | Resultados y errores de escaneo no pisan el aprovisionamiento. | RF-22 |
| CP-13 | Regresión del camino feliz 005/010 y del listado sin conexión. | RNF-02, RNF-08, RNF-09 |
| CP-14 | Fase de apertura con estado propio, cancelar, sin progreso ni lista, sin consumir ventana ni renovación. | RF-05, RF-23 |
| CP-15 | Petición de lista descartada con estado de mayor precedencia y aceptada solo con «escaneo detenido», dejando la lista visible al salir. | RF-08, RF-24 |
| CP-16 | `unavailable` y `unauthorized` con su mensaje, ajustes y sin ciclo; `turningOn`/`turningOff` sin aviso. | RF-11, RF-12, RF-25 |
| CP-17 | Tokens y escala globales, textos en español sin emojis, sin temporizadores, sin dependencias y manifiesto acotado. | RNF-03, RNF-04, RNF-06, RNF-07, RNF-08 |

Cobertura: RF-01 a RF-25 aparecen en la columna RF (RF-01/02/03/04/05→CP-01..CP-03, CP-14; RF-06..RF-10→CP-04, CP-05; RF-11..RF-14→CP-06, CP-07, CP-09; RF-15/16→CP-02, CP-07, CP-08; RF-17/18→CP-07, CP-09, CP-10; RF-19..RF-22→CP-11, CP-12; RF-23..RF-25→CP-01, CP-03, CP-14, CP-15, CP-16). RNF-05 se valida con todos los CP; RNF-01 en CP-11. Notas: la apertura no cuenta como ventana ni renovación (RF-23); un dispositivo solo sale de la lista al abrir ventana nueva o reiniciar (RF-04); `turningOn`/`turningOff` son transitorios (RF-11); el presupuesto de 60 s prevalece sobre una etapa que no venció su límite (RF-20).

## Fuera de alcance
- Dispensador guardado sin `petId` al aprovisionar (`dispenser_bloc.dart:820-829`) y su filtrado (`dispenser_repository_impl.dart:202`): spec propia.
- Firmware ESP32 y backend FastAPI (endpoints, anuncios, publicidad, reseteo de credenciales).
- Rediseño de pantallas más allá de estados y acciones: solo la precedencia de RF-24 toca el listado.
- Cambios de arquitectura, gestor de estado, enrutador o dependencias.
- Reconexión automática tras pérdida de conexión y aprovisionamiento simultáneo o escaneo en segundo plano.
- Filtro `PDAM-Config-`, UUID GATT, credenciales seguras y diagnóstico del hardware que no anuncia.

## Criterios de finalización
1. Sin indicador de progreso si no hay ventana abierta; apertura y resultados conservados tienen estado propio sin progreso (CP-01, CP-02, CP-03, CP-06, CP-07, CP-14).
2. Estado final con «Volver a buscar» tras tres ventanas de 15 s desde escaneo activo, sin consumo por la apertura (CP-01, CP-14).
3. Inicio, renovación y detención serializados e idempotentes, sin que un cierre afecte a otro ciclo (CP-04, CP-05).
4. Avisos de adaptador en pantalla, sin modal ni auto-encendido; `paused`/`hidden` cierran e `inactive` no; reanudación e `unavailable`/`unauthorized` con su aviso (CP-06, CP-07, CP-16).
5. Sin listas de caché, sin estados equivalentes y sin que una lista pise un estado de mayor precedencia; «escaneo detenido» como único punto de cesión (CP-05, CP-08, CP-15).
6. Permisos y ubicación informados en español con acción de ajustes al escanear y al aprovisionar (CP-09, CP-10).
7. Aprovisionamiento con estado terminal en 60 s, código de etapa, copy del catálogo y sin ser pisado por el escaneo (CP-11, CP-12).
8. Lo no funcional se cumple y `flutter test` pasa completo, `flutter analyze` da cero errores, sin regresión 005/010 y con `MEMORY.md` actualizado (CP-13, CP-17).

Prevalencia: 018 manda en ciclo de escaneo, adaptador, permisos y timeouts; 005 en flujo de credenciales y hardware; 010 en sus demás correcciones.

## Dudas abiertas
Dudas: ninguna.

## Notas de implementación
- La espera de la detención pendiente (RF-09) se acota a 5 s (`_pendingStopLimit`): una liberación atascada no bloquea la cola.
- `scanFailed` no estaba en el catálogo: se adopta «No se pudo iniciar la búsqueda de dispensadores. Revisa el Bluetooth e inténtalo de nuevo.»
- «Abrir ajustes de ubicación» abre los ajustes de la aplicación con `openAppSettings`; los ajustes del sistema de ubicación exigen una dependencia nueva (RNF-07).
- Tensión RF-04/RF-05: en resultados conservados y estado final conviven «Volver a buscar» y «Cancelar»; con ventana abierta solo «Cancelar» (RF-06).
- `androidCheckLocationServices` se condiciona también a la versión (≤ API 30) para que el plugin no exija ubicación en Android 12+.
- Se retiró el reintento automático de `startScan` heredado de 005: un fallo transitorio pasa a aviso `scanFailed` con «Reintentar».
- `unavailable` y `unauthorized` muestran también «Reintentar», permitido por CP-09; `unknown` se trata como transitorio.
- Cifras 2 s / 500 ms / 15 / 10 / 10 / 5 / 60 s verificadas en QA. Módulo dispensadores 296/296; suite 1101/1101; `flutter analyze` 0 errores.
