# Tareas: Sincronización Offline Avanzada y Gestión de Sesión

Lista de tareas desglosadas en pasos pequeños (máx. 20-30 min), ordenadas por dependencia y alineadas con el Modelo en V y la Constitución de PDAM.

- [x] **Tarea 1: Backend - Esquema Pydantic y lógica de resolución por timestamp**

  - **RF cubiertos:** RF-04
  - **Descripción:** Crear `api/app/schemas/sync_schema.py` para lotes de sincronización e implementar la función pura en Python para comparar marcas de tiempo con umbral de 5 min y prioridad al servidor.
  - **Hecho cuando:** Los modelos Pydantic validan correctamente las marcas de tiempo y las pruebas unitarias pasan en `pytest`.

- [x] **Tarea 2: Backend - Endpoint de sincronización bidireccional**

  - **RF cubiertos:** RF-04, RF-05
  - **Descripción:** Implementar el servicio y router en FastAPI (`api/app/services/sync_service.py`) para procesar solicitudes de sincronización y adopción de registros remotos ante fallos.
  - **Hecho cuando:** El endpoint responde correctamente a solicitudes HTTP POST de sincronización con datos simulados y reales en SQLite.

- [x] **Tarea 3: Backend - Pruebas unitarias de sincronización (pytest)**

  - **RF cubiertos:** RF-04, RF-05
  - **Descripción:** Escribir pruebas en `api/tests/` para verificar la resolución de conflictos, desfase de reloj (*clock drift*) y gestión de errores en FastAPI.
  - **Hecho cuando:** `pytest` ejecuta exitosamente todas las pruebas del módulo de sincronización sin errores.

- [x] **Tarea 4: Frontend - Almacenamiento seguro de credenciales con flutter_secure_storage**

  - **RF cubiertos:** RF-01, RF-02, RNF-02
  - **Descripción:** Modificar `AuthLocalDatasource` en Flutter para guardar y recuperar de forma cifrada las credenciales de inicio de sesión utilizando estrictamente `flutter_secure_storage`.
  - **Hecho cuando:** Las credenciales del usuario se almacenan y leen de forma cifrada sin exponer texto plano.

- [x] **Tarea 5: Frontend - Autenticación offline con timeout de 10s**

  - **RF cubiertos:** RF-02, RF-03
  - **Descripción:** Actualizar `AuthRepositoryImpl` para interceptar fallos de red o timeouts de 10 segundos al iniciar sesión, validando contra el almacenamiento local cifrado. Asegurar restricción de cambio de credenciales online (RF-03).
  - **Hecho cuando:** Al simular ausencia de red o timeout de 10s, el login se resuelve exitosamente con las credenciales locales cacheadas.

- [x] **Tarea 6: Frontend - Actualización de AuthBloc**

  - **RF cubiertos:** RF-02, RF-03
  - **Descripción:** Adaptar `AuthBloc` para emitir estados de autenticación offline y bloquear intentos de actualización de contraseña sin conexión.
  - **Hecho cuando:** La interfaz reacciona fluidamente ante logins offline y muestra advertencias claras al intentar actualizar credenciales sin red.

- [x] **Tarea 7: Frontend - Implementación de función pura resolveConflict**

  - **RF cubiertos:** RF-04
  - **Descripción:** Crear la función pura de dominio en Flutter para comparar objetos locales y remotos considerando el umbral de 5 minutos y la prioridad del servidor ante colisiones.
  - **Hecho cuando:** La función pura pasa todas las pruebas unitarias con diferentes casos de prueba de marcas de tiempo.

- [x] **Tarea 8: Frontend - Servicio de sincronización en segundo plano con Isar**

  - **RF cubiertos:** RF-04, RF-05, RNF-03
  - **Descripción:** Implementar `SyncService` en Flutter para ejecutar la sincronización bidireccional y fusión con Isar de manera asíncrona al recuperar conectividad.
  - **Hecho cuando:** Al recuperar la red, los cambios pendientes en Isar se sincronizan y resuelven automáticamente en segundo plano.

- [x] **Tarea 9: Frontend - Pruebas unitarias y de integración offline-first**

  - **RF cubiertos:** RF-02, RF-04, RF-05
  - **Descripción:** Ejecutar y ampliar la suite de pruebas en Flutter (`flutter test`) para validar el comportamiento offline del login, timeout y resolución de conflictos.
  - **Hecho cuando:** `flutter test` pasa satisfactoriamente validando la arquitectura offline-first completa.
