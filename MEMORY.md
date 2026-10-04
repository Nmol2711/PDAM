# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
* #### Corrección y Robustecimiento de Persistencia Offline (`specs/002-offline-data-persistence-fix`) — **Completado con Correcciones Críticas (Pendiente de Validación de Usuario)**
  * Tareas 1 a 13 implementadas y validadas con 43/43 tests unitarios superados en `flutter test` y 24/24 tests en `pytest`.
  * **Corrección de Logout Destructivo:** Se eliminó la llamada a `IsarService.clearAllData()` en el cierre de sesión (`AuthLogoutPressed`), permitiendo que al cerrar sesión y reiniciar o iniciar sesión offline, todos los datos (mascotas, horarios, logs, summary, dispensadores) se mantengan intactos y disponibles.
  * **Preservación de Tokens y Reautenticación Transparente:** Se corrigió el flujo para que al iniciar sesión offline se mantengan los tokens de sesión válidos en `flutter_secure_storage`, evitando errores 401 de "No autenticado" al encender el servidor posteriormente.

* #### APP Móvil & API
  * Arquitectura Limpia, BLoC, GoRouter, Isar e integración con FastAPI funcionando robustamente tanto online como offline.

## Decisiones (y por qué)
- Preservar la base de datos local Isar en logout para cumplir estrictamente con el principio Offline-First (evitando la pérdida de caché local al re-autenticarse sin conexión).
- Validación de cambio de usuario en `UserRepositoriesImpl.login` para limpiar Isar únicamente cuando cambia el email del usuario.

## Aprendizajes y errores a evitar
- Nunca vaciar bases de datos locales (`IsarService.clearAllData()`) en operaciones de cierre de sesión ordinarias si se requiere arquitectura Offline-First.

## Próximos pasos
- Validación final del usuario en la aplicación móvil física.
