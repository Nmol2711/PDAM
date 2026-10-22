# Spec 010 — Corrección Crítica de Aprovisionamiento, Persistencia Isar, NVS, Filtrado y Ciclo BLE

Estado: borrador

## Contexto y objetivo
Durante el funcionamiento del sistema PDAM se han identificado 5 fallos críticos que afectan la estabilidad del almacenamiento local en Isar, el aprovisionamiento y ciclo de vida BLE en la app móvil, el filtrado de dispositivos, la actualización visual de credenciales WiFi y el borrado NVS en el ESP32:
1. **Isar Unique Index Violation:** Ocurre el error `IsarError: Unique index violated` al guardar o aprovisionar dispensadores en la base de datos local Isar cuando ya existe un registro con el mismo identificador o MAC, debido a inserciones directas sin verificar existencia previa (upsert).
2. **Borrado NVS en ESP32 al Flashear:** El almacenamiento NVS del ESP32 no siempre borra de forma infalible las credenciales anteriores tras cargar un nuevo build, requiriendo una rutina de detección de compilación o reseteo NVS más robusta.
3. **Filtrado del Listado de Dispositivos:** El listado de dispensadores en la app móvil muestra todos los registros locales sin discriminar si están asociados a una mascota, mostrando dispositivos huérfanos (`petId == null`). Debe restringirse para mostrar únicamente dispensadores con mascota asociada (`petId != null`).
4. **Actualización de Estado de Credenciales WiFi en UI:** La interfaz de usuario no actualiza de manera reactiva y correcta el estado visual indicando que las credenciales WiFi han sido proporcionadas exitosamente.
5. **Ciclo de Escaneo BLE:** Al salir del formulario de aprovisionamiento BLE y reintentar escanear, el escáner BLE se queda en un estado inactivo o bloqueado que requiere reiniciar la aplicación.

El objetivo de esta especificación es resolver estos 5 puntos críticos garantizando operaciones robustas de almacenamiento (upsert en Isar), borrado de NVS en firmware, filtrado estricto por `petId != null`, sincronización visual de credenciales WiFi y correcto reinicio del ciclo de vida del escaneo BLE.

## Usuarios
* **Dueño de mascota / Usuario de la App:** Desea que la aplicación móvil liste únicamente los dispensadores de sus mascotas (`petId != null`), muestre con precisión el estado de las credenciales WiFi, y permita reintentar el escaneo BLE y aprovisionar sin errores de índice en Isar ni bloqueos de reinicio.
* **Sistema / Hardware ESP32:** Requiere un borrado NVS infalible al detectar una nueva carga de código para evitar interferencias de credenciales obsoletas.

## Historias de usuario
- HU-1. Como usuario de la app, quiero que al guardar o sincronizar dispensadores no se produzca el error `IsarError: Unique index violated`, implementando un mecanismo de upsert o validación previa.
- HU-2. Como desarrollador / operador de hardware, quiero que al flashear el ESP32 con un nuevo código, el almacenamiento NVS se borre de forma infalible para evitar credenciales obsoletas.
- HU-3. Como usuario de la app, quiero que el listado de dispensadores muestre **únicamente** aquellos dispositivos que tienen una mascota asociada (`petId != null`), ocultando dispositivos huérfanos.
- HU-4. Como usuario de la app, quiero que el estado visual de las credenciales WiFi se actualice correctamente en la interfaz cuando ya han sido configuradas exitosamente.
- HU-5. Como usuario de la app, quiero que al salir del formulario de aprovisionamiento BLE y volver a entrar, el escaneo BLE se reinicie correctamente sin necesidad de reiniciar toda la aplicación.

## Requisitos funcionales (EARS)
- RF-01 (Upsert en Base de Datos Isar): CUANDO el sistema intente guardar o aprovisionar un dispensador en la base de datos local Isar, EL SISTEMA debe implementar una operación de upsert (verificación previa por MAC/ID o actualización si ya existe) para evitar completamente el error `IsarError: Unique index violated`.
- RF-02 (Borrado Infalible NVS en ESP32): CUANDO el ESP32 se inicialice tras una nueva compilación o flasheo de firmware, EL SISTEMA debe ejecutar una rutina de detección de nuevo build mediante la comparación del sello de compilación (`build_stamp` con `__DATE__ __TIME__`) para borrar de manera infalible el almacenamiento NVS de credenciales.
- RF-03 (Filtrado Estricto de Dispositivos por Mascota): CUANDO la aplicación móvil cargue el listado de dispensadores, EL SISTEMA debe filtrar y mostrar **únicamente** los dispositivos que contengan una mascota asociada (`petId != null`).
- RF-04 (Actualización Visual de Credenciales WiFi): CUANDO las credenciales WiFi sean cargadas y confirmadas exitosamente, EL SISTEMA debe actualizar de forma reactiva a través del BLoC y el estado de la UI en la aplicación móvil reflejando el estatus correcto.
- RF-05 (Reinicio del Ciclo de Vida del Escaneo BLE): CUANDO el usuario abandone el formulario de aprovisionamiento y regrese o solicite un nuevo escaneo BLE, EL SISTEMA debe reiniciar correctamente el ciclo de vida del escáner liberando recursos previos (streams, suscripciones y controladores BLE) y reiniciando la búsqueda sin requerir reiniciar la aplicación.

## Requisitos no funcionales
- RNF-01 (Clean Architecture): Mantener estrictamente la separación de responsabilidades según la Clean Architecture (capas data, domain y presentation en Flutter; separación modular en C++ para ESP32).
- RNF-02 (Protección de Datos): Resguardo seguro de credenciales y datos sensibles sin comprometer la integridad de la base de datos local ni del almacenamiento NVS.
- RNF-03 (Idioma): Toda la interfaz de usuario, mensajes de estado y descripciones deben estar en perfecto español.

## Fuera de alcance
- Cambios en el motor de dosificación nutricional o en los microservicios de la API de backend (FastAPI).

## Criterios de finalización
1. La persistencia en Isar gestiona los dispensadores mediante upsert, eliminando el error `IsarError: Unique index violated` (verificado con pruebas unitarias).
2. El firmware ESP32 borra infaliblemente NVS en flasheos nuevos (verificado con PlatformIO).
3. El listado de dispensadores en la app muestra exclusivamente dispositivos con `petId != null` (verificado con pruebas de widgets).
4. La UI de la app actualiza correctamente el estado de las credenciales WiFi tras la configuración.
5. El escaneo BLE se puede reiniciar y reintentar múltiples veces desde la UI sin reiniciar la app.
6. Todos los tests pasan exitosamente (`flutter test`, `pio run`) y `flutter analyze` reporta cero errores.

## Dudas abiertas
- [NECESITA ACLARACIÓN] Ninguna.
