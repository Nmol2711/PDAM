# Tareas 021 — Vencimiento de la solicitud rápida que nunca se entrega

Orden: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8. Tests primero en cada tarea y la
suite en verde al terminarla. Constitución: P2 (trazabilidad RF → prueba →
componente), P3 (lógica fuera de las vistas), P4 (pruebas obligatorias), P5 (sin
datos sensibles) y P6 (textos en español).

- [x] **T1. Plazo de entrega y causa del catálogo.** RF-1, RF-9
- Incluye: en `api/app/domain/tiempo.py`, `PLAZO_SOLICITUD_RAPIDA =
  timedelta(minutes=15)`, `limite_de_entrega(recibida_en)` y
  `entrega_vencida(recibida_en, ahora)` (límite inclusivo, sin `TOLERANCIA`,
  `a_utc_naive` en la comparación); en `api/app/domain/catalogos.py`, la causa
  `"solicitud_vencida": Causa("Solicitud vencida", FALLO, ORIGEN_SERVIDOR)` sin
  tocar `MENSAJES_ERROR`; nuevo `api/tests/test_quick_dispense_expiry.py` con
  `TestPlazoDeEntrega` y `TestCatalogoDeCausas`; en `api/tests/test_logs_domain.py`
  añadir la causa a `CAUSAS_ESPERADAS` y pasar los conteos a 13 causas y 7 del
  servidor (sin debilitar las comparaciones).
- Pruebas: `TestPlazoDeEntrega::test_a_los_quince_minutos_exactos_sigue_vigente`,
  `::test_un_segundo_despues_del_limite_esta_vencida`,
  `::test_el_limite_es_la_recepcion_mas_quince_minutos`,
  `::test_no_aplica_la_tolerancia_de_un_segundo_de_las_ordenes`,
  `::test_compara_instantes_con_y_sin_zona_horaria`;
  `TestCatalogoDeCausas::test_solicitud_vencida_tiene_etiqueta_fallo_y_origen_servidor`,
  `::test_solicitud_vencida_no_es_motivo_de_reporte`,
  `::test_el_catalogo_de_errores_no_cambia`.
- Hecho cuando: `cd api && pytest tests/test_quick_dispense_expiry.py -q
  tests/test_logs_domain.py` pasa; en el límite exacto `entrega_vencida` es falso
  y un segundo después verdadero.
- Constitución: P2, P3 (regla pura con reloj inyectado), P4.
- Depende de: nada.

- [x] **T2. Descarte transaccional con registro.** RF-2, RF-9, RF-10, RNF-5, RNF-8
- Incluye: en `api/app/services/order_service.py`, `CAUSA_SOLICITUD_VENCIDA`,
  `DESCRIPCION_SOLICITUD_VENCIDA = "Solicitud rápida vencida sin entregar"`,
  `descartar_solicitudes_vencidas(db, ahora=None, dispenser_id=None)` y
  `_descartar_vencida(db, solicitud_id, instante)` según el plan: filtro por
  `tiempo.entrega_vencida`, `activity_service.registrar` sin `commit`, `UPDATE
  ... consumed_at IS NULL` con `rowcount`, `commit` único, `rollback` y `False`
  ante cualquier fallo, una transacción por solicitud. Dueño y mascota con
  `_datos_de_la_mascota`; si la mascota ya no existe, dueño actual del
  dispensador y `pet_name = NO_DISPONIBLE`. Contexto con `gramos_reservados`,
  `recibida_en` y `limite_entrega` como ISO UTC; `order_id`,
  `measured_grams`, `discounted_grams` y `retry_count` en `None`.
- Pruebas en `api/tests/test_quick_dispense_expiry.py`:
  `TestDescarte::test_descarta_la_solicitud_vencida_y_la_marca_consumida`,
  `::test_no_descarta_una_solicitud_en_el_limite_exacto`,
  `::test_el_descarte_no_crea_orden_ni_toca_la_cola_ni_el_stock`,
  `::test_varias_vencidas_escriben_un_registro_cada_una`,
  `::test_una_vencida_con_orden_en_curso_se_descarta_sin_tocar_la_orden`,
  `::test_una_vencida_con_el_dispensador_desactivado_se_descarta`;
  `TestRegistroDelDescarte::test_usa_tipo_comida_dispensada_resultado_fallo_y_causa_vencida`,
  `::test_conserva_mascota_mac_parcial_y_gramos_solicitados`,
  `::test_el_contexto_guarda_gramos_recepcion_y_limite`,
  `::test_los_datos_ausentes_quedan_como_no_disponible`,
  `::test_el_stock_resultante_es_el_stock_actual`,
  `::test_no_guarda_la_mac_completa`,
  `::test_la_mascota_eliminada_tras_reasignar_queda_como_no_disponible`;
  `TestIdempotenciaDelDescarte::test_dos_barridos_seguidos_dejan_un_unico_registro`,
  `::test_dos_sesiones_simultaneas_producen_una_sola_transicion`;
  `TestFalloDeEscritura::test_un_fallo_al_registrar_no_deja_marca_ni_registro`,
  `::test_la_solicitud_fallida_conserva_su_reserva`,
  `::test_el_barrido_siguiente_descarta_la_solicitud_fallida`,
  `::test_el_fallo_de_una_no_impide_descartar_el_resto`.
- Hecho cuando: `cd api && pytest tests/test_quick_dispense_expiry.py -q` pasa y
  `pytest -q` sigue en verde; tras el descarte hay un registro, `consumed_at`
  puesto, cero órdenes nuevas y el stock igual.
- Constitución: P2, P3 (servicio, no vista), P4, P5 (MAC parcial, sin
  credenciales).
- Depende de: T1.

- [x] **T3. Barrido periódico de 30 s.** RF-3, RNF-6, RF-11
- Incluye: en `api/app/services/background_tasks/background_schedules.py`,
  llamar a `order_service.descartar_solicitudes_vencidas(db, ahora=ahora)` entre
  `cerrar_vencidas` y `encolar_comida`, y devolver `{cerradas, descartadas,
  encoladas}`; en `api/tests/test_orders_expiry.py`, parchear también
  `descartar_solicitudes_vencidas` en
  `test_el_job_ejecuta_primero_el_cierre_y_despues_el_encolado` y exigir el orden
  `cerrar → descartar → encolar`. Sin job, temporizador ni intervalo nuevos.
- Pruebas en `api/tests/test_quick_dispense_expiry.py`:
  `TestBarridoPeriodico::test_el_ciclo_descarta_las_vencidas`,
  `::test_el_ciclo_devuelve_las_descartadas`,
  `::test_el_ciclo_no_descarta_una_solicitud_vigente`,
  `::test_el_ciclo_conserva_el_cierre_y_el_encolado` (no regresión de la 014).
- Hecho cuando: `cd api && pytest tests/test_orders_expiry.py
  tests/test_quick_dispense_expiry.py -q` pasa; un barrido descarta la vencida y
  deja intactas las vigentes, la cola y las órdenes.
- Constitución: P2, P4.
- Depende de: T2.

- [x] **T4. Consulta del dispositivo y entrega.** RF-3, RF-4, RF-5, RF-11
- Incluye: en `order_service.entregar_orden`, barrido perezoso
  `descartar_solicitudes_vencidas(instante, dispenser_id=dispensador.id)` cuando
  `simular` es falso, justo después del reset de WiFi y antes de evaluar la orden
  en curso; en `entregar_solicitud_manual`, guarda de vigencia con el mismo
  `instante`: si `simular`, devolver `dict(REPOSO)`; si no, excluir la solicitud
  en memoria y seguir con la siguiente. Sin cambios en la respuesta
  `{serve, amount, order_id, reset_wifi}` ni en el orden manual → cola.
- Pruebas en `api/tests/test_quick_dispense_expiry.py`:
  `TestConsultaDelDispositivo::test_la_consulta_descarta_la_vencida_de_su_dispensador`,
  `::test_la_consulta_entrega_la_vigente_y_descarta_la_vencida`,
  `::test_la_consulta_no_descarta_las_vencidas_de_otro_dispensador`,
  `::test_la_consulta_descarta_la_vencida_aunque_haya_una_orden_en_curso`,
  `::test_la_consulta_descarta_la_vencida_con_el_dispensador_desactivado`,
  `::test_la_consulta_en_el_limite_exacto_entrega_una_orden`,
  `::test_la_consulta_un_segundo_despues_del_limite_descarta_y_no_entrega`,
  `::test_la_consulta_no_entrega_una_vencida_cuando_el_descarte_falla`,
  `::test_la_consulta_de_diagnostico_no_entrega_una_vencida_y_responde_reposo`,
  `::test_la_consulta_de_diagnostico_no_escribe`,
  `::test_la_consulta_conserva_el_contrato_de_respuesta`,
  `::test_la_consulta_mantiene_la_prioridad_manual_sobre_la_cola`.
- Hecho cuando: `cd api && pytest tests/test_quick_dispense_expiry.py
  tests/test_quick_dispense_delivery.py tests/test_orders_dispensing.py -q` pasa;
  con una vencida y una vigente se entrega la vigente y queda un solo registro.
- Constitución: P2, P4.
- Depende de: T2.

- [x] **T5. Aceptación de una solicitud nueva y reintento idempotente.** RF-6, RF-7
- Incluye: en `solicitar_dispensacion_rapida`, llamar a
  `descartar_solicitudes_vencidas(instante, dispenser_id=dispensador.id)` después
  del retorno idempotente y antes de `cerrar_vencidas`; el retorno temprano por
  `operation_id` queda antes de cualquier barrido, sin cambiar el cuerpo ni el
  202. No se toca `_cantidades_pendientes`, `dispensado_rapido.stock_reservado`
  ni la cifra de stock del dispensador.
- Pruebas en `api/tests/test_quick_dispense_expiry.py`:
  `TestAceptacionConReservaCaducada::test_la_aceptacion_descarta_antes_las_vencidas_del_dispensador`,
  `::test_la_aceptacion_descarta_antes_de_cerrar_vencidas` (ancla del orden con
  ambas funciones parcheadas: exige `["descartar", "cerrar"]`),
  `::test_la_reserva_caducada_ya_no_rechaza_una_solicitud_nueva` (stock 100,
  vencida de 100, nueva de 100 aceptada),
  `::test_el_stock_mostrado_al_dueno_no_cambia`,
  `::test_el_reintento_de_una_solicitud_vencida_devuelve_el_mismo_202_y_status`,
  `::test_el_reintento_informa_el_stock_del_instante_del_reintento`,
  `::test_el_reintento_no_descarta_otras_solicitudes_ni_escribe_segundo_registro`,
  `::test_el_reintento_no_crea_orden_ni_cubre_horarios_ni_reserva`,
  `::test_el_reintento_con_otro_identificador_crea_una_solicitud_nueva`.
- Hecho cuando: `cd api && pytest tests/test_quick_dispense_expiry.py
  tests/test_quick_dispense.py -q` pasa; la reserva caducada se libera en la
  misma aceptación y el reintento no escribe nada.
- Constitución: P2, P4.
- Depende de: T2.

- [x] **T6. App: reflejo del registro en el historial.** RF-8
- Incluye: en
  `app/app_movil_pdam/lib/features/logs/presentation/widgets/log_item_widget.dart`,
  una línea «Stock resultante: <gramos>» dentro del item existente, solo cuando
  `resultingStock` no es nulo, con el formato de gramos que ya usa el item
  («900 g»); sin pantalla ni aviso nuevos y sin textos nuevos en la hoja
  «Dispensar ahora». En `app/app_movil_pdam/test/features/logs/presentation/views/logs_view_test.dart`,
  un caso con `eventLabel` «Comida dispensada», `outcomeLabel` «Fallo»,
  `causeLabel` «Solicitud vencida», mascota, MAC parcial, gramos y la línea de
  stock resultante, más el caso negativo sin stock; en
  `app/app_movil_pdam/test/features/logs/data/datasource/local/local_log_datasource_test.dart`,
  el ida y vuelta por Isar que conserva `cause`, `causeLabel`, mascota, MAC
  parcial y gramos de la causa nueva.
- Pruebas: `test_el_registro_de_solicitud_vencida_muestra_fallo_causa_y_gramos`
  (logs_view_test; con `resultingStock: 900` y `orderId`/`retryCount` nulos,
  espera «Stock resultante: 900 g»),
  `test_el_registro_sin_stock_no_muestra_la_linea_de_stock` (sin la línea
  cuando `resultingStock` es nulo) y
  `test_conserva_la_causa_de_solicitud_vencida_en_la_cache`
  (local_log_datasource_test, con mascota, MAC parcial, gramos y la orden y los
  reintentos nulos conservados por Isar).
- Hecho cuando: `cd app/app_movil_pdam && flutter test test/features/logs` pasa y
  `flutter analyze` no añade errores; el item muestra el stock resultante solo
  cuando el registro lo trae; no aparece ninguna vista, aviso ni texto nuevo en
  la hoja «Dispensar ahora».
- Constitución: P3 (la vista solo presenta lo que envía el servidor), P4, P6.
- Depende de: T1 (causa del catálogo).

- [x] **T7. No regresión y verificación manual.** RF-11, RNF-1 a RNF-9
- Incluye: suites completas de backend, app y firmware; `flutter analyze`;
  revisión de textos nuevos en español y sin datos sensibles; verificación manual.
- Pruebas añadidas en `api/tests/test_quick_dispense_expiry.py` para los dos casos
  límite que quedaban sin cubrir y la cota de RNF-6:
  `TestDescarte::test_stock_cero_con_solicitud_vencida_la_descarta_y_sigue_sin_stock`
  (RF-2, RF-6), `TestRegistroDelDescarte::test_el_dispensador_reasignado_y_vencido_guarda_la_mascota_original`
  (RF-9) y `TestBarridoPeriodico::test_el_barrido_respeta_la_cota_de_sesenta_segundos`
  (RNF-6, RNF-2). Cada una se comprobó en rojo con una mutación sobre una copia
  fuera del repositorio.
- Verificación manual confirmada por el usuario el 2026-11-01 con el APK
  `0.2.0+3`, backend reiniciado y ESP32 sin cambios: el descarte aparece en el
  siguiente ciclo del barrido, el historial muestra «Solicitud vencida» con
  «Fallo», gramos y stock resultante, la nueva solicitud por la misma cantidad se
  acepta con la reserva ya liberada y el reintento con el mismo identificador no
  duplica el registro.
- Resultado 2026-11-01 (árbol con la 022 ya commiteada): `pytest -q` 887 passed /
  965 subtests; `flutter test` 1213; `flutter analyze` 103 issues (85 avisos, 18
  info) y 0 errores, ninguno en archivos de la 021; `pio test -e native` 230/230;
  `pio run` SUCCESS (RAM 19,7 %, Flash 64,5 %).
- Checklist manual (paso → resultado esperado):

  | Paso | Resultado esperado |
  |---|---|
  | Solicitar 50 g con el dispensador sin consultar y esperar un ciclo | La solicitud queda consumida, el historial muestra «Solicitud vencida» con «Fallo», gramos y stock, y no hay orden. |
  | Repetir la misma cantidad por la misma mascota | Se acepta con 202: la reserva ya se liberó. |
  | Reintentar con el mismo identificador de operación | Mismo 202 y mismo `status`, sin segundo registro ni orden. |
  | Encender el equipo después del plazo y consultar | No recibe nada de esa solicitud y el registro sigue visible. |
  | Consultar `check-taks-test` con una vencida | Responde `serve: false` sin escribir nada. |
  | Revisar el registro en la app con la caché local (sin red) | Se ve la causa «Solicitud vencida» y el resultado «Fallo». |

- Hecho cuando: `cd api && pytest` completo en verde; `cd app/app_movil_pdam &&
  flutter test` completo en verde y `flutter analyze` con 0 errores; `cd
  DispensadorESP32 && pio test -e native` y `pio run` en verde; el checklist se
  cumple.
- Constitución: P2 (cada RF con su prueba), P4, P6.
- Depende de: T3, T4, T5, T6.

- [x] **T8. Actualización de `MEMORY.md`.** RNF-1
- Incluye: cerrar la línea «021 aprobada, plan y tareas pendientes» con el estado
  implementado, anotar la decisión del plazo de 15 min sin tolerancia y del
  barrido perezoso, retirar la deuda «solicitud que nunca se entrega» y registrar
  las cifras nuevas de `pytest`, `flutter test`, `flutter analyze` y `pio`.
  Máximo ~50 líneas y sin datos sensibles.
- Hecho cuando: `MEMORY.md` refleja la 021 cerrada y ya no lista la deuda de la
  solicitud huérfana.
- Constitución: P2, P6.
- Depende de: T7.
