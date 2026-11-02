# Plan 020 — Dispensación rápida manual y acceso a dispositivos

Spec: `specs/020-dispensado-rapido-manual/spec.md` (aprobada; T1–T5 implementadas,
T6 pendiente). Toca backend y app; el firmware no cambia y no se añaden
dependencias.

## Enfoque

1. **Backend, reglas.** Límite de 200 g, validaciones, ventana de coincidencia,
   catálogo de errores y stock reservado como dominio puro. Una tabla nueva para
   las solicitudes manuales evita reconstruir `dispensing_queue` y conserva
   intacta la spec 014.
2. **Backend, solicitud y entrega.** La solicitud y la cobertura de ocurrencias se
   escriben en una transacción. La deduplicación por `operation_id` ocurre antes
   de validar cantidad y stock. La entrega manual tiene prioridad sobre la cola
   programada y reutiliza la orden, el reporte, el cierre y el descuento
   existentes.
3. **Backend, migración.** La tabla nueva la crea `create_all`; en bases donde ya
   existe se añade `operation_id` y su índice único sin destruir datos.
4. **App, datos y estado.** Límite y validación en dominio, caso de uso,
   repositorio, datasource y un `QuickDispenseCubit` dedicado para no mezclar este
   flujo con el BLoC de escaneo.
5. **App, interfaz.** Acción «Dispensar ahora» en la ficha de la mascota, hoja con
   solo la cantidad y corrección de la navegación del dashboard.

## Archivos

| Archivo | Cambio |
|---------|--------|
| `api/app/domain/dispensado_rapido.py` (nuevo) | `LIMITE_RAPIDO_GRAMOS = 200.0`; `normalizar_cantidad_rapida(valor)`; `normalizar_operation_id(valor)`; `stock_reservado(stock, pendientes)`; `codigo_rechazo(cantidad, stock_reservado, activo, orden_en_curso)`; `ocurrencias_en_ventana(hora, instante_local, ventana)`; `en_ventana_coincidencia(...)`. Puros, con reloj y ventana como parámetros. RF-2 a RF-7, RF-14, RNF-9. |
| `api/app/domain/catalogos.py` | Cinco códigos nuevos: `cantidad_rapida_invalida`, `stock_insuficiente`, `dispensador_desactivado`, `dispensacion_en_curso` y `operacion_invalida`, con los textos exactos de la spec. RF-2 a RF-5, RF-14, RF-15. |
| `api/app/models/models.py` | `ManualDispensingRequest`: `id`, `dispenser_id` con FK en cascada, `pet_id`, `amount`, `operation_id`, `requested_at`, `consumed_at`; índice `(dispenser_id, consumed_at, requested_at)` y restricción única `(dispenser_id, operation_id)`. RF-7 a RF-9, RF-14, RF-16. |
| `api/app/models/__init__.py` | Exporta el modelo nuevo. |
| `api/app/db/database.py` | `_migrar_solicitudes_rapidas`: si la tabla no existe, no hace nada y `create_all` la crea con la columna; si existe y le falta `operation_id`, la añade, rellena `'legado:' || id` y crea el índice único `(dispenser_id, operation_id)`. Sin borrar datos. RF-14. |
| `api/app/services/order_service.py` | `solicitar_dispensacion_rapida(...)`, `_stock_reservado(...)`, `_solicitud_por_operacion(...)`, `_cubrir_ocurrencias_programadas(...)`, `entregar_solicitud_manual(...)`; `entregar_orden` entrega la manual antes de la cola; `encolar_comida` no vuelve a encolar una ocurrencia cubierta; descarta una solicitud con `pet_id` distinto al del dispensador. `_ocurrencias_del_horario` queda como envoltorio de dominio (refactor sin cambio de comportamiento, cubierto por las pruebas de la 014). RF-1 a RF-10, RF-16. |
| `api/app/services/account_service.py` | La baja de cuenta borra en cascada las solicitudes rápidas pendientes del usuario; `contar_huerfanos` y `_borrar_datos` las incluyen. RF-16. |
| `api/app/schemas/dispenser.py` | `QuickDispenseRequest` (`amount: Any`, `operation_id: Any`) y `QuickDispenseResponse` (`status`, `requested_grams`, `stock_grams`). RF-1, RF-14, RNF-5. |
| `api/app/api/endpoints/dispenser.py` | `POST /dispensers/{dispenser_id}/quick-dispense` autenticado, cuerpo como `Any` y traducción de `ErrorDominio` a 400; 404 si no existe o no es del usuario. RF-1 a RF-6, RF-14, RF-15. |
| `api/tests/test_quick_dispense.py` (nuevo) | Dominio, validaciones, reserva de stock, idempotencia, creación, cobertura y atomicidad. RF-1 a RF-7, RF-14, RF-15. |
| `api/tests/test_quick_dispense_delivery.py` (nuevo) | Prioridad, reclamación única, reporte, evento, stock, cierre por plazo y reasignación de dispensador. RF-8 a RF-10, RF-16. |
| `api/tests/test_quick_dispense_migration.py` (nuevo) | Tabla nueva por `create_all` y migración de `operation_id` con índice único en una base existente. RF-14. |
| `api/tests/test_account_deletion.py` | Prueba de baja de cuenta con una solicitud pendiente: se borra sin error y sin evento. RF-16. |
| `api/tests/test_logs_domain.py` | Actualiza `ERRORES_ESPERADOS` con los cinco códigos nuevos. |
| `app/app_movil_pdam/lib/features/dispenser/domain/utils/quick_dispense_limits.dart` (nuevo) | `maxQuickDispenseGrams = 200.0` y `validarCantidadRapida(texto, stockReservado)` con resultado tipado (`ok`, `vacia`, `noNumerica`, `noPositiva`, `superaLimite`, `superaStock`); admite decimales. RF-2, RF-3, RF-11. |
| `app/app_movil_pdam/lib/features/dispenser/domain/repository/dispenser_repositories.dart` | `Future<Either<Failures, bool>> quickDispense(int dispenserId, double grams, String operationId)`. RF-1, RF-12, RF-14. |
| `app/app_movil_pdam/lib/features/dispenser/domain/use_case/quick_dispense_uc.dart` (nuevo) | Caso de uso que delega en el repositorio. RF-1. |
| `app/app_movil_pdam/lib/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart` | `quickDispense` con POST a `/dispensers/{id}/quick-dispense` y cuerpo `{amount, operation_id}`; reutiliza `_apiExceptionFrom`. RF-1, RF-12, RF-14. |
| `app/app_movil_pdam/lib/features/dispenser/data/repositories_impl/dispenser_repository_impl.dart` | Comprueba conexión, llama al datasource y mapea de forma explícita los cinco códigos nuevos a `ServerFailures` con el texto del catálogo; el `default` conserva el mensaje del catálogo y nunca presenta excepciones crudas. Sin conexión devuelve `ConnectivityRequiredFailures`. RF-12, RF-15. |
| `app/app_movil_pdam/lib/features/dispenser/presentation/bloc/quick_dispense_cubit.dart` (nuevo) | Estados `inicial`, `enviando`, `aceptada(cantidad)`, `error(mensaje)`; evento único `solicitar`. Genera el `operation_id` con `generarIdentificadorOperacion()`, lo reutiliza mientras la hoja siga abierta y la cantidad no cambie, y lo renueva al cambiarla o al reabrir la hoja. RF-11, RF-14, RNF-3. |
| `app/app_movil_pdam/lib/features/dispenser/presentation/widgets/quick_dispense_sheet.dart` (nuevo) | Hoja con campo de cantidad, textos de máximo y stock, validación local, confirmación, bloqueo mientras envía y aviso de resultado. RF-11, RNF-7. |
| `app/app_movil_pdam/lib/features/pets/presentation/views/pet_detail_view.dart` | Acción «Dispensar ahora» en la tarjeta del dispensador, visible solo si existe y deshabilitada si está inactivo o con stock 0; abre la hoja y refresca los datos del dispensador al cerrar con éxito. RF-11. |
| `app/app_movil_pdam/lib/core/di/injection_container.dart` | Registra `QuickDispenseUc`; el cubit se crea en la ficha con `sl`. RF-11. |
| `app/app_movil_pdam/lib/features/dashboard/presentation/views/dashboard_view.dart` | «Dispositivos» navega con `context.go('/dispensers')`. RF-13. |
| `app/app_movil_pdam/test/features/dispenser/...` | Pruebas de límites, datasource, repositorio, cubit, hoja (incluido 360 dp y sin conexión) e idempotencia en la app. RF-1 a RF-12, RF-14. |
| `app/app_movil_pdam/test/features/dashboard/presentation/views/dashboard_theme_test.dart` | Añade la prueba de que «Dispositivos» abre `/dispensers`. RF-13. |
| `MEMORY.md` | Solo en el cierre. |

## Funciones puras

| Función | Responsabilidad | RF |
|---|---|---|
| `normalizar_cantidad_rapida(valor)` | Convierte a `float` finito o devuelve el código `cantidad_rapida_invalida`; rechaza texto, `NaN`, infinitos, `bool`, ≤0 y >200. Admite decimales. | RF-2 |
| `normalizar_operation_id(valor)` | Exige una cadena no vacía, sin espacios y de hasta 128 caracteres; si no, devuelve `operacion_invalida`. No genera el identificador. | RF-14 |
| `stock_reservado(stock, pendientes)` | Devuelve `stock − suma(pendientes)` acotado a 0; el llamador ya trae las solicitudes pendientes de la base de datos. | RF-3, RNF-9 |
| `codigo_rechazo(cantidad, stock_reservado, activo, orden_en_curso)` | Recibe la cantidad ya normalizada (no evalúa el formato) y devuelve el primer código aplicable en este orden: stock, desactivado, orden en curso. | RF-3 a RF-5 |
| `ocurrencias_en_ventana(hora, instante_local, ventana)` | Aplica `(instante − ventana, instante]` a un horario `HH:MM`, incluida la ocurrencia del día anterior. Reutilizada por `encolar_comida`. | RF-7 |
| `en_ventana_coincidencia(ocurrencia, instante_local, ventana)` | Frontera exacta de la ventana. | RF-7 |
| `validarCantidadRapida(texto, stockReservado)` | Devuelve el resultado tipado que usa la hoja; el servidor sigue siendo la autoridad. | RF-2, RF-3, RF-11 |

## Algoritmo

```
solicitar_dispensacion_rapida(dispenser_id, cantidad, operation_id, usuario):
  ahora = reloj()
  dispensador = buscar por id y dueño; si no existe o no es suyo -> 404
  operacion = normalizar_operation_id(operation_id)          # operacion_invalida
  existente = buscar por (dispensador, operacion)
  si existente: devolver la misma solicitud registrada con el mismo 202
                (sin crear, sin cubrir horarios; si ya se entregó, no se
                vuelve a dispensar)
  cerrar_vencidas(dispensador, ahora)
  cantidad = normalizar_cantidad_rapida(cantidad)
  reservado = stock_reservado(dispensador.stock, solicitudes_pendientes)
  codigo = codigo_rechazo(cantidad, reservado, activo, hay_orden_en_curso)
  si codigo: -> 400 con el código
  transacción:
    insertar ManualDispensingRequest(dispensador, cantidad, operacion, ahora)
    flush()                                   # toma el bloqueo de escritura
    # revalidación: otra solicitud pudo reservar entre la lectura y el flush
    reservado = stock_reservado(stock, pendientes_incluida_la_nueva)
    si reservado < 0: rollback -> 400 stock_insuficiente
    si hay orden en curso: rollback -> 400 dispensacion_en_curso
    para cada horario de la mascota:
      para cada ocurrencia en (ahora_local − 10 min, ahora_local]:
        fila = buscar en dispensing_queue por (dispensador, horario, ocurrencia)
        si fila existe y consumed_at es NULL: marcarla consumida
        si fila no existe: insertarla ya consumida (cobertura)
    commit
  responder pendiente con cantidad y stock actual

entregar_orden(mac):
  ... comprobaciones actuales de reset, orden pendiente y dispensador activo ...
  entrega = entregar_solicitud_manual(dispensador, ahora)
  si no hay: entrega = entregar_comida_en_espera(dispensador, ahora)
  respuesta

entregar_solicitud_manual(dispensador, ahora):
  solicitud = la más antigua con consumed_at NULL
  si solicitud.pet_id != dispensador.pet_id: marcarla consumida y descartar
                                             (sin orden ni evento)
  reclamar con UPDATE ... WHERE id=? AND consumed_at IS NULL y rowcount
  si pierde: probar la siguiente
  crear la orden con la cantidad y confirmar en la misma transacción
```

- La precedencia es cantidad → stock reservado → desactivado → orden en curso; el
  servicio evalúa cantidad con `normalizar_cantidad_rapida` y el resto con
  `codigo_rechazo`, que ya no vuelve a mirar el formato.
- Tras el `flush` se revalidan la reserva y la orden en curso bajo el bloqueo de
  escritura: la lectura previa no basta cuando dos solicitudes llegan a la vez.
- `encolar_comida` busca cualquier fila con la clave única, consumida o no; por
  eso una ocurrencia cubierta no se vuelve a encolar.
- El cierre y el descuento no cambian: `procesar_reporte` y `cerrar_vencidas` de la
  spec 014 se ejecutan igual para la orden manual y solo descuentan si el cierre
  es exitoso.

## Interfaz

`POST /dispensers/{id}/quick-dispense`, autenticado:

```json
{ "amount": 50.0, "operation_id": "8f14e45fceea167a5a36dedd4bea2543" }
```

- `202` `{ "status": "pending", "requested_grams": 50.0, "stock_grams": 950.0 }`.
- `400` `detail={code,message}` con los cinco códigos de la spec.
- `404` si el dispensador no existe o no pertenece al usuario.

App: la tarjeta del dispensador en la ficha de la mascota ofrece la acción
«Dispensar ahora», deshabilitada si el dispensador está inactivo o el stock es 0.
La hoja solo pide la cantidad, muestra «Máximo 200 g» y «Stock disponible: N g»,
valida localmente y deshabilita «Dispensar» mientras envía. Al aceptar se cierra y
se muestra «Orden de dispensación enviada»; el resultado real llega al historial
cuando el equipo reporta.

## Decisiones

| Decisión | Alternativa descartada | Porqué |
|----------|------------------------|---------|
| Tabla nueva `manual_dispensing_requests` | Hacer nullable `dispensing_queue.schedule_id` | Evita reconstruir una tabla de la spec 014 y separa la prioridad manual de la ocurrencia programada. |
| Stock reservado = stock − solicitudes pendientes | Validar solo contra el stock actual | Impide que dos solicitudes pendientes sumen más que el stock y que el equipo reciba más comida de la anotada. |
| `operation_id` obligatorio y deduplicado por dispensador | Reintentos sin identificador | Un reintento tras un timeout duplicaría la ración; el identificador es la única forma de distinguirlo de dos solicitudes iguales. |
| Migración DDL directa de `operation_id` | Framework de migraciones | El proyecto ya migra así en `db/database.py`; la tabla nueva la crea `create_all` y la base existente no se destruye. |
| Solicitud manual antes que la cola programada | Ordenar por fecha de la ocurrencia | La comida programada de la ventana ya se cubrió; la manual debe salir primero sin depender de milisegundos. |
| Insertar la ocurrencia cubierta como fila consumida | Borrar la ocurrencia de la cola | La clave única impide que cualquier otra operación que intente insertar la misma ocurrencia la vuelva a encolar; borrar permitiría reencolarla. |
| Rechazar si hay orden en curso | Encolar para después | Evita dobles raciones cuando el equipo ya está dispensando y cumple «solo la opción rápida». |
| Límite 200 g validado en servidor y app | Confiar solo en la interfaz | El servidor es la autoridad y la app da respuesta inmediata; el límite es un tope de seguridad, no una promesa de entrega dentro de los 30 s de la 013. |
| Sin tipo de evento nuevo | `quick_feeding_dispensed` | Se mantiene el historial y los filtros de la spec 014; el usuario pidió «Comida dispensada». |
| Cubit dedicado | Añadir el flujo al `DispenserBloc` | El BLoC existente ya coordina escaneo, BLE y aprovisionamiento; el flujo nuevo es independiente. |
| Reutilizar `generarIdentificadorOperacion()` | Añadir el paquete `uuid` | Ya existe una utilidad probada para el reabastecimiento y no se añaden dependencias (RNF-2). |
| `context.go('/dispensers')` | `context.push('/dispensers')` | `/dispensers` es una rama del shell; `go` cambia de pestaña y no apila una ruta sobre la rama actual. |
| Mantener `_ocurrencias_del_horario` como envoltorio | Duplicar el cálculo en el planificador | La cobertura y la cola usan el mismo criterio; el refactor no cambia el comportamiento de la 014 y lo cubren sus pruebas. |

## Estrategia de tests

- **Dominio (T1):** casos de frontera de cantidad, `operation_id`, ventana y
  precedencia de rechazo; `test_logs_domain.py` actualizado con los cinco códigos;
  migración sobre una base con la tabla ya creada.
- **Servicio y endpoint (T2):** reserva de stock con dos solicitudes, reserva
  concurrente en dos sesiones (stock 300 y dos solicitudes de 200, solo una
  aceptada) y su revalidación bajo el bloqueo de escritura, dedupe por
  `operation_id` (misma solicitud y mismo 202, sin cobertura nueva), 400 con
  `detail={code,message}`, 404 sin filtrar datos y rollback atómico.
- **Cobertura y concurrencia (T2):** ocurrencias en cola, no encoladas,
  inexistentes y fronteras de la ventana; dos solicitudes manuales compitiendo por
  la misma clave única y baja de cuenta con solicitud pendiente.
- **Entrega y cierre (T3):** prioridad, reclamación única, evento y descuento solo
  en cierre exitoso, `sin_reporte` sin descuento, reasignación, 409
  `pet_has_dispenser` al eliminar una mascota con dispensador y no regresión de
  las specs 013 y 014.
- **App (T4, T5):** límites con decimales, datasource con `{amount,
  operation_id}`, repositorio con mapeo explícito, cubit que reutiliza el
  identificador, hoja en 360 dp, aviso de sin conexión y navegación del dashboard.
- **Cierre (T6):** `cd api && pytest`, `flutter test`, `flutter analyze`,
  `pio test -e native`, `pio run` y checklist manual.

## Trazabilidad

| RF | Tarea | Pruebas |
|----|-------|---------|
| RF-1 | T2.a, T4 | Solicitud aceptada con dueño, dispensador y datos válidos; endpoint autenticado; caso de uso y cubit. |
| RF-2 | T1, T2.a, T4 | Cantidad 0, negativa, texto, `NaN`, infinito, >200 y 200 exacto; mismo límite en la app. |
| RF-3 | T1, T2.a, T2.b, T4 | Cantidad igual y mayor que el stock reservado; reserva concurrente (stock 300 y dos solicitudes de 200, solo una aceptada) y revalidación bajo bloqueo de escritura; stock 0. |
| RF-4 | T1, T2.a | Dispensador desactivado. |
| RF-5 | T1, T2.a | Orden pendiente en plazo y orden vencida que se cierra antes de aceptar. |
| RF-6 | T2.a, T5 | Mascota ajena o sin dispensador; 404 sin datos de otra cuenta; acción no ofrecida. |
| RF-7 | T1, T2.b | Cobertura en cola, no encolada, varias, fronteras y ocurrencia inexistente; concurrencia entre dos solicitudes manuales por la misma clave; atomicidad. |
| RF-8 | T3.a | La consulta del equipo entrega la manual antes que la programada; reclamación única. |
| RF-9 | T2.a, T3.a, T3.b | Solicitud sin consulta permanece pendiente sin vencimiento; la app informa envío. |
| RF-10 | T3.a, T3.b | Evento `feeding_dispensed` y descuento solo en cierre exitoso; cierre fallido y `sin_reporte` sin descuento. |
| RF-11 | T4, T5 | Hoja con solo cantidad, máximo, stock, decimales, bloqueo al enviar, éxito y errores; botón deshabilitado con stock 0 o inactivo. |
| RF-12 | T4, T5 | Sin conexión no se envía y se muestra el aviso en la hoja. |
| RF-13 | T5 | «Dispositivos» del dashboard abre `/dispensers`. |
| RF-14 | T1, T2.a, T4 | `operation_id` ausente o inválido da 400; repetido devuelve la misma solicitud y el mismo 202, sin cobertura nueva ni segundo dispensado; la app lo reutiliza mientras la hoja sigue abierta y lo renueva al cambiarla. |
| RF-15 | T2.a | 400 con `detail={code,message}` en todos los rechazos; 404 sin filtrar datos. |
| RF-16 | T2.b, T3.b | Baja de cuenta y cascada del dispensador; 409 `pet_has_dispenser` al eliminar una mascota con dispensador y solicitud intacta; reasignación descarta la solicitud sin orden ni evento. |
| RNF-1 | T6 | Suites completas en verde. |
| RNF-2 | T6 | Sin cambios de firmware ni dependencias: `pio test -e native`, `pio run`. |
| RNF-3 | T4, T5 | Lógica en dominio, caso de uso y cubit; vistas solo presentan. |
| RNF-4 | T5, T6 | Revisión de textos en español. |
| RNF-5 | T1, T2.b, T3.a | Pruebas de atomicidad, reclamación única y carrera de cobertura. |
| RNF-6 | T3.a, T3.b | No regresión de la 013 y la 014; sin doble evento ni doble descuento. |
| RNF-7 | T5 | Hoja y acción sin desbordamientos en 320 y 360 dp. |
| RNF-8 | T2.b | La cobertura no escribe evento; verificación en base de datos. |
| RNF-9 | T1, T2.a | El stock reservado se calcula en el servidor con las solicitudes pendientes. |

## Riesgos

- **Solicitud pendiente que nunca se entrega:** si el equipo no consulta, la
  solicitud queda sin vencimiento y sin evento, igual que la cola programada; es
  un riesgo aceptado y no se compensa el stock reservado.
- **Sobre-stock:** la reserva lógica evita aceptar más de lo disponible, pero una
  entrega fallida no descuenta stock (014), de modo que la reserva puede liberar
  gramos que ya salieron del depósito; se documenta como desvío aceptado.
- **Límite de 200 g frente a los 30 s de la 013:** si el presupuesto de motor no
  alcanza, la orden cierra como `objetivo_no_alcanzado` o `entrega_incompleta` sin
  descuento; el usuario lo ve en el historial.
- **Idempotencia:** depende de que la app reutilice el identificador mientras la
  hoja siga abierta y la cantidad no cambie; un cliente que lo renueve en cada
  reintento duplica la solicitud y la cobertura. El reintento debe devolver el
  mismo 202 y, si la solicitud ya se entregó, no volver a dispensar.
- **Reasignación o borrado:** una solicitud con el `pet_id` anterior debe
  descartarse al entregarse; la cascada del dispensador debe borrarla sin dejar
  órdenes ni eventos huérfanos. La mascota con dispensador no se borra: 409
  `pet_has_dispenser` de la 015, sin cascada y con la solicitud intacta.
- **Reserva concurrente:** dos solicitudes manuales pueden leer el mismo stock
  antes de escribir; tras el `flush` hay que revalidar la suma de pendientes bajo
  el bloqueo de escritura y rechazar la que exceda con `stock_insuficiente`.
- **Cobertura concurrente:** dos operaciones pueden competir por la misma clave de
  ocurrencia; la inserción consumida y el `IntegrityError` deben resolverse con la
  fila ganadora, sin duplicar ni perder la ocurrencia. Una ocurrencia inexistente
  no se cubre ni crea filas fantasma. Probar con dos sesiones.
- **Prueba existente del catálogo de errores:** `test_logs_domain.py` compara el
  diccionario completo; hay que actualizarlo, no debilitar la comparación.
- **Ficha de la mascota:** hoy usa el `DispenserBloc` para cargar; el cubit nuevo
  debe ser independiente y no pisar `DispenserLoaded`.
- **Hoja y teclado:** validar en 320 y 360 dp con `textScaler` 1.3 para evitar
  desbordamientos.
- **Navegación del dashboard:** las pruebas actuales pueden usar un `MaterialApp`
  sin router; la nueva prueba necesita un `GoRouter` real o un doble de navegación.
