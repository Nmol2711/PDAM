# MEMORY.md — PDAM

## Estado actual
* **Spec 014 implementada; repetición de P-T9-B pendiente (2026-10-29):** todo aprobado salvo
  esa repetición, bloqueada por un corte de luz; firmware corregido ya flasheado y escenario
  preparado. S2–S6, S8 y S7, P-T8-A, P-T9-A, P-T9-C y P-T9-D aprobadas; 41 RF con trazabilidad.
  Specs 001–013 cerradas; rama `pruebas/endpoint-fijo-hx711` pendiente de merge a `main`.
* **Cifras:** `pytest` 530 + 541 subtests; `flutter test` 412/412; `flutter analyze` 0 errores
  (95 avisos); `pio test -e native` 165/165; `pio run` SUCCESS; base de desarrollo reseteada.
* **Físicas:** orden 3, 22,23 g medidos y descontados (4637,16 → 4614,93 g); orden 4, atasco no
  resuelto (−6,28 g) sin descuento. P-T9-B conservó el pendiente y lo reenvió con cierre único,
  pero el reenvío iba después de la primera consulta; ya es al arrancar y la repetición quedó
  pendiente por corte de luz. P-T9-C no reintentó ni dejó pendiente; P-T9-D cerró `sin_reporte`.

## Decisiones clave
* Orden con ID y estados pendiente/cerrada; el stock se descuenta al cerrar con éxito, nunca al
  entregar, y se descuenta lo medido acotado a 0. El éxito compara contra los solicitados de la
  orden; si medidos < solicitados, `entrega_incompleta` sin descuento.
* **Stock relativo y atómico:** descuento `UPDATE ... stock - :d WHERE stock - :d >= 0` y
  reabastecimiento `UPDATE ... stock + :g WHERE stock + :g <= 5000`, con `rowcount`, reintento y
  traducción a `stock_fuera_de_rango`/`supera_capacidad`; nunca un stock absoluto.
* **Una orden pendiente por dispensador:** índice único parcial
  `ux_dispensing_orders_pending_dispenser` (`WHERE status='pending'`) en modelo y migración; dos
  entregas simultáneas dejan una orden y la perdedora devuelve la ocurrencia a la cola.
* Plazo de 5 min más 1 s, barrido cada 30 s y exclusión mutua con el reporte; duplicado responde
  200 con `ya_cerrada: true`. Motivo inválido: 400 sin registro; ningún rechazo de negocio es 422.
* MAC parcial `**:AB:1F`; filtros ISO con desplazamiento (`Z`); errores `detail={code,message}`.
  `Schedule.time` en zona local del servidor (`a_local_naive`, `zona` inyectable); órdenes y plazos en UTC.
* Reabastecimiento: 400 con registro en transacción aparte; la app envía `operation_id` y el
  servidor deduplica por `(user_id, operation_id)`; `current_food_grams` del cliente se ignora
  (RF-23). Comida bloqueada: espera en `dispensing_queue` a que la orden cierre o venza.
* Borrado de mascota con dispensador: 409 `pet_has_dispenser`. Firmware: timeout de 10 s, reintentos
  5/15 s, pendiente en NVS, descarte deliberado de 2xx/4xx y monitor sin MAC (orden, motivo y
  longitud formateados desde el `ReporteCiclo`, nunca releyendo el JSON; corregido en `f10802d`).
* **RF-37:** el pendiente se reenvía al arrancar, tras el WiFi y antes de validar el servidor y de
  la primera consulta, aunque no responda y una vez por arranque; sin reenvío en `STATE_NORMAL`.
* App: `locale: es` del SDK; los logs locales no se sincronizan (`isSynced = true`) y `LogState` usa solo `isOffline` como señal de caché.
* Atasco (011/013): mediana móvil de 5 válidas, ventana de 5 s, presupuesto de motor de 30 s y 3
  reintentos; retroceso a 180° de 1,2 s; verificación de 2 s; reposo en `serve:false`.

## Errores a evitar
* No comparar el progreso contra lecturas individuales ni contar el reintento al iniciar el
  retroceso; no duplicar umbrales fuera de `dispensing_utils.h`.
* No descontar stock al entregar ni omitir el filtro `fecha`; no comparar `Schedule.time` contra
  UTC. No consumir cola, bandera ni stock con asignación ORM: usar `UPDATE` y `rowcount`.
* No aplicar stock desde el cliente ni añadir `skip` por zona horaria: inyectar el desplazamiento
  (`zona`, `offsetInicio`/`offsetFin`). La migración de `logs` corre una vez por archivo y proceso
  (`BASES_MIGRADAS`); tras alterar el esquema por fuera de SQLAlchemy, usar `olvidar_migraciones`.
* No reenviar el pendiente después de consultar ni duplicarlo en dos estados: llegaría tarde.

## Deuda aceptada y riesgos
* Entrega incompleta o reporte tardío no descuentan stock (queda por encima del real). La ventana
  de 10 min de `encolar_comida` no recupera ocurrencias si el proceso cae más. Un cliente sin
  `operation_id` duplica reenvíos. Ruta con typo `/dispenserscheck-taks/{mac}`.
* Calibración válida solo para este montaje; P3 sin instrumento independiente y hardware de 005 sin probar.
