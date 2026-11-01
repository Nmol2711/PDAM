# Tareas 020 — Dispensación rápida manual y acceso a dispositivos

Orden: T1 → T2 (a, b) → T3 (a, b) → T4 → T5 → T6. Tests primero en cada tarea.
Cada tarea respeta la constitución: P2 trazabilidad, P3 lógica fuera de la vista,
P4 pruebas obligatorias y P6 textos en español.

- [x] **T1. Dominio, catálogo de errores, modelo y migración.**
  RF-2, RF-3, RF-4, RF-5, RF-14, RNF-5, RNF-9
- Incluye: `domain/dispensado_rapido.py` con límite de 200 g, normalización de
  cantidad y de `operation_id`, `stock_reservado`, precedencia de rechazo y
  ventana de coincidencia; los cinco códigos nuevos en `domain/catalogos.py`;
  `ManualDispensingRequest` con `operation_id` y restricción única
  `(dispenser_id, operation_id)`; la tabla nueva la crea `create_all` y
  `_migrar_solicitudes_rapidas` añade la columna y el índice único en bases donde
  la tabla ya existía, sin borrar datos; `_ocurrencias_del_horario` queda como
  envoltorio de dominio (refactor sin cambio de comportamiento, cubierto por las
  pruebas de la 014); actualización de `test_logs_domain.py`.
- Hecho cuando: `cd api && pytest tests/test_quick_dispense.py
  tests/test_quick_dispense_migration.py tests/test_logs_domain.py` pasa; 0,
  negativo, texto, `NaN`, infinito, 200 exacto, 200,1 y 50,5 tienen el resultado
  esperado; una ocurrencia en el límite exacto de 10 min queda fuera y una en el
  instante exacto queda dentro; una base con la tabla antigua queda con
  `operation_id` relleno y el índice único; el conjunto `ERRORES_ESPERADOS`
  incluye los cinco códigos.
- Constitución: P2 (trazabilidad), P3 (dominio puro), P4 (pruebas primero).
- Depende de: nada.
- Ejecutado: `normalizar_operation_id` y `stock_reservado` en dominio,
  `codigo_rechazo(stock_reservado, ...)` con docstring corregido,
  `operacion_invalida` en el catálogo, `ManualDispensingRequest.operation_id` con
  índice `ux_manual_dispensing_operacion` y `_migrar_solicitudes_rapidas` en el
  listener `connect`. Tests primero (rojo 41 fallos) y después verdes:
  `pytest tests/test_quick_dispense.py tests/test_quick_dispense_migration.py
  tests/test_logs_domain.py -q` → 126 passed; suite completa `pytest -q` → 749
  passed.

- [x] **T2. Servicio de solicitud, reserva de stock, idempotencia, cobertura y
  endpoint.** RF-1, RF-2, RF-3, RF-4, RF-5, RF-6, RF-7, RF-9, RF-14, RF-15, RF-16,
  RNF-5, RNF-8, RNF-9

  **T2.a. Solicitud, reserva de stock e idempotencia.**
  RF-1, RF-2, RF-3, RF-4, RF-5, RF-6, RF-9, RF-14, RF-15
  - Incluye: `solicitar_dispensacion_rapida` con deduplicación por
    `(dispensador, operation_id)` antes de validar cantidad y stock, stock
    reservado a partir de las solicitudes pendientes, cierre previo de una orden
    vencida, rechazo de orden en curso, endpoint autenticado con cuerpo `Any` y
    esquemas `{amount, operation_id}` → 202 `{status, requested_grams,
    stock_grams}`; pruebas de dueño, stock reservado, desactivado,
    `operation_id` ausente o inválido, reintento idempotente y errores 400/404.
  - Hecho cuando: `cd api && pytest tests/test_quick_dispense.py` pasa; dos
    solicitudes que suman más que el stock rechazan la segunda con
    `stock_insuficiente`; el mismo `operation_id` devuelve la misma solicitud y el
    mismo 202 sin crear otra ni recubrir; un `operation_id` ausente da 400
    `operacion_invalida`; los rechazos responden `detail={code,message}` y el 404
    no filtra datos.

  **T2.b. Cobertura de ocurrencias, atomicidad, concurrencia y baja de cuenta.**
  RF-3, RF-7, RF-16, RNF-5, RNF-8, RNF-9
  - Incluye: `_cubrir_ocurrencias_programadas` en la transacción de la solicitud,
    inserción de la ocurrencia ya consumida, `IntegrityError` resuelto con la fila
    ganadora, ocurrencia inexistente sin fila fantasma, prueba de dos solicitudes
    manuales compitiendo por la misma clave de ocurrencia (no contra
    `encolar_comida`), prueba de reserva concurrente en dos sesiones (stock 300 g y
    dos solicitudes de 200 g, solo una aceptada), revalidación de la reserva y de
    la orden en curso tras el `flush` bajo bloqueo de escritura, rollback atómico,
    comprobación de que la cobertura no escribe evento y baja de cuenta con una
    solicitud pendiente (cascada en `account_service.py` y
    `tests/test_account_deletion.py`).
  - Hecho cuando: `cd api && pytest tests/test_quick_dispense.py
    tests/test_account_deletion.py` pasa; una solicitud aceptada crea la petición
    y cubre todas las ocurrencias de la ventana; un fallo no deja ni petición ni
    cobertura; la concurrencia por la misma clave no duplica ni pierde la
    ocurrencia; con stock 300 g solo una de las dos solicitudes de 200 g se
    acepta; la revalidación bajo bloqueo rechaza la que exceda la reserva; no hay
    ningún registro nuevo por la cobertura; la baja de cuenta con solicitud
    pendiente termina sin error y sin evento.
- Constitución: P2, P3 (lógica en el servicio), P4 (pruebas de servicio y
  endpoint).
- Ejecutado: `solicitar_dispensacion_rapida` recibe `operation_id`, comprueba en
  el orden pedido (identificador, dueño, reintento idempotente, vencidas,
  cantidad, stock reservado, estado y orden en curso) y repite tras el `flush` la
  comprobación de la orden en curso y de la reserva bajo bloqueo de escritura, con
  `IntegrityError` de la clave única resuelto
  como reintento; el endpoint acepta `{amount, operation_id}` y un cuerpo no
  objeto responde `operacion_invalida`. Pruebas nuevas de reserva
  (200+200 con 300 g), idempotencia (sin recubrir, sin validar stock),
  concurrencia de dos sesiones, cobertura sin eventos, rollback a mitad de la
  cobertura y baja de cuenta con solicitud pendiente. Tests primero (rojo 62
  fallos) y después verdes: `pytest tests/test_quick_dispense.py
  tests/test_quick_dispense_delivery.py tests/test_account_deletion.py
  tests/test_feeding_queue.py -q` → 119 passed; suite completa `pytest -q` → 769
  passed.
- Depende de: T1.

- [x] **T3. Entrega prioritaria, reporte, evento, stock y ciclo de vida.**
  RF-8, RF-9, RF-10, RF-16, RNF-5, RNF-6

  **T3.a. Entrega prioritaria y cierre.**
  RF-8, RF-9, RF-10, RNF-5, RNF-6
  - Incluye: `entregar_solicitud_manual`, prioridad en `entregar_orden`,
    reclamación atómica, integración con el reporte y el cierre por plazo; pruebas
    de entrega antes de la cola, doble consulta simultánea, evento
    `feeding_dispensed`, descuento solo en cierre exitoso, `sin_reporte` sin
    descuento y no regresión de la spec 014.
  - Hecho cuando: `cd api && pytest tests/test_quick_dispense_delivery.py
    tests/test_orders_dispensing.py tests/test_orders_expiry.py` pasa; el equipo
    recibe la manual antes que la programada; una solicitud se entrega una sola
    vez; el reporte escribe un único evento y aplica el descuento de la 014 solo
    si el cierre es exitoso.

  **T3.b. Ciclo de vida y límite frente al presupuesto de la 013.**
  RF-9, RF-10, RF-16, RNF-6
  - Incluye: descarte de una solicitud con `pet_id` distinto al del dispensador
    reasignado (sin orden ni evento), cascada al eliminar el dispensador, prueba de
    eliminación de una mascota con dispensador vinculado → 409
    `pet_has_dispenser` con la solicitud intacta (sin cascada por mascota),
    solicitud que nunca se consulta y permanece pendiente sin vencimiento, y
    cierre de una orden rápida que no alcanza los 200 g dentro del presupuesto de
    30 s como `objetivo_no_alcanzado` o `entrega_incompleta`, sin descuento.
  - Hecho cuando: `cd api && pytest tests/test_quick_dispense_delivery.py
    tests/test_orders_expiry.py` pasa; la reasignación no crea orden ni evento;
    eliminar la mascota con dispensador responde 409 `pet_has_dispenser` y la
    solicitud pendiente sigue intacta; la solicitud pendiente sigue visible sin
    vencimiento; el cierre por presupuesto aparece en el historial con la causa de
    la 014 y sin descuento.
- Constitución: P2, P4, P3 (cierre y descuento reutilizan la 014).
- Depende de: T2.b.
- Ejecutado: `entregar_solicitud_manual` descarta con `UPDATE ... consumed_at IS
  NULL` + `rowcount` la solicitud cuyo `pet_id` no coincide con el dispensador
  reasignado (sin orden ni evento) y sigue con la siguiente, también en modo
  simulado (omisión en memoria). Pruebas nuevas en
  `test_quick_dispense_delivery.py`: reasignación con descarte y con entrega de
  la solicitud vigente, cascada al eliminar el dispensador, solicitud sin
  consulta que no vence y cierre de 200 g como `objetivo_no_alcanzado` y
  `entrega_incompleta` sin descuento. Tests primero (rojo: 2 fallos) y después
  verdes: `pytest tests/test_quick_dispense_delivery.py
  tests/test_orders_dispensing.py tests/test_orders_expiry.py -q` → 81 passed;
  suite completa `pytest -q` → 775 passed.

- [x] **T4. App: límites, caso de uso, repositorio y cubit.**
  RF-1, RF-2, RF-3, RF-11, RF-12, RF-14, RNF-3
- Incluye: `quick_dispense_limits.dart` con decimales, método en el contrato del
  repositorio, `QuickDispenseUc`, POST en el datasource con `{amount,
  operation_id}`, comprobación de conexión, mapeo explícito de los cinco códigos
  en el repositorio (el `default` conserva el mensaje del catálogo, sin
  excepciones crudas), `QuickDispenseCubit` con `generarIdentificadorOperacion()`
  reutilizado mientras la hoja siga abierta y la cantidad no cambie, y renovado al
  cambiarla o al reabrir la hoja, y su registro en DI; pruebas de límites,
  datasource, repositorio, cubit e idempotencia en la app.
- Hecho cuando: `cd app/app_movil_pdam && flutter test test/features/dispenser`
  pasa; el datasource envía `{amount, operation_id}`; el cubit reutiliza el
  identificador en un reintento con la misma cantidad y lo renueva al cambiarla o
  al reabrir la hoja; sin conexión no hay POST y el cubit emite error con el texto
  correspondiente.
- Constitución: P3 (lógica en dominio y cubit), P4, P6 (textos en español).
- Depende de: T2.a (contrato del endpoint).
- Ejecutado: `quickDispense(dispenserId, grams, operationId)` en el contrato, el
  caso de uso y el datasource (cuerpo `{amount, operation_id}`); el repositorio
  propaga el identificador y mapea explícitamente los cinco códigos nuevos a
  `ServerFailures(message)`; el cubit genera/reutiliza el identificador según la
  cantidad (inyectable en pruebas, por defecto `generarIdentificadorOperacion`),
  mantiene el guardia `isClosed` y el bloqueo mientras envía. Fakes actualizados
  en bloc, vista de registro, hoja y ficha. Tests primero (rojo por firma) y
  después verdes: `flutter test test/features/dispenser` → 326 passed; suite
  completa `flutter test` → 1135 passed; `flutter analyze` sin errores (solo
  avisos previos).

- [x] **T5. App: hoja de dispensación, acción en la ficha y navegación del
  dashboard.** RF-6, RF-11, RF-12, RF-13, RNF-3, RNF-4, RNF-7
- Incluye: `QuickDispenseSheet` con campo único, máximo, stock, validación,
  decimales, bloqueo mientras envía, mensajes y aviso de sin conexión; botón
  «Dispensar ahora» en la tarjeta del dispensador, visible solo con dispensador
  (no se ofrece sin dispensador) y deshabilitado si está inactivo o con stock 0;
  corrección de «Dispositivos» a `/dispensers`; pruebas de widget en 320 y 360 dp
  con `textScaler` 1.3, aviso de sin conexión y prueba de navegación.
- Hecho cuando: `cd app/app_movil_pdam && flutter test test/features/dispenser
  test/features/pets test/features/dashboard` pasa; la hoja no muestra más campos
  que la cantidad; en 360 dp no hay desbordamientos; sin conexión se muestra el
  aviso y no se envía; sin dispensador no se ofrece la acción; el éxito muestra
  «Orden de dispensación enviada»; «Dispositivos» abre `/dispensers`; `cd
  app/app_movil_pdam && flutter analyze` sin errores.
- Constitución: P3 (vistas sin lógica y widgets aislados), P4, P6 (textos).
- Depende de: T4.
- Ejecutado: «Dispensar ahora» deshabilitado con el dispensador inactivo o con
  `currentFoodGrams <= 0` (el resto de la tarjeta no cambia); la hoja mantiene su
  lógica y el aviso de sin conexión se muestra como `errorText` sin cerrarla.
  `MockDispenserRepository` admite `dispenserStock` (5000 por defecto). Pruebas
  nuevas: hoja a 360 dp con `textScaler` 1.3, aviso de
  `ConnectivityRequiredFailures` visible, stock 0 deshabilitado y mascota sin
  dispensador sin acción; se conserva la prueba de «Dispositivos» → `/dispensers`.
  Tests primero (rojo: stock 0) y después verdes: `flutter test
  test/features/dispenser test/features/pets test/features/dashboard` → 391
  passed; suite completa `flutter test` → 1139 passed; `flutter analyze` sin
  errores (avisos previos).

- [x] **T6. Cierre, verificación manual y commit.**
  RF-1 a RF-16, RNF-1 a RNF-9
- Incluye: suites completas de API y app, `flutter analyze`, `pio test -e native`,
  `pio run`, revisión de textos en español, checklist manual en el móvil y
  actualización de `MEMORY.md`.
- Checklist manual (paso → resultado esperado):

  | Paso | Resultado esperado |
  |------|--------------------|
  | Dispensar 50 g desde la ficha | Se muestra «Orden de dispensación enviada»; al consultar el equipo se escribe `feeding_dispensed` y el stock baja. |
  | Solicitar con un horario dentro de la ventana de 10 min | El horario no se dispensa y no aparece un evento extra (verificado en la base de datos). |
  | Reintentar con la misma cantidad | No se crea otra solicitud ni otro evento. |
  | Cantidad 0, >200 g o mayor que el stock reservado | Se rechaza con el mensaje del catálogo y no queda solicitud. |
  | Mascota sin dispensador | La acción «Dispensar ahora» no se ofrece. |
  | Dispensador desactivado o stock 0 | La acción queda deshabilitada y el servidor rechaza cualquier cantidad. |
  | App sin conexión | La hoja muestra el aviso de sin conexión y no se envía nada. |
  | Pantalla de 360 dp con la hoja abierta | Sin desbordamientos y con todos los textos en español. |
  | «Dispositivos» en el dashboard | Abre la pestaña de dispensadores (`/dispensers`). |
  | `cd DispensadorESP32 && pio test -e native` y `pio run` | Pruebas nativas en verde y compilación correcta, sin cambios de firmware. |
  | Revisión final de textos y commit/PR | Textos en español, diff revisado y commit o PR abierto. |

- Hecho cuando: `cd api && pytest` completo en verde; `cd app/app_movil_pdam &&
  flutter test` completo en verde; `flutter analyze` con 0 errores; `cd
  DispensadorESP32 && pio test -e native` y `pio run` en verde; el checklist
  manual se cumple; `MEMORY.md` actualizado y los cambios subidos en un commit/PR
  revisado.
- Ejecutado: verificación manual en el móvil confirmada por el usuario
  (dispensación rápida, evento y stock, choque con horario, rechazos y
  «Dispositivos» → `/dispensers`); `pytest` 778 passed (937 subtests), `flutter
  test` 1139/1139, `flutter analyze` 0 errores, `pio test -e native` 230/230 y
  `pio run` SUCCESS. Pendiente: commit/PR.
- Constitución: P2 (mapeo RF→prueba completo), P4 y P6 (revisión de textos).
- Depende de: T5.
