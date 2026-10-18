# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
* #### Spec 005 (Aprovisionamiento WiFi por Bluetooth) — **En Progreso (Tareas T1 y T2 completadas)**
  * T1: Definidos modelos y esquemas Pydantic para dispensadores y reseteo WiFi (`api/app/schemas/dispenser.py`).
  * T2: Implementado servicio `reset_wifi_credentials` y endpoint `/dispensers/{id}/reset-wifi` en FastAPI (RF-09).
  * Todos los tests de backend (`pytest`) pasan exitosamente (54/54).

## Decisiones (y por qué)
- Modularización de esquemas Pydantic de dispensadores en `api/app/schemas/dispenser.py` manteniendo compatibilidad con `schemas.py`.
- Inclusión del campo `pending_wifi_reset` en el modelo `Dispenser` con migración automática SQLite en `database.py`.
- Cobertura de pruebas unitarias y de integración para el reseteo de WiFi (`TestDispenserWiFiReset`).

## Aprendizajes y errores a evitar
- Nunca vaciar bases de datos locales en operaciones de cierre de sesión ordinarias.
- Las migraciones en SQLite se hacen en el listener `connect`.
- `scrollable: true` en `AlertDialog` y constraints explícitas (`BoxConstraints`) para evitar overflow con fuentes grandes.

## Próximos pasos
- Continuar con la tarea T3 (Hardware ESP32: gestión WiFi y NVS).