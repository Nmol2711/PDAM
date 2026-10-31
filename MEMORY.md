# MEMORY.md — PDAM

## Estado actual
* **Specs 001–016 aprobadas.** La 016 (solo firmware) tiene T1–T8 hechas y **T9 pendiente de las pruebas físicas
  (a)–(d) y de la no regresión física de la 013**; el resto de T9 (documentación) está cerrado. La 015 quedó con
  T1–T10 y correcciones finales; la rama `pruebas/endpoint-fijo-hx711` sigue sin merge.
* **Cifras:** `pio test -e native` 230/230 en verde; `pio run` SUCCESS (RAM 19,7 % / 64 476 B, Flash 64,5 % /
  2 028 994 B); `pytest` en `api/` 685 passed (848 subtests); `flutter test` 737/737; `flutter analyze` 0 errores.
* **Documentación 2026-10-30:** diagrama de flujo de los 7 procesos en `docs/informes/informe-diagrama-flujo-sistema-2026-10-30.md`; el de `docs/docs-diagramas/Diagrama-Flujo.md` sigue desactualizado.

## Decisiones clave
* 016 — lógica pura y constantes en `config/scale_guard_utils.h` y `dispensing_utils.h` (único lugar, con
  `static_assert(kMedianBufferSize >= 11)`); asentamiento a 5 Hz desde `loop()` con `ensureHx711Initialized()`
  (un solo `hx711.begin()`), sin tarea FreeRTOS ni memoria compartida.
* 016 — la compuerta `decideDispenseEntry` va **antes** de comprobar el factor: un factor de calibración inválido
  (0, −1, NaN, inf) se reporta como `sensor_no_disponible`, nunca como `orden_invalida` (caso (d)); sin
  asentamiento no se toca el servo y el reporte va sin `gramos_medidos`.
* 016 — en la línea base, el aborto por 3 inválidas se resuelve **antes** de `assessBaseline` (el `break` de la
  ventana no distingue el motivo); el veredicto es `CycleDiagnostics::baselineRejection` con `NOT_EVALUATED`
  porque el veredicto puro no tiene «sin veredicto», y `verificationBaseline` queda para la mediana de diagnóstico.
* 016 — la plausibilidad se evalúa en cada lectura válida de avance, retroceso y pausa antes del objetivo y del
  atasco; 3 lecturas fuera cierran con `SENSOR_UNAVAILABLE` sin retroceso. `maxIncrementGrams` se inicializa con
  el primer incremento válido (`hasIncrement`), así que un ciclo todo negativo informa −12 g y no un 0 g no medido.
* 016 — `api_service` invalida el asentamiento al abrir el ciclo y tras `SENSOR_UNAVAILABLE`/`SENSOR_FAILURE`
  (motivos neutros), nunca tras `COMPLETED` ni un atasco reintentado; `reporteDesdeResultado` omite
  `gramos_medidos` solo con `SENSOR_UNAVAILABLE`, sin alterar `order_id`, solicitados, reintentos ni el contrato 014.
* 016 — el plan quedó alineado (§5.3, §5.4, §9.2) con el caso feliz a **20 g** y no 50 g: a 1 g/s, 50 g superarían
  los 30 s de motor de RNF-2. «Tope sobre atasco» es inalcanzable (todo salto > tope supera el objetivo); la
  prioridad de RF-6 se fija con el suelo.
* 015 — `SessionEvents` es el canal único interceptor→`AuthBloc`; el 401 limpia en `AuthBloc` token, tipo,
  credenciales y perfil (conserva mascotas, horarios, historial y `user_theme_mode`). La baja ordena
  marca → token/tipo → credenciales → perfil → Isar acotado → borrar marca, nunca `clear()`.
* 015 — `debeMostrarEntrada(ancho, ubicacion)` decide cabecera (`<600`) o barra (`>=600`), nunca ambas;
  `ThemeCubit` persiste en `user_theme_mode` y `aThemeMode()`/`codigoDeModo()` viven fuera del dominio.
* Stock: descuento al cerrar con éxito (nunca al entregar) con `UPDATE` relativo y `rowcount` (tope 5000); entrega
  incompleta o reporte tardío no descuentan. Firmware: timeout 10 s, reintentos 5/15 s, pendiente en NVS.

## Errores a evitar
* La regla de `gramos_medidos` tiene **dos** mitades: un caso `SENSOR_UNAVAILABLE` no prueba
  `incrementAvailable = false`; hace falta un motivo que sí declararía medidos (`NOT_REACHED`, `SENSOR_FAILURE`).
  Fue un hueco real: con el mutante que quita `incrementAvailable &&` el caso antiguo seguía pasando.
* No volcar estados ni errores completos en `AppBlocObserver` (solo `runtimeType`); no usar `RadioListTile`; no
  limpiar la sesión desde el interceptor; no crear `DioClient` sin `SessionEvents`.
* No crear un BLoC en `setUp` de un `testWidgets` ni usar `pumpAndSettle` con indicadores animados.

## Deuda aceptada y riesgos
* Marca de baja sin identidad y dispensadores con `petRemoteId == null` se borran siempre: perfil local único.
* Incidente 2026-10-30 (013): línea base 0,0 g inestable y 364,66 g para 17,27 g; ciclo anulado (stock 4614,93 g;
  copia en `/tmp/opencode/pdam-antes-limpieza-2026-10-30.db`).
* Intermitencia preexistente de las dos pruebas de rendimiento con umbral ≤100 ms: fallan por carga, no por regresión.
