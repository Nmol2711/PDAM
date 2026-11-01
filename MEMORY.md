# MEMORY.md — PDAM

## Estado actual
* **Specs 001–019 aprobadas e implementadas.** 018 (ciclo de escaneo BLE) cerrada el 2026-11-01 con T1–T10, solo
  app Flutter; 019 (refresco de historial) cerrada el mismo día con T1–T3.
* **Cifras:** `flutter test` 1077/1077 (164/164 en `test/features/logs`) y `flutter analyze` 91 issues con 0
  errores; `pytest` 685 passed (848 subtests); `pio test -e native` 230/230; `pio run` SUCCESS (RAM 19,7 %,
  Flash 64,5 %).
* 016 cerrada con el firmware del 2026-10-30 14:18:04 (`HEAD 05703d5` en `pruebas/endpoint-fijo-hx711`), sin merge.

## Decisiones clave
* 019 — refresco manual solo con el spinner del gesto; ventana de 4 s desde el fin del último automático (mostrar la
  pestaña o reanudar con el historial visible, guardado con `Navigator.of(context, rootNavigator: true).canPop()`);
  máximo una consulta extra de ajuste; un solo indicador; error y sin conexión excluyentes; filtros por 017;
  `refrescoEnCurso` evita que el gesto quede pendiente.
* 018 — ciclo con identidad (`cycleId`): la ventana de 15 s cuenta desde el escaneo activo; el cierre libera solo su
  ciclo y la detención es idempotente. `BleScanStoppedState` es la única cesión a la lista (RF-24).
* 018 — apertura, renovación y detención van por una cola de comandos secuencial propia, sin `bloc_concurrency`; tres
  ventanas vacías pasan al estado final. Sin dependencias nuevas.
* 018 — frontera `BleAdapter`/`BlePermissions` con implementación real por defecto; las pruebas usan
  `FakeBleAdapter`/`FakeBlePermissions` y el plugin real se verificó en dispositivo (2026-11-01).
* 018 — `neverForLocation`: `androidUsesFineLocation` y `androidCheckLocationServices` solo en Android ≤11
  (`AndroidScanLocationPolicy`); ubicación en el manifiesto con `maxSdkVersion="30"`.
* 018 — aprovisionamiento acotado a 15/10/10/5 s y presupuesto de 60 s; etapas tipadas y copy en
  `provisioning_stage_messages.dart`; avisos con «Abrir ajustes»/«Reintentar». Un aviso de adaptador prevalece sobre
  permisos/ubicación y `scanFailed` (`canReplaceScanNotice`, único punto de emisión); con aviso vigente `_stopScan`
  no emite «detenido» (RF-24 prevalece).
* 017 — tokens claro/oscuro, `ColorScheme` explícito, radios 8/12 y escala 4–32.
* 015 — `SessionEvents` es el canal único; la baja ordena marca → token → credenciales → perfil → Isar.
* Stock: descuento con `UPDATE` relativo y `rowcount` (tope 5000); firmware con timeout 10 s y pendiente en NVS.

## Errores a evitar
* No duplicar duraciones (ventana/cooldown/poll) fuera del servicio; no leer `Platform` fuera de
  `AndroidLocationRequirement` y no exigir ubicación si el parseo falla.
* No emitir listas (`LoadDispensersEvent`, refresco o reabastecimiento) sin `_puedeEmitirLista()`: pisaría
  apertura, escaneo, avisos o aprovisionamiento.
* No usar textos de excepciones en la UI (RNF-01): siempre etapa tipada o copy fijo en español.
* `StatefulShellRoute.indexedStack` mantiene las ramas montadas: usar `TickerMode` o estado local.
* No volcar estados completos en `AppBlocObserver`; no crear BLoC en `setUp` de un `testWidgets`.
* Las pruebas de logs de la 019 fallan por carga de forma intermitente: repetir, no tocarlas.

## Deuda aceptada y riesgos
* 019: `canPop()` del navegador raíz no detecta modales abiertos dentro de la rama (hoy sin efecto); mientras hay un
  refresco en curso el gesto manual se ignora; un refresco puede solaparse con una carga de filtro/página (el
  resultado viejo se descarta por generación).
* 018: verificación manual en dispositivo el 2026-11-01 (Bluetooth apagado/encendido, permisos y ubicación): el
  escaneo siempre encuentra el dispensador; `openAppSettings` y las 3 ventanas funcionan. «Abrir ajustes de
  ubicación» abre los ajustes de la app (sin API directa) y los textos legados del listado de 010 quedan sin tocar.
* Tensión RF-04/RF-05: en resultados conservados y final conviven «Volver a buscar» y «Cancelar»; en ventana abierta
  solo cancelar. `workspace.json` de Obsidian es ajeno al repositorio.
