# Especificación: Corrección y Robustecimiento de Persistencia de Datos Offline en Isar

**Estado:** borrador

## 1. Contexto y Objetivo
El inicio de sesión offline opera correctamente en la aplicación móvil; sin embargo, los datos locales del dominio del usuario (tales como mascotas, horarios de alimentación, logs de dispensación, registros de actividad y configuración del dispensador/dirección MAC) experimentaban incidencias de persistencia, desaparición temporal en la UI tras creaciones manuales offline, fallos por excepciones de red (`DioException`) no controladas al registrar la MAC sin conexión, y visualización de alertas intrusivas innecesarias cuando los datos se leen exitosamente desde la caché local de Isar.
El objetivo de esta especificación es definir los requisitos funcionales y no funcionales para garantizar la persistencia confiable, lectura optimista, soporte offline completo para el dispensador y una experiencia de usuario silenciosa y transparente (Offline-First) en todas las vistas de mascotas, horarios, logs y dispensador, cumpliendo estrictamente con la Constitución de PDAM.

## 2. Usuarios
* **Propietario de la mascota / Usuario final:** Requiere consultar, crear, actualizar y eliminar información de sus mascotas, horarios de alimentación, logs de actividad y configuración del dispensador tanto con conexión como sin ella, asegurando una experiencia fluida, sin desaparición de elementos creados localmente y sin alarmas de red inoportunas cuando opera offline con datos locales.

## 3. Historias de Usuario
* **HU-01:** Como usuario operando sin conexión a internet o tras reiniciar la aplicación, quiero visualizar correctamente la lista de mis mascotas, horarios de alimentación y logs almacenados localmente en Isar, para mantener el control de mis dispositivos de alimentación.
* **HU-02:** Como usuario sin conexión, quiero registrar nuevas mascotas, programar horarios de alimentación y generar logs locales, para que estos cambios se persistan inmediatamente en Isar y se sincronicen de forma transparente al recuperar la red.
* **HU-03:** Como usuario, quiero que cualquier modificación o eliminación de datos de dominio realizada offline se refleje consistentemente en la interfaz y se preserve de forma robusta en la base de datos local.
* **HU-04:** Como usuario sin conexión, quiero crear horarios manuales de alimentación y registrar la dirección MAC del dispensador de forma local y optimista, para que los datos aparezcan inmediatamente en la pantalla sin desaparecer ni lanzar errores de red no controlados.
* **HU-05:** Como usuario operando sin conexión, quiero que la aplicación cargue los datos desde la caché local de Isar de manera silenciosa y transparente, sin mostrar alertas o avisos intrusivos de error de red cuando la información local está disponible.

## 4. Requisitos Funcionales (RF-x) con Criterios de EARS
* **RF-01 (Persistencia local de mascotas):** Cuando el usuario cree, edite o reciba datos de mascotas desde el servidor, el sistema debe almacenar y persistir dichos registros en el esquema correspondiente de Isar.
* **RF-02 (Lectura offline de mascotas):** Si la aplicación inicia o se encuentra sin conexión a internet, el sistema debe leer y cargar la lista de mascotas directamente desde Isar hacia la capa de dominio y presentación en un tiempo menor o igual a 100 ms y sin pérdida de información.
* **RF-03 (Persistencia y lectura de horarios de alimentación):** Cuando se configuren o sincronicen horarios de alimentación, el sistema debe garantizar su escritura en Isar y su recuperación con un tiempo menor o igual a 100 ms ante reinicios de la aplicación o cortes de red.
* **RF-04 (Registro y persistencia de logs de actividad):** Cuando el dispensador o la aplicación generen logs de dispensación y eventos de alimentación, el sistema debe persistir dichos logs localmente en Isar para asegurar su trazabilidad offline.
* **RF-05 (Sincronización bidireccional de datos de dominio):** Cuando se restablezca la conexión a internet, el sistema debe sincronizar los cambios pendientes en Isar (mascotas, horarios, logs y configuración MAC) con el backend, aplicando la estrategia Last-Write-Wins basada en UTC timestamps con un umbral de desfase de reloj (clock drift) de 5 minutos, otorgando prioridad absoluta al servidor si el desfase supera dicho umbral o hay colisión exacta, conforme a la política Offline-First.
* **RF-06 (Creación optimista y persistente de horarios offline):** Cuando el usuario cree un horario de alimentación estando sin conexión, el sistema debe actualizar de forma optimista el estado del BLoC y persistir el registro localmente en Isar de manera inmediata, garantizando su visualización continua en la UI sin requerir reinicio de la aplicación.
* **RF-07 (Soporte offline para el dispensador y dirección MAC):** Cuando el usuario registre o actualice la dirección MAC del dispensador sin conexión a internet, el sistema debe interceptar cualquier excepción de red (`DioException`), almacenar localmente la MAC en Isar y marcarla para su sincronización posterior al reconectar, evitando fallos no controlados.
* **RF-08 (Operación offline silenciosa y transparente en la UI):** Si la aplicación carga datos de dominio (mascotas, horarios, logs y dispensador) desde la caché local de Isar en ausencia de red, el sistema debe operar de forma silenciosa sin mostrar alertas intrusivas o errores de red innecesarios al usuario en ninguna de las vistas principales.

## 5. Requisitos No Funcionales
* **RNF-01 (Clean Architecture):** La lógica de acceso, mapeo y persistencia en Isar debe implementarse estrictamente en la capa de datos (`data/datasources`, `data/repositories`), manteniendo aisladas las capas de dominio y presentación (`BLoC`, `views`, `widgets`).
* **RNF-02 (Disponibilidad Offline-First):** Las operaciones de lectura y escritura de datos de dominio deben resolverse localmente contra Isar en menos de 100 ms, garantizando disponibilidad total sin dependencia estricta de la red.
* **RNF-03 (Integridad de datos):** La estructura de esquemas en Isar debe mantener relaciones íntegras entre usuarios, mascotas, horarios, logs y configuración del dispensador, evitando estados corruptos o huérfanos ante reinicios de la app.

## 6. Casos Límite
* **Espacio de almacenamiento local agotado:** Si el almacenamiento del dispositivo se agota al intentar persistir logs, mascotas o configuración MAC en Isar, el sistema debe capturar la excepción, notificar al usuario de forma clara y operar en modo de solo lectura si es posible.
* **Conflicto de IDs locales vs remotos:** Registros creados offline con IDs temporales deben asociarse y actualizarse correctamente con los IDs definitivos devueltos por el servidor durante la sincronización.
* **Reinicio durante escritura masiva:** Si la app se cierra bruscamente mientras se escriben datos en Isar, el sistema debe asegurar transacciones atómicas para evitar corrupción de esquemas.
* **Corrupción de base de datos local o fallo de migración:** Si se detecta corrupción en el archivo de la base de datos local Isar o falla la migración de esquemas durante el arranque, el sistema debe capturar la excepción, recrear limpiamente la instancia local de Isar y notificar al usuario para iniciar una resincronización con el servidor.
* **Excepciones de red en llamadas al dispensador/MAC:** Si el backend no está disponible al registrar o consultar la dirección MAC, el sistema debe manejar el error de red de manera elegante mediante control de excepciones en la capa de datos, evitando bloqueos o caídas de la app.
* **Concurrencia en actualizaciones optimistas:** Si se producen múltiples acciones de creación o edición de horarios offline de forma simultánea, el BLoC y Isar deben mantener la consistencia de la lista sin duplicar elementos en la interfaz.

## 7. Fuera de Alcance
* Modificación del protocolo de autenticación offline (ya cubierto en specs previas).
* Sincronización de firmware o configuración de hardware ESP32 directamente desde la base de datos local (se gestiona vía API/servicios).

## 8. Criterios de Finalización
* Verificación mediante pruebas unitarias e integración de que las entidades de mascotas, horarios de alimentación, logs y configuración de dirección MAC del dispensador se persisten, leen y actualizan correctamente en Isar.
* Comprobación de que la creación manual de horarios offline se refleja de forma optimista e inmediata en el BLoC y la UI sin requerir reinicio.
* Validación de que el registro de la dirección MAC offline intercepta adecuadamente las excepciones de red (`DioException`) y persiste localmente sin fallos.
* Comprobación de que la interfaz de usuario muestra los datos locales de manera silenciosa y transparente, sin mostrar alertas intrusivas de error de red al operar offline con caché local.

## 9. Dudas Abiertas
* *Ninguna.*
