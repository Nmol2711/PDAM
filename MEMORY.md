# MEMORY.md — PDAM

## Estado actual
* **021 implementada, aprobada y verificada (2026-11-01).** Verificación manual confirmada por el usuario
  en app y ESP32 con el APK `0.2.0+3`, backend reiniciado y firmware sin cambios. Pendiente solo el
  commit/PR acotado a la 021; la 020 ya está commiteada (`19897cb`).
* **022 cerrada (T1–T8)**, verificada manualmente el 2026-11-01 y ya commiteada (`2dfce6c`).
* **Specs 001–021 aprobadas e implementadas**; 018 y 019 cerradas el 2026-11-01. La 016 quedó con el
  firmware del 2026-10-30 (`HEAD 05703d5` en `pruebas/endpoint-fijo-hx711`), sin merge.
* **Cifras 2026-11-01 (árbol con la 022 ya commiteada):** `pytest` 887 passed / 965 subtests;
  `flutter test` 1213; `flutter analyze` 103 issues (85 avisos, 18 info) y 0 errores, ninguno en archivos
  de la 021; `pio test -e native` 230/230 y `pio run` SUCCESS (RAM 19,7 %, Flash 64,5 %).

## Decisiones clave
* 021 — plazo de entrega de 15 min desde la recepción, límite inclusivo y sin la tolerancia de 1 s de las
  órdenes; el instante del servidor se inyecta y se compara en UTC naive.
* 021 — descarte transaccional por solicitud (`UPDATE ... consumed_at IS NULL` con `rowcount` y un solo
  `commit`): marca, un registro y una liberación, sin orden ni descuento de stock; un fallo no deja nada.
* 021 — barrido `cerrar → descartar → encolar` en el ciclo de 30 s, más barrido perezoso limitado al
  dispensador al consultar el equipo y al aceptar una solicitud; sin tarea ni temporizador nuevos.
* 021 — el registro guarda la mascota de la solicitud (no la actual del equipo) y el historial añade la
  línea «Stock resultante» solo cuando el registro la trae.
* 022 — fuente del panel: `logs` con `event_type='feeding_dispensed'` y gramos = `measured_grams`;
  meta = suma de horarios de mascotas con dispensador activo (nunca 300); caché Isar de clave fija
  `ultimo` con `today_index` y `calculated_at` del servidor, nunca del reloj del dispositivo.
* 020 — reserva = stock − pendientes, `operation_id` idempotente y descuento solo al cerrar.
* 019/018/017/015 — refresco manual de 4 s; BLE con identidad y ventana de 15 s; tokens de tema; canal
  único `SessionEvents`. Stock con `UPDATE` relativo y `rowcount`; firmware con timeout 10 s y NVS.

## Verificación manual confirmada el 2026-11-01
* 022: panel con datos reales, caché sin red, sin conectividad sin caché, error de servidor con resumen
  visible y reintento, gráfico de 7 días con los días en 0 sin barra.
* 021: descarte en el siguiente ciclo, historial con «Solicitud vencida», «Fallo», gramos y stock, nueva
  solicitud aceptada con la reserva liberada y reintento sin duplicar registro.

## Errores a evitar
* No usar `DateTime.now` en negocio ni presentación del panel; no introducir `300` ni series literales.
* No usar textos de excepción en la UI (RNF-01); no volver a `n * 50`.
* `StatefulShellRoute.indexedStack` mantiene ramas montadas: `TickerMode` o estado local.
* La prueba de rendimiento de la 022 tiene base propia y temporal; `api/test.db` la comparten otras suites
  (contamina resultados): para esas, `DATABASE_URL` temporal; repetir fallos de la 019, no tocarlos.

## Deuda aceptada y riesgos
* 022 — la atribución es agregada (no por mascota); el día del servidor puede diferir del usado en 014;
  la caché no se borra al eliminar la cuenta.
* `build_runner`: [SEVERE] preexistente en `account_local_cleaner.dart:245`; APK `0.2.0+3` con clave debug.
* 021 — el barrido recorre todo el histórico si creciera mucho y el diagnóstico no escribe, así que su
  vista puede divergir.
* 020 — idempotencia según `operation_id`; 019 — `canPop()` no detecta modales; 018 — «Abrir ajustes» abre
  los ajustes de la app; `workspace.json` es ajeno al repositorio.
