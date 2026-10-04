# Tareas: Corrección y Robustecimiento de Persistencia de Datos Offline en Isar

Lista de tareas desglosadas en pasos pequeños (máx. 20-30 min), ordenadas por dependencia y alineadas con el Modelo en V y la Constitución de PDAM.

- [x] **Tarea 1: Robustecimiento de IsarService y adición del esquema LocalDispenser**
  - **RF cubiertos:** RNF-02, RNF-03, RF-07
  - **Descripción:** Actualizar `IsarService` en `app/app_movil_pdam/lib/core/offline/isar_service.dart` para registrar el modelo `LocalDispenser` con el flag `isSynced`, implementando manejo seguro de excepciones de almacenamiento y corrupción.
  - **Hecho cuando:** Las pruebas unitarias validan la apertura correcta de Isar con el nuevo esquema y la recuperación ante errores.

- [x] **Tarea 2: Creación de LocalDispenserDatasource y refactorización de datasources locales de mascotas, horarios y logs**
  - **RF cubiertos:** RF-01, RF-03, RF-04, RF-07, RNF-02
  - **Descripción:** Implementar `LocalDispenserDatasource` y asegurar transacciones atómicas (`isar.writeTxn`) en los datasources locales de mascotas, horarios y logs para respuestas $\le$ 100 ms.
  - **Hecho cuando:** Las pruebas unitarias validan el CRUD local en Isar para todos los dominios con tiempos menores a 100 ms.

- [x] **Tarea 3: Implementación de soporte offline y manejo de DioException en DispenserRepositoryImpl**
  - **RF cubiertos:** RF-07, RNF-02
  - **Descripción:** Modificar `DispenserRepositoryImpl` para interceptar `DioException` al registrar o actualizar la dirección MAC, persistiendo localmente en Isar con `isSynced = false`.
  - **Hecho cuando:** Las pruebas unitarias confirman que el registro de MAC sin conexión se guarda localmente en Isar sin lanzar excepciones no controladas.

- [x] **Tarea 4: Actualización de Repositorios de Dominio (Pets, Schedules, Logs, Dispenser) con estrategia Offline-First**
  - **RF cubiertos:** RF-01, RF-02, RF-03, RF-04, RF-07, RNF-01
  - **Descripción:** Refactorizar los repositorios para priorizar la lectura instantánea desde Isar y sincronizar de forma transparente con la API remota cuando haya conectividad.
  - **Hecho cuando:** Los repositorios devuelven datos locales ante ausencia de red y actualizan Isar tras operaciones exitosas con el backend.

- [x] **Tarea 5: Implementación de creación optimista de horarios manuales en ScheduleBloc**
  - **RF cubiertos:** RF-06, RNF-01
  - **Descripción:** Actualizar `ScheduleBloc` para aplicar actualización optimista inmediata en el estado al crear horarios offline, persistiendo simultáneamente en Isar.
  - **Hecho cuando:** Las pruebas unitarias del `ScheduleBloc` confirman que un horario creado offline se añade inmediatamente al estado sin requerir red ni reinicio.

- [x] **Tarea 6: Supresión de alertas intrusivas y habilitación de operación silenciosa en UI**
  - **RF cubiertos:** RF-08
  - **Descripción:** Modificar las vistas principales (`PetsView`, `ScheduleView`, `LogsView`, `RegisterDispenserView`) y BLoCs asociados para operar de forma silenciosa cuando los datos se cargan exitosamente desde la caché local de Isar, evitando Snackbars de error de red innecesarios.
  - **Hecho cuando:** La navegación y visualización offline se ejecutan sin mostrar alertas intrusivas de red al usuario.

- [x] **Tarea 7: Ampliación de SyncService para sincronización bidireccional y de MAC offline**
  - **RF cubiertos:** RF-05, RF-07
  - **Descripción:** Actualizar `SyncService` en `app/app_movil_pdam/lib/core/offline/sync_service.dart` para sincronizar elementos pendientes (mascotas, horarios, logs y configuración MAC con `isSynced = false`) al recuperar red, usando Last-Write-Wins.
  - **Hecho cuando:** Al restablecer la conectividad, todos los registros pendientes en Isar se sincronizan correctamente con el backend.

- [x] **Tarea 8: Implementación y pruebas unitarias de creación optimista de horarios manuales (`ScheduleBloc`)**
  - **RF cubiertos:** RF-06, RNF-01
  - **Descripción:** Desarrollar y verificar la lógica de actualización optimista en `ScheduleBloc` para la creación de horarios offline, asegurando persistencia inmediata en Isar y actualización fluida en la UI sin requerir red.
  - **Hecho cuando:** Las pruebas unitarias confirman que `ScheduleBloc` añade y muestra horarios offline de forma optimista.

- [x] **Tarea 9: Implementación y pruebas unitarias de soporte offline para dirección MAC del dispensador (`DioException`)**
  - **RF cubiertos:** RF-07, RNF-02
  - **Descripción:** Implementar el manejo robusto de `DioException` en `DispenserRepositoryImpl` y `DispenserBloc`, permitiendo el almacenamiento local de la dirección MAC en Isar con `isSynced = false` en ausencia de red.
  - **Hecho cuando:** Las pruebas unitarias validan que registrar una MAC sin conexión no arroja errores no controlados y se almacena correctamente en Isar.

- [x] **Tarea 10: Verificación de operación silenciosa y transparente en la UI ante uso offline**
  - **RF cubiertos:** RF-08, RNF-01
  - **Descripción:** Comprobar que todas las vistas principales (`PetsView`, `ScheduleView`, `LogsView`, `RegisterDispenserView`) operan de forma silenciosa al cargar datos desde Isar sin conexión, suprimiendo Snackbars o alertas de red innecesarias.
  - **Hecho cuando:** La navegación y visualización de datos locales se realizan sin mostrar alertas de error de red al usuario.

- [x] **Tarea 11: Pruebas de integración del flujo offline completo y sincronización**
  - **RF cubiertos:** RF-01 a RF-08, RNF-01, RNF-02, RNF-03
  - **Descripción:** Ejecutar pruebas de integración completas en Flutter cubriendo creación optimista de horarios, persistencia y sincronización de MAC offline, carga silenciosa en UI y sincronización bidireccional con SyncService.
  - **Hecho cuando:** `flutter test` pasa todas las pruebas de integración y unitarias exitosamente.

- [x] **Tarea 12: Preservación de la base de datos Isar y tokens de sesión en Logout para Offline-First**
  - **RF cubiertos:** RF-01, RF-02, RF-03, RF-04, RNF-03
  - **Descripción:** Ajustar `AuthBloc._onLogoutPressed` para evitar la llamada destructiva a `IsarService.clearAllData()`, asegurando que al cerrar sesión y reiniciar o iniciar sesión sin conexión, todos los datos locales (mascotas, horarios, logs, summary, dispensadores) permanezcan intactos y disponibles.
  - **Hecho cuando:** Iniciar sesión offline tras cerrar sesión muestra correctamente todos los datos guardados previamente en Isar.

- [x] **Tarea 13: Persistencia de tokens y reautenticación transparente al reconectar servidor**
  - **RF cubiertos:** RF-05, RNF-03
  - **Descripción:** Asegurar que las credenciales y tokens de sesión cacheados se preserven adecuadamente tras login offline, permitiendo que al encender el servidor posterior, las peticiones HTTP se envíen con cabecera `Authorization` válida sin errores de autenticación 401.
  - **Hecho cuando:** Las peticiones al servidor tras un inicio de sesión offline son aceptadas con éxito por el backend al restablecerse la conectividad.
