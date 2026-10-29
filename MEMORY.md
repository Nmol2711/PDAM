# MEMORY.md — PDAM

## Estado actual
* **Spec 014 implementada (2026-10-28), pendiente de pruebas físicas:** 41 RF con prueba
  automatizada y trazabilidad en `test_traceability_rf.py`; quedan P-T8-A, P-T9-B/C/D. Specs 001–013 cerradas.
* **P-T9-A aprobada con hardware real el 2026-10-29:** orden 3 con 17,27 g solicitados y 22,23 g
  medidos y descontados (4637,16 → 4614,93 g) y orden 4 con atasco y sin descuento, ambas con
  HTTP 200 al intento 1; la orden 1 (344,75 g) no es evidencia válida (el usuario manipuló la celda).
* **Auditoría 2026-10-29:** `pytest` 530 + 541 subtests; `flutter test` 412/412; `flutter analyze`
  0 errores (95 avisos); `pio test -e native` 163/163 (157 + 6 del resumen); `pio run` SUCCESS.
  Base de desarrollo reseteada (respaldo `/tmp/opencode/pdam-pre-014.db`); login sin credenciales.

## Decisiones clave (Spec 014)
* Orden con ID y estados pendiente/cerrada; el stock se descuenta al cerrar con éxito, nunca al
  entregar, y se descuenta lo medido acotado a 0. El éxito compara contra los solicitados de la
  orden; si medidos < solicitados, `entrega_incompleta` sin descuento.
* **Stock relativo y atómico:** descuento `UPDATE ... stock - :d WHERE stock - :d >= 0` y
  reabastecimiento `UPDATE ... stock + :g WHERE stock + :g <= 5000`, con `rowcount`, reintento y
  traducción a `stock_fuera_de_rango`/`supera_capacidad`; nunca un stock absoluto leído antes.
* **Una orden pendiente por dispensador:** índice único parcial
  `ux_dispensing_orders_pending_dispenser` (`WHERE status='pending'`) en modelo y migración; dos
  entregas simultáneas dejan una orden y la perdedora devuelve la ocurrencia a la cola.
* Plazo de 5 min más 1 s, barrido cada 30 s y exclusión mutua con el reporte; duplicado responde
  200 con `ya_cerrada: true`. Motivo inválido: 400 sin registro; ningún rechazo de negocio es 422.
* MAC parcial `**:AB:1F`; filtros ISO con desplazamiento (`Z`); errores `detail={code,message}`.
  `Schedule.time` en zona local del servidor (`a_local_naive`, `zona` inyectable); órdenes y plazos en UTC.
* Reabastecimiento: 400 con registro en transacción aparte; la app envía `operation_id` y el
  servidor deduplica por `(user_id, operation_id)`. `current_food_grams` del cliente se ignora
  sin error y no cuenta como campo modificado (RF-23).
* Comida programada bloqueada: espera en `dispensing_queue` a que la orden cierre o venza; `pending_dispensing` solo se consume si ya estaba puesta.
* Borrado de mascota con dispensador: 409 `pet_has_dispenser`. Firmware: timeout de 10 s, reintentos
  5/15 s, pendiente en NVS, descarte deliberado de 2xx/4xx y monitor sin MAC (orden, motivo y
  longitud formateados desde el `ReporteCiclo`, nunca releyendo el JSON).
* App: `locale: es` del SDK; los logs locales no se sincronizan (`isSynced = true`) y `LogState` usa solo `isOffline` como señal de caché.

## Decisiones clave (Specs 011 y 013)
* Atasco por mediana móvil de 5 válidas, ventana de 5 s, presupuesto de motor de 30 s y 3
  reintentos; retroceso a 180° de 1,2 s; verificación fija de 2 s; pines y motor WSAVA en la 013.
* `serve:false`/`amount:0` es reposo; `reset_wifi` tiene prioridad absoluta; consulta cada 20 s.

## Errores a evitar
* No comparar el progreso contra lecturas individuales ni contar el reintento al iniciar el
  retroceso; no duplicar umbrales fuera de `dispensing_utils.h`.
* No descontar stock al entregar ni omitir el filtro `fecha`; no comparar `Schedule.time` contra
  UTC. No consumir cola, bandera ni stock con asignación ORM: usar `UPDATE` y `rowcount`.
* No aplicar stock desde el cliente ni añadir `skip` por zona horaria: inyectar el desplazamiento
  (`zona`, `offsetInicio`/`offsetFin`). La migración de `logs` corre una vez por archivo y proceso
  (`BASES_MIGRADAS`); tras alterar el esquema por fuera de SQLAlchemy, usar `olvidar_migraciones`.

## Deuda aceptada y riesgos
* Entrega incompleta o reporte tardío no descuentan stock (queda por encima del real). La ventana
  de 10 min de `encolar_comida` no recupera ocurrencias si el proceso cae más. Ruta con typo
  `/dispenserscheck-taks/{mac}`.
* Persistencia del reporte en NVS y reenvío tras reinicio: solo P-T9-B. Calibración válida solo para
  este montaje; P3 sin instrumento independiente, hardware real de 005 sin probar y rama `pruebas/endpoint-fijo-hx711` sin merge a `main`.
