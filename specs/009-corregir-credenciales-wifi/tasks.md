# Tareas — Spec 009: Corrección y Validación Robusta de Credenciales WiFi y Sincronización en App y ESP32

- [x] **T1. App Móvil — Integración de `flutter_secure_storage` en repositorio de dispensadores.** RF-01, RNF-02
  - Hecho cuando: Las credenciales WiFi y datos sensibles del aprovisionamiento se guardan cifrados mediante `flutter_secure_storage` en la capa de datos de la app móvil.

- [x] **T2. App Móvil — Corrección de estado y sincronización en `DispensersBloc` y `WifiProvisioningPage`.** RF-01, RNF-03
  - Hecho cuando: Al guardar las credenciales desde la app se evita el falso error de guardado y se actualiza de forma inmediata y reactiva el listado de dispositivos mostrando que están registradas en perfecto español.

- [x] **T3. Firmware ESP32 — Implementación de validación HTTP GET al endpoint raíz (`/`) en `WifiService`.** RF-02
  - Hecho cuando: `WifiService` incluye la función para realizar una petición HTTP GET al servidor solicitando `/` y requiriendo un código de estado `200` para aprobar la conectividad.

- [x] **T4. Firmware ESP32 — Integración de la validación HTTP en la máquina de estados (`dispenser_task.cpp`).** RF-02, RNF-01
  - Hecho cuando: El ESP32 comprueba la conexión local WiFi y exige el status 200 HTTP del servidor antes de establecer el estado normal, haciendo rollback a aprovisionamiento BLE si falla.

- [x] **T5. Firmware ESP32 — Implementación de borrado NVS en inicialización por flasheo (`main.cpp` / `wifi_service.cpp`).** RF-03, RNF-02
   - Hecho cuando: El ESP32 detecta el primer arranque tras una nueva carga de código y limpia de forma automática y limpia el almacenamiento interno NVS de credenciales obsoletas.

- [x] **T6. Pruebas — Creación y ejecución de pruebas unitarias y de widgets en Flutter.** RF-01, RNF-03
  - Hecho cuando: Todos los tests en `app/app_movil_pdam/test/` correspondientes al aprovisionamiento y BLoC de dispensadores pasan exitosamente con `flutter test`.

- [x] **T7. Pruebas y Compilación — Verificación de compilación de firmware en PlatformIO.** RF-02, RF-03
  - Hecho cuando: Se ejecuta `pio run` en `DispensadorESP32` y compila al 100% sin errores ni advertencias.

- [x] **T8. Verificación integral, análisis estático y actualización de memoria.** General
  - Hecho cuando: Se ejecuta `flutter analyze`, se verifica el cumplimiento de `docs/constitution.md` y se actualiza `MEMORY.md` con los resultados de la Spec 009.
