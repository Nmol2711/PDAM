# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
* #### Spec 008 (Migración Arduino PlatformIO ESP32) — **Completado y Verificado**
  * Migración exitosa del sketch monolítico a estructura modular PlatformIO (`config`, `drivers`, `services`, `tasks`, `main.cpp`).
  * Compilación exitosa en PlatformIO (`pio run`) con partición `huge_app.csv`.
  * Código original de Arduino preservado intacto en `arduino/sketch_jul3a/sketch_jul3a.ino` como respaldo.

## Decisiones (y por qué)
* Uso de Isar y arquitectura Offline-First.
* Estructuración modular en PlatformIO para ESP32 desacoplando config, drivers y services.
* Validación matemática estricta de 5,000 g (5 kg) en reabastecimientos.

## Aprendizajes y errores a evitar
* Ejecutar build_runner al modificar modelos Isar.
* Mantener textos en español y diseño Material 3.

## Próximos pasos
* Ejecución y validación de la tarea T5 (spec 008).
