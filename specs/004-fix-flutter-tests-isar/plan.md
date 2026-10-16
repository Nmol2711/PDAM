# Plan — Spec 004: Corrección de Pruebas y Entorno de Isar en Flutter

## Archivos y responsabilidades
1. **`app/app_movil_pdam/pubspec.yaml`**: Eliminar la referencia a `assets/icos/` o crear el directorio vacío para resolver la advertencia de activos.
2. **`app/app_movil_pdam/test/` (setUpAll en tests de Isar / IsarService)**: Actualizar `Isar.initializeIsarCore(download: true)` para asegurar que el binario nativo (`libisar.so`) se descargue y configure correctamente en tiempo de prueba.

## Pseudocódigo / Algoritmo de Inicialización
```dart
setUpAll(() async {
  try {
    await Isar.initializeIsarCore(download: true);
  } catch (e) {
    // Fallback or ignore if already initialized
  }
});
```

## Decisiones justificadas
- Usar `Isar.initializeIsarCore(download: true)` en los tests garantiza que el binario nativo requerido para FFI (`libisar.so`) se obtenga automáticamente en el entorno de prueba Linux/CI sin requerir instalación manual de librerías del sistema operativo.
- Limpiar o remover `assets/icos/` en `pubspec.yaml` elimina el error de directorio no encontrado en `flutter test`.

## Estrategia de tests
- Ejecutar `flutter test` en `app/app_movil_pdam/` y verificar que 100% de las pruebas pasen en verde.
