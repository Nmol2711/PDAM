# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
* #### Spec 006 (Interfaz de Dispositivos, Visualización de Dispensadores Vinculados y Gestión de Credenciales WiFi) — **Completado, Robustecido y Verificado con Éxito**
  * Mejora en `BleProvisioningService.scanDevices()`: espera reactiva al estado del adaptador Bluetooth (`FlutterBluePlus.adapterState` con timeout) en lugar de lectura sincrónica inmediata que fallaba cuando el Bluetooth ya estaba encendido.
  * Verificado con `flutter test` (103/103 tests verdes) y `pytest` (54/54 tests verdes).
* #### Spec 005 (Aprovisionamiento WiFi por Bluetooth y Gestión de Dispensadores) — **Completado con Éxito**
  * T1 & T2: Backend implementado y verificado (`pytest` 54/54 verde).
  * T3 & T4: Firmware ESP32 implementado con NVS, máquina de estados, servidor GATT BLE (`PDAM-Config-[MAC]`), apagado automático de BLE al conectar, restricción a 2.4GHz y sin emojis.
  * T6 - T9: Frontend en Flutter (`features/dispensers/`) con Clean Architecture, GoRouter, servicio BLE (`flutter_blue_plus`), vistas con advertencia prominente de redes de 2.4GHz, persistencia Isar (Offline-First) y pruebas unitarias/widgets (103/103 tests verdes).
  * T10: Verificación integral finalizada (54 pytest y 103 flutter test al 100% en verde).

## Decisiones (y por qué)
- Modularización de esquemas Pydantic en `api/app/schemas/dispenser.py` y campo `pending_wifi_reset` en modelo ORM.
- Uso de `flutter_blue_plus` en Flutter por su robustez y mantenimiento activo.
- Advertencia técnica prominente en UI sobre la incompatibilidad del ESP32 con redes de 5GHz.

## Aprendizajes y errores a evitar
- El ESP32 opera estrictamente en 2.4GHz; la app y el firmware deben advertir y restringir acorde a esta limitación de hardware.
- Cumplimiento riguroso de la regla "sin emojis" en código y comentarios.

## Próximos pasos
- Spec 005 totalmente finalizada y probada. Preparado para siguientes requerimientos del sistema.