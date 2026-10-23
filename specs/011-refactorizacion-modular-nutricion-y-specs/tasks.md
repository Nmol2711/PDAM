# Tareas 011 — Refactorización Modular, Motor Nutricional WSAVA y Sincronización de Especificaciones

- [x] **T1. Implementación de esquemas Pydantic con validación estricta de entradas y rangos en el Backend.** RF-1, RF-2
  - Hecho cuando: Los esquemas Pydantic en FastAPI validan correctamente BW > 0, densidad calórica > 0, comidas entre 1 y 6, BCS de 1 a 9, MCS, actividad, estatus reproductivo y etapa de vida, rechazando valores inválidos con errores descriptivos y pasando las pruebas unitarias correspondientes.

- [x] **T2. Implementación del motor de cálculo nutricional WSAVA en el servicio Python con funciones puras y manejo de snacks.** RF-3
  - Hecho cuando: Se implementan las funciones puras para RER, MER con factores correctores, rango de variabilidad (±30% / ±50%), evaluación del límite de snacks al 10% (solo alerta visual + recálculo de ración principal, sin bloquear) y ración diaria exclusivamente ponderal en gramos, cubiertas con tests unitarios en verde.

- [x] **T3. Implementación del endpoint REST de dosificación en FastAPI y suite de pruebas unitarias backend.** RF-4, Criterios de finalización
  - Hecho cuando: El endpoint de FastAPI procesa peticiones válidas e inválidas devolviendo los resultados del motor, y `pytest` ejecuta con éxito el 100% de los tests de nutrición sin errores.

- [x] **T4. Implementación de entidades de dominio y casos de uso en Flutter con idéntica lógica WSAVA.** RF-3, RF-4
  - Hecho cuando: La capa de dominio en Flutter replica exactamente la lógica matemática y de validación del backend mediante clases y casos de uso puros y testeables.

- [x] **T5. Implementación del BLoC y componentes visuales limpios para la calculadora nutricional en Flutter.** RF-4, RNF-2
  - Hecho cuando: Se desarrolla el BLoC de nutrición y las pantallas/widgets limpios (sin lógica espagueti ni `setState` en vistas principales) que reflejan los resultados de dosificación y alertas de snacks.

- [x] **T6. Unificación del módulo de dispensadores en Flutter.** RF-5
  - Hecho cuando: Se consolida en Flutter un único flujo de dispensadores que integra aprovisionamiento BLE/WiFi y asociación por QR o dirección MAC, permitiendo asociar, activar, desactivar y borrar dispositivos sin duplicidades.

- [x] **T7. Pruebas unitarias y de widgets en Flutter para nutrición y dispensadores.** Criterios de finalización
  - Hecho cuando: La suite de `flutter test` ejecuta y aprueba todas las pruebas unitarias y de widgets para los módulos de nutrición y dispensadores unificados.

- [x] **T8. Verificación formal y cierre de tareas de persistencia local (Spec 004) y pruebas de sistema (Spec 005).** Criterios de finalización
  - Hecho cuando: Se auditan y documentan formalmente las tareas de persistencia local con Isar y las pruebas de sistema de las especificaciones 004 y 005.

- [x] **T9. Análisis estático y validación integral del sistema.** Constitución, Criterios de finalización
  - Hecho cuando: Se ejecuta `flutter analyze` sin errores de sintaxis, se comprueba que todos los tests de backend (`pytest`) y frontend (`flutter test`) pasan al 100%, y se verifica el cumplimiento constitucional.

- [x] **T10. Actualización de MEMORY.md y resumen final.** Memoria, Criterios de finalización
  - Hecho cuando: Se actualiza `MEMORY.md` con el estado actual, decisiones tomadas y conclusiones, manteniendo la documentación breve y alineada.

## Tareas de corrección (ronda posterior a auditoría)

- [x] **T11. Unificar las fórmulas divergentes en el motor único.** RF-3, RF-4, RNF-4
  - **Descripción:** `schedule_service.auto_generar_horarios_wsava` delega en `nutrition_service.calculate_nutrition` manteniendo intacto su contrato externo (request, respuesta de horarios, advertencias y agua). `pet_detail_view.dart` elimina su fórmula embebida y usa el motor/caso de uso de dominio Dart. Añadir tests de regresión en `api/tests/` y `app/app_movil_pdam/test/` que fijen los valores esperados con la lógica unificada.
  - **Validación Constitución:** Principio 2 (trazabilidad del requisito a la prueba) y principio 3 (separación lógica-interfaz: cero fórmulas en la vista).
  - **Hecho cuando:** No queda ninguna fórmula WSAVA duplicada en backend ni en Flutter; los tests de regresión de `auto_generar_horarios_wsava` y de `pet_detail_view` pasan en verde junto con la suite completa.
  - **Nota de corrección (2026-10-22):** tras revisión se alineó la app con RF-2: `speciesForNutrition` devuelve `null` para `TypePest.otros`, `petWsavaDailyLimitGrams` no produce límite y `pet_detail_view` no muestra avisos WSAVA en ese caso. El backend de auto-horarios canoniza `mcs` y `activity_level` reutilizando las whitelists de `nutrition_schemas.py`. Se añadieron pruebas de regresión del servicio y una prueba de widget real de `pet_detail_view` que verifica el límite del helper para canino y la ausencia de límite para `otros`.

- [x] **T12. Punto de entrada visible a la calculadora nutricional.** RF-6, RNF-2
  - **Descripción:** Añadir un botón/acción visible (dashboard o navegación principal) que navegue mediante GoRouter a la ruta existente `nutrition_calculator`, usando la paleta y temas globales y textos en español.
  - **Validación Constitución:** Principio 3 (la vista solo presenta y navega, sin lógica) y principio 6 (textos visibles en español).
  - **Hecho cuando:** Un usuario puede llegar a la calculadora desde la navegación sin conocer la ruta, y una prueba de widget verifica que el acceso existe y navega a `NutritionCalculatorView`.

- [x] **T13. Prueba de contrato compartida backend↔frontend.** RF-4
  - **Descripción:** Crear el fixture `specs/011-refactorizacion-modular-nutricion-y-specs/fixtures/nutrition_contract_cases.json` con casos válidos, límites y valores esperados (RER, MER, variabilidad, límite de snacks, alerta, kcal finales y gramos). Consumirlo desde `api/tests/test_nutrition_contract.py` y `app/app_movil_pdam/test/features/nutrition/nutrition_contract_test.dart` con la misma tolerancia decimal.
  - **Validación Constitución:** Principio 2 (validación requisito↔prueba) y principio 4 (cobertura obligatoria en API y app).
  - **Hecho cuando:** `pytest` y `flutter test` ejecutan el mismo fixture y ambos pasan; si se altera una fórmula o tabla en un solo lado, al menos una de las dos suites falla.

- [x] **T14. Sincronización documental de las Specs 004 y 005.** Criterios de finalización
  - **Descripción:** Marcar `specs/004-fix-flutter-tests-isar/spec.md` y `specs/005-wifi-ble-provisioning/spec.md` como `Estado: implementada`, y corregir las rutas obsoletas de la Spec 005 (`lib/features/dispensers/` → `lib/features/dispenser/`, `arduino/sketch_jul3a/` → `DispensadorESP32/`).
  - **Validación Constitución:** Principio 2 (trazabilidad estricta) y principio 6 (documentación coherente en español).
  - **Hecho cuando:** Ambas specs declaran `Estado: implementada` y no queda ninguna referencia a rutas de código inexistentes en la Spec 005.

## Nota de cierre T8 (2026-10-22)

### Auditoría Spec 004 — Persistencia local con Isar
- **T1 verificado:** `app/app_movil_pdam/pubspec.yaml` declara solo `assets/` y `assets/imgs/`; ambos directorios existen. No hay referencias a `assets/icos/` ni advertencias de activos faltantes durante `flutter test`.
- **T2 verificado:** los cinco tests de datasources Isar invocan `Isar.initializeIsarCore(download: true)` en `setUpAll`.
- **T3 verificado:** `flutter test` completo en verde (**232/232**), incluido el subconjunto de persistencia local/Isar y offline (**31/31**), sin errores de `libisar.so`.
- Las tareas T1, T2 y T3 de `specs/004-fix-flutter-tests-isar/tasks.md` quedaron marcadas como `[x]`.

### Auditoría Spec 005 — Pruebas de sistema de firmware ESP32
- Se configuró `[env:native]` (`platform = native`) en `DispensadorESP32/platformio.ini` y la suite `DispensadorESP32/test/test_provisioning_utils/`.
- `pio test -e native`: **5/5 pruebas en verde** sobre lógica pura extraída de los servicios WiFi/BLE (formato de MAC, nombre BLE `PDAM-Config-<MAC>` y validación de credenciales completas).
- `pio run`: **SUCCESS**, compilación del firmware ESP32 sin errores.
- **Limitación documentada:** al no haber hardware conectado no se ejecutaron pruebas de conexión WiFi real, lectura/escritura de NVS ni servidor GATT BLE. La suite nativa se ignora en `esp32dev` mediante `test_ignore`; las pruebas que dependen del dispositivo físico quedan pendientes de validación en banco.
- Se corrigieron las referencias obsoletas a `arduino/sketch_jul3a/` en las tareas T3/T4 y en `plan.md` de la Spec 005, apuntando al firmware activo `DispensadorESP32/src/services/wifi_service.cpp` y `dispenser_task.cpp` según la migración de la Spec 008.
- La tarea T5 de `specs/005-wifi-ble-provisioning/tasks.md` quedó marcada como `[x]` porque `pio test` se ejecuta realmente en verde y el firmware compila; su nota de cierre explicita la limitación de hardware.

## Nota de cierre T9 (2026-10-22)

### Validación integral
- **Backend:** `cd api && pytest` → **221 passed, 109 subtests passed, 0 fallos**. Se corrigió el test desactualizado `test_check_pending_task_discounts_food_automatically` declarando `pending_wifi_reset = False` en el mock; un `MagicMock` devuelve un valor verdadero para atributos no definidos y el servicio (Spec 005) consulta esa bandera antes de servir. El servicio no se modificó porque su lógica es correcta y la columna del modelo tiene `default=False`.
- **Frontend:** `flutter test` → **232/232 tests passed** (suite completa, sin fallos por timing).
- **Análisis estático:** `flutter analyze` → **0 errores**; se mantienen warnings/infos preexistentes (imports sin uso, `withOpacity` y `value` deprecados) sin introducir nuevos.
- **Firmware:** `pio test -e native` → **5/5 PASSED**; `pio run` → **SUCCESS** (RAM 19.7%, Flash 63.3%).
- **Cumplimiento constitucional:** stack respetado (FastAPI/SQLite, Flutter/BLoC/GoRouter/Isar, ESP32), trazabilidad RF↔pruebas verificada en las suites nutrición/dispensadores, separación lógica-interfaz mantenida (`NutritionCubit` + vista sin `setState`), datos sensibles fuera del código y textos visibles en español.
