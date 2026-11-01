# MEMORY.md — PDAM

## Estado actual
* **020 cerrada (T1–T6); verificación manual confirmada. Pendiente solo commit/PR:** dispensación rápida manual
  (máx. 200 g), cobertura de horarios en la ventana de 10 min y acceso «Dispositivos».
* **Specs 001–019 aprobadas e implementadas.** 018 (escaneo BLE) y 019 (refresco de historial) cerradas el 2026-11-01.
* **Cifras:** `pytest` 778 passed (937 subtests); `flutter test` 1139/1139; `flutter analyze` 91 issues con 0 errores;
  `pio test -e native` 230/230; `pio run` SUCCESS (RAM 19,7 %, Flash 64,5 %).
* 016 cerrada con el firmware del 2026-10-30 14:18:04 (`HEAD 05703d5` en `pruebas/endpoint-fijo-hx711`), sin merge.

## Decisiones clave
* 020 — reserva de stock = stock − solicitudes pendientes, revalidada bajo bloqueo de escritura; `operation_id`
  obligatorio con deduplicación por dispensador; revalidación de orden en curso tras el bloqueo; cobertura de ocurrencias
  sin rastro visible; prevalencia acotada sobre 014 RF-25 (solo la ocurrencia cubierta); descuento solo en cierre exitoso;
  solicitud descartada si el dispensador se reasigna; baja de mascota con dispensador como 409 `pet_has_dispenser` (sin
  cascada por mascota); solicitud sin entrega queda pendiente sin vencimiento.
* 019 — refresco manual solo con el spinner del gesto; ventana de 4 s desde el fin del último automático; máximo una
  consulta extra de ajuste; un solo indicador; error y sin conexión excluyentes; filtros por 017.
* 018 — ciclo con identidad (`cycleId`) y ventana de 15 s; cierre idempotente; comandos por cola secuencial propia;
  tres ventanas vacías pasan al estado final; `BleScanStoppedState` es la única cesión a la lista (RF-24).
* 018 — frontera `BleAdapter`/`BlePermissions` con implementación real por defecto y dobles en pruebas; aprovisionamiento
  acotado a 15/10/10/5 s y presupuesto de 60 s; avisos tipados con «Abrir ajustes»/«Reintentar»; `neverForLocation` y
  ubicación en el manifiesto solo para Android ≤11.
* 017 — tokens claro/oscuro, `ColorScheme` explícito, radios 8/12 y escala 4–32.
* 015 — `SessionEvents` es el canal único; la baja ordena marca → token → credenciales → perfil → Isar.
* Stock: descuento con `UPDATE` relativo y `rowcount` (tope 5000); firmware con timeout 10 s y pendiente en NVS.

## Errores a evitar
* No duplicar duraciones (ventana/cooldown/poll) fuera del servicio; no leer `Platform` fuera de
  `AndroidLocationRequirement` y no exigir ubicación si el parseo falla.
* No emitir listas (`LoadDispensersEvent`, refresco o reabastecimiento) sin `_puedeEmitirLista()`.
* No usar textos de excepciones en la UI (RNF-01): siempre etapa tipada o copy fijo en español.
* `StatefulShellRoute.indexedStack` mantiene las ramas montadas: usar `TickerMode` o estado local.
* No volcar estados completos en `AppBlocObserver`; no crear BLoC en `setUp` de un `testWidgets`.
* Las pruebas de logs de la 019 fallan por carga de forma intermitente: repetir, no tocarlas.

## Deuda aceptada y riesgos
* 020: una solicitud sin entrega no vence; la idempotencia depende de que la app reutilice el `operation_id`; el límite de
  200 g no garantiza alcanzarlo en los 30 s de la 013; la base `test.db` es compartida entre pruebas.
* 019: `canPop()` del navegador raíz no detecta modales abiertos dentro de la rama; mientras hay un refresco en curso el
  gesto manual se ignora; un refresco puede solaparse con una carga de filtro/página (el resultado viejo se descarta por
  generación).
* 018: escaneo verificado en dispositivo el 2026-11-01; «Abrir ajustes de ubicación» abre los ajustes de la app y los
  textos legados del listado de 010 quedan sin tocar.
* Tensión RF-04/RF-05: en resultados conservados y final conviven «Volver a buscar» y «Cancelar»; en ventana abierta
  solo cancelar. `workspace.json` de Obsidian es ajeno al repositorio.
