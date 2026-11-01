# Plan — Spec 018 (ciclo de escaneo BLE)

Base: `specs/018-ciclo-escaneo-ble/spec.md` (aprobada: 25 RF, 9 RNF, 17 CP). Solo app Flutter; sin firmware, backend ni dependencias nuevas.

## Enfoque técnico

El ciclo se modela en el servicio BLE con un `cycleId` incremental, una fase de apertura (cooldown 1,2 s + comprobación de permisos y adaptador) y una ventana de 15 s que arranca cuando el escaneo del adaptador está activo. El servicio emite eventos tipados por ciclo (dispositivos, ventana cerrada, fallo) y expone el estado del adaptador; el bloc los consume en orden, decide renovación (3 ventanas), conserva resultados sin temporizadores y aplica la precedencia de estados con cesión única del estado detenido. Timeouts y presupuesto del aprovisionamiento viven en el servicio y devuelven una etapa tipada; la presentación traduce el catálogo a español. La frontera `BleAdapter` + `BlePermissions` (interna, con implementación real por defecto) permite pruebas sin hardware. Sin `bloc_concurrency` ni `fake_async`.

## Archivos

| Ruta (bajo `app/app_movil_pdam/`) | Acción | Qué cambia | RF/RNF |
| --- | --- | --- | --- |
| `lib/.../domain/entity/ble_adapter_status.dart` | crear | Enum de 7 estados (`unknown`, `unavailable`, `unauthorized`, `turningOn`, `on`, `turningOff`, `off`) + `isUsable`. | RF-11, 12, 25 |
| `lib/.../domain/entity/ble_permission_result.dart` | crear | `granted`, `denied`, `permanentlyDenied` + `locationRequired`. | RF-17, 18 |
| `lib/.../domain/entity/provisioning_stage.dart` | crear | Enum de 6 etapas y `ProvisioningException(stage, permission)` tipada. | RF-19..21, RNF-01 |
| `lib/.../domain/entity/ble_scan_event.dart` | crear | `BleScanDevices(cycleId, devices)`, `BleScanWindowClosed(cycleId, hasDevices)`, `BleScanFailed(failure)`. | RF-01..04, 11, 17, 18 |
| `lib/.../domain/entity/scanned_device.dart` | modificar | `Equatable` por `remoteId`; el `rssi` no participa en igualdad. | RF-10 |
| `lib/.../domain/repository/dispenser_repositories.dart` | modificar | `scanBleDispensers({cycleId, window})`, `stopBleScan({cycleId})`, `Stream<BleAdapterStatus> adapterStatus`, `connectAndProvisionBle` con excepción tipada. | RF-01..25 |
| `lib/.../data/services/ble_adapter.dart` | crear | Frontera: soporte, estado actual y flujo, `startScan`, `stopScan`, `isScanning`, `scanResults`, `lastScanResults`. | RF-11, 14, 15, 25 |
| `lib/.../data/services/ble_permissions.dart` | crear | Frontera de permisos y ubicación con resultado real. | RF-17, 18 |
| `lib/.../data/services/ble_provisioning_service.dart` | modificar | Ciclo con identidad, ventana, sondeo ligado, sin caché, timeouts 15/10/10/5, presupuesto 60 s, etapas. | RF-01..08, 15, 16, 19..21 |
| `lib/.../data/repositories_impl/dispenser_repository_impl.dart` | modificar | Delega las firmas nuevas y mapea excepciones a tipos. | todos |
| `lib/.../presentation/bloc/dispenser_state.dart` | modificar | Estados de apertura, escaneo, resultados conservados, final, detenido, avisos y permisos; rango de precedencia. | RF-02, 11, 17, 23..25 |
| `lib/.../presentation/bloc/dispenser_event.dart` | modificar | Eventos de ciclo y de ciclo de vida (`AppLifecycleChangedBleEvent`). | RF-13 |
| `lib/.../presentation/bloc/dispenser_bloc.dart` | modificar | Transformer secuencial, máquina de fases, renovación, suscripción del adaptador, precedencia y cesión. | RF-05..10, 13, 22, 24 |
| `lib/.../presentation/views/ble_scan_page.dart` | modificar | `WidgetsBindingObserver`, estados y acciones (progreso solo con ventana). | RF-01, 05, 11, 13, 23..25 |
| `lib/.../presentation/widgets/provisioning_stage_messages.dart` | crear | Catálogo de etapas → copy en español. | RF-19..21, RNF-04 |
| `lib/.../presentation/views/wifi_provisioning_page.dart` | modificar | Copy por etapa y por permiso; botón siempre recuperable. | RF-17, 19..21 |
| `lib/core/di/injection_container.dart` | modificar | Construye adapter, permisos y servicio con duraciones. | RNF-07 |
| `android/app/src/main/AndroidManifest.xml` | modificar | Coherencia de `neverForLocation` y ubicación. | RF-18, RNF-08 |
| `test/.../dispenser/...` | crear/modificar | Dobles (`FakeBleAdapter`, `FakeBlePermissions`), pruebas de servicio, bloc y widgets; actualizar `MockDispenserRepository` de dos archivos. | RNF-05, 09 |

## Decisiones

1. **Identidad de ciclo numérica en el servicio**: `stopBleScan(cycleId)` solo detiene si el ciclo vigente coincide. Alternativa descartada: cancelar solo la suscripción, que no evita que el cierre tardío del `async*` detenga el escaneo nuevo.
2. **`EventTransformer` propio secuencial** para `StartScanBleEvent`, `StopScanBleEvent` y lifecycle. Alternativa descartada: `bloc_concurrency` (dependencia nueva, RNF-07). Bloc 9 ejecuta handlers concurrentes por defecto.
3. **Máquina de fases en el bloc**: apertura, escaneando, resultados conservados, final, detenido. Alternativa descartada: temporizadores en la vista (rompe RNF-01 y RNF-06).
4. **Ventana y cooldown con `Timer` y duraciones inyectadas** (`window`, `cooldown`). Alternativa descartada: `fake_async` (no declarado; lint `depend_on_referenced_packages`).
5. **Frontera `BleAdapter`/`BlePermissions` con implementación real por defecto**: los tests inyectan dobles. Alternativa descartada: mockear canales de plataforma (no cubre estados ni temporización).
6. **Etapa tipada + mapper de copy**: el servicio no contiene textos. Alternativa descartada: propagar `e.toString()` (prohibido por RNF-01 y RF-19).
7. **Precedencia como tabla de rangos**: `_canEmitListState` se sustituye por `_puedeEmitirLista()` con cesión exclusiva de `BleScanStoppedState`. Alternativa descartada: ampliar la lista blanca con estados de escaneo (deja pasar listas sobre avisos).
8. **`ScannedDevice` igual por `remoteId`**: el RSSI se refresca sin reemitir. Alternativa descartada: igualdad por todos los campos (parpadeo y rebuilds).

## Pruebas

- **Servicio**: `FakeBleAdapter` con `StreamController` y duraciones cortas (ventana 40 ms, cooldown 1 ms) para probar ventana, cierre, renovación, identidad, sondeo y ausencia de caché sin esperas reales.
- **Bloc**: `bloc_test` no está disponible; se usa el patrón actual (`expectLater` sobre `bloc.stream`) y eventos explícitos para serialización, descarte, precedencia y cesión.
- **Widgets**: `tester.pump(Duration)`; RNF-06 se valida porque `testWidgets` falla si quedan timers y se cierra con `pumpWidget(SizedBox())`.
- **Aprovisionamiento**: `FakeBleAdapter` expone un dispositivo falso con `discoverServices`/`write`/`disconnect` que vencen el plazo; se comprueban códigos de etapa y presupuesto.
- **Prohibido**: esperas reales de 15 s, `fake_async`, canales de plataforma.

## Trazabilidad RF → CP → tarea

| RF | CP | Tarea |
| --- | --- | --- |
| RF-01..05, RF-23 | CP-01, CP-02, CP-03, CP-14 | T1, T3, T4, T9 |
| RF-06..10 | CP-04, CP-05 | T1, T3, T5 |
| RF-11..14, RF-25 | CP-06, CP-07, CP-16 | T1, T2, T6 |
| RF-15, RF-16 | CP-02, CP-08 | T3, T4 |
| RF-17, RF-18 | CP-09, CP-10 | T2, T6, T7, T10 |
| RF-19..RF-22 | CP-11, CP-12 | T1, T7, T9 |
| RF-24 | CP-06, CP-15 | T5, T8 |
| RNF-01..09 | CP-11, CP-13, CP-17 | Todas; T10 cierra |

## Riesgos y mitigación

1. Bloc 9.2.1 concurrente: transformer secuencial propio probado con dos eventos solapados (T4).
2. `fake_async` no declarado: duraciones inyectadas y `pump(Duration)` (T3, T9).
3. `scanResults` no cierra al vencer el timeout y emite lista vacía al arrancar: se etiqueta cada emisión con `cycleId` y se ignora la ventana no activa (T3).
4. `DispenserBloc` singleton: la detención es el único punto de cesión y se prueba la secuencia `dispose` (T8).
5. RNF-06 solo visible en `testWidgets`: prueba de página con cierre explícito y sin timers (T9).
6. Mocks compartidos: cambiar la firma rompe dos archivos de prueba; se actualizan en la misma tarea que el contrato (T2).

## Orden y regresión

T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10. Cada tarea termina con `flutter analyze` sin errores y `flutter test` del módulo en verde; T10 ejecuta la suite completa y verifica que las pruebas de 005/010 (escaneo, aprovisionamiento y listado) siguen pasando.
