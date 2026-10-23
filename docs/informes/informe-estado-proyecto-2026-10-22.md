# Informe — Estado Actual del Proyecto PDAM

**Fecha:** 2026-10-22
**Alcance:** Revisión integral del estado del proyecto (backend, frontend, hardware, especificaciones y control de versiones) con fines de diagnóstico. No se modifica código.
**Método:** Lectura del código fuente, de las 11 specs en `specs/`, de la constitución (`docs/constitution.md`), de los informes previos (`docs/informes/`) y del historial de git.

> Este documento describe el estado verificado del proyecto. No corrige ni propone cambios; identifica deuda técnica y hallazgos para revisión posterior.

---

## 1. Qué es el proyecto

**PDAM** (Prototipo dispensador de comida para mascotas) automatiza la alimentación de perros y gatos. El sistema se compone de tres capas:

1. **Backend** — FastAPI + SQLite. Lógica de negocio, persistencia de usuarios/mascotas/horarios/dispensadores y comunicación con el hardware.
2. **Frontend** — Flutter + Dart con Clean Architecture, BLoC, GoRouter e Isar, bajo arquitectura Offline-First (la app opera localmente cuando no hay conexión o el servidor no responde).
3. **Hardware** — ESP32 (PlatformIO). ServoMotor MG966R, aprovisionamiento WiFi por BLE, cliente HTTP hacia la API.

La constitución (`docs/constitution.md`) fija 6 principios innegociables: stack tecnológico, trazabilidad Spec↔Código (Modelo en V), Clean Architecture, política de tests obligatorios, protección de datos y español en UI/documentación.

---

## 2. Estado del Backend (FastAPI)

### 2.1 Endpoints registrados (`api/app/main.py`)

| Prefijo | Router | Propósito |
|---|---|---|
| `/users` | `users` | Gestión de usuarios |
| `/auth` | `auth` | Autenticación |
| `/pets` | `pets` | Mascotas |
| `/schedules` | `schedules` | Horarios de alimentación |
| `/logs` | `logs` | Registros de actividad |
| `/dispensers` | `dispenser` | Dispensadores (alta, consulta, refill, reset-wifi, check-taks) |
| `/dashboard` | `dashboard` | Resumen para el panel |
| `/sync` | `sync` | Sincronización bidireccional |

Además, `/` responde `{"status": ...}` y sirve el validador de conectividad HTTP que usa el ESP32. Un `BackgroundScheduler` (APScheduler) ejecuta cada minuto `check_and_activate_scheduled_feedings`.

### 2.2 Modelos (`api/app/models/models.py`)

`User`, `Pet`, `Dispenser`, `Schedule`, `ActivityLog`. Destacan:
- `Dispenser.mac_normalized` (columna única + índice) para unicidad global de la MAC independiente del formato (Spec 003).
- `Dispenser.current_food_grams` (default 5000 g), `pending_dispensing`, `pending_wifi_reset` (Specs 007/009).

### 2.3 Servicios

- `mac_service.py` — normalización/validación pura de MAC (`AABBCCDDEEFF`), códigos de error estables (`mac_already_registered`, `mac_in_use`, `mac_invalid_format`, `pet_already_has_dispenser`).
- `dispenser_service.py` — alta/modificación con unicidad por forma normalizada, `check_pending_task` (descuenta stock y acota a 0), `refill_dispenser` (convierte kg→g, límite 5000 g), `reset_wifi_credentials`.
- `schedule_service.py` — CRUD de horarios + `auto_generar_horarios_wsava` (motor de dosificación nutricional).
- `sync_service.py`, `pet_service.py`, `logs_service.py`, `user_service.py`.

### 2.4 Tests

`api/tests/` contiene 12 archivos (`test_api_basic`, `test_auth`, `test_dispenser_food`, `test_dispenser_mac`, `test_nutrition`, `test_nutrition_schemas`, `test_nutrition_endpoint`, `test_nutrition_contract`, `test_protected_routes`, `test_schedule_service`, `test_sync`, `test_users`). El módulo nutricional (WSAVA) **sí tiene tests** de esquemas, motor, endpoint y contrato compartido.

> **Actualización 2026-10-22 (tras Spec 011):** la afirmación original de que WSAVA no tenía tests quedó obsoleta; la suite backend actual es de **240 passed + 113 subtests**.

---

## 3. Estado del Frontend (Flutter)

### 3.1 Estructura y features

- `core/` — constantes, DI (GetIt), errores, red (Dio), offline (Isar + `SyncService` + `sync_conflict_resolver`), presentación (widgets globales), router (GoRouter), servicios y tema (Material 3, claro/oscuro).
- `features/` — `auth`, `dashboard`, `dispenser`, `home`, `logs`, `nutrition`, `pets`.

**Actualización 2026-10-22 (tras Spec 011):** ya **no existe** `features/dispensers/`; se unificó en `features/dispenser/`, que integra el flujo BLE/WiFi (`BleProvisioningService`) y la asociación por QR/MAC con un único `DispenserBloc`.

### 3.2 Offline-First

`IsarService` (esquemas `LocalDispenser`, `LocalPet`, `LocalSchedule`, `LocalLog`), `SyncService` (sincronización Last-Write-Wins con umbral de 5 min y prioridad al servidor), `flutter_secure_storage` para credenciales. El logout **no** borra Isar (lección documentada en MEMORY).

### 3.3 Tests

Según `MEMORY.md`, la suite llega a **256/256 tests en verde** tras la Spec 011. Históricamente Spec 003 llegó a 98, y Specs 009/010/011 ampliaron la cobertura (BLoC de dispensadores, mapper de avisos, `AppNoticeDialog`, `mac_normalizer`, nutrición y contrato backend↔frontend).

---

## 4. Estado del Hardware (ESP32 / PlatformIO)

Migrado de un sketch Arduino único a estructura modular PlatformIO (`DispensadorESP32/src/`): `config/config.h`, `drivers/servo_driver`, `services/wifi_service` + `api_service`, `tasks/dispenser_task`, `main.cpp`.

- Máquina de estados: `STATE_CHECK_NVS` → `STATE_CONNECT_WIFI` → `STATE_BLE_PROVISIONING` → `STATE_NORMAL`.
- `wifi_service.cpp`: borrado NVS por detección de nuevo build (`__DATE__ __TIME__`), validación de conectividad HTTP al endpoint raíz exigiendo status 200 (Spec 009), servidor GATT BLE `PDAM-Config-<MAC>`.
- `api_service.cpp`: sondeo HTTP, parseo JSON (`serve`, `reset_wifi`), dispensación vía servomotor.
- `platformio.ini`: `espressif32` + Arduino framework; dependencias `ESP32Servo`, `ArduinoJson`.

---

## 5. Estado de las Especificaciones

| Spec | Tema | Estado (spec.md) | Tareas |
|---|---|---|---|
| 001 | Sincronización offline + gestión de sesión | — | Todas [x] |
| 002 | Corrección persistencia offline Isar | borrador | Todas [x] |
| 003 | MAC única por dispensador | implementada | Todas [x] (bloqueo T8 resuelto y documentado) |
| 004 | Fix tests Isar + activos | implementada | Todas [x] |
| 005 | Aprovisionamiento WiFi/BLE | implementada | Todas [x] (T5 `pio test` en verde; hardware real pendiente) |
| 006 | UI Dispositivos + credenciales WiFi | borrador | Todas [x] |
| 007 | Estimación de alimento sin sensor | borrador | Todas [x] (veredicto RF-1: cambios necesarios) |
| 008 | Migración Arduino→PlatformIO | implementada | Todas [x] |
| 009 | Corrección credenciales WiFi | borrador | Todas [x] |
| 010 | Corrección crítica aprovisionamiento | borrador | Todas [x] (+ T7 cooldown BLE reciente) |

Notas de estado:
- **Spec 004**: `Estado: implementada`; T1–T3 marcadas como `[x]` y verificadas en la auditoría de la Spec 011 (T8).
- **Spec 005**: `Estado: implementada`; T5 ya no está pendiente (`pio test -e native` 5/5 y `pio run` SUCCESS). Limitación: WiFi/NVS/GATT reales no se probaron por falta de hardware.
- **Spec 007**: el veredicto del reviewer marcó RF-1 (conversión kg→g en backend) como parcialmente cumplida.

> **Actualización 2026-10-22 (tras Spec 011):** las filas y notas originales de las Specs 004 y 005 quedaron corregidas; ambas declaran `Estado: implementada` en su `spec.md`.

---

## 6. Estado de Git

- Rama: `main` (sincronizada con `origin/main`).
- Commits recientes destacables: `ef3c164` (spec 010), `497e961` (spec 009), `1c9c984` (migración PlatformIO), `08c6e16` (reset WiFi + filtrado).
- **Cambios sin commitear** (working tree modificado):
  - `ble_provisioning_service.dart` — `scanCooldown` 800→1200 ms, polling de `lastScanResults` (Timer 500 ms), `androidUsesFineLocation: true`, reintento de `startScan` con throw explícito de error.
  - `dispensers_bloc.dart` — reset de adaptador con delay 500→1000 ms.
  - `dispersers_bloc_test.dart` — ajuste del delay de test (600→1300 ms).
  - `specs/010/.../tasks.md` — T7 añadida y marcada.
  - `.opencode/agents/implementer.md` y `reviewer.md`.
- Archivo no rastreado: `app/app_movil_pdam/devtools_options.yaml`.

---

## 7. Hallazgos y deuda técnica

### 7.1 Críticos
1. **Mismatch URL ESP32 ↔ API.** `config/config.h` define `BASE_URL = "http://192.168.1.58:8000/dispenserscheck-taks/"`, pero la ruta real es `/dispensers/check-taks/{address_mac}` (falta el separador `/` entre `dispensers` y `check-taks`, además del typo `taks`). Riesgo de que el hardware no encuentre el endpoint en producción.
2. **Motor WSAVA sin tests** (`auto_generar_horarios_wsava`). El módulo nutricional, pese a ser central, no tiene cobertura en `api/tests/`.
3. **Límites del motor sin validar.** `food_kcal_per_kg = 0` o `meals_per_day = 0` provocan división por cero; `meals_per_day > 6` genera 6 horarios pero divide los gramos entre más comidas (subalimentación silenciosa). `bcs`/`mcs`/`activity_level` sin enum ni cota.

> **Actualización 2026-10-22 (tras Spec 011):** los hallazgos 2 y 3 quedaron cubiertos con esquemas Pydantic de whitelist y rangos estrictos, motor WSAVA con tests propios, contrato compartido y endpoint `POST /nutrition/calculate`. El hallazgo 1 (mismatch de URL del ESP32) sigue vigente como deuda de hardware.

### 7.2 Medios
4. **Doble módulo de dispensador** (`features/dispenser` vs `features/dispensers`) con lógica y modelos solapados; riesgo de divergencia y mantenimiento duplicado.
5. **Fórmula de dosificación duplicada** backend vs app (`pet_detail_view.dart`), con factores y densidad calórica distintos (documentado en `informe-motor-dosificacion-wsava-2026-10-05.md`).
6. **Spec 004 desincronizada**: código corregido pero tareas sin marcar.
7. **Spec 005 T5 pendiente**: sin pruebas de firmware (`pio test`).

> **Actualización 2026-10-22 (tras Spec 011):** los hallazgos 4, 5, 6 y 7 quedaron resueltos. El módulo es único (`features/dispenser/`), la fórmula está unificada en el motor backend y su espejo Dart con fixture de contrato (`nutrition_contract_cases.json`), y las Specs 004/005 están implementadas (T5 con `pio test` en verde y limitación de hardware documentada).

### 7.3 Menores
8. Typo recurrente `taks`/`check-taks` en endpoints y funciones (`dispenser.py`, `config.h`).
9. Artefactos de BD en el repo: `api/app/db/pdam.db` y `test.db` (raíz).
10. `README.md` describe hardware como "Arduino" (desactualizado tras Spec 008) y no menciona BLE ni Isar.

---

## 8. Recomendaciones

1. Alinear la URL del ESP32 con la ruta real de la API y corregir el typo `taks` → `tasks`.
2. Añadir tests del motor WSAVA y validar sus entradas (evitar división por cero y acotar `meals_per_day`/`bcs`).
3. Decidir el destino de los dos módulos de dispensador (consolidar o delimitar responsabilidades).
4. Marcar/cerrar Spec 004 y completar T5 de Spec 005 (tests de firmware).
5. Commitear los cambios BLE pendientes (cooldown/reset de adaptador) una vez validados.

> **Actualización 2026-10-22 (tras Spec 011):** las recomendaciones 2, 3 y 4 ya se ejecutaron (tests WSAVA, módulo de dispensador unificado y Specs 004/005 cerradas). Siguen pendientes la validación en hardware (WiFi/NVS/GATT), el mismatch de URL del ESP32 y el commit de los cambios acumulados.

---

## 9. Fuentes

- Backend: `api/app/main.py`, `api/app/models/models.py`, `api/app/services/*.py`, `api/app/api/endpoints/*.py`, `api/tests/`.
- Frontend: `app/app_movil_pdam/lib/**`, `app/app_movil_pdam/pubspec.yaml`.
- Hardware: `DispensadorESP32/src/**`, `DispensadorESP32/platformio.ini`.
- Especificaciones: `specs/001-011/` (`spec.md`, `plan.md`, `tasks.md`).
- Normativa: `docs/constitution.md`, `AGENTS.md`, `MEMORY.md`.
- Informes previos: `docs/informes/informe-motor-dosificacion-wsava-2026-10-05.md`, `docs/informes/REVIEWER_VERDICT_007.md`.
- Git: `git log`, `git status`, `git diff`.
