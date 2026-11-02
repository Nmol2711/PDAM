# MEMORY.md — PDAM

## Estado actual
* **022 cerrada (T1–T8); verificación manual confirmada el 2026-11-01.** Pendiente solo commit/PR acotado a los
  archivos de la 022, sin incluir los cambios de 021 ni de docs. La verificación manual de la 021 T7 sigue
  pendiente; también el commit/PR de 020.
* **Specs 001–021 aprobadas e implementadas**; 018 y 019 cerradas el 2026-11-01. La 016 quedó con el firmware
  del 2026-10-30 (`HEAD 05703d5` en `pruebas/endpoint-fijo-hx711`), sin merge.
* **Cifras 2026-11-01 (árbol con 022):** `pytest` 884 passed / 961 subtests; `flutter test` 1213;
  `flutter analyze` 103 issues (85 avisos, 18 info) y 0 errores; RNF-4 p95 59,3 ms con 10 000 logs
  (6 000 en la semana y 4 000 anteriores, base propia); `pio test` 230/230 y `pio run` SUCCESS sin cambios.

## Decisiones clave
* 022 — el APK `0.2.0+3` es la versión que incluye la 022 y se mantiene; no se toca `pubspec.yaml`.
* 022 — fuente del panel: `logs` con `event_type='feeding_dispensed'` y gramos = `measured_grams`, con
  `discounted_grams` como respaldo solo para nulos inesperados; meta = suma de horarios de mascotas con
  dispensador activo (nunca 300); completadas = éxitos de hoy con gramos acotados a las ocurrencias.
* 022 — `today_index` y `calculated_at` (ISO UTC con `Z`) vienen del servidor o de la caché, nunca del
  reloj del dispositivo; caché Isar de clave fija `ultimo`; un refresco fallido conserva lo visible con
  copy fijo; el gráfico pinta 7 posiciones y un día en 0 no lleva barra ni fondo.
* 021 — plazo de 15 min inclusivo, barrido `cerrar → descartar → encolar`, un `instante` por consulta.
* 020 — reserva = stock − pendientes, `operation_id` idempotente y descuento solo al cerrar.
* 019/018/017/015 — refresco manual de 4 s; BLE con identidad y ventana de 15 s; tokens de tema; canal
  único `SessionEvents`. Stock con `UPDATE` relativo y `rowcount`; firmware con timeout 10 s y NVS.

## Verificación manual de la 022 (confirmada el 2026-11-01)
1. Panel con datos reales: mascotas, dispensado hoy, semana y completadas/pendientes.
2. Sin conexión con caché: aviso y fecha del servidor.
3. Sin conexión sin caché: solo mascotas locales y ceros, sin gráfico inventado.
4. Error de servidor con resumen visible: conserva cifras, avisa y no muestra textos de excepción.
5. Reintento desde el error inicial.
6. Gráfico: 7 días, días en 0 sin barra, resaltado de hoy y mensaje de semana vacía.

## Errores a evitar
* No usar `DateTime.now` en negocio ni presentación del panel; no introducir `300` ni series literales.
* No usar textos de excepción en la UI (RNF-01); no volver a `n * 50`.
* `StatefulShellRoute.indexedStack` mantiene ramas montadas: `TickerMode` o estado local.
* La prueba de rendimiento de la 022 tiene base propia y temporal; `api/test.db` la comparten otras suites
  (contamina resultados): para esas, `DATABASE_URL` temporal; repetir fallos de la 019, no tocarlos.

## Deuda aceptada y riesgos
* 022 — la atribución es agregada (no por mascota); el día del servidor puede diferir del usado en 014;
  la caché no se borra al eliminar la cuenta.
* `build_runner` arrastra un [SEVERE] preexistente en `account_local_cleaner.dart:245`; el APK `0.2.0+3` va
  firmado con clave debug e incluye la 022 sin commitear.
* 021 — su verificación manual sigue pendiente; el barrido recorre todo el histórico si creciera mucho y el
  diagnóstico no escribe, así que su vista puede divergir.
* 020 — idempotencia según `operation_id`; 019 — `canPop()` no detecta modales; 018 — «Abrir ajustes» abre
  los ajustes de la app; `workspace.json` es ajeno al repositorio.
