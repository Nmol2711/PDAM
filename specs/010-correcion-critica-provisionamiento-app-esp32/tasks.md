# Tareas — Spec 010: Corrección Crítica de Aprovisionamiento, Persistencia Isar, NVS, Filtrado y Ciclo BLE

- [x] **T1. App Móvil — Implementación de Upsert en `DispensersLocalDatasource` (Isar).** RF-01, RNF-01
  - Hecho cuando: Se modifica `dispensers_local_datasource.dart` para verificar existencia previa o usar lógica de upsert por MAC/ID, evitando `IsarError: Unique index violated` validado con test unitario.
- [x] **T2. Firmware ESP32 — Rutina de borrado NVS por detección de nuevo build.** RF-02, RNF-02
  - Hecho cuando: En `wifi_service.cpp` se implementa la comparación de `__DATE__ __TIME__` con NVS para limpiar credenciales al flashear, verificado por compilación PlatformIO.
- [x] **T3. App Móvil — Filtrado estricto de dispensadores por `petId != null`.** RF-03, RNF-01
  - Hecho cuando: `DispensersRepositoryImpl` y datasource aplican el filtro Isar `petIdIsNotNull()` para excluir dispensadores huérfanos, probado con test unitario.
- [x] **T4. App Móvil — Actualización reactiva del estado de credenciales WiFi en BLoC y UI.** RF-04, RNF-03
  - Hecho cuando: El `DispensersBloc` y la interfaz de usuario reflejan correctamente y de forma reactiva el estatus exitoso de configuración WiFi tras el aprovisionamiento.
- [x] **T5. App Móvil — Reinicio y limpieza del ciclo de vida del escáner BLE.** RF-05, RNF-01
  - Hecho cuando: `BleProvisioningService` cancela suscripciones previas, detiene escaneos activos y permite reintentar la búsqueda BLE sin reiniciar la aplicación.
- [x] **T6. Validación Integral — Ejecución de pruebas unitarias, de widgets y análisis estático.** General
  - Hecho cuando: Se ejecutan `flutter test`, `flutter analyze` (cero errores) y `pio run`, pasando todas las validaciones correctamente.
