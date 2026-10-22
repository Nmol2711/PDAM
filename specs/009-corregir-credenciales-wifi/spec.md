# Spec 009 — Corrección y Validación Robusta de Credenciales WiFi y Sincronización en App y ESP32

Estado: borrador

## Contexto y objetivo
El sistema PDAM permite configurar redes WiFi para los dispensadores ESP32 mediante aprovisionamiento e interacción con la aplicación móvil. Actualmente se han detectado tres problemáticas críticas que afectan la experiencia y el funcionamiento del sistema:
1. Al ingresar credenciales en la aplicación móvil, se muestra incorrectamente un error indicando que no se pudieron guardar, y en el listado de dispositivos se refleja como si no existieran credenciales registradas, debido a problemas de sincronización, persistencia o UI.
2. El ESP32 valida la conexión WiFi únicamente verificando el enlace inalámbrico local, sin comprobar la conectividad real con el servidor mediante una petición HTTP al endpoint raíz (`/`), lo que puede causar falsos positivos de red.
3. Al flashear o iniciar el ESP32 por primera vez tras una nueva carga de código, las credenciales almacenadas previamente en la memoria no se limpian de manera garantizada, pudiendo persistir estados obsoletos.

El objetivo de esta especificación es resolver la persistencia y sincronización de credenciales en la aplicación móvil, incorporar la validación obligatoria de conectividad HTTP (status 200 en `/`) por parte del ESP32 para aprobar una red WiFi, y asegurar el borrado o reseteo limpio de credenciales en la inicialización posterior a una carga de código en el hardware.

## Usuarios
* **Dueño de mascota / Usuario de la App:** Desea ingresar credenciales WiFi y verificar de manera inmediata, coherente y sin errores falsos que el dispositivo se encuentra correctamente configurado y vinculado.
* **Sistema / Hardware ESP32:** Requiere validar de forma estricta tanto el acceso a la red WiFi como la comunicación HTTP exitosa con el servidor (status 200 en `/`) antes de aprobar la red, además de limpiar el almacenamiento de credenciales al inicializarse tras una carga de código.

## Historias de usuario
- HU-1. Como usuario, quiero ingresar las credenciales WiFi desde la aplicación móvil y que estas se guarden y sincronicen correctamente sin mensajes de error falsos, actualizando el listado de dispositivos de forma inmediata.
- HU-2. Como administrador del hardware, quiero que el ESP32 valide la conectividad de red haciendo una petición HTTP al servidor en el endpoint raíz (`/`) y requiera un código de estado 200 para aprobar la red WiFi, rechazándola en caso contrario.
- HU-3. Como desarrollador / operador de hardware, quiero que cada vez que se cargue código nuevo en el ESP32 (o en su inicialización tras flasheo), las credenciales previamente guardadas se borren de forma limpia para evitar estados obsoletos.

## Requisitos funcionales (EARS)
- RF-01 (Sincronización y Persistencia en App Móvil): CUANDO el usuario ingrese y guarde las credenciales WiFi en la aplicación móvil, EL SISTEMA debe persistirlas utilizando `flutter_secure_storage` y sincronizarlas correctamente, evitando mensajes de error erróneos y reflejando de inmediato en el listado de dispositivos que las credenciales están registradas.
- RF-02 (Validación de Conectividad HTTP por ESP32): CUANDO el ESP32 intente validar una red WiFi, EL SISTEMA debe comprobar la conexión inalámbrica y realizar obligatoriamente una petición HTTP al servidor en el endpoint principal (`/`), aprobando y conectando a la red únicamente si el servidor responde con un código de estado `200`, o rechazándola/no aprobándola en caso contrario.
- RF-03 (Limpieza de Credenciales en Inicialización de Hardware): CUANDO el ESP32 se inicialice por primera vez tras una nueva carga de código o flasheo, EL SISTEMA debe borrar o reiniciar de manera limpia el almacenamiento interno NVS (Non-Volatile Storage) de credenciales en el ESP32 para evitar estados obsoletos.

## Requisitos no funcionales
- RNF-01 (Clean Architecture y Separación Lógica-Interfaz): La solución debe mantener los principios de Clean Architecture, separando la lógica de negocio y la gestión de datos de los componentes visuales en Flutter, y modularizando adecuadamente el código en C++ del ESP32 (`config`, `drivers`, `services`).
- RNF-02 (Protección de Datos Sensibles): Las credenciales WiFi y tokens deben manejarse de manera segura, sin hardcodear secretos y utilizando almacenamiento cifrado donde aplique (`flutter_secure_storage` en la app móvil y almacenamiento seguro/no volátil en NVS para el ESP32).
- RNF-03 (Idioma): Toda la interfaz de usuario, mensajes de estado y descripciones deben estar en perfecto español.

## Fuera de alcance
- Modificaciones en la lógica interna del motor de dosificación nutricional o en los servicios de control del motor de alimentos del ESP32.

## Criterios de finalización
1. La aplicación móvil guarda y sincroniza de forma segura las credenciales WiFi usando `flutter_secure_storage` sin mostrar errores falsos, actualizando el estado visual en el listado de dispositivos (verificado mediante pruebas unitarias e integración para RF-01).
2. El ESP32 valida la red WiFi mediante conectividad HTTP al endpoint raíz (`/`), requiriendo status 200 para aprobar la conexión (verificado mediante pruebas de integración en hardware para RF-02).
3. El ESP32 borra automáticamente las credenciales guardadas en NVS al inicializarse tras una nueva carga de código o flasheo (verificado mediante pruebas unitarias en hardware para RF-03).
4. Todas las pruebas unitarias y de integración asociadas a cada RF pasan correctamente sin errores, cumpliendo con la política de tests de la constitución del proyecto.

## Dudas abiertas
- [NECESITA ACLARACIÓN] Ninguna. Los requisitos cubren exactamente los tres puntos solicitados sobre la corrección de credenciales y validación de red.
