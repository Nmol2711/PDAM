# Tareas — Spec 004

- [ ] **T1. Corregir referencias a activos inexistentes en `pubspec.yaml`.** RF-02
  - Hecho cuando: `pubspec.yaml` no incluye `assets/icos/` o el directorio existe, y `flutter test` no muestra advertencias de directorios faltantes.
- [ ] **T2. Actualizar inicialización de Isar Core en pruebas (`Isar.initializeIsarCore(download: true)`).** RF-01
  - Hecho cuando: Los archivos de test de datasources Isar descargan/inicializan correctamente el binario nativo en Linux.
- [ ] **T3. Ejecutar `flutter test` y verificar 100% éxito.** RNF-02
  - Hecho cuando: Todos los tests automatizados de Flutter pasan sin errores de `libisar.so`.
