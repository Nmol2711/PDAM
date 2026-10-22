# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
* #### Spec 010 (Corrección Crítica de Aprovisionamiento, Persistencia Isar, NVS, Filtrado y Ciclo BLE) — **Completado y Verificado**
  * T1 implementada: `DispensersLocalDatasource` actualizado con lógica de upsert por MAC/ID en Isar para prevenir `IsarError: Unique index violated`, validado con test unitario en verde (RF-01, RNF-01).
  * T2 implementada: Rutina de borrado NVS por detección de nuevo build (`__DATE__ __TIME__`) en `wifi_service.cpp` para ESP32, verificada mediante compilación PlatformIO `pio run` exitosa (RF-02, RNF-02).
  * T3 implementada: Filtrado estricto `petId != null` en el repositorio de dispensadores para excluir dispensadores huérfanos, validado con test unitario en verde (RF-03, RNF-01).
  * T4 implementada: Actualización reactiva del estado de credenciales WiFi en BLoC y UI con tests de widgets exitosos (RF-04, RNF-03).
  * T5 implementada: Reinicio y limpieza del ciclo de vida del escáner BLE en `BleProvisioningService` y BLoC para reintentar búsquedas sin reiniciar la app (RF-05, RNF-01).
    - **Fix:** Resuelto condición de carrera de suscripción en `_onStartScanBle` y `scanDevices()` (ver commit/archivos modificados).
    - **Verificación:** `flutter analyze` sin errores; `flutter test` passing en feature dispensers (14/14).
  * T6 implementada: Validación integral superada (`flutter test` con 112/112 tests pasados, `flutter analyze` sin errores, y `pio run` compilado al 100%). Auditoría global aprobada por @reviewer.
* #### Spec 009 (Corrección y Validación de Credenciales WiFi y Sincronización en App y ESP32) — **Completado y Verificado**
  * T1 a T8 ejecutadas y aprobadas previamente.
