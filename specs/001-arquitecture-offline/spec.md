# Especificación: Sincronización Offline Avanzada y Gestión de Sesión

## 1. Contexto y Objetivo
El sistema necesita garantizar la continuidad operativa cuando el dispositivo no disponga de conexión a internet o el servidor no responda. El objetivo de esta especificación es definir el comportamiento funcional para permitir el inicio de sesión offline, la sincronización bidireccional de datos con resolución de conflictos basada en marcas de tiempo (con umbral de desfase de reloj y prioridad al servidor), uso de `flutter_secure_storage` e `Isar`, y el manejo robusto de errores durante la reconexión.

## 2. Usuarios
* **Propietario de la mascota / Usuario final:** Gestiona la información de sus mascotas, horarios de alimentación y registros de actividad tanto con conexión como sin ella, percibiendo una experiencia fluida e idéntica en ambos estados.

## 3. Historias de Usuario
* **HU01:** Como usuario sin conexión a internet, quiero iniciar sesión en la aplicación utilizando mis credenciales almacenadas localmente para acceder a mis datos y mascotas sin interrupciones.
* **HU02:** Como usuario, quiero registrar operaciones y cambios localmente cuando no haya red, para que posteriormente se sincronicen de manera transparente al recuperar la conexión.
* **HU03:** Como usuario, quiero que el sistema resuelva automáticamente los conflictos de sincronización usando el registro más reciente o la política del servidor, para evitar la pérdida de información actualizada.

## 4. Requisitos Funcionales (RF-x) con Criterios de EARS

* **RF-01 (Inicio de sesión con conexión):** Cuando el usuario intente iniciar sesión y exista conexión con el servidor, el sistema debe validar las credenciales de manera remota y almacenar una copia segura de autenticación en el dispositivo local.
* **RF-02 (Inicio de sesión sin conexión):** Si el usuario intenta iniciar sesión y el dispositivo se encuentra sin conexión a internet o el servidor no responde tras un timeout de 10 segundos, el sistema debe autenticar localmente utilizando las credenciales cacheadas mediante `flutter_secure_storage`, mostrando una interfaz idéntica a cuando hay conexión.
* **RF-03 (Restricción de actualización de credenciales):** Para realizar modificaciones o actualizaciones de credenciales, el sistema debe requerir obligatoriamente conexión activa con el servidor.
* **RF-04 (Sincronización basada en tiempo y umbral):** Cuando se restablezca la conexión con el servidor, el sistema debe comparar las marcas de tiempo (timestamp) de los registros locales y remotos. Si la discrepancia (*clock drift*) es menor a 5 minutos, se aplica el registro más reciente; si supera los 5 minutos o hay colisión exacta, se prioriza el registro del servidor.
* **RF-05 (Gestión de fallos de sincronización):** Si un cambio pendiente realizado offline falla en el servidor durante el proceso de sincronización, el sistema debe reintentar la operación y, de persistir el fallo, sincronizar adoptando el registro del servidor para prevenir conflictos futuros.

## 5. Requisitos No Funcionales
* **RNF-01:** La experiencia de usuario en escenarios offline debe ser indistinguible en velocidad y disponibilidad respecto al estado online.
* **RNF-02:** Los datos de sesión y credenciales almacenados en el dispositivo local deben protegerse bajo mecanismos de cifrado robustos utilizando estrictamente `flutter_secure_storage`, y los datos de la aplicación mediante la base de datos local **Isar**, conforme a la Constitución de PDAM.
* **RNF-03:** El proceso de sincronización automática al recuperar la conectividad debe ejecutarse en segundo plano sin bloquear la interacción del usuario.

## 6. Casos Límite
* **Expiración de token offline:** Si el token almacenado localmente expira durante un período prolongado sin conexión, el sistema requerirá autenticación online al detectar red.
* **Desfase horario (*clock drift*):** Diferencias de marcas de tiempo superiores a 5 minutos o colisiones exactas se resuelven adoptando el registro del servidor.
* **Interrupción durante sincronización:** Si la conexión se interrumpe a mitad de una sincronización masiva, el proceso se reanudará en la siguiente reconexión sin corromper la integridad de los datos en Isar.
* **Cambio de contraseña remoto:** Cambio de contraseña en otro dispositivo mientras el usuario actual opera offline con credenciales antiguas (se resolverá mediante la validación del servidor al reconectar).

## 7. Fuera de Alcance
* Resolución manual de conflictos por parte del usuario mediante interfaces de comparación de datos.
* Sincronización de archivos multimedia pesados (fotografías) en redes celulares de baja velocidad (se diferirá hasta contar con red estable).

## 8. Criterios de Finalización
* Validación exitosa de los flujos de inicio de sesión offline utilizando credenciales cacheadas con un timeout de 10s.
* Pruebas unitarias y de integración que verifiquen la resolución de conflictos basada en marcas de tiempo con umbral de 5 minutos y prioridad al servidor.
* Verificación del comportamiento del sistema ante fallos de sincronización e interrupciones de red.

## 9. Dudas Abiertas
* *Ninguna.*
