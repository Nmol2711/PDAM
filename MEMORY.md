# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
* **Spec 011 cerrada (T1–T14).** Motor WSAVA único con validación estricta, endpoint `POST /nutrition/calculate`, espejo Dart con fixture de contrato, `NutritionCubit` + calculadora, y módulo unificado `features/dispenser/` (BLE/WiFi + QR/MAC).
* **Specs 001–010 cerradas.** Spec 004 `Estado: implementada` (Isar T1–T3) y Spec 005 `Estado: implementada` (T5 `pio test` en verde; hardware real sin probar).
* **T14:** Specs 004/005 sincronizadas; rutas obsoletas (`features/dispensers/`, `arduino/sketch_jul3a/`, `ble_service.cpp`) corregidas en `spec.md`/`plan.md` de 005. Informe de estado actualizado.

## Decisiones clave (Spec 011)
* Fórmula compartida: `RER = 70·BW^0.75`, `MER = RER·factor`, snacks ≤10% MER (alerta + recálculo, sin bloqueo), `Final = max(0, MER − snacks)`, gramos = kcal / (kcal/kg ÷ 1000).
* Factores MER base: canino adulto entero 1.8 / castrado 1.6 / crecimiento 2.0; felino 1.4 / 1.2 / 2.5. Ajustes: actividad low 0.9 / medium 1.0 / high 1.2; BCS ≤3 1.2, 4–6 1.0, ≥7 0.8; MCS normal-mild 1.0, moderate 0.95, marked 0.9. Variabilidad ±30% perro, ±50% gato.
* Dominio Dart devuelve `Either<Failures, NutritionResult>`; `NutritionCubit` por cálculo síncrono.
* Un solo módulo `features/dispenser/`; `features/dispensers/` eliminado (tests movidos).
* Contrato compartido: `specs/011.../fixtures/nutrition_contract_cases.json` consumido por `api/tests/test_nutrition_contract.py` y `app/app_movil_pdam/test/features/nutrition/nutrition_contract_test.dart`.
* T11: `auto_generar_horarios_wsava` delega en `nutrition_service`; `pet_detail_view` usa `pet_wsava_limit.dart`; especie `otros` → sin límite (RF-2).
* Suite nativa PlatformIO `pio test -e native` para formato MAC, nombre BLE y credenciales.

## Validación (2026-10-22, cierre Spec 011)
* `pytest`: 240 passed, 113 subtests. `flutter test`: 256 passed. `pio test -e native`: 5/5. `pio run`: SUCCESS. `flutter analyze`: 0 errores (warnings/infos preexistentes).

## Pendientes honestos
* Probar en hardware: WiFi real, NVS y GATT BLE del ESP32.
* Warnings/infos preexistentes de `flutter analyze`; no se introdujeron nuevos.
* Cambios de Spec 011 y BLE de Spec 010 sin commitear (working tree amplio).
* `guided_schedule_form_view.dart` sigue usando `ScheduleBloc` + endpoint de auto-horarios, ya respaldado por el motor único.
* Deuda: mismatch URL ESP32↔API (`config.h` usa `.../dispenserscheck-taks/`; ruta real `/dispensers/check-taks/{mac}`).

## Reglas y deuda vigentes
* Offline-First: logout **no** borra Isar; nunca `clearAllData()`.
* MAC normalizada en servidor (`mac_normalized`), HTTP 409/400 con `detail={code,message}`.
* Registro/cambio de MAC/desactivación/eliminación exigen conexión; el resto opera offline.
* Avisos con `AppNoticeDialog` (MD3), nunca SnackBars rojos.
