# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
* #### Spec 009 (Corrección y Validación de Credenciales WiFi y Sincronización en App y ESP32) — **Completado y Verificado**
  * T1 & T2 implementadas: Integración de `flutter_secure_storage` en repositorio de dispensadores y corrección de estado/sincronización en app móvil (RF-01, RNF-02, RNF-03).
  * T3 & T4 implementadas: Validación de conectividad HTTP al endpoint raíz `/` exigiendo status `200` en el ESP32, con integración en la máquina de estados y rollback a BLE (RF-02).
  * T5 implementada: Limpieza automática de almacenamiento NVS de credenciales obsoletas al detectar nuevo flasheo en el ESP32 (RF-03).
  * T6, T7 & T8 ejecutadas: 108/108 pruebas unitarias y de widgets de Flutter aprobadas (`flutter test`), compilación limpia de firmware en PlatformIO (`pio run`), análisis estático sin errores y auditoría global aprobada por @reviewer.
