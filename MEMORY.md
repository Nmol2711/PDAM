# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual

* #### API (FastAPI + SQLite)
  * Endpoints implementados y probados: Autenticación, usuarios, mascotas (`pets`), programación de dosificación (`schedules`), registros de actividad (`logs`) y resumen de panel (`dashboard`).
  * Integración del motor de cálculo nutricional (WSAVA 2011) para perros y gatos.
  * Soporte de almacenamiento de archivos multimedia (fotos de mascotas).

* #### APP Móvil (Flutter + BLoC + GoRouter + Isar)
  * Arquitectura Limpia implementada (`core/` y `features/` con capas de datos, dominio y presentación).
  * Soporte Offline-First robusto con Isar: opera sin conexión a internet y realiza fallback automático a la fuente de datos local cuando el servidor no responde o no está disponible.
  * Módulos completos: Autenticación, Dashboard interactivo con gráficos, Gestión de Mascotas, Generación guiada de horarios/porciones y Logs de actividad.
  * Integración de recursos gráficos y logos nativos (Android/iOS) y temas con Material Design 3.

* #### Hardware (ESP32)
  * Código base en Arduino para integración con ServoMotor MG966R, HX711 y celda de carga de 5kg.

## Decisiones (y por qué)
- Uso de Clean Architecture y BLoC en Flutter para garantizar escalabilidad, separación de responsabilidades y testabilidad.
- Implementación de Isar para arquitectura Offline-First para garantizar disponibilidad continua tanto sin conexión a internet como ante fallas o falta de respuesta del servidor.
- Adopción de normas WSAVA 2011 para el cálculo nutricional preciso en el módulo de dosificación.

## Aprendizajes y errores a evitar
- Nunca incrustar credenciales o archivos `.env` en el repositorio (usar siempre `.env-example`).
- Evitar lógica de negocio pesada en las vistas de Flutter; mantenerlas limpias usando BLoC/Cubit y componentes reutilizables.

## Próximos pasos
- Pruebas de integración end-to-end (Hardware - Backend - App Móvil).
- Refinamiento de la sincronización offline avanzada ante reconexión.
