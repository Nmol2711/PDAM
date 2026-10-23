# Tareas — Spec 004

- [x] **T1. Corregir referencias a activos inexistentes en `pubspec.yaml`.** RF-02
  - Hecho cuando: `pubspec.yaml` no incluye `assets/icos/` o el directorio existe, y `flutter test` no muestra advertencias de directorios faltantes.

- [x] **T2. Actualizar inicialización de Isar Core en pruebas (`Isar.initializeIsarCore(download: true)`).** RF-01
  - Hecho cuando: Los archivos de test de datasources Isar descargan/inicializan correctamente el binario nativo en Linux.

- [x] **T3. Ejecutar `flutter test` y verificar 100% éxito.** RNF-02
  - Hecho cuando: Todos los tests automatizados de Flutter pasan sin errores de `libisar.so`.

## Verificación de cierre (2026-10-22)

- **T1:** `app/app_movil_pdam/pubspec.yaml` declara únicamente `assets/` y `assets/imgs/`; ambos directorios existen. No hay referencias a `assets/icos/` ni advertencias de activos faltantes en `flutter test`.
- **T2:** Los cinco tests de datasources Isar invocan `Isar.initializeIsarCore(download: true)` en `setUpAll`.
- **T3:** `flutter test` completo ejecutado en verde: **232 tests passed**, incluidos los 31 tests de persistencia local/Isar (`test/core/offline/` y `test/features/*/data/datasource/local/`), sin errores de `libisar.so`.
