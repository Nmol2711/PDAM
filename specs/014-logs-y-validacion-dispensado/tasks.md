# Tareas — Spec 014

Cada tarea es un corte vertical de una capa. Si al ejecutarla supera los 30 minutos, se subdivide internamente en `Tn.a`/`Tn.b` sin añadir una tarea nueva ni pasar de 10. Los tests se escriben primero y se ponen en rojo antes de implementar. Ninguna tarea se marca hasta cumplir su comprobación.

- [x] **T1. Restaurar el árbol limpio y fijar la línea base.**
  RNF-4, RNF-6
- Hecho cuando: los tres archivos de la implementación parcial vuelven a `HEAD`; el grep de `stock_solicitado`, `descripcion_contexto`, `validar_stock_despues_dispensado` y `crear_log_con_stock` en `api/app` no devuelve nada; el diff de seguridad existe y no está vacío en `/tmp/opencode/spec014-parcial.diff`; la línea base queda registrada con sus cifras de `pytest`, `flutter test`, `flutter analyze` y `pio test -e native`; y las pruebas que codifican el comportamiento viejo que la 014 cambia quedan anotadas para reescribirlas en T4 y T6: `test_check_pending_task_discounts_food_automatically`, los dos tests de refill que esperan `refill_exceeds_capacity` y los subtests `POST /logs/` de `test_api_basic.py` y `test_protected_routes.py`; añade también a esa lista los tests de `GET /logs/` que cambian de contrato en T7.
- Ejecutado 2026-10-28: los tres archivos coinciden con `HEAD` (`git hash-object` = `HEAD:<ruta>`, `git status` limpio para ellos) y el diff descartado quedó guardado en `/tmp/opencode/spec014-parcial.diff` (8 858 B); la búsqueda de `stock_solicitado`, `descripcion_contexto`, `validar_stock_despues_dispensado` y `crear_log_con_stock` en `api/app` no devuelve nada (se borraron los `.pyc` obsoletos de esos tres módulos). Línea base medida: `pytest` 244 passed + 113 subtests, `flutter test` 286 passed, `flutter analyze` 0 errores (71 warnings y 30 infos preexistentes), `pio test -e native` 137/137. Todo en verde porque el código de `HEAD` todavía coincide con sus pruebas. Las pruebas que codifican el comportamiento viejo que la 014 cambia y que se reescribirán: `tests/test_dispenser_food.py::test_check_pending_task_discounts_food_automatically` (T4), `::test_refill_dispenser_rejects_exceeding_capacity` y `::test_refill_dispenser_rejects_amount_above_capacity`, ambos por `refill_exceeds_capacity` (T6), el subtest `POST /logs/` de `test_post_routes_require_authentication` en `tests/test_api_basic.py` y `tests/test_protected_routes.py` (T6), y los tests de `GET /logs/` que cambian de contrato (T7).

- [x] **T2. Modelo, migración de `logs` y tablas nuevas.**
  RF-3, RF-6, RF-41, RNF-8
- Hecho cuando: `models.py` define `ActivityLog` con las columnas de §6.1 y las tablas `dispensing_orders`, `dispensing_queue` y `refill_operations`; `database.py` expone `_migrar_logs` idempotente que reconstruye una base legada (con `event`/`timestamp` y, si existe, con columnas parciales), conserva `id`, `user_id`, `pet_id`, `description` y `created_at`, rellena `pet_name`, deja los campos tipados en `NULL` y crea los índices; `pytest api/tests/test_logs_migration.py` pasa con base nueva, base legada y doble apertura, y comprueba que borrar la mascota no anula `logs.pet_id`; `seed_logs.py` usa el esquema nuevo.
- Ejecutado 2026-10-28: `ActivityLog` tiene las 18 columnas de §6.1 (sin `event`/`timestamp`, con `pet_id` y `dispenser_id` como instantáneas sin FK) y existen `DispensingOrder`, `DispensingQueue` y `RefillOperation` con sus índices y únicas (`ux_dispensing_queue_ocurrencia`, `ux_refill_operations_usuario_operacion`), exportadas en `models/__init__.py`. `database.py` añade `_migrar_logs(conexion, cursor)` con helpers (`_crear_tabla_logs_nueva`, `_copiar_filas_logs`, `_crear_indices_logs`), invocada en el listener `connect` después de las migraciones existentes (MAC y columnas de `dispensers`, intactas) y antes del `create_all` de `main.py`; reconstruye `logs` cuando falta `event_type`/`description`/`created_at` o sobrevive alguna columna descartada, conserva id, user_id, pet_id, dispenser_id, description (=`description` o `event`) y created_at (=`created_at` o `timestamp`), rellena `pet_name` desde `pets`, deja tipados y métricas en NULL, y aborta con `RuntimeError` sin borrar la tabla si el recuento no coincide. `pytest api/tests/test_logs_migration.py`: 15 pruebas en verde (rojo inicial con 14 fallos). Ajuste mínimo de compatibilidad, sin adelantar T4/T6/T7: en `schemas.py` `ActivityLogBase.event`/`ActivityLog.timestamp` pasan a `description`/`created_at` (mismo nombre de clase, que T7 sustituye por `schemas/logs.py`), `logs_service` consulta y crea con `created_at`/`description`, y `seed_logs.py` siembra filas sin tipo (`event_type`/`outcome`/`cause` en NULL) con `pet_name` y `created_at` UTC naive. `pytest` completo: 259 passed + 113 subtests (244 + 15 nuevas, ningún test previo modificado). Prueba manual sobre copia de `api/app/db/pdam.db` en `/tmp/opencode/pdam-copia.db`: 4 filas conservadas (la base real tiene 4, no 56), 18 columnas, `pet_name` rellenado, tipados en NULL, las tres tablas nuevas creadas y `GET /logs/` autenticado responde 200. Pendiente para T4/T6/T7: reescribir `logs_service`/`schemas` con el sobre paginado, filtros, catálogo y sin `POST /logs/`; `order_service` y el barrido de vencimiento; la validación de reabastecimiento idempotente.

- [x] **T3. Catálogos cerrados, relojes, MAC parcial, descuento y validación de consulta.**
  RF-2, RF-3, RF-7, RF-14, RF-21, RF-24, RF-30, RF-31, RF-32, RNF-1, RNF-7
- Hecho cuando: `domain/catalogos.py` contiene los catálogos completos de la spec con etiquetas y mensajes exactos y el subconjunto de motivos de reporte; `domain/tiempo.py` acepta `Z` y desplazamientos, rechaza naive e inválidos y define el plazo con tolerancia inclusiva; `domain/stock.py` calcula el descuento acotado y el faltante; `domain/consulta.py` valida filtros, precedencia y paginación; `mask_mac` devuelve `**:AB:1F` para cualquier MAC equivalente; `pytest api/tests/test_logs_domain.py` pasa con tablas de casos para los 9 tipos, 2 resultados, 12 causas, 6 motivos y 11 errores, y comprueba que no hay valores libres aceptados.
- Ejecutado 2026-10-28: creados `api/app/domain/{__init__,catalogos,tiempo,stock,consulta}.py` y `api/tests/test_logs_domain.py` (rojo inicial por `ModuleNotFoundError: app.domain`). `catalogos.py` define `TIPOS_EVENTO` (9), `RESULTADOS` (2), `CAUSAS` (12, con `etiqueta`/`resultado`/`origen`), `MOTIVOS_REPORTE` (6 derivados del origen), `MENSAJES_ERROR`, `ETIQUETA_SIN_CLASIFICAR`, `es_tipo_valido`, `es_resultado_valido`, `es_causa_valida`, `es_causa_de_reporte`, `etiqueta_*`, `resultado_para_motivo(motivo, medidos, solicitados)` y `ErrorDominio(code)` con `.code`, `.message` y `.detail` para el 400 de T4/T7. `tiempo.py`: `PLAZO_ORDEN` 5 min, `TOLERANCIA` 1 s, `INTERVALO_BARRIDO` 30 s, `ahora_utc`, `a_utc_naive`, `parsear_instante_explicito` (`Z`→`+00:00`, rechaza naive e inválidos con `rango_fechas_invalido`), `limite_del_plazo`, `dentro_del_plazo` inclusivo y `plazo_vencido` exclusivo. `stock.py`: `CAPACIDAD_MAXIMA_GRAMOS` y `calcular_descuento(medidos, stock) → (descontados, faltante)` acotado entre 0 y el stock. `consulta.py`: `normalizar_paginacion` (1..∞, 1..100, sin recortes), `validar_filtros`, `validar_consulta` con la precedencia `rango_fechas_invalido → tipo_evento_invalido → resultado_invalido → pagina_invalida → tamano_pagina_invalido`, `total_paginas` con `max(1, ceil)` y `orden_estable()`. `mask_mac` en `mac_service` reutiliza `normalize_mac` y devuelve `**:AB:1F` también con 8 octetos y con cualquier separador; sin dos octetos hexadecimales devuelve `**`. Verificación de los textos: comparación programática de las tablas de la spec con los catálogos, idénticos carácter a carácter para 9 tipos, 2 resultados, 12 causas y los mensajes de error. Discrepancia documental: la tabla de errores de `spec.md` tiene **11** filas (las que se implementan, porque su prueba transversal exige que ninguna fila quede sin uso en un RF) y no se inventa ningún código; la nota quedó fijada en el test y las cifras de `plan.md`/`tasks.md` se corrigieron a 11. `pytest api/tests/test_logs_domain.py`: 66 pruebas y 266 subtests en verde. `pytest` completo: 325 passed + 379 subtests (259 + 113 previos, ninguna prueba anterior modificada). No se creó `cierre.py`, ni servicios, endpoints, schemas o filtros aplicados a la base: eso queda para T4 y T7.

- [x] **T4. Entrega de orden, reporte, cierre atómico y descuento.**
  RF-1, RF-13, RF-14, RF-15, RF-16, RF-17, RF-18, RF-20, RF-21, RF-22, RF-23, RF-24, RNF-3, RNF-8
- Hecho cuando: `check_pending_task` crea la orden pendiente con `order_id`, hora del servidor y sin tocar stock; `POST /dispensers/reports` normaliza la MAC, valida motivo y orden en el orden definido, cierra con éxito solo si los medidos alcanzan los solicitados de la orden, descuenta lo medido acotado, guarda medidos y descontados separados, responde `ya_cerrada` en duplicados y tardíos, y devuelve 400 `mac_no_registrada`/`motivo_invalido`/`orden_desconocida`; la transición usa `UPDATE ... WHERE status='pending'` con `rowcount`; un fallo al escribir el log revierte descuento y cierre y devuelve 500; `pytest api/tests/test_orders_dispensing.py api/tests/test_orders_concurrency.py` pasa, incluido el caso de dos reportes simultáneos con un único log y un único descuento.
- Ejecutado 2026-10-28: creados `api/app/services/order_service.py` (`entregar_orden`, `procesar_reporte`; `cerrar_vencidas`/`encolar_comida` quedan en T5), `api/app/services/activity_service.py` (`registrar` con `flush` y sin `commit`, `registrar_rechazo` en `SessionLocal` con confirmación), `api/app/schemas/reports.py` (`DispenserReportRequest` con todos los campos `Any` y `extra="ignore"`, `DispenserReportResponse`) y `api/app/domain/cierre.py` (`resolver_cierre_por_reporte` → `(outcome, cause, tardio)`, que reutiliza `resultado_para_motivo` y `plazo_vencido` de T3 sin duplicar catálogos ni plazos). En `domain/stock.py` se añaden `stock_fuera_de_rango` y `aplicar_descuento_acotado(stock, medidos) → (descontados, faltante, stock_resultante)`, que rechaza con `stock_fuera_de_rango` si el resultante sale de 0..5000 g antes de escribir nada; `normalizar_gramos` y `aplicar_reabastecimiento` quedan para T6. `dispenser_service.check_pending_task` delega en `order_service.entregar_orden(db, mac, simular=test)`: ya no descuenta stock, crea la orden pendiente con `delivered_at` del servidor en UTC naive y devuelve `order_id`; conserva el 404 sin registro, el reseteo de WiFi con prioridad absoluta (antes de `is_active`, según §4.1) y el reposo `{serve:false, amount:0}`; `check-taks-test` simula sin escribir nada. Endpoint `POST /dispensers/reports` sin token que traduce `ErrorDominio` a 400 `detail={code,message}` y deja el 500 al fallo de escritura. Cierre: el registro se escribe primero (con `flush`) para guardar su `log_id`, la transición es un único `UPDATE ... WHERE id=? AND status='pending'` con `rowcount` y, si no afecta filas, `rollback` (descarta el registro del perdedor) y respuesta con el resultado guardado y `ya_cerrada:true`; el stock se descuenta en la misma transacción y solo con éxito; cualquier excepción revierte y responde 500. Pruebas nuevas: `test_orders_dispensing.py` (38 pruebas, 19 subtests) y `test_orders_concurrency.py` (2 pruebas: dos reportes en hilos con sesiones distintas y una sesión que leyó la orden como pendiente antes de que otra la cerrara; en ambos casos un único cierre, un único registro y un único descuento). En `test_dispenser_food.py` solo cambia `test_check_pending_task_creates_the_order_without_discounting_stock` (antes `..._discounts_food_automatically`): el esperado pasa de 950 g a 1000 g y se comprueba la orden pendiente creada; los códigos de refill siguen intactos para T6. `pytest` completo: 365 passed + 398 subtests (325 + 40 nuevos, ninguna otra prueba previa modificada). Queda para T5 el barrido de vencimientos y la cola, para T6 el registro de mascotas/dispensadores/reabastecimiento y la retirada de `POST /logs/`, y para T7 la consulta con filtros y paginación.

- [x] **T5. Vencimiento a 30 s y comidas en espera.**
  RF-19, RF-25, RF-40, RNF-3
- Hecho cuando: `main.py` programa un único job cada 30 s con `max_instances=1` que ejecuta `cerrar_vencidas` y luego `encolar_comida`; una orden pendiente se cierra como `sin_reporte` a más tardar 60 s después del plazo más 1 s, nunca antes y sin descuento; una comida programada que coincide con una orden pendiente o un dispensador desactivado queda en `dispensing_queue`, no se descarta y se entrega al cerrar/vencer/reactivarse; el firmware antiguo cierra por plazo; `pytest api/tests/test_orders_expiry.py api/tests/test_feeding_queue.py` pasa con reloj falso y pruebas de frontera en el límite exacto.
- Ejecutado 2026-10-28: `order_service.cerrar_vencidas(db, ahora, dispenser_id=None)` selecciona las pendientes con `plazo_vencido` (exclusivo: en el límite exacto no cierra), escribe el registro `sin_reporte` con `flush` y transiciona con `UPDATE ... WHERE status='pending'` y `rowcount` en la misma transacción, sin tocar el stock ni exigir reporte (RF-19, RF-40); si otra transacción gana, revierte su registro. `encolar_comida(db, ahora)` inserta una fila por ocurrencia `(dispenser_id, schedule_id, scheduled_for)` dentro de `VENTANA_OCURRENCIA` (10 min, el margen del job anterior) con la clave única como red y un punto de guardado por fila; `entregar_comida_en_espera(db, dispensador, ahora)` consume la ocurrencia y crea la orden en la misma transacción, sin descontar. `entregar_orden` aplica RF-25 en este orden: orden pendiente en plazo → reposo sin consumir la cola; orden vencida → se cierra en esa consulta y la cola sigue esperando (se entrega en la consulta siguiente); dispensador desactivado → reposo sin consumir la cola; si no hay bloqueo, entrega la espera más antigua. `main.py` deja un único job `barrido_ordenes` cada `INTERVALO_BARRIDO` (30 s) con `max_instances=1`, `coalesce=True` y `replace_existing=True`, que ejecuta `background_schedules.ejecutar_barrido` (primero `cerrar_vencidas`, después `encolar_comida`); se retiró el job de 60 s que activaba `pending_dispensing` y ese es el único cambio de tareas programadas (no había otras). No se creó `background_tasks/order_expiry.py` del plan: el ciclo vive en `background_schedules.py` y `check_and_activate_scheduled_feedings` queda como alias del barrido. `pending_dispensing` no se migra: la columna se conserva y solo se consume como solicitud puntual heredada, nunca como fuente de verdad. Pruebas: `test_orders_expiry.py` (16) y `test_feeding_queue.py` (17) nuevas; `test_orders_dispensing.py` suma `TestAjustesDeCierreDeT4` (8) con los cierres del bloque A: `reintentos` ausente en el contexto como «no disponible», `_numero` solo admite finitos (`NaN`, `±infinito`, `"1e999"` y texto no numérico se tratan como ausentes; los negativos no descuentan ni acreditan), el 500 de la entrega ya es genérico y `POST /dispensers/reports` recibe el cuerpo como `Any` y responde 400 `motivo_invalido` a lista, cadena, número, `null` y cuerpo vacío (el catálogo no tiene código propio y no se inventa). Ajuste mínimo documentado en `test_dispenser_food.py`: el mock de la entrega declara vacíos los conjuntos nuevos (órdenes pendientes y cola) para que la bandera heredada siga entregando como en T4. `pytest` completo: 406 passed + 410 subtests (365 + 41 nuevas, ningún test previo reescrito). Corrección tras la revisión (2026-10-28): (1) `Schedule.time` se interpreta en la zona local del servidor con `tiempo.a_local_naive` y `scheduled_for` guarda esa hora de pared local; las órdenes, los plazos y los registros siguen en UTC (RNF-8). (2) la ocurrencia se reclama con `UPDATE ... SET consumed_at = :ahora WHERE id = :id AND consumed_at IS NULL` y `rowcount`, y la bandera heredada con `UPDATE ... SET pending_dispensing = 0 WHERE pending_dispensing = 1`; si se pierde la reclamación se prueba la siguiente ocurrencia y, si no hay, se responde reposo, todo en la misma transacción que crea la orden. (3) opción (a): `DispenserUpdate` ya no acepta `pending_dispensing` (un campo extra se ignora sin 422) y la bandera solo se consume si ya estaba puesta; una bandera preexistente puede añadir una entrega heredada después de drenar la cola (deuda de compatibilidad). (4) `plan.md` §4.1 describe que el cierre por vencimiento responde reposo y entrega la cola en la consulta siguiente (hasta 20 s por el intervalo del firmware) y el límite de la ventana de 10 min si el proceso está caído. Pruebas nuevas: `TestHoraLocalDelServidor` (3) y `TestConcurrenciaDeEntrega` (2) en `test_feeding_queue.py`, más `test_el_put_ya_no_acepta_la_bandera_heredada` en `test_orders_dispensing.py`; con el código anterior fallaban las 3 de hora local y la concurrencia 5 de 5 ejecuciones. `pytest` completo: 412 passed + 410 subtests (406 + 410 de base más 6 nuevas); `TZ=America/Bogota`: 412 passed + 410 subtests; la suite de concurrencia (2 reportes + 2 entregas simultáneas) pasó 5 de 5 ejecuciones.
- Cierre 2026-10-28 (revisión): se añade `test_un_dispensador_desactivado_no_dispensa_al_vencer_su_orden_pendiente` en `test_feeding_queue.py`, que cubre la cláusula de RF-25 «un dispensador desactivado no dispensa aunque venza el plazo de su orden pendiente»: con la orden ya fuera de plazo más la tolerancia y el dispensador desactivado, la consulta responde reposo, la orden se cierra como `sin_reporte`, no se crea una orden nueva y la ocurrencia sigue sin consumir; la consulta siguiente —ya sin orden pendiente y con el dispensador aún desactivado— tampoco dispensa ni consume la cola, que es el punto donde el vencimiento podría habilitar la dispensación por error. Se comprobó con una copia en `/tmp/opencode` que la prueba falla si se invierte la condición `is_active` de `entregar_orden` (la segunda consulta dispensaba 40 g y creaba la orden 2). También se corrige el docstring de `app/domain/tiempo.py`, que afirmaba no usar la zona horaria del sistema cuando `a_local_naive` sí la usa para los horarios de comida. `pytest` completo: 413 passed + 410 subtests; `test_feeding_queue.py`: 23.

- [x] **T6. Registros de mascotas, dispensadores y reabastecimiento; retirada del `POST /logs/`.**
  RF-1, RF-2, RF-4, RF-5, RF-6, RF-7, RF-8, RF-9, RF-10, RF-11, RF-12, RF-22, RF-23, RNF-1, RNF-7
- Hecho cuando: crear, modificar y eliminar mascota o dispensador, el reseteo de WiFi y el reabastecimiento escriben su registro con tipo, resultado, causa, mascota, MAC parcial, descripción y contexto en la misma transacción; `pet_updated`/`dispenser_updated` solo guardan nombres de campos; ningún contexto contiene SSID, credenciales, tokens, correos ni MAC completa; el reabastecimiento aceptado registra `origen=servidor`, el sincronizado usa la hora de la sincronización y `origen=sincronizacion_sin_conexion`, el doble `operation_id` no duplica, y los rechazos responden 400 `cantidad_invalida`/`supera_capacidad` con stock intacto y log en sesión independiente; `POST /logs/` ya no existe; `pytest api/tests/test_activity_logs_crud.py api/tests/test_refill_logs.py api/tests/test_dispenser_food.py api/tests/test_protected_routes.py api/tests/test_api_basic.py` pasa y no queda `refill_exceeds_capacity` en `api/`.
- Ejecutado 2026-10-28: `pet_service` registra `pet_created`/`pet_updated`/`pet_deleted` con `flush` previo y un único `commit`; el borrado escribe el registro antes de `db.delete` y conserva `pet_id`/`pet_name` (instantáneas sin FK). `dispenser_service` registra `dispenser_linked`, `dispenser_updated`, `dispenser_unlinked`, `dispenser_wifi_reset` y `dispenser_refilled` en la misma transacción del cambio, con la MAC siempre enmascarada; `pet_updated`/`dispenser_updated` guardan en `contexto.campos_modificados` solo los **nombres** de los campos cuyo valor cambia (`name`, `species`, `birth_date`, `weight`, `reproductive_status`, `path_url` y `pet_id`, `mac_address`, `is_active`, `current_food_grams`) y el contexto de la mascota usa `mascota_id` para no filtrar el nombre nuevo. `refill_dispenser` valida la cantidad y la capacidad en el servicio (`domain/stock.normalizar_gramos` y `aplicar_reabastecimiento`; el ajuste manual del PUT se ignora por RF-23) y responde 400 del catálogo, nunca 422: el esquema `DispenserRefillRequest` pasa a `Any` en `amount`/`unit` y añade `operation_id`/`origen`; la idempotencia se resuelve por `(user_id, operation_id)` con `refill_operations` (la clave única cubre la carrera y el perdedor devuelve el stock sin registrar ni sumar); `origen` solo admite `servidor` y `sincronizacion_sin_conexion` y cualquier otro valor se normaliza a `servidor` porque el catálogo de errores no tiene código para él; el rechazo se registra con `activity_service.registrar_rechazo` en su propia sesión y deja el stock intacto. Cambios de soporte: `activity_service.registrar` deja `dispenser_mac_masked` en `NULL` cuando no hay dispensador afectado (antes guardaba `**`), el endpoint de refill recibe el cuerpo como `Any` (un cuerpo que no es objeto JSON responde 400 `cantidad_invalida`), se retira `POST /logs/` junto con `logs_service.crear_log` y `ActivityLogCreate`, y se elimina del endpoint de alta el `print` que volcaba la `secret_key_qr`. `delete_dispenser` propaga el 404 (antes lo convertía en `false`) y no confirma el borrado si el registro falla. Caso límite comprobado: mascota eliminada con dispensador desvinculado y orden pendiente → la orden conserva `pet_id`/`dispenser_id`, cierra por plazo como `sin_reporte` sin descuento, la consulta posterior de esa MAC responde 404 y no hay una segunda orden; con el dispensador aún vinculado, el borrado de la mascota se rechaza por la FK y no deja registro. Pruebas nuevas: `test_activity_logs_crud.py` (17) y `test_refill_logs.py` (20, 9 subtests); `test_dispenser_food.py` reescribe los dos tests de `refill_exceeds_capacity` y el que esperaba 422 del esquema; `test_api_basic.py` y `test_protected_routes.py` retiran el subtest `POST /logs/` y comprueban que el método responde 405. `pytest` completo: 455 passed + 425 subtests (base 413 + 410); ninguna prueba ajena a las tres citadas queda modificada y `refill_exceeds_capacity` no aparece en `api/`. Queda para T7 el `GET /logs/` paginado, los filtros, el catálogo y el rendimiento.
- Corrección bloqueante del reenmascarado (revisión de T6, 2026-10-28): `order_service._cerrar_vencida` pasa a `activity_service.registrar` la instantánea `orden.dispenser_mac_masked` cuando el dispensador ya se eliminó, y `registrar` la volvía a enmascarar: `mask_mac("**:AB:1F")` no encuentra dígitos hexadecimales y devolvía el prefijo suelto `**`, así que el registro de una orden que vencía después de borrar su dispensador perdía la MAC parcial. Arreglo: `mask_mac` es ahora idempotente mediante `es_mac_parcial(valor)` (nueva en `mac_service`), que reconoce `**:XX:YY` y `**` y los devuelve tal cual; cuando el dispensador existe se sigue pasando la MAC cruda, como antes. Pruebas: la aserción `dispenser_mac_masked == "**:AB:1F"` añadida a `test_eliminar_mascota_y_dispensador_con_orden_pendiente` fallaba sin el arreglo (`'**' != '**:AB:1F'`), y `test_logs_domain.py` suma `test_una_mac_ya_enmascarada_se_conserva_tal_cual` y `test_una_mac_completa_no_se_confunde_con_una_parcial`. Atomicidad añadida en `test_activity_logs_crud.py`: `test_la_escritura_del_registro_falla_y_la_modificacion_no_se_aplica` (mascota y dispensador), `..._y_la_mascota_no_se_elimina` y `..._y_el_reset_de_wifi_no_se_aplica`, todas con el patrón de inyectar el fallo en `activity_service.registrar`; se comprobó con un `commit` adelantado temporal en `actualizar_mascota` y en `update_dispenser` que las pruebas fallan si el cambio se confirma antes de escribir el registro. Documentación de la limitación: en `spec.md` se añade la definición «Identificador de operación del reabastecimiento» y el caso límite «Reabastecimiento sincronizado sin identificador de operación» (sin `operation_id` el servidor aplica la cantidad una sola vez por petición pero no deduplica reenvíos), y T8 lo recoge como requisito de la app. `pytest`: 461 passed + 432 subtests tras las correcciones (455 + 4 de atomicidad y 2 de `mask_mac`, con los 7 subtests nuevos de la enmascaradura).

- [x] **T7. Consulta del historial, filtros, paginación, catálogo y rendimiento.**
  RF-26, RF-27, RF-28, RF-29, RF-30, RF-31, RF-32, RF-41, RNF-2, RNF-8
- Hecho cuando: `GET /logs/` devuelve solo los registros del usuario autenticado, ordenados por `created_at DESC, id DESC`, con el sobre `{items,total,page,page_size}`; aplica los cuatro filtros en conjunción, ambos extremos inclusivos, acepta `Z` como UTC y rechaza naive con `rango_fechas_invalido`; `page`/`page_size` inválidos responden `pagina_invalida`/`tamano_pagina_invalido` sin recortar; los históricos se muestran como «Sin clasificar» sin filtros y quedan excluidos al filtrar por tipo o resultado; `GET /logs/catalog` devuelve tipos y resultados con etiquetas; `pytest api/tests/test_logs_query.py api/tests/test_logs_errors.py api/tests/test_logs_performance.py` pasa con 10 000 registros y p95 inferior a 1 s, y ningún rechazo responde 422.
- Ejecutado 2026-10-28: `api/app/schemas/logs.py` (nuevo) define `ActivityLogItem`, `ActivityLogPage`, `ActivityLogContext` (`RootModel` de objeto libre), `ActivityLogCatalog` y `ActivityLogCatalogEntry`; se retiraron `ActivityLogBase`/`ActivityLog` de `schemas/schemas.py` y ninguna otra clase usa el contrato viejo. `test_logs_domain.py` suma `TestTextoUtc` para el formato `Z` de `tiempo.a_texto_utc`. `activity_service` añade `a_item(registro)` (etiquetas de tipo/resultado/causa desde `domain/catalogos`, «Sin clasificar» para `event_type` nulo y sin etiquetas de resultado ni causa, «Contexto» como objeto, `created_at` con sufijo `Z`) y `contexto_desde_texto`; `tiempo.a_texto_utc` centraliza el formato `2026-10-01T12:00:00Z` (sin fracciones cuando son cero, RNF-8). `logs_service` queda solo de lectura: `consultar(...)` valida en `domain.consulta` con la precedencia del plan §5.3, filtra por usuario y por los cuatro filtros en conjunción (rango inclusivo, `Z` aceptado y naive rechazado vía `parsear_instante_explicito`), ordena con `consulta.orden_estable()` (`created_at DESC, id DESC`), pagina con `offset/limit` y devuelve el sobre; `catalogo()` publica los 9 tipos y los 2 resultados en el orden de los catálogos, sin causas. El endpoint `GET /logs/` declara `pet_id`, `event_type`, `outcome`, `from`, `to`, `page` y `page_size` como `Optional[str]` (nunca tipos de FastAPI) y traduce `ErrorDominio` a 400 `detail={code,message}`; `GET /logs/catalog` es nuevo y ambos exigen token. Decisión no cubierta por el plan: `pet_id` no tiene código de error en el catálogo y no se inventa uno; un valor no numérico no corresponde a ninguna mascota, así que devuelve página vacía con total 0 (y el parámetro vacío se trata como ausente), documentado en el servicio y en el docstring del endpoint. Índices: `models.ActivityLog` añade `ix_logs_user_id_created_at` (`user_id, created_at`) y `database.INDICES_LOGS` lo incluye con la lista de columnas; `_migrar_logs` crea los índices que falten también cuando la tabla ya está en el esquema final (`CREATE INDEX IF NOT EXISTS` + commit), de modo que una base ya migrada recibe el índice nuevo sin reconstruirse; la constante de índices esperados de `test_logs_migration.py` se amplía con ese índice y se añade una prueba de que una base con el esquema final pero sin el índice lo recupera al abrirse (3 casos previos afectados). Pruebas nuevas: `test_logs_query.py` (29: propiedad, sobre exacto, orden con desempate por id, 50 por defecto, segunda página, página fuera del total, vacío, máximo 100, cada filtro, mascota eliminada, conjunción de los cuatro, extremos inclusivos, `Z` ≡ `+00:00`, desplazamiento `-05:00`, históricos visibles y excluidos, etiquetas y `created_at` con `Z`, catálogo y `pet_id` no numérico o vacío), `test_logs_errors.py` (17 con 51 subtests: cada rechazo con su código y mensaje exactos, naive/inválidos/rango invertido, página y tamaño no numéricos y fuera de rango, tabla de precedencia, ausencia de 422, ningún rechazo escribe ni devuelve ítems, 401 sin token, y la tabla RF→prueba de §9.5 comprobada mecánicamente contra los identificadores reales) y `test_logs_performance.py` (3: p95 con los cuatro filtros, p95 sin filtros y existencia del índice compuesto). Rendimiento medido con 10 000 registros del usuario: con los cuatro filtros, p50 de 25 a 27 ms y p95 de 28 a 29 ms (máximo 32 ms) en cuatro corridas consecutivas; en la primera página sin filtros, p50 19 ms y p95 21 ms. Todo queda muy por debajo del segundo que exige RNF-2. `pytest` completo: 514 passed + 485 subtests (461 + 53 pruebas nuevas: las 49 de las tres suites de consulta, `test_completa_el_indice_compuesto_que_falta_sin_reconstruir` en `test_logs_migration.py` y las 3 de `TestTextoUtc` en `test_logs_domain.py`, más 2 subtests por añadir `/logs/catalog` a las listas de rutas protegidas de `test_api_basic.py` y `test_protected_routes.py`); `pytest api/tests/test_logs_query.py api/tests/test_logs_errors.py api/tests/test_logs_performance.py`: 49 passed + 51 subtests. No se tocaron Flutter ni firmware, no hay dependencias nuevas y `MEMORY.md` queda para T10.

- [x] **T8. App móvil: contrato nuevo, caché Isar, BLoC, pantalla de historial y reabastecimiento idempotente.**
  RF-11, RF-12, RF-27, RF-28, RF-29, RF-30, RF-31, RF-32, RF-33, RF-34, RF-35, RF-41, RNF-4, RNF-5
- Hecho cuando: la entidad, el modelo, el datasource remoto y el repositorio usan el contrato nuevo con `from`/`to`, `page`/`page_size` y el sobre; `LocalLog` guarda los campos tipados y las etiquetas con índices, hace upsert por `remoteId` y pagina y filtra en Isar; el BLoC mantiene filtros, página, totales, error, reintento, aviso offline y lista previa; la pantalla muestra fecha y hora, etiquetas, mascota, MAC parcial y gramos en dispensados, los cuatro filtros combinables, «Limpiar filtros», «Página X de Y», vacío con el texto «No hay registros para los filtros seleccionados», error con reintento y aviso de datos locales; el rango de fechas se traduce en dominio a instantes con desplazamiento propio, incluido el cambio de horario; el refill envía `operation_id`, persiste `pendingRefillId` y reconoce `supera_capacidad`; `flutter test` pasa con las pruebas nuevas de utilidades, modelo, datasources, repositorio, BLoC y widget, y `flutter analyze` no reporta errores; la adaptación al ancho del móvil queda verificada manualmente sin desbordamientos. Además, T8 es la tarea que adapta el contrato móvil al cambio de `event`/`timestamp` a los campos tipados que introduce T2; hasta T8 el historial de la app no puede leer la respuesta nueva. La app debe enviar siempre el identificador de operación del reabastecimiento (`operation_id`), generarlo una vez por reabastecimiento y conservarlo con el pendiente hasta recibir una respuesta definitiva: sin él el servidor aplica la cantidad una sola vez por petición, pero no puede deduplicar los reenvíos del mismo pendiente (limitación fijada en `spec.md`).
- Ejecutado 2026-10-28: (1) **Dominio**: `activity_log.dart` reescrito con `ActivityLog` tipado (18 campos más `context` como mapa), `LogPage`, `LogFetchResult`, `LogCatalog` y `LogCatalogEntry`; `log_filters.dart` nuevo (`LogFilters` inmutable con `copyWith` de limpiezas explícitas, `hasActiveFilters`, `hasDateRange` y `fromIso`/`toIso`/`fromUtc`/`toUtc`); `domain/utils/log_time_utils.dart` (`formatearInstanteConDesplazamiento` con sufijo `Z` para desplazamiento cero y fracciones solo si existen, `rangoDiaLocalAInstantes` con un desplazamiento por extremo para el cambio de horario, `instanteUtcDeHoraDePared`, `formatearFechaHoraLocal`, `formatearFechaCorta`), `log_pagination_utils.dart` (`calcularTotalPaginas` con 1 página en vacío y `ArgumentError` si el tamaño no es positivo) y `operation_id_utils.dart` (`generarIdentificadorOperacion` de 128 bits con `Random.secure`, sin dependencias); `LogRepositories`/`GetLogsUc` con `LogFilters` y página, y `GetLogCatalogUc` nuevo. (2) **Datos**: `ActivityLogModel`/`LogPageModel`/`LogCatalogModel` con `fromJson`/`toJson` y `created_at` parseado con `DateTime.parse` (fracciones opcionales) y `toUtc`; datasource remoto con los parámetros `pet_id`/`event_type`/`outcome`/`from`/`to`/`page`/`page_size` y **solo los filtros activos** (los vacíos o nulos se omiten), sobre parseado y mensaje de los 400 tomado de `detail.message`; `LogRemoteDatasource.getCatalog` con la ruta nueva `ApiConstants.logsCatalog`; `LocalLog` con los campos tipados, etiquetas, `contextJson` e índices en `timestamp`/`petRemoteId`/`eventType`/`outcome` (además del `remoteId` único), regenerado con `build_runner` (los `.g.dart` están en `.gitignore`, así que no se commitean); datasource local con filtros y orden (`timestamp DESC, id DESC`, con `timestampGreaterThan/LessThan(include: true)` para ambos extremos) y conteo en Isar, paginación, upsert por `remoteId` y `getLocalCatalog()` derivado de las etiquetas cacheadas para que los filtros funcionen sin conexión. El repositorio cachea cada página descargada (best-effort: un fallo de caché no oculta lo recibido), y si falla la red responde la caché con los mismos filtros y página; `getCatalog` cae al catálogo local y, si tampoco hay caché, devuelve `ServerFailures`. (3) **Presentación**: `LogBloc` con un único `LogState` (`items`, `filters`, `page`, `pageSize`, `total`, `totalPages`, `isLoading`, `errorMessage`, `isOffline`, `usingCache`, `catalog`, `hasLoaded`) y eventos `LogsRequested`, `LogFiltersChanged`, `LogFiltersCleared`, `LogPageRequested`, `LogRetryRequested`, `LogCatalogRequested`; un filtro nuevo y la limpieza vuelven a la página 1; `isLoading` es una bandera que no vacía la lista previa; un error conserva filtros y lista y el reintento repite la misma consulta; un fallo del catálogo no marca la lista como error. `LogsView` solo compone (`LogFiltersBar` con mascota/tipo/resultado/rango y «Limpiar filtros», `LogItemWidget` con fecha y hora, etiquetas, mascota, MAC parcial y gramos solo en `feeding_dispensed`, `LogNoticeWidget` con «Datos sin conexión», «No hay registros para los filtros seleccionados», «No hay datos locales guardados» y error con «Reintentar», y `LogPaginationBar` con «Página X de Y» y los extremos deshabilitados). En anchos menores de 400 dp cada filtro ocupa una fila completa. (4) **Reabastecimiento**: `Dispenser.pendingRefillId` y `LocalDispenser.pendingRefillId` (aditivo, Isar regenerado); `refillDispenser` remoto exige `operationId` y envía `operation_id` y `origen`; el repositorio genera el identificador una vez por operación, lo reutiliza si ya había un pendiente, lo persiste antes de enviar en la sincronización y lo conserva ante fallo de red; lo limpia solo con respuesta definitiva o al reconciliar un `supera_capacidad`; el código pasó de `refill_exceeds_capacity` a `supera_capacidad`. (5) **Pruebas**: nuevas `log_time_utils_test` (13), `log_pagination_utils_test` (5), `operation_id_utils_test` (4), `log_filters_test` (11), `activity_log_model_test` (11), `log_remote_datasource_test` (8, con un `HttpClientAdapter` falso que comprueba los parámetros exactos), `local_log_datasource_test` (16, Isar real: filtros, orden, paginación, upsert, extremos inclusivos y catálogo local), `log_repository_impl_test` (7), `log_bloc_test` (11) y `logs_view_test` (17, con 320 dp, 360 dp y `textScaler` 1.3 sin desbordamientos; los BLoC se crean dentro del cuerpo del test porque `setUp` queda fuera de la zona de tiempo simulado). En `dispenser_repository_impl_test` se añaden 6 pruebas del identificador de operación y se actualizan los dos códigos de capacidad. `flutter test`: 391 pruebas en verde (base 286); `flutter analyze`: 98 issues y 0 errores (base 101). No se añadieron dependencias y `MEMORY.md` queda para T10.

- Corrección (revisión de T8, 2026-10-28): cinco bloques cerrados sin cambiar el contrato.
  (1) **Cambio de horario**: `LogFilters` construía el extremo de 23:59:59.999 con
  `toDate.timeZoneOffset`, que es el desplazamiento de medianoche; en un día con cambio
  de horario el extremo quedaba una hora desplazado. Los cuatro accesores usan ahora la
  utilidad compartida de `log_time_utils.dart`: `rangoDiaLocalAInstantes` cuando los dos
  extremos existen y están ordenados (deja de estar sin uso) y
  `formatearInstanteConDesplazamiento`/`instanteUtcDeHoraDePared` para un extremo suelto,
  de modo que cada uno resuelve el desplazamiento de su propio instante. Pruebas nuevas en
  `log_filters_test.dart` con `Europe/Madrid`: 29/03/2026
  (`+01:00` al inicio, `+02:00` al final, `toUtc` 2026-03-29T21:59:59.999Z) y 25/10/2026
  (`+02:00` y `+01:00`, `toUtc` 2026-10-25T22:59:59.999Z) más un rango de dos días por el
  cambio; las tres fallaban antes (`toIso` con el desplazamiento de medianoche y una hora
  de diferencia en UTC) y pasan después. Sin `TZ=Europe/Madrid` se omiten con el comando
  en el mensaje.
  (2) **Payload del reabastecimiento**: `dispenser_remote_datasource_test.dart` (nuevo)
  con un `HttpClientAdapter` falso comprueba que el POST a `/dispensers/7/refill` envía
  exactamente `{amount, unit, operation_id, origen}`, que `origen` vale `servidor` por
  defecto y que el reintento tras un fallo de red reenvía el mismo `operation_id`.
  (3) **`pendingRefillId`**: pruebas con Isar real en `local_dispenser_datasource_test.dart`
  de las tres semánticas (persistir, conservar con `null`, limpiar con `''`) y de su
  supervivencia al cierre y reapertura.
  (4) **Evidencia del layout**: pruebas de widget a 360 dp con `textScaler` 1.3 (registros
  con etiquetas largas y aviso de error) además de las de 320 dp.
  (5) **Vacío y caché**: la vista no muestra «No hay registros…» antes de la primera
  consulta (prueba que fallaba en el primer fotograma) y el repositorio ya no cae a la
  caché ante 400/401 (sí ante red, timeout y 5xx), con pruebas de los cuatro casos; el
  datasource remoto lanza `ApiException` con el código HTTP para que el repositorio pueda
  clasificar el fallo. `flutter test`: 405 pruebas (402 en verde y las 3 de cambio de
  horario omitidas en la zona del equipo; 405/405 con `TZ=Europe/Madrid`); `flutter
  analyze`: 0 errores (95 avisos e infos preexistentes en la medición final).

- [x] **T9. Firmware: reporte de fin de ciclo, reintentos y persistencia.**
  RF-14, RF-17, RF-21, RF-36, RF-37, RF-38, RF-39, RF-40, RNF-4, RNF-6
- Hecho cuando: `report_utils.h` (sin Arduino) traduce cada motivo de `DispenseReason` al código del catálogo, construye el JSON con MAC, orden, motivo, solicitados, medidos y reintentos omitiendo los ausentes, y clasifica la respuesta; `report_service` persiste el reporte en NVS antes de enviarlo, aplica timeout de 10 s y reintentos a 5 s y 15 s, descarta ante 200 o 400 `orden_desconocida`/`motivo_invalido`/`mac_no_registrada` y conserva el pendiente ante red, timeout o 5xx; `api_service` parsea `order_id`, reporta tras el ciclo y reporta `orden_invalida` cuando corresponde; `dispenser_task` reenvía el pendiente al arrancar y conserva el temporizador de 20 s; no cambia ninguna constante de la spec 013; `pio test -e native` pasa con la suite nueva y `pio run` compila en `esp32dev`; las pruebas físicas documentadas (reporte real, red caída con reinicio, descarte definitivo, firmware antiguo) quedan registradas.
- Ejecutado 2026-10-28:
  - **Cabecera pura** `src/config/report_utils.h` (sin `<Arduino.h>`, sin dependencias nuevas): `motivoPara(DispenseReason)`, `ReporteCiclo` con banderas de disponibilidad, `reporteVacio(motivo)`, `reporteDesdeResultado(result, orderId, …)`, `construirReporteJson(mac, reporte, buffer, size)` con `snprintf`/`vsnprintf`, `esCodigoDescartable`, `clasificarRespuestaReporte(status, codigo)` y las constantes `kReportTimeoutMs = 10000`, `kReportRetryDelaysMs = {5000, 15000}`, `kReportMaxAttempts = 3` con `hayReintentoDisponible`. El JSON se rechaza completo si el buffer no es usable o no cabe entero (`buffer[0] = '\0'`), de modo que nunca se envía un cuerpo truncado.
  - **Motivos cubiertos** (cada uno con su prueba): `COMPLETED → objetivo_alcanzado`, `NOT_REACHED → objetivo_no_alcanzado`, `SENSOR_UNAVAILABLE → sensor_no_disponible` (sin gramos medidos), `SENSOR_FAILURE → fallo_sensor_dispensacion`, `STALL_UNRESOLVED → atasco_no_resuelto`, `INVALID_CONFIG` e `INVALID_AMOUNT → orden_invalida`. Los gramos medidos son el incremento del ciclo y solo se envían si hay línea base; los solicitados solo si son positivos; el `order_id` solo si el dispositivo lo conoce. `reintentos` es `retryCount` del ciclo (reintentos de atasco), no los de red.
  - **Cuerpo enviado** (§5.2 del plan): `{"mac":"…","order_id":12,"motivo":"objetivo_alcanzado","gramos_solicitados":50.00,"gramos_medidos":50.40,"reintentos":0}`. Los tres campos opcionales se omiten cuando no están disponibles y el resto conserva el orden. Se usa `POST /dispensers/reports` con el mismo host de `BASE_URL`; la consulta mantiene la ruta real del servidor con el typo (`/dispenserscheck-taks/{mac}`), que no se cambia, y la nueva constante `REPORTS_URL` queda documentada en `config.h`.
  - **Clasificación de respuestas** (`clasificarRespuestaReporte`): 2xx (incluido 200 con `ya_cerrada: true` y el cierre tardío `orden_cerrada`) → `DESCARTAR`; 400 de `orden_desconocida`, `motivo_invalido` o `mac_no_registrada` → `DESCARTAR`; cualquier otro 400 → `DESCARTAR` (decisión defensiva del plan §8.19, evita el bucle); 5xx, timeout y error de red (status negativo) → `REINTENTAR`. `esCodigoDescartable` reconoce los tres códigos enumerados y el `report_service` los imprime en serie para el diagnóstico.
  - **Persistencia y limpieza**: `src/services/report_service.{h,cpp}` guarda el JSON en la NVS **antes** de enviarlo, en el namespace propio `pdam_report` (clave `pending`), distinto de `pdam_wifi` para que borrar credenciales no borre el reporte. Cada intento usa `HTTPClient` con `setTimeout`/`setConnectTimeout` de 10 s; tras el primero y el segundo fallo espera 5 s y 15 s y hace un máximo de tres intentos; solo limpia la clave con respuesta definitiva. Sin respuesta válida tras los tres intentos el reporte queda en NVS y `dispenser_task` lo reenvía una vez al entrar en `STATE_NORMAL` del siguiente arranque (`pendingReportRetried`), antes de consultar. Como el plan fija una sola clave, si un ciclo posterior fallara antes del reenvío el reporte nuevo reemplaza al anterior: la ventana es de un reporte y el envío es bloqueante, así que no se acumulan.
  - **`api_service`**: parsea `order_id` (entero positivo; si falta o no es numérico el campo se omite), envía el reporte tras `dispenseWeight(amount)` y, en `INVALID_ORDER`, envía `orden_invalida` sin gramos medidos y sin solicitados si la cantidad no era numérica o no era positiva. `REST` y `reset_wifi` no reportan. La respuesta HTTP de la consulta se sigue cerrando antes del ciclo.
  - **Sin regresión de 013 (RF-38)**: `dispensing_utils.h`, `dispensing_cycle.h`, `CHECK_INTERVAL`, ventanas de verificación/gracia/estancamiento, presupuesto de motor y tolerancias quedan intactos (`git diff` de esos archivos vacío). El temporizador de 20 s se sigue reiniciando al terminar la consulta, que ahora incluye el envío del reporte.
  - **Verificación**: `pio test -e native` 157/157 en verde (137 previos + 20 nuevos de `test_report_utils`; rojo inicial por `config/report_utils.h` ausente) y `pio run` en `esp32dev` SUCCESS (RAM 64 444 B, 19,7 %; Flash 2 030 750 B, 64,6 %). `test_report_utils` queda en `test_ignore` como las demás suites nativas.
  - **Pruebas físicas registradas y pendientes de ejecución con el usuario** (no ejecutables por el agente; RNF-6 las exige además de las automatizadas):
    - **P-T9-A — reporte real (RF-36):** programar una comida, esperar el ciclo y comprobar en el monitor serie `Reporte de fin de ciclo: intento 1, HTTP 200` con la orden cerrada, y en el historial de la app el registro `feeding_dispensed` con medidos y descontados.
    - **P-T9-B — red caída con reinicio (RF-37):** apagar el WiFi del router o el servidor durante un ciclo; verificar los intentos 1–3 con las esperas de 5 s y 15 s y el mensaje «se conserva pendiente»; reiniciar el ESP32, restablecer la red y comprobar que al arrancar reenvía el mismo cuerpo (`Reporte pendiente encontrado en NVS`) y que la orden se cierra una sola vez.
    - **P-T9-C — descarte definitivo (RF-39):** con una orden ya cerrada por el barrido o con `order_id` inexistente, comprobar que el firmware recibe 200/400 y **no** reenvía; reiniciar y verificar que el monitor no muestra `Reporte pendiente encontrado en NVS`.
    - **P-T9-D — firmware antiguo (RF-40):** flashear el firmware sin reporte y comprobar que la orden se cierra a los ~5 min con `sin_reporte` y sin descuento de stock.

- [x] **T10. Validación global, trazabilidad RF por RF y cierre documental.**
  RNF-4, RNF-6
- Hecho cuando: `cd api && pytest`, `cd app/app_movil_pdam && flutter test`, `flutter analyze`, `cd DispensadorESP32 && pio test -e native` y `pio run` pasan sin errores ni regresiones de las specs 011, 012 y 013; se revisa que no hay dependencias externas nuevas en `requirements`, `pubspec.yaml` ni `platformio.ini` (excepción: `flutter_localizations` e `intl` provienen del SDK de Flutter y no cuentan como dependencia externa); se recorre la tabla de cobertura y cada uno de los 41 RF tiene al menos una prueba automatizada fallando si el requisito se incumple, y los RF con efecto físico o visual tienen además su comprobación manual documentada; `MEMORY.md` queda actualizado con estado, decisiones y riesgos; ningún archivo de código queda con restos de la implementación parcial descartada.
- Ejecutado 2026-10-28: ver el cierre al final del archivo (correcciones del bloque A, cifras de las cuatro suites, tabla RF → prueba y procedimientos manuales pendientes).
- Corrección 2026-10-29: `TestStockConcurrente` pasa a un intercalado determinista con punto de pausa controlado (`PausaAntesDeEscribirStock`); ver «Corrección de la prueba de concurrencia de stock» al final del cierre.

## Cobertura RF → tarea

| RF | Tarea(s) | RF | Tarea(s) |
|---|---|---|---|
| RF-1 | T4, T6 | RF-22 | T4, T6 |
| RF-2 | T3, T4, T6, T7 | RF-23 | T4, T6, T8 |
| RF-3 | T2, T3, T6 | RF-24 | T3, T4 |
| RF-4 | T6 | RF-25 | T5 |
| RF-5 | T6 | RF-26 | T7 |
| RF-6 | T2, T6 | RF-27 | T7, T8 |
| RF-7 | T3, T6 | RF-28 | T7, T8 |
| RF-8 | T6 | RF-29 | T7, T8 |
| RF-9 | T6 | RF-30 | T3, T7, T8 |
| RF-10 | T6 | RF-31 | T3, T7, T8 |
| RF-11 | T6, T8 | RF-32 | T3, T7, T8 |
| RF-12 | T6, T8 | RF-33 | T8 |
| RF-13 | T4 | RF-34 | T8 |
| RF-14 | T3, T4, T9 | RF-35 | T8 |
| RF-15 | T4 | RF-36 | T9 |
| RF-16 | T4 | RF-37 | T9 |
| RF-17 | T4, T9 | RF-38 | T9, T10 |
| RF-18 | T4 | RF-39 | T9 |
| RF-19 | T5 | RF-40 | T5, T9 |
| RF-20 | T4 | RF-41 | T2, T7, T8 |
| RF-21 | T3, T4, T9 | | |

| RNF | Tarea(s) |
|---|---|
| RNF-1 | T3, T6, T10 |
| RNF-2 | T7 |
| RNF-3 | T4, T5 |
| RNF-4 | T1, T10 |
| RNF-5 | T8, T10 (`logs_view_layering_test.dart`) |
| RNF-6 | T1, T10 |
| RNF-7 | T3, T6 |
| RNF-8 | T2, T3, T7 |

## Cierre de T10 (2026-10-28)

### Correcciones finales del bloque A

1. **Stock del cliente ignorado (RF-23).** `dispenser_service.update_dispenser` ya no aplica
   `current_food_grams`: el campo se sigue aceptando en `DispenserUpdate` por
   compatibilidad, se ignora sin error y la respuesta lleva el stock del servidor. El
   campo tampoco aparece en `contexto.campos_modificados`. Se sustituyó la prueba que
   exigía `stock_fuera_de_rango` en el PUT por
   `TestRegistrosDeDispensadores.test_un_stock_enviado_por_el_cliente_se_ignora_sin_error`
   (900, 6000 y 0 g no cambian el stock ni escriben campos modificados), y se ajustó la
   prueba de nombres de campos. La app nunca enviaba ese campo al editar (su modelo solo
   lo lee de la respuesta), así que no hubo cambio de payload móvil. La frase quedó añadida
   a RF-23 de `spec.md`.
2. **Pruebas independientes de la zona del anfitrión.** Las tres pruebas de cambio de
   horario de `log_filters_test.dart` inyectan ahora `offsetInicio`/`offsetFin` en
   `rangoDiaLocalAInstantes` y se ejecutan sin `skip` en UTC, Europe/Madrid y
   America/New_York; se añadió una cuarta que comprueba que `LogFilters` usa un
   desplazamiento por extremo. La prueba de backend
   `test_un_horario_que_coincide_con_utc_pero_no_con_la_hora_local_no_se_encola` inyecta la
   zona con el nuevo parámetro `zona` de `tiempo.a_local_naive` y
   `order_service.encolar_comida`; se añadió
   `test_la_hora_local_del_servidor_acepta_cualquier_desplazamiento` con UTC+02 y UTC-05.
   Ya no hay ningún `skip` por zona horaria en ninguna suite.
3. **Borrado de mascota con dispensador vinculado.** El `IntegrityError` que SQLAlchemy
   provoca al intentar anular `dispensers.pet_id` se traduce en
   `409 {"code": "pet_has_dispenser", "message": "La mascota tiene un dispensador
   vinculado. Desvincule el dispensador antes de eliminarla."}`. No se usó un 400 del
   catálogo porque ningún código de la spec 014 describe este conflicto y RNF-7 prohíbe
   inventar códigos del catálogo; se reutiliza el 409 que el proyecto ya emplea para los
   conflictos de vínculo (MEMORY). Pruebas:
   `TestRegistrosDeMascotas.test_eliminar_mascota_con_dispensador_vinculado_responde_conflicto`,
   `TestBorradoDeMascotaPorApi.test_borrar_una_mascota_con_dispensador_responde_conflicto`
   (nivel API, antes habría sido un 500) y
   `TestBorradoDeMascotaPorApi.test_borrar_una_mascota_sin_dispensador_sigue_funcionando`.
4. **Limpieza.** Se retiró el alias sin llamadores `check_and_activate_scheduled_feedings`,
   se eliminó el `print` de depuración de `endpoints/pets.py` y el de relleno de
   `app_router.dart` (único `print` de depuración restante, heredado de la spec 011), y se
   purgaron los `.pyc` de `api/app` y `api/tests`. `grep` de `stock_solicitado`,
   `descripcion_contexto`, `validar_stock_despues_dispensado`, `crear_log_con_stock` y
   `check_and_activate_scheduled_feedings` sin resultados; sin `TODO`/`FIXME` en `api/app`
   ni `api/tests`. Las menciones a las columnas descartadas que quedan en
   `database.py`/`test_logs_migration.py` son intencionadas: son la lista que detecta y
   reconstruye una base parcial.

### Ronda de correcciones de la auditoría final (2026-10-28)

1. **Localización de la app (T10).** `main.dart` declara `locale: Locale('es')`,
   `supportedLocales: [Locale('es')]` y los delegados de
   `flutter_localizations` (paquete del SDK, no dependencia externa), centralizados en
   `core/localization/app_localization.dart`. Así el `showDateRangePicker` del
   historial muestra «Guardar» y los rótulos del SDK en español. Prueba:
   `test/core/localization/app_localization_test.dart` (configuración declarada y
   selector con `MaterialLocalizations.saveButtonLabel == 'Guardar'`).
2. **Stock con escrituras relativas.** `order_service._descontar_stock_atomico` usa
   `UPDATE ... SET stock = stock - :d WHERE id = :id AND stock - :d >= 0` y relee para
   el registro; `dispenser_service._sumar_stock_atomico` usa
   `UPDATE ... SET stock = stock + :g WHERE id = :id AND stock + :g <= 5000`. Ambas
   comprueban `rowcount` y reintentan con el valor vigente; si no se aplica, se traduce
   a `stock_fuera_de_rango` y `supera_capacidad`. Se eliminó la asignación ORM absoluta
   (`dispensador.current_food_grams = ...`). Pruebas de concurrencia:
   `test_orders_concurrency.py::TestStockConcurrente` (descuento + reabastecimiento
   simultáneos dejan 1150 g) y `TestEntregasSimultaneas` (dos entregas dejan una única
   orden pendiente y devuelven la ocurrencia perdedora a la cola).
3. **Índice único parcial.** `models.DispensingOrder` declara
   `ux_dispensing_orders_pending_dispenser` con `sqlite_where`/`postgresql_where`
   `status = 'pending'`; `database._crear_indice_orden_pendiente` lo crea de forma
   idempotente en bases existentes y aborta con un mensaje claro si ya hubiera dos
   pendientes. Pruebas: `test_el_indice_unico_impide_dos_ordenes_pendientes_del_mismo_dispensador`,
   `test_una_orden_cerrada_no_cuenta_para_el_indice_parcial` y las dos de
   `test_logs_migration.py` (base nueva y reparación del índice).
4. **Migración por conexión.** El listener `connect` ejecuta las migraciones una sola vez
   por archivo y proceso (`BASES_MIGRADAS`, con `olvidar_migraciones` para simular un
   arranque nuevo) y fija `PRAGMA busy_timeout=30000` además del `timeout` del motor.
   Prueba: `test_no_repite_la_migracion_en_otra_conexion_del_mismo_proceso`; la prueba
   del índice de logs olvida la marca antes de reabrir, porque el cambio se hizo fuera de
   SQLAlchemy.
5. **Firmware, clasificación.** `clasificarRespuestaReporte` consulta el código en el
   400 (`esCodigoDescartable`) y documenta que cualquier otro 4xx se descarta también de
   forma deliberada (plan §8.19). `esCodigoDescartable` ya no es código muerto.
6. **Firmware, monitor serie.** `report_service` imprime solo `order_id`, motivo y
   longitud del cuerpo, nunca el JSON completo ni la MAC (RNF-1); se conserva el mensaje
   «Reporte pendiente encontrado en NVS» que usa P-T9-B.
7. **App, sincronización.** `sync_service` ya no envía `type: "log"`: los logs locales se
   guardan con `isSynced = true` y el servidor no persiste ese tipo. Pruebas:
   `sync_service_test.dart` (un log pendiente no provoca petición y el lote solo lleva
   `pet`/`schedule`).
8. **App, estado.** Se eliminó `usingCache` de `LogState` y de sus usos; queda
   `isOffline`, que es la única señal que consume la vista.
9. **Documentación.** `plan.md` corrige los nombres inexistentes (`order_expiry`,
   `validar_intervalo_stock`, `registrar_rechazo_reabastecimiento`) y el esquema
   permisivo del reporte; `AGENTS.md` añade `api/app/domain/` al árbol del backend;
   `MEMORY.md` se recorta a ~55 líneas. Las cifras de `flutter analyze` de T8 y de la
   validación global se unifican con la medición final.
10. **Pruebas con hueco.** `test_los_solicitados_del_reporte_no_se_usan_para_comparar`
    envía 100 solicitados frente a 50 medidos; se añadió el 400 HTTP
    `stock_fuera_de_rango`; `logs_view_layering_test.dart` comprueba mecánicamente que la
    vista no calcula totales ni condiciona paddings a datos de negocio y que los totales
    se muestran verbatim (RNF-5).

### Auditoría de la ronda de correcciones (2026-10-29)

Se revisaron uno por uno los diez puntos del encargo anterior: el código ya cumplía todos;
quedaban dos restos documentales, que se cierran aquí. `plan.md` §7.2 ya no declara
`usingCache` en `LogState` (la única señal de caché es `isOffline`) y las frases que citaban
nombres inexistentes (`background_tasks/order_expiry.py`, `validar_intervalo_stock`) ahora
solo describen el comportamiento real, sin nombrarlos. `MEMORY.md` queda en 55 líneas con la
medición de esta auditoría. Suites re-ejecutadas: `pytest` 530 + 541 subtests, `flutter test`
412/412, `flutter analyze` 95 avisos y 0 errores, `pio test -e native` 157/157 y `pio run`
SUCCESS. `test_orders_concurrency.py` pasó 5 de 5 ejecuciones. La migración sobre una copia de
`api/app/db/pdam.db` en `/tmp/opencode/` deja el mismo conjunto de índices en dos aperturas
seguidas y `PRAGMA busy_timeout` vale 30000. Hallazgo: `skills-lock.json` y `.agents/skills/`
ya venían modificados por la instalación de las skills del entorno; no forman parte de la
spec y no se tocaron.

### Validación global (2026-10-28)

| Suite | Comando | Resultado |
|---|---|---|
| Backend | `cd api && pytest` | **530 passed + 541 subtests**, 0 fallos |
| App | `cd app/app_movil_pdam && flutter test` | **412/412**, 0 omitidas |
| App estático | `flutter analyze` | **0 errores**, 95 avisos/infos preexistentes |
| Firmware nativo | `pio test -e native` | **157/157** (4 suites) |
| Firmware build | `pio run` | **SUCCESS** (RAM 64 444 B, 19,7 %; Flash 2 030 750 B, 64,6 %) |
| Zona horaria | `TZ=UTC`, `TZ=Europe/Madrid`, `TZ=America/New_York` | suites de horarios en verde en las tres |

- Dependencias: sin dependencias externas nuevas; `flutter_localizations` e `intl`
  provienen del SDK de Flutter y no cuentan como dependencia externa.
  `api/requirements.txt` no cambia; en `pubspec.yaml` se añade `flutter_localizations` y
  llega `intl` como transitiva, sin paquete de zonas horarias; en
  `DispensadorESP32/platformio.ini` el único cambio es ampliar `test_ignore` con
  `test_report_utils` (no es una dependencia).
- Sin regresiones de las specs 011, 012 y 013: `test_nutrition*` y
  `test_schedule_service` (011) siguen con 181 pruebas + 4 subtests;
  `test_dispenser_food`, `test_sync` y `test_dispenser_mac` (012 y 005) con 50 + 79
  subtests; las suites nativas de 013 (`test_dispensing_utils` 110,
  `test_dispensing_cycle` 22, `test_provisioning_utils` 5) siguen dentro de los 157 casos y
  sus archivos no cambiaron en esta spec (`git diff` vacío).

### Trazabilidad RF → prueba

La prueba `api/tests/test_traceability_rf.py` sostiene esta tabla: comprueba que la spec
declara 41 RF, que cada referencia de la API existe, que cada caso de Flutter y del
firmware aparece literalmente en su archivo y que los cinco RF con efecto físico o visual
tienen su procedimiento manual documentado aquí.

| RF | Archivo de prueba y nombre de la prueba |
|---|---|
| RF-1 | `test_orders_dispensing.py` TestAtomicidadDelCierre.test_fallo_al_escribir_el_log_revierte_y_devuelve_500<br>`test_orders_dispensing.py` TestAtomicidadDelCierre.test_el_reintento_tras_el_500_cierra_una_sola_vez |
| RF-2 | `test_activity_logs_crud.py` TestRegistrosDeMascotas.test_una_modificacion_rechazada_no_registra<br>`test_orders_dispensing.py` TestRechazosDelReporte.test_mac_no_registrada_responde_400_sin_registro<br>`test_orders_dispensing.py` TestRechazosDelReporte.test_motivo_invalido_responde_400_sin_registro_y_la_orden_sigue_pendiente<br>`test_refill_logs.py` TestRechazosDelReabastecimiento.test_el_registro_de_fallo_persiste_en_una_sesion_independiente |
| RF-3 | `test_activity_logs_crud.py` TestRegistrosDeMascotas.test_crear_mascota_escribe_pet_created<br>`test_activity_logs_crud.py` TestRegistrosDeDispensadores.test_vincular_dispensador_escribe_dispenser_linked<br>`test_logs_domain.py` TestMaskMac.test_la_mac_parcial_nunca_contiene_la_direccion_completa<br>`test_logs_query.py` TestHistoricosYEtiquetas.test_created_at_se_devuelve_en_utc_con_sufijo_z |
| RF-4 | `test_activity_logs_crud.py` TestRegistrosDeMascotas.test_crear_mascota_escribe_pet_created |
| RF-5 | `test_activity_logs_crud.py` TestRegistrosDeMascotas.test_modificar_mascota_escribe_solo_los_nombres_de_los_campos<br>`test_activity_logs_crud.py` TestRegistrosDeMascotas.test_modificar_un_solo_campo_registra_un_unico_nombre |
| RF-6 | `test_activity_logs_crud.py` TestRegistrosDeMascotas.test_eliminar_mascota_conserva_la_referencia_de_los_historicos<br>`test_activity_logs_crud.py` TestBorradoDeMascotaPorApi.test_borrar_una_mascota_con_dispensador_responde_conflicto<br>`test_logs_migration.py` TestBaseLegada.test_borrar_la_mascota_no_anula_pet_id_ni_dispenser_id |
| RF-7 | `test_activity_logs_crud.py` TestRegistrosDeDispensadores.test_vincular_dispensador_escribe_dispenser_linked |
| RF-8 | `test_activity_logs_crud.py` TestRegistrosDeDispensadores.test_modificar_dispensador_escribe_solo_los_nombres_de_los_campos<br>`test_activity_logs_crud.py` TestRegistrosDeDispensadores.test_cambiar_la_mac_registra_el_nombre_del_campo_y_no_la_direccion |
| RF-9 | `test_activity_logs_crud.py` TestRegistrosDeDispensadores.test_desvincular_dispensador_escribe_dispenser_unlinked |
| RF-10 | `test_activity_logs_crud.py` TestRegistrosDeDispensadores.test_reset_wifi_escribe_dispenser_wifi_reset_sin_ssid_ni_credenciales |
| RF-11 | `test_refill_logs.py` TestReabastecimientoAceptado.test_reabastecimiento_con_conexion_registra_origen_servidor<br>`test_refill_logs.py` TestReabastecimientoAceptado.test_reabastecimiento_sincronizado_usa_la_hora_de_la_sincronizacion<br>`test_refill_logs.py` TestIdempotenciaDelReabastecimiento.test_el_doble_operation_id_no_duplica_ni_registra_dos_veces<br>`dispenser_remote_datasource_test.dart` «un reintento del reabastecimiento reenvía el mismo operation_id» |
| RF-12 | `test_refill_logs.py` TestRechazosDelReabastecimiento.test_cantidad_cero_responde_400_cantidad_invalida<br>`test_refill_logs.py` TestRechazosDelReabastecimiento.test_cantidad_no_numerica_responde_400_cantidad_invalida<br>`test_refill_logs.py` TestRechazosDelReabastecimiento.test_superar_la_capacidad_responde_400_supera_capacidad<br>`test_refill_logs.py` TestRechazosDelReabastecimiento.test_los_rechazos_nunca_responden_422<br>`dispenser_remote_datasource_test.dart` «el POST envía solo amount, unit, operation_id y origen» |
| RF-13 | `test_orders_dispensing.py` TestEntregaDeOrden.test_entrega_crea_la_orden_pendiente_sin_descontar_stock<br>`test_orders_dispensing.py` TestEntregaDeOrden.test_check_taks_entrega_order_id_y_no_descuenta |
| RF-14 | `test_orders_dispensing.py` TestRechazosDelReporte.test_la_mac_se_normaliza_antes_de_buscarla<br>`test_orders_dispensing.py` TestCierrePorReporte.test_orden_invalida_sin_gramos_solicitados_ni_medidos<br>`test_orders_dispensing.py` TestAjustesDeCierreDeT4.test_reintentos_ausente_se_registra_como_no_disponible<br>`test_orders_dispensing.py` TestRechazosDelReporte.test_ningun_reporte_de_negocio_responde_422<br>`test_report_utils.cpp` `test_json_omite_los_medidos_ausentes` |
| RF-15 | `test_orders_dispensing.py` TestCierrePorReporte.test_exito_descuenta_lo_medido_y_guarda_medidos_y_descontados<br>`test_orders_dispensing.py` TestCierrePorReporte.test_medidos_mayores_que_los_solicitados_descuentan_lo_medido<br>`test_orders_dispensing.py` TestCierrePorReporte.test_los_solicitados_del_reporte_no_se_usan_para_comparar<br>`test_orders_dispensing.py` TestCierrePorReporte.test_medidos_mayores_que_el_stock_descuentan_todo_el_disponible |
| RF-16 | `test_orders_dispensing.py` TestCierrePorReporte.test_medidos_menores_que_los_solicitados_cierra_entrega_incompleta<br>`test_orders_dispensing.py` TestCierrePorReporte.test_objetivo_alcanzado_sin_medidos_no_acredita_el_objetivo |
| RF-17 | `test_orders_dispensing.py` TestCierrePorReporte.test_cada_motivo_de_fallo_cierra_con_su_causa_y_sin_descuento<br>`test_logs_domain.py` TestMotivosDeReporte.test_cada_motivo_de_fallo_produce_la_causa_homonima_sin_exito |
| RF-18 | `test_orders_dispensing.py` TestIdempotenciaYTardanza.test_un_segundo_reporte_devuelve_ya_cerrada_sin_nuevo_log_ni_descuento<br>`test_orders_dispensing.py` TestIdempotenciaYTardanza.test_duplicado_identico_del_mismo_reporte |
| RF-19 | `test_orders_expiry.py` TestFronterasDelVencimiento.test_no_cierra_una_orden_cuyo_plazo_mas_1_s_no_ha_vencido<br>`test_orders_expiry.py` TestFronterasDelVencimiento.test_el_cierre_ocurre_dentro_de_60_s_con_el_barrido_de_30_s<br>`test_orders_expiry.py` TestAlcanceDelBarrido.test_solo_cierra_las_ordenes_vencidas<br>`test_orders_expiry.py` TestBarridoProgramado.test_el_arranque_programa_un_unico_job_cada_30_s |
| RF-20 | `test_orders_dispensing.py` TestIdempotenciaYTardanza.test_reporte_en_el_limite_exacto_del_plazo_sigue_dentro<br>`test_orders_dispensing.py` TestIdempotenciaYTardanza.test_reporte_tardio_cierra_orden_cerrada_sin_descuento<br>`test_orders_expiry.py` TestExclusionMutuaConElReporte.test_el_barrido_cierra_y_el_reporte_tardio_devuelve_ya_cerrada |
| RF-21 | `test_orders_dispensing.py` TestRechazosDelReporte.test_orden_desconocida_responde_400_con_registro_de_fallo<br>`test_orders_dispensing.py` TestRechazosDelReporte.test_motivo_invalido_responde_400_sin_registro_y_la_orden_sigue_pendiente<br>`test_orders_dispensing.py` TestRechazosDelReporte.test_mac_no_registrada_responde_400_sin_registro |
| RF-22 | `test_logs_domain.py` TestDescuentoAcotado.test_el_stock_resultante_nunca_sale_del_intervalo_permitido<br>`test_orders_dispensing.py` TestCierrePorReporte.test_un_stock_de_partida_fuera_de_rango_rechaza_el_cierre_sin_cambios<br>`test_refill_logs.py` TestReabastecimientoAceptado.test_el_limite_de_capacidad_exacto_se_acepta |
| RF-23 | `test_orders_dispensing.py` TestCierrePorReporte.test_el_stock_no_se_toma_del_reporte<br>`test_activity_logs_crud.py` TestRegistrosDeDispensadores.test_un_stock_enviado_por_el_cliente_se_ignora_sin_error |
| RF-24 | `test_orders_dispensing.py` TestCierrePorReporte.test_el_registro_guarda_orden_solicitados_medidos_stock_y_reintentos<br>`test_orders_dispensing.py` TestAjustesDeCierreDeT4.test_reintentos_ausente_se_registra_como_no_disponible |
| RF-25 | `test_feeding_queue.py` TestEntregaDeLaComidaEnEspera.test_con_orden_pendiente_en_plazo_no_entrega_y_conserva_la_cola<br>`test_feeding_queue.py` TestEntregaDeLaComidaEnEspera.test_al_vencer_la_consulta_cierra_la_orden_y_la_cola_sigue_esperando<br>`test_feeding_queue.py` TestEntregaDeLaComidaEnEspera.test_un_dispensador_desactivado_no_dispensa_al_vencer_su_orden_pendiente<br>`test_feeding_queue.py` TestEntregaDeLaComidaEnEspera.test_al_reactivarse_se_entrega_la_comida_en_espera<br>`test_feeding_queue.py` TestHoraLocalDelServidor.test_la_hora_local_del_servidor_acepta_cualquier_desplazamiento |
| RF-26 | `test_logs_query.py` TestPropiedadYOrden.test_devuelve_solo_los_registros_del_usuario_autenticado<br>`test_logs_query.py` TestPropiedadYOrden.test_ordena_del_mas_reciente_al_mas_antiguo_y_desempata_por_id |
| RF-27 | `test_logs_query.py` TestFiltros.test_filtra_por_mascota<br>`test_logs_query.py` TestFiltros.test_filtra_por_mascota_eliminada_cuyo_identificador_se_conserva |
| RF-28 | `test_logs_query.py` TestFiltros.test_filtra_por_tipo_de_evento<br>`test_logs_query.py` TestHistoricosYEtiquetas.test_los_historicos_quedan_excluidos_al_filtrar_por_tipo |
| RF-29 | `test_logs_query.py` TestFiltros.test_filtra_por_resultado<br>`test_logs_query.py` TestHistoricosYEtiquetas.test_los_historicos_quedan_excluidos_al_filtrar_por_resultado |
| RF-30 | `test_logs_query.py` TestFiltros.test_el_rango_de_fechas_incluye_ambos_extremos<br>`test_logs_query.py` TestFiltros.test_los_limites_con_desplazamiento_se_convierten_a_utc<br>`test_logs_errors.py` TestRechazosDeLaConsulta.test_un_limite_sin_desplazamiento_responde_rango_fechas_invalido<br>`log_filters_test.dart` «el 29/03/2026 el fin del día usa +02:00 y no el +01:00 de medianoche»<br>`log_filters_test.dart` «el 25/10/2026 el fin del día usa +01:00 y no el +02:00 de medianoche» |
| RF-31 | `test_logs_query.py` TestFiltros.test_aplica_los_cuatro_filtros_en_conjuncion<br>`test_logs_errors.py` TestRechazosDeLaConsulta.test_un_tipo_fuera_del_catalogo_responde_tipo_evento_invalido<br>`test_logs_errors.py` TestRechazosDeLaConsulta.test_un_resultado_fuera_del_catalogo_responde_resultado_invalido<br>`test_logs_errors.py` TestRechazosDeLaConsulta.test_la_precedencia_de_rechazo_es_la_del_plan<br>`log_remote_datasource_test.dart` «omite los filtros vacíos o ausentes» |
| RF-32 | `test_logs_query.py` TestPropiedadYOrden.test_el_sobre_tiene_items_total_pagina_y_tamano<br>`test_logs_query.py` TestPropiedadYOrden.test_cincuenta_items_por_defecto_y_total_completo<br>`test_logs_errors.py` TestRechazosDeLaConsulta.test_una_pagina_menor_que_uno_responde_pagina_invalida<br>`test_logs_errors.py` TestRechazosDeLaConsulta.test_un_tamano_de_pagina_fuera_del_intervalo_es_invalido<br>`logs_view_test.dart` «muestra la página, el total de páginas y los registros»<br>`logs_view_test.dart` «la página siguiente pide la página 2» |
| RF-33 | `logs_view_test.dart` «muestra fecha, hora, etiquetas, mascota, MAC y gramos»<br>`logs_view_test.dart` «muestra los cuatro filtros y el botón de limpiar»<br>`logs_view_test.dart` «limpiar filtros restablece la primera página sin filtros»<br>`logs_view_test.dart` «vacío muestra el texto exacto»<br>`logs_view_test.dart` «un error muestra el mensaje y el reintento vuelve a consultar»<br>`logs_view_test.dart` «se pinta sin desbordamientos en 360 dp con texto al 130 %»<br>**Manual:** P-T8-A |
| RF-34 | `log_repository_impl_test.dart` «si falla la red devuelve la caché con los mismos filtros y página»<br>`local_log_datasource_test.dart` «pagina y calcula el total sobre la caché»<br>`logs_view_test.dart` «offline muestra los datos locales y su aviso» |
| RF-35 | `local_log_datasource_test.dart` «hace upsert por remoteId sin duplicar (RF-35)»<br>`local_log_datasource_test.dart` «cacheLogs no borra los registros ya cacheados» |
| RF-36 | `test_report_utils.cpp` `test_json_completo_con_todos_los_campos`<br>`test_report_utils.cpp` `test_json_omite_los_solicitados_ausentes`<br>`test_report_utils.cpp` `test_json_omite_los_medidos_ausentes`<br>`test_report_utils.cpp` `test_cada_motivo_tiene_su_codigo_del_catalogo`<br>**Física:** P-T9-A |
| RF-37 | `test_report_utils.cpp` `test_la_politica_conserva_timeout_y_esperas`<br>`test_report_utils.cpp` `test_se_reintenta_solo_mientras_queden_intentos`<br>**Física:** P-T9-B |
| RF-38 | `test_dispensing_cycle.cpp` `test_cycle_limits_default_to_approved_constants`<br>`test_dispensing_utils.cpp` `test_verification_window_is_exactly_two_seconds`<br>`test_dispensing_utils.cpp` `test_is_check_due_waits_the_full_interval` |
| RF-39 | `test_report_utils.cpp` `test_un_200_descarta_el_reporte`<br>`test_report_utils.cpp` `test_los_tres_400_enumerados_se_descartan`<br>`test_report_utils.cpp` `test_un_400_no_enumerado_tambien_se_descarta`<br>`test_report_utils.cpp` `test_los_5xx_y_los_errores_de_red_se_reintentan`<br>**Física:** P-T9-C |
| RF-40 | `test_orders_expiry.py` TestAlcanceDelBarrido.test_firmware_antiguo_cierra_por_plazo_sin_reporte_ni_descuento<br>**Física:** P-T9-D |
| RF-41 | `test_logs_query.py` TestHistoricosYEtiquetas.test_los_historicos_se_muestran_como_sin_clasificar_sin_filtros<br>`test_logs_query.py` TestHistoricosYEtiquetas.test_los_historicos_quedan_excluidos_al_filtrar_por_tipo<br>`test_logs_query.py` TestHistoricosYEtiquetas.test_los_historicos_quedan_excluidos_al_filtrar_por_resultado<br>`logs_view_test.dart` «un registro histórico se muestra como «Sin clasificar»» |

**Resumen:** 41/41 RF con al menos una prueba automatizada. Cinco exigen además
comprobación manual o física (RF-33 visual, RF-36, RF-37, RF-39 y RF-40 físico) y sus
procedimientos están abajo; en ningún caso la prueba manual sustituye a la automatizada.

### Pruebas manuales y físicas pendientes (las ejecuta el usuario con el dispositivo)

Estas pruebas no las puede ejecutar el agente: necesitan el ESP32, la celda y el router.
Ninguna bloquea la suite automatizada, pero sí el cierre «sin reservas» de la spec.

- **P-T8-A — adaptación del historial al ancho del móvil (RF-33).**
  1. `cd app/app_movil_pdam && flutter run --debug --host-vmservice-port=8888` con el
     Samsung A15 conectado.
  2. Ajustes del sistema → Pantalla → Tamaño de letra: 130 %; abrir el historial.
  3. Recorrer la lista con registros de etiquetas largas
     («Fallo del sensor durante la dispensación»), abrir los cuatro filtros, aplicar un
     rango de fechas y llegar a la última página; después provocar el error (servidor
     apagado) y el aviso sin conexión.
  4. Esperado: sin franjas amarillas/negras de desbordamiento, sin texto cortado, los
     botones de página deshabilitados en los extremos y «No hay registros para los
     filtros seleccionados» cuando no hay resultados. Registrar captura y resultado.
- **P-T9-A — reporte real de fin de ciclo (RF-36).**
  1. Servidor en marcha con la app abierta en el historial.
  2. Programar una comida a 2 minutos con al menos 100 g de stock.
  3. `cd DispensadorESP32 && pio device monitor` antes de la hora programada.
  4. Esperado en el monitor: `Reporte de fin de ciclo: intento 1` seguido de HTTP 200; en
     el historial, un registro `feeding_dispensed` con solicitados, medidos y descontados.
  5. Registrar gramos medidos y descontados y el stock final.
- **P-T9-B — red caída con reinicio (RF-37).**
  1. Iniciar un ciclo con el firmware actual y apagar el router (o el servidor) durante el
     ciclo.
  2. Esperado en el monitor: intento 1, espera de 5 s, intento 2, espera de 15 s, intento 3
     y el mensaje de que el reporte se conserva pendiente.
  3. Reiniciar el ESP32 con la red aún caída, restablecer la red y esperar el arranque.
  4. Esperado: `Reporte pendiente encontrado en NVS` y un único cierre de la orden (un solo
     registro en el historial, un único descuento). Registrar los tiempos observados.
- **P-T9-C — descarte definitivo (RF-39).**
  1. Con una orden ya cerrada por el barrido (esperar más de 6 minutos tras el ciclo) o con
     un `order_id` inexistente, ejecutar el ciclo.
  2. Esperado en el monitor: respuesta 200 con `ya_cerrada: true` (o 400
     `orden_desconocida`) y **sin** reintentos.
  3. Reiniciar el ESP32: el monitor no debe mostrar `Reporte pendiente encontrado en NVS`.
- **P-T9-D — firmware antiguo (RF-40).**
  1. Flashear una build sin la llamada al reporte (por ejemplo, comentando el envío en
     `api_service` solo para esta prueba y restaurándolo después).
  2. Provocar una dispensación y no reportar.
  3. Esperado: a los ~5 min más la tolerancia, la orden se cierra como `sin_reporte` en el
     historial, sin descuento de stock, sin reiniciar el servidor.

### Deudas aceptadas y riesgos abiertos al cerrar la 014

- **Deuda aceptada:** una entrega incompleta o un reporte tardío no descuentan stock, así
  que el stock del servidor queda por encima del real y solo se corrige con un
  reabastecimiento o un ajuste manual futuro (fuera de alcance).
- **Deuda aceptada:** sin `operation_id` el servidor no puede deduplicar reenvíos; la app
  lo envía siempre, pero un cliente antiguo seguiría duplicando al sincronizar.
- **Deuda aceptada:** la persistencia del reporte pendiente en NVS y el reenvío tras
  reinicio solo se acreditan con P-T9-B; la suite nativa cubre la política de timeout y
  reintentos, no `Preferences`.
- **Deuda aceptada:** la ventana de 10 min de `encolar_comida` no recupera ocurrencias si el
  proceso cae más tiempo; se documentó en T5.
- **Riesgo abierto:** P-T8-A y P-T9-A a P-T9-D pendientes de ejecución física; hasta
  entonces la spec queda «implementada (pendiente de pruebas físicas)».
- **Riesgo abierto:** los umbrales de la 013 siguen siendo válidos solo para el montaje
  actual (celda y cableado) y con croqueta de ~3 cm los atascos mecánicos continúan; no se
  ajustaron umbrales.
- **Riesgo abierto:** la rama `pruebas/endpoint-fijo-hx711` con la spec 013 cerrada sigue
  pendiente de merge a `main`.

### Corrección de la prueba de concurrencia de stock (2026-10-29)

`TestStockConcurrente` no era fiable: la `threading.Barrier` solo sincronizaba el arranque y
la ventana lectura→escritura real del stock dura microsegundos, así que con el patrón antiguo
(leer y escribir un valor absoluto) la prueba solo fallaba en 3 de 10 ejecuciones. Se sustituye
por un intercalado determinista que no depende del planificador.

- **Mecanismo:** `PausaAntesDeEscribirStock` se engancha al evento `before_cursor_execute` de
  SQLAlchemy (sin ningún gancho en el código de producción) y, para el hilo armado, bloquea la
  sentencia `UPDATE dispensers SET current_food_grams = ...` hasta que la prueba la libera. El
  `SELECT` del stock ya se emitió, así que la pausa cae exactamente en la ventana donde se
  pierde la actualización; la otra operación se confirma entera durante la pausa. La pausa se
  localiza por el SQL real, así que una implementación que lea y escriba un valor absoluto se
  detiene en el mismo punto (`intentos`, forma de la sentencia y número de lecturas no influyen).
  Cada prueba comprueba además que el hilo pausado había leído el stock antes de la pausa
  (`sentencias_previas`), para que el caso no pueda quedar vacío.
- **Casos (3):** reabastecimiento confirmado mientras el cierre espera (1000 → 1200 → 1150);
  caso espejo con el reabastecimiento en espera y el cierre confirmado (1000 → 950 → 1150); y
  dos descuentos simultáneos (1000 → 900). El simétrico se ejerce sobre
  `order_service._descontar_stock_atomico`, porque la regla de una única orden pendiente por
  dispensador impide que dos cierres se solapen a través de `procesar_reporte`; es la misma
  escritura de stock que usa el cierre.
- **Mutación (copia en `/tmp/opencode/pdam-mutacion`, reintroducido el patrón antiguo leer →
  escribir absoluto en `_descontar_stock_atomico` y en `_sumar_stock_atomico`):**
  `pytest tests/test_orders_concurrency.py` → 3 de las 3 pruebas nuevas en rojo (950≠1150,
  1200≠1150, 950≠900) y las otras 3 del archivo en verde; `TestStockConcurrente` ejecutado 10
  veces: 10/10 con 3 fallos (antes, con la barrera, 3/10). Con el código actual, las 10
  ejecuciones dan 6 passed.
- **Suite:** `cd api && pytest` → 530 passed + 541 subtests (antes del cambio 528 + 541: se
  retira una prueba con barrera y se añaden tres deterministas). No se modificó ningún archivo
  de producción, ni Flutter, ni firmware.

## Cierre de las pruebas físicas (2026-10-29)

Las cinco pruebas que solo podía ejecutar el usuario se ejecutaron el 2026-10-29 con el
ESP32, la celda y el móvil reales. Con ellas, la spec 014 pasa de «implementada (pendiente de
pruebas físicas)» a **implementada y validada**. El detalle de cada ejecución está en el
[informe de pruebas](../../docs/informes/informe-pruebas-spec-014-2026-10-29.md) §12.

| Prueba | Resultado | Evidencia |
|---|---|---|
| P-T9-A — reporte real de fin de ciclo (RF-36) | Aprobada | Dos ciclos con `Reporte de fin de ciclo: intento 1, HTTP 200` sin reintentos. Orden 3: 17,27 g solicitados, 22,23 g medidos y descontados, stock 4637,16 → 4614,93 g. Orden 4: atasco no resuelto, −6,28 g medidos y sin descuento, stock 4614,93 g. La orden 1 (344,75 g) se descarta porque el usuario manipuló la celda al no tener bandeja. El resumen del monitor mostraba «no disponible» y se corrigió en `f10802d`; el firmware reflasheado se verificó en el ciclo siguiente con `order_id=5` y su motivo |
| P-T9-B — red caída con reinicio (RF-37) | Aprobada | Con la API detenida 2 s después de `serve:true` de la orden 5: 15:51:47 HTTP −1, espera 5 s, 15:52:02 HTTP −1, espera 15 s, 15:52:27 HTTP −1 y «se conserva pendiente para reenviarlo tras un reinicio». Reinicio con la API caída: WiFi OK, validación HTTP −1, vuelta a BLE y el pendiente conservado. Reinicio con la API en marcha: `Reporte pendiente encontrado en NVS`, reenvío de la orden 5 con HTTP 200 al intento 1 y cierre único (un solo registro, sin descuento, stock 4614,93 g). Matiz aceptado: el reinicio llegó más de 5 min después, el barrido ya había cerrado la orden 5 como `sin_reporte` y el reenvío, 0,8 s posterior, se aceptó como orden ya cerrada |
| P-T9-C — descarte definitivo (RF-39) | Aprobada | El reenvío de P-T9-B recibió 200 de orden ya cerrada y el firmware descartó el reporte sin reintentar; tras reiniciar de nuevo, la placa **no** mostró `Reporte pendiente encontrado en NVS` (confirmado por el usuario) |
| P-T9-D — firmware antiguo (RF-40) | Aprobada | La orden 5 se cerró sola a los ~5 min como `sin_reporte`, sin descuento y sin exigir reporte. No se flasheó una build sin la llamada al reporte porque el comportamiento bajo prueba es del servidor y quedó acreditado del lado del servidor |
| P-T8-A — historial en el móvil (RF-33) | Aprobada | En el Samsung A15 los registros aparecen, los cuatro filtros y la paginación funcionan y el registro nuevo se reflejó al levantar la API (confirmado por el usuario) |
| S7 — app sin conexión (RF-34, RF-35) | Aprobada | Con la API apagada, la app mostró los registros de la caché con el aviso de datos locales (confirmado por el usuario) |

Nota: P-T9-D se acreditó con evidencia del servidor. El procedimiento del informe ofrecía
flashear una build sin la llamada al reporte, pero el plazo y el cierre `sin_reporte` viven en
el backend; la orden 5 se cerró así sin intervención del dispositivo y sin tocar el stock, que
es exactamente lo pedido para firmware antiguo. La alternativa de flashear esa build queda
descartada por innecesaria, no por imposibilidad.

Las deudas aceptadas de la spec siguen vigentes: una entrega incompleta o un reporte tardío no
descuentan stock, un cliente sin `operation_id` no se puede deduplicar y la ventana de 10
minutos de `encolar_comida` no recupera ocurrencias perdidas. La rama
`pruebas/endpoint-fijo-hx711` sigue pendiente de merge a `main`. Este cierre sustituye al
«Riesgo abierto» de la sección anterior sobre las pruebas físicas pendientes; el resto de
deudas y riesgos de esa sección se mantiene.
