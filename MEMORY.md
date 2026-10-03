# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
* #### Sincronización Offline Avanzada (`specs/001-arquitecture-offline`) — **Completado al 100% (Tareas 1 a 9)**
  * Tareas 1-3 completadas: Esquemas Pydantic, endpoint `/sync/` y suite completa de pruebas unitarias en backend (FastAPI).
  * Tareas 4-6 completadas: Almacenamiento seguro cifrado con `flutter_secure_storage`, login con timeout de 10s y fallback offline, y adaptación de `AuthBloc` con restricciones de red (RF-01 a RF-03).
  * Tareas 7-9 completadas: Función pura `resolveConflict`, servicio de sincronización en segundo plano `SyncService` con Isar y suite completa de pruebas unitarias en Flutter (`flutter test`) superadas al 100% (RF-02, RF-04, RF-05, RNF-03).

* #### API (FastAPI + SQLite)
  * Endpoints implementados y probados: Autenticación, usuarios, mascotas (`pets`), programación de dosificación (`schedules`), registros de actividad (`logs`) y resumen de panel (`dashboard`).
  * Integración del motor de cálculo nutricional (WSAVA 2011) para perros y gatos.
  * Soporte de almacenamiento de archivos multimedia (fotos de mascotas).

* #### APP Móvil (Flutter + BLoC + GoRouter + Isar)
  * Arquitectura Limpia implementada (`core/` y `features/` con capas de datos, dominio y presentación).
  * Soporte Offline-First robusto con Isar: opera sin conexión a internet y realiza fallback automático a la fuente de datos local cuando el servidor no responde o no está disponible.
  * Módulos completos: Autenticación, Dashboard interactivo con gráficos, Gestión de Mascotas, Generación guiada de horarios/porciones y Logs de actividad.
  * Navegación responsiva: barra de navegación inferior clásica (`BottomNavigationBar`) para dispositivos móviles (`< 600px`) y menú lateral desplegable (`NavigationDrawer`) con iconos a la izquierda, texto en la misma fila y `AppBar` con título dinámico para tablets/horizontal (`>= 600px`).
  * Integración de recursos gráficos y logos nativos (Android/iOS) y temas con Material Design 3.
  * **Actualización Spec 001:** Revisión QA completada y especificación `specs/001-arquitecture-offline/spec.md` refinada (timeout de 10s para offline, control de *clock drift* de 5 minutos, uso estricto de `flutter_secure_storage` e `Isar`).

* #### Hardware (ESP32)
  * Código base en Arduino para integración con ServoMotor MG966R, HX711 y celda de carga de 5kg.

## Decisiones (y por qué)
- Creación de la Constitución de PDAM (`docs/constitution.md`) bajo el Modelo en V para estructurar principios innegociables (stack, spec-código, separación lógica-interfaz, tests, seguridad de datos e idioma).
- Uso de Clean Architecture y BLoC en Flutter para garantizar escalabilidad, separación de responsabilidades y testabilidad.
- Implementación de Isar para arquitectura Offline-First para garantizar disponibilidad continua tanto sin conexión a internet como ante fallas o falta de respuesta del servidor.
- Adopción de normas WSAVA 2011 para el cálculo nutricional preciso en el módulo de dosificación.
- Uso de `LayoutBuilder` con breakpoint de 600px para mantener `BottomNavigationBar` en móvil y `NavigationDrawer` en pantallas grandes/tablets.
- Definición de parámetros precisos en `specs/001-arquitecture-offline/spec.md` (timeout 10s, umbral clock drift 5 min, cifrado con `flutter_secure_storage`).
- Actualización de `AGENTS.md` con los comandos de ejecución y pruebas para Backend, Frontend y Hardware.

## Aprendizajes y errores a evitar
- Nunca incrustar credenciales o archivos `.env` en el repositorio (usar siempre `.env-example`).
- Evitar lógica de negocio pesada en las vistas de Flutter; mantenerlas limpias usando BLoC/Cubit y componentes reutilizables.
- Validar rigurosamente especificaciones técnicas mediante auditoría QA antes de iniciar implementaciones complejas.

## Próximos pasos
- Creación de las tareas detalladas `specs/001-arquitecture-offline/tasks.md` ordenadas por dependencia y criterios de finalización.
- Ejecución de las tareas de implementación de la sincronización offline avanzada y autenticación sin conexión.
- Pruebas de integración end-to-end (Hardware - Backend - App Móvil).
