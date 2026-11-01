# Tareas — Spec 018

Cada tarea termina con `flutter analyze` limpio y `flutter test` del módulo en verde. Tests primero.

- [x] **T1. Dominio tipado del ciclo, permisos y etapas**
  Archivos: `lib/.../domain/entity/ble_adapter_status.dart`, `ble_permission_result.dart`, `provisioning_stage.dart`, `ble_scan_event.dart`; prueba `test/.../domain/ble_scan_types_test.dart`.
  Test primero: mapeo de los 7 estados del adaptador, igualdad de eventos y `ProvisioningException` con etapa y permiso.
  RF: RF-11, 12, 17..21, 25 · RNF-01.
  Hecho cuando: los tipos son `Equatable`/enum cerrados, compilan sin dependencias nuevas y la prueba cubre cada valor del catálogo de etapas.

- [x] **T2. Contrato del repositorio, fronteras y DI**
  Archivos: `domain/repository/dispenser_repositories.dart`, `data/services/ble_adapter.dart`, `ble_permissions.dart`, `data/repositories_impl/dispenser_repository_impl.dart`, `core/di/injection_container.dart`, `domain/entity/scanned_device.dart`; actualizar `test/.../presentation/bloc/dispenser_bloc_test.dart` y `test/.../views/register_dispenser_view_test.dart`.
  Test primero: `FakeBlePermissions` traduce concedido, denegado y permanente, y `granted` con ubicación desactivada; `ScannedDevice` igual por `remoteId`.
  RF: RF-10, 17, 18 · RNF-07, 08.
  Hecho cuando: existen `scanBleDispensers({cycleId, window})`, `stopBleScan({cycleId})` y `adapterStatus`, los dos mocks compilan y el servicio real arranca sin comportamiento nuevo.

- [x] **T3. Servicio: ventana con identidad, sondeo y sin caché**
  Archivos: `data/services/ble_provisioning_service.dart`; prueba `test/.../data/services/ble_provisioning_service_test.dart` con `FakeBleAdapter`.
  Test primero: ventana de 15 s (inyectada corta) sin consumirse por cooldown; cierre emite `BleScanWindowClosed`; sondeo solo con ventana y cancelado al cerrar; ninguna lista de `lastScanResults`; `stopBleScan(cycleId)` no detiene un ciclo posterior.
  RF: RF-01, 03, 07, 08, 10, 15, 16.
  Hecho cuando: la prueba falla si se reemite caché, si el sondeo sobrevive al cierre o si un `stop` ajeno detiene el ciclo vigente.

- [x] **T4. Bloc: estados, transformer secuencial, apertura y renovación**
  Archivos: `presentation/bloc/dispenser_state.dart`, `dispenser_event.dart`, `dispenser_bloc.dart`; prueba `test/.../bloc/dispenser_bloc_scan_test.dart`.
  Test primero: `BleScanOpeningState` al iniciar sin consumir ventana; tres ventanas automáticas y `BleScanFinishedState`; contador a cero con búsqueda manual o resultado; dos `StartScanBleEvent` solapados no duplican ciclo; `StartScanBleEvent` + `StopScanBleEvent` se serializan.
  RF: RF-01..05, 09, 23.
  Hecho cuando: el transformer propio está aplicado a los eventos de escaneo y la prueba demuestra que la apertura no cuenta como ventana ni renovación.

- [x] **T5. Bloc: identidad, deduplicación, detención y prelación manual**
  Archivos: `dispenser_bloc.dart`, `dispenser_state.dart`; prueba `test/.../bloc/dispenser_bloc_scan_test.dart`.
  Test primero: dos listas equivalentes emiten un estado aunque cambie el RSSI; cierre tardío del ciclo anterior no altera el nuevo; doble `StopScanBleEvent` idempotente y un único `BleScanStoppedState`; manual durante apertura de renovación cancela y abre ciclo con contador a cero; manual desde resultados conservados abre ciclo vacío.
  RF: RF-06..10, 24.
  Hecho cuando: ninguna secuencia de eventos deja dos ciclos vivos ni reinicia la ventana por un inicio repetido.

- [x] **T6. Adaptador y ciclo de vida en bloc y pantalla**
  Archivos: `dispenser_bloc.dart`, `dispenser_event.dart`, `ble_scan_page.dart`; pruebas `dispenser_bloc_scan_test.dart` y `ble_scan_page_test.dart`.
  Test primero: `off` produce aviso sin progreso y sin `turnOn`; `on` reabre ciclo; `unavailable` y `unauthorized` producen su aviso; `paused`/`hidden` cierran, `inactive` no, `resumed` reabre salvo aviso vigente.
  RF: RF-11..14, 25 · RNF-06.
  Hecho cuando: la página registra y quita el observer, y el bloc no invoca ningún encendido del adaptador en toda la prueba.

- [x] **T7. Aprovisionamiento acotado y permisos al aprovisionar**
  Archivos: `ble_provisioning_service.dart`, `provisioning_stage.dart`, `wifi_provisioning_page.dart`; prueba `test/.../data/services/ble_provisioning_test.dart`.
  Test primero: conexión 15 s, descubrimiento 10 s, escritura 10 s y desconexión 5 s vencen con su etapa; presupuesto 60 s devuelve `presupuesto_agotado`; pérdida de conexión devuelve `conexion_perdida`; permisos denegados no inician y no dejan el botón deshabilitado.
  RF: RF-17, 19..22 · RNF-01.
  Hecho cuando: cada etapa tiene prueba propia, ninguna prueba espera segundos reales y el estado de aprovisionamiento siempre termina.

- [x] **T8. Precedencia de estados y cesión a la lista**
  Archivos: `dispenser_bloc.dart`, `dispenser_event.dart` (comando interno de carga); prueba `test/.../bloc/dispenser_bloc_precedence_test.dart` y ajuste de `dispenser_bloc_scan_test.dart`. `ble_scan_page.dart` no requirió cambios: ya emite stop y carga en orden.
  Nota: `_stopScan` durante un aviso no emite `BleScanStoppedState` (RF-24 prevalece sobre RF-08) y deja la cesión interna para que la lista de 010 RF-05 se restaure al salir.
  Test primero: `LoadDispensersEvent` y `RefreshDispensersEvent` se descartan con apertura, escaneo, resultados conservados, final, aviso, permisos y aprovisionamiento; se aceptan con `BleScanStoppedState`; la secuencia de `dispose` (stop + load) termina en lista.
  RF: RF-08, 24 · RNF-06.
  Hecho cuando: la tabla de rangos es única y una prueba por combinación demuestra que ningún estado de lista pisa el escaneo ni el aviso.

- [x] **T9. Vistas de escaneo y aprovisionamiento con tema global**
  Archivos: `ble_scan_page.dart`; pruebas `ble_scan_page_test.dart` y `wifi_provisioning_page_test.dart`. `wifi_provisioning_page.dart` y `provisioning_stage_messages.dart` ya tenían el copy y las acciones desde T7; T9 añade la prueba de los seis literales exactos del catálogo.
  Nota: en resultados conservados y final conviven «Volver a buscar» y «Cancelar Escaneo» (RF-05); en la ventana abierta no hay acción de búsqueda (RF-06). La denegación de permisos al aprovisionar ofrece «Abrir ajustes» (RF-17).
  Test primero: progreso solo con ventana abierta y sin dispositivos; «Buscando más dispensadores...» con lista; final con «Volver a buscar» y cancelar; avisos en la zona de la lista con «Abrir ajustes» y «Reintentar»; «Conectar» navega; copy por etapa; cierre de página sin timers pendientes.
  RF: RF-01..05, 11, 17, 19..21, 23..25 · RNF-03, 04, 06.
  Hecho cuando: no hay colores literales ni textos fuera de español, no quedan timers al cerrar y `flutter analyze` sigue limpio.

- [x] **T10. Manifiesto, regresión y cierre**
  Archivos: `android/app/src/main/AndroidManifest.xml`, `MEMORY.md`; pruebas de regresión existentes.
  Test primero: prueba de ubicación (exigida y no exigida) y de permiso permanente con apertura de ajustes.
  RF: RF-18, RNF-08, RNF-09.
  Hecho cuando: el bloque de permisos Bluetooth y ubicación es coherente con `neverForLocation`, `flutter analyze` da 0 errores, `flutter test` pasa completo, las pruebas de 005/010 siguen verdes y `MEMORY.md` recoge la decisión de ciclo con identidad.
