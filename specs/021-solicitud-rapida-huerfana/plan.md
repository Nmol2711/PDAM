# Plan 021 — Vencimiento de la solicitud rápida que nunca se entrega

Spec: `specs/021-solicitud-rapida-huerfana/spec.md` (aprobada). Backend y un
cambio localizado en la app; el firmware no cambia. Sin dependencias, tablas,
columnas ni migraciones (RNF-2).

## Enfoque

1. **Plazo (RF-1).** Plazo de 15 min desde `manual_dispensing_requests.requested_at`
   como regla pura con el instante inyectado, junto a los demás plazos del
   servidor. Límite inclusivo y sin la tolerancia de 1 s que usan las órdenes.
2. **Descarte (RF-2, RF-9, RF-10).** Nueva función de servicio
   `descartar_solicitudes_vencidas`, hermana de `cerrar_vencidas`: por cada
   solicitud vencida, registro + `UPDATE` condicional en la misma transacción,
   `rowcount` como único ganador, `rollback` si falla el registro o la marca.
3. **Disparadores (RF-3, RF-6, RNF-6).** El ciclo de 30 s ya existente
   (`ejecutar_barrido`) añade un paso; la consulta del dispositivo y la
   aceptación de una nueva solicitud barren de forma perezosa solo su
   dispensador, antes de evaluar la entrega o el stock.
4. **Entrega (RF-4, RF-5).** La consulta usa un único instante para barrido y
   entrega, así el reloj decide el ganador; la entrega nunca reclama una solicitud
   vencida y el modo diagnóstico responde sin dispensación.
5. **Reintento y app (RF-7, RF-8, RF-11).** La deduplicación por `operation_id`
   sigue devolviendo antes de cualquier comprobación y de cualquier barrido; la
   app solo presenta lo que ya sirve el servidor: la etiqueta nueva y, en el
   item del historial, el stock resultante cuando viene informado.

## Archivos

| Archivo | Cambio |
|---|---|
| `api/app/domain/tiempo.py` | `PLAZO_SOLICITUD_RAPIDA = timedelta(minutes=15)`, `limite_de_entrega(recibida_en)` y `entrega_vencida(recibida_en, ahora)`, sin tolerancia y con límite inclusivo. RF-1, RNF-8. |
| `api/app/domain/catalogos.py` | `"solicitud_vencida": Causa("Solicitud vencida", FALLO, ORIGEN_SERVIDOR)` en `CAUSAS`. `MOTIVOS_REPORTE` lo excluye solo (origen servidor) y `MENSAJES_ERROR` no cambia. RF-9, RF-8. |
| `api/app/services/order_service.py` | Constantes `CAUSA_SOLICITUD_VENCIDA`, `DESCRIPCION_SOLICITUD_VENCIDA`, `CLAVE_GRAMOS_RESERVADOS/RECIBIDA_EN/LIMITE_ENTREGA`; `descartar_solicitudes_vencidas(db, ahora, dispenser_id=None)` y `_descartar_vencida(db, solicitud_id, instante)`; barrido perezoso en `entregar_orden` y en `solicitar_dispensacion_rapida`; guarda de vigencia en `entregar_solicitud_manual`. RF-1 a RF-7, RF-9, RF-10, RNF-5, RNF-8. |
| `api/app/services/background_tasks/background_schedules.py` | `ejecutar_barrido` descarta vencidas entre el cierre de órdenes y el encolado; devuelve `{cerradas, descartadas, encoladas}`. RF-3, RNF-6. |
| `api/tests/test_quick_dispense_expiry.py` (nuevo) | Plazo, descarte, registro, idempotencia, fallo de escritura, barrido periódico, consulta y aceptación. RF-1 a RF-7, RF-9, RF-10, RNF-5, RNF-6, RNF-8. |
| `api/tests/test_quick_dispense_delivery.py` | `test_una_solicitud_sin_consulta_sigue_pendiente_y_no_vence` pasa a `test_una_solicitud_sin_consulta_se_entrega_antes_del_plazo` y se añade `test_una_solicitud_sin_consulta_vence_y_ya_no_se_entrega`: la 021 deroga el caso límite de la 020 («sin consulta queda pendiente sin vencimiento»). RF-1, RF-4. |
| `api/tests/test_logs_domain.py` | `CAUSAS_ESPERADAS` con `solicitud_vencida`; 12 → 13 causas y 6 → 7 del servidor. No se debilita ninguna comparación. RF-9. |
| `api/tests/test_orders_expiry.py` | `test_el_job_ejecuta_primero_el_cierre_y_despues_el_encolado` pasa a parchear también `descartar_solicitudes_vencidas` y exige el orden `cerrar → descartar → encolar`. RF-3, RF-11. |
| `app/app_movil_pdam/lib/features/logs/presentation/widgets/log_item_widget.dart` | Línea «Stock resultante: <gramos>» dentro del item existente, solo cuando `resultingStock` no es nulo, con el formato de gramos que ya usa el item. Sin pantalla, aviso ni texto nuevos en la hoja «Dispensar ahora». RF-8. |
| `app/app_movil_pdam/test/features/logs/presentation/views/logs_view_test.dart` | Caso del registro con «Comida dispensada», «Fallo», «Solicitud vencida», mascota, MAC parcial, gramos y la línea de stock resultante; caso negativo sin la línea cuando `resultingStock` es nulo. RF-8. |
| `app/app_movil_pdam/test/features/logs/data/datasource/local/local_log_datasource_test.dart` | Ida y vuelta de la caché que conserva `cause`, `causeLabel`, mascota, MAC parcial y gramos de la solicitud vencida. RF-8. |

Sin cambios en `api/app/models/models.py`, `api/app/db/database.py`,
`api/app/api/endpoints/*` ni esquemas: no hay campo de estado nuevo
(`consumed_at` ya existe) ni texto nuevo que traducir. En la app el único cambio
de `lib/` es el item del historial: no hay pantallas, avisos, filtros ni textos
nuevos en la hoja «Dispensar ahora» (RF-8).

## Reglas puras nuevas

| Función | Responsabilidad | RF |
|---|---|---|
| `tiempo.limite_de_entrega(recibida_en)` | `recibida_en` (UTC naive) + 15 min; instante máximo que sigue vigente. | RF-1 |
| `tiempo.entrega_vencida(recibida_en, ahora)` | `ahora > limite_de_entrega(recibida_en)`; en el límite exacto devuelve `False`. | RF-1, RF-5 |

## Algoritmo

```
descartar_solicitudes_vencidas(db, ahora=None, dispenser_id=None) -> [ids]:
  instante = a_utc_naive(ahora o ahora_utc())
  candidatas = ids de ManualDispensingRequest con consumed_at NULL
               [y dispenser_id == el indicado]
               filtradas por tiempo.entrega_vencida(requested_at, instante)
  para cada id:
    si _descartar_vencida(db, id, instante): añadir a descartadas
  devolver descartadas

_descartar_vencida(db, id, instante) -> bool:
  solicitud = por id; si no existe o consumed_at no es NULL -> False
  si no tiempo.entrega_vencida(solicitud.requested_at, instante) -> False
  dispensador = por id; si no existe -> False        # cascada ya la borró
  nombre, dueno = _datos_de_la_mascota(solicitud.pet_id)
  si nombre es NULL: dueno = dueño de la mascota actual del dispensador
                     nombre = NO_DISPONIBLE          # RF-9
  try:
    registro = activity_service.registrar(            # sin commit
        feeding_dispensed, FALLO, causa solicitud_vencida,
        "Solicitud rápida vencida sin entregar",
        user_id=dueno, pet_id=solicitud.pet_id, pet_name=nombre,
        dispenser_id, dispenser_mac=dispensador.mac_address,
        context={gramos_reservados, recibida_en, limite_entrega},
        order_id=None, requested_grams=amount,
        measured_grams=None, discounted_grams=None, retry_count=None,
        resulting_stock=dispensador.current_food_grams,
        created_at=instante)
    filas = UPDATE manual_dispensing_requests
               SET consumed_at = instante
             WHERE id = ? AND consumed_at IS NULL
    si filas == 0: rollback; return False             # otro ganó (RNF-5)
    commit; return True
  except: rollback; return False                      # RF-10, reintenta el ciclo
```

```
ejecutar_barrido(ahora):
  cerradas = cerrar_vencidas(ahora)
  descartadas = descartar_solicitudes_vencidas(db, ahora)      # RF-3, RNF-6
  encoladas = encolar_comida(ahora)

entregar_orden(mac, ahora, simular):
  ... reset de WiFi (prioridad absoluta), sin cambios ...
  si no simular: descartar_solicitudes_vencidas(db, instante, dispenser_id)  # RF-4
  ... después, sin cambios: evaluación de la orden en curso, is_active,
      entrega manual, cola y bandera ...

entregar_solicitud_manual(dispensador, instante, simular):
  bucle:
    solicitud = la más antigua con consumed_at NULL
    si tiempo.entrega_vencida(solicitud.requested_at, instante):
        si simular: return REPOSO          # RF-4: diagnóstico sin dispensación
        añadir a descartadas y continuar   # defensa si el barrido falló (RF-10)
    ... reasignación, reclamación y orden, sin cambios ...

solicitar_dispensacion_rapida(...):
  operacion = normalizar_operation_id(...)
  dispensador = dueño
  si existe solicitud con (dispensador, operacion): devolverla  # RF-7, sin barrido
  descartar_solicitudes_vencidas(db, instante, dispenser_id)     # RF-6
  cerrar_vencidas(dispersador)
  ... cantidad, stock, estado y orden en curso, sin cambios ...
```

- El descarte no crea orden, no toca `dispensing_queue` ni descuenta stock: solo
  pone `consumed_at` y escribe el registro.
- `_cantidades_pendientes` y `dispensado_rapido.stock_reservado` no cambian: la
  reserva sigue siendo `consumed_at IS NULL` y libera al consumir.
- Un único `instante` para barrido y entrega en la misma consulta: si la
  solicitud no estaba vencida en el barrido, no puede vencer en la reclamación.

## Decisiones

| Decisión | Alternativa descartada | Porqué |
|---|---|---|
| Plazo en `domain/tiempo.py` | Poner el plazo en `domain/dispensado_rapido.py` | Es un plazo del servidor como `PLAZO_ORDEN`; convive con `a_utc_naive` y con la misma semántica de frontera (RF-1, RNF-3). |
| Función `entrega_vencida` sin `TOLERANCIA` | Reutilizar `tiempo.plazo_vencido` | Esa tolerancia de 1 s pertenece al plazo de 5 min de las órdenes (014 RF-20); aplicarla aquí retrasaría el descarte y rompería el límite inclusivo de RF-1. |
| Registro y marca en una transacción con `UPDATE ... consumed_at IS NULL` | Marcar primero y registrar después | Un fallo intermedio dejaría la solicitud consumida sin registro (RF-10) o un registro duplicado en dos barridos (RNF-5). |
| Una transacción por solicitud | Un `commit` por ciclo | RNF-5 exige idempotencia y que una solicitud no bloquee al resto; el fallo de una no revierte las demás. |
| Barrido perezoso llamando a la misma función con `dispenser_id` | Duplicar la consulta en la consulta del dispositivo | Una sola regla de descarte para los tres disparadores (RF-3) y menos superficie de error. |
| El barrido perezoso va antes de evaluar orden en curso y de `is_active` | Descartar solo al final de la consulta | Los casos «solicitud vencida con orden en curso: se descarta igual y no toca la orden» y «dispensador desactivado con solicitud pendiente: vence y se descarta igual» exigen que el descarte no quede detrás del bloqueo. |
| Diagnóstico (`simular`) devuelve reposo al topar una vencida | Saltarla en memoria y entregar la siguiente vigente | RF-4 dice «responde sin dispensación»; sin barrido no puede saber si esa solicitud se descartaría, y devolver reposo nunca entrega una vencida. |
| Reclamación exige vigencia con el mismo instante del barrido | Revalidar el reloj al reclamar | Con un único instante el ganador lo fija el reloj y no el orden de llegada (RF-5); revalidar con otro reloj crearía dos ganadores posibles. |
| Barrido perezoso después del reintento idempotente | Barrer antes de buscar el `operation_id` | RF-7 exige responder antes que cualquier otra comprobación y que el reintento no descarte otras solicitudes. |
| `status: "pending"` también en el reintento de una vencida | Inventar `discarded` en la respuesta | RNF-7 congela el contrato y «Fuera de alcance» excluye estados nuevos; el reintento no resucita la solicitud, solo informa el stock actual. |
| `pet_name` del registro en «no disponible» cuando la mascota ya no existe | Dejar `pet_name` nulo y resolverlo en la app | RF-9 pide explícitamente «no disponible» y la app no debe añadir textos ni vistas (RF-8); el `pet_id` se conserva para el filtro y la referencia. |
| Dueño del registro: la mascota de la solicitud; si no existe, el dueño actual del dispensador | Dueño del dispensador siempre | Con la mascota viva el registro aparece en el historial del dueño real; si se eliminó tras reasignar, el registro queda visible para quien gestiona el equipo y no se pierde. |
| Stock resultante visible en el item del historial | Pantalla de detalle, aviso o recalcular el stock en la app | El servidor ya envía `resultingStock` en el registro (RF-9) y el item ya pinta el resto de los datos; mostrarlo en la misma tarjeta no recalcula nada y respeta P3: la vista solo presenta (RF-8). |

## Estrategia de tests

Archivo nuevo `api/tests/test_quick_dispense_expiry.py`, reutilizando
`BaseDispensacionRapidaTests`, `AHORA`, `MAC`, `STOCK_INICIAL` y `_en_utc` de
`tests/test_quick_dispense.py`. En `api/tests/test_quick_dispense_delivery.py` se
reescribe el caso límite de la 020: la solicitud sin consulta se entrega antes
del plazo y, pasado el plazo, la consulta la descarta y no dispensa (RF-1, RF-4).

- **Plazo (RF-1):** vigente a `requested_at + 15 min`, vencida un segundo después,
  comprobación de que la tolerancia de 1 s no se aplica, instante inyectado.
- **Descarte (RF-2, RF-9):** marca `consumed_at`, un único registro, sin orden, sin
  cola, stock intacto, contexto con gramos/recepción/límite, `order_id` nulo,
  medidos/descontados/reintentos en «no disponible», MAC parcial únicamente,
  mascota eliminada como «no disponible».
- **Idempotencia y fallo (RNF-5, RF-10):** dos barridos seguidos, dos sesiones
  simultáneas con hilos, `registrar` que lanza y no deja marca ni registro,
  varias vencidas con un registro cada una, una que falla no impide el resto.
- **Disparadores (RF-3, RF-4, RF-5, RF-6, RNF-6):** barrido periódico, consulta
  real, consulta de diagnóstico, límite exacto en la consulta, aislamiento por
  dispensador, reserva caducada que ya no rechaza y reintento idempotente.
- **Contrato (RF-7, RF-11):** 202 con `{status, requested_grams, stock_grams}`,
  reintento sin descartar otras solicitudes ni escribir segundo registro,
  consulta con `{serve, amount, order_id, reset_wifi}` y no regresión de la cola,
  la cobertura de 10 min y `sin_reporte`.
- **App (RF-8):** el item del historial pinta la etiqueta del servidor con
  «Comida dispensada», «Fallo», «Solicitud vencida», mascota, MAC parcial y
  gramos; la línea de stock resultante aparece con el formato de gramos que ya
  usa el item y desaparece cuando `resultingStock` es nulo; la caché local
  conserva causa, etiqueta de causa, mascota, MAC parcial y gramos.
- **Cierre (T7):** `TestDescarte::test_stock_cero_con_solicitud_vencida_la_descarta_y_sigue_sin_stock`
  (stock 0 con vencida: se descarta y el stock sigue en 0; RF-2, RF-6),
  `TestRegistroDelDescarte::test_el_dispensador_reasignado_y_vencido_guarda_la_mascota_original`
  (el registro conserva la mascota de la solicitud; RF-9) y
  `TestBarridoPeriodico::test_el_barrido_respeta_la_cota_de_sesenta_segundos`
  (el descarte cae en el siguiente ciclo de 30 s, sin temporizador propio; RNF-6, RNF-2).

## Trazabilidad

| RF | Tarea | Pruebas |
|---|---|---|
| RF-1 | T1, T4 | `TestPlazoDeEntrega` (límite exacto y un segundo después), `test_la_consulta_en_el_limite_exacto_entrega`. |
| RF-2 | T2 | `TestDescarte` (marca, un registro, sin orden ni cola, stock intacto). |
| RF-3 | T3, T4, T5 | `TestBarridoPeriodico`, `TestConsultaDelDispositivo` (solo su dispensador), `TestAceptacionConReservaCaducada`. |
| RF-4 | T4 | Entrega de la vigente y descarte de la vencida; diagnóstico sin entrega y sin escritura. |
| RF-5 | T1, T4 | Carrera con el mismo instante: límite exacto gana la entrega, después gana el descarte; nunca doble transición. |
| RF-6 | T5 | Stock 100 con solicitud de 100 vencida: la nueva de 100 se acepta; stock mostrado sin cambios. |
| RF-7 | T5 | Reintento de una vencida: mismo 202 y `status`, `stock_grams` del reintento, sin orden, cobertura, reserva ni segundo registro, sin descartar otras. |
| RF-8 | T6 | `logs_view_test.dart` (causa nueva, stock resultante presente y ausente) y `local_log_datasource_test.dart` con la caché de la causa nueva. |
| RF-9 | T1, T2 | Catálogo de causas y contenido completo del registro. |
| RF-10 | T2 | Fallo de escritura: sin marca ni registro, reserva intacta, el siguiente barrido lo resuelve. |
| RF-11 | T3, T4, T7 | `test_orders_expiry.py` actualizado y suites completas de la 014, 019 y 020. |
| RNF-1, RNF-2 | T1–T7 | Prueba por RF; sin dependencias, migraciones ni firmware. |
| RNF-3, RNF-4 | T1–T6 | Lógica en dominio y servicios con el instante como parámetro; textos en español sin emojis. |
| RNF-5 | T2 | Dos barridos seguidos y dos sesiones simultáneas. |
| RNF-6 | T3, T4 | Barrido periódico en el siguiente ciclo; descarte inmediato en consulta y aceptación. |
| RNF-7 | T4, T5 | Contrato de la consulta y de la aceptación sin cambios. |
| RNF-8 | T1, T2 | Instantes del servidor en UTC, límite y descarte con el reloj inyectado. |
| RNF-9 | T7 | `pio test -e native` y `pio run` sin cambios. |

## Riesgos y deuda aceptada

- **Barrido de todo el histórico:** `descartar_solicitudes_vencidas` sin
  `dispenser_id` recorre las solicitudes no consumidas; con el barrido perezoso y
  el descarte diario el conjunto se mantiene pequeño y cabe en un `SELECT` por
  ciclo. Si creciera, se filtraría por fecha en SQL (`requested_at < limite`), lo
  que duplicaría la regla del plazo fuera del dominio.
- **Divergencia del diagnóstico:** no escribe, así que una vencida sigue en la
  base hasta el siguiente ciclo; responde reposo para no entregarla (RF-4).
- **Mascota eliminada:** el registro queda con `pet_id` y «no disponible»; la
  visibilidad pasa al dueño actual del dispensador. Es una concesión para no
  perder el registro cuando el filtro del historial es por usuario.
- **Fallos de escritura:** la solicitud sigue reservando hasta que un ciclo
  consiga escribir el registro; el dueño sigue viendo el stock reducido ese
  tiempo (RF-10).
- **`test.db` compartida:** las pruebas de concurrencia usan dos sesiones sobre la
  misma base; no relajar los tiempos ni el número de reintentos.

## Verificación

```
cd api && pytest tests/test_quick_dispense_expiry.py -q
cd api && pytest tests/test_quick_dispense.py tests/test_quick_dispense_delivery.py \
           tests/test_orders_expiry.py tests/test_logs_domain.py -q
cd api && pytest -q
cd app/app_movil_pdam && flutter test test/features/logs
cd app/app_movil_pdam && flutter test && flutter analyze
cd DispensadorESP32 && pio test -e native && pio run
```
