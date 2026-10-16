# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
* #### Compilación APK Release y Pruebas Isar en Flutter — **Completado con Éxito**
  * Solucionado el error de compilación `verifyReleaseResources` (`lStar not found`) en `:isar_flutter_libs` actualizando `compileSdk = 36` en `app/build.gradle.kts` y configurando un hook `afterEvaluate` en `build.gradle.kts` para forzar `compileSdk = 36` en todos los submódulos.
  * APK compilado exitosamente: `build/app/outputs/flutter-apk/app-release.apk (81.5MB)`.
  * Pruebas completas: 52 pytest y 98 flutter test en verde (100%).

## Decisiones (y por qué)
- Forzar `compileSdk = 36` a nivel global y de submódulos para resolver referencias a atributos nuevos (`lStar`) en dependencias nativas como Isar.
- Usar `Isar.initializeIsarCore(download: true)` en tests.

## Aprendizajes y errores a evitar
- Nunca vaciar bases de datos locales en operaciones de cierre de sesión ordinarias.
- Las migraciones en SQLite se hacen en el listener `connect`. Las críticas (`mac_normalized`) propagan `RuntimeError`.
- `scrollable: true` en `AlertDialog` y constraints explícitas (`BoxConstraints`) para evitar overflow con fuentes grandes.

## Próximos pasos
- Spec 003 totalmente completada. Preparado para siguientes requerimientos del sistema.