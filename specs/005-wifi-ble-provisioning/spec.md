# Spec 005 — Aprovisionamiento WiFi por Bluetooth (BLE) para Dispensadores ESP32

Estado: borrador

## Contexto y objetivo

El sistema PDAM gestiona dispensadores de comida para mascotas basados en hardware ESP32 y una aplicación móvil en Flutter. Actualmente, los dispositivos requieren configuración de red que debe realizarse de forma robusta e intuitiva por cercanía física, sin depender de redes ad-hoc complejas.

El objetivo de esta especificación es definir los requisitos funcionales, no funcionales y de arquitectura para permitir el aprovisionamiento de credenciales WiFi (SSID y Password) desde la aplicación móvil en Flutter hacia el dispensador ESP32 mediante tecnología Bluetooth Low Energy (BLE), almacenamiento en memoria no volátil (NVS), apagado automático del Bluetooth tras la conexión exitosa, soporte exclusivo para redes de **2.4GHz**, y un mecanismo backend/API para solicitar el reseteo de credenciales y reinicio en modo aprovisionamiento.

## Usuarios

* **Dueño de mascota / Usuario de la App:** Desea configurar fácilmente el dispensador WiFi cercano mediante BLE, seleccionando su red de 2.4GHz e introduciendo las credenciales de forma segura.
* **Administrador / Sistema:** Requiere que el estado de conexión del dispensador y su gestión de red estén sincronizados y controlados tanto localmente como vía API.

## Historias de usuario

* **HU-1.** Como usuario, quiero navegar a una sección dedicada a "Dispensadores" en la barra de navegación principal para ver mis dispensadores registrados y buscar nuevos dispositivos cercanos por Bluetooth.
* **HU-2.** Como usuario, quiero que la aplicación escanee y encuentre dispensadores cercanos que estén en modo de configuración (anunciándose con el prefijo `PDAM-Config-[MAC]`) para seleccionarlos e iniciar la configuración WiFi.
* **HU-3.** Como usuario, quiero ser advertido claramente de que el dispensador solo soporta redes WiFi de **2.4GHz**, para evitar intentar conectarlo a redes de 5GHz que no son compatibles.
* **HU-4.** Como usuario, quiero ingresar el SSID y la contraseña de mi red WiFi y enviarlos al dispensador seleccionado mediante BLE de forma sencilla y directa.
* **HU-5.** Como usuario, quiero recibir confirmación visual cuando el dispensador se haya conectado exitosamente al WiFi y haya apagado su radio BLE.
* **HU-6.** Como administrador o usuario avanzado, quiero contar con un endpoint en la API backend que permita ordenar al dispensador borrar sus credenciales WiFi actuales de la NVS y reiniciar en modo de aprovisionamiento BLE.

## Definiciones

* **BLE (Bluetooth Low Energy):** Tecnología de comunicación inalámbrica de corto alcance utilizada para el intercambio de credenciales de configuración.
* **Servicio GATT BLE:** Estándar de atributos BLE expuesto por el ESP32 que contiene características específicas para la escritura de SSID y Contraseña.
* **NVS (Non-Volatile Storage):** Memoria flash no volátil del ESP32 donde se almacenan permanentemente las credenciales WiFi configuradas.
* **Red de 2.4GHz:** Única banda de frecuencia WiFi compatible con el chip ESP32 utilizado en el prototipo.
* **Modo Aprovisionamiento:** Estado del ESP32 en el cual no posee credenciales válidas (o falló la conexión) y emite beacons BLE con el nombre `PDAM-Config-[MAC]`.

## Requisitos funcionales (EARS)

* **RF-01 (Sección de Dispensadores en Navegación):** EL SISTEMA debe incluir una nueva sección denominada **"Dispensadores"** en la barra de navegación principal de la aplicación móvil, accesible mediante GoRouter, donde se listen los dispensadores registrados y se permita acceder al escáner BLE.
* **RF-02 (Escáner BLE de Dispensadores Cercanos):** CUANDO el usuario acceda a la función de búsqueda de dispositivos en la sección de Dispensadores, EL SISTEMA (empleando `flutter_blue_plus`) debe escanear y listar los dispositivos BLE cercanos cuyo nombre publicitado comience con el prefijo `PDAM-Config-[` (siguiendo el patrón `PDAM-Config-[MAC]`).
* **RF-03 (Selección de Dispositivo y Conexión BLE):** CUANDO el usuario seleccione un dispensador de la lista de escaneo BLE, EL SISTEMA debe establecer una conexión GATT con el ESP32 seleccionado.
* **RF-04 (Advertencia de Restricción de 2.4GHz):** EL SISTEMA debe mostrar de forma prominente en la interfaz de aprovisionamiento WiFi una advertencia técnica indicando que el dispensador ESP32 **solo es compatible con redes WiFi de 2.4GHz** y no soporta bandas de 5GHz.
* **RF-05 (Envío de Credenciales WiFi vía BLE):** CUANDO el usuario introduzca el SSID y la contraseña de la red WiFi y pulse el botón de envío, EL SISTEMA debe transmitir dichos valores a través de las características GATT correspondientes del servicio de aprovisionamiento del ESP32.
* **RF-06 (Recepción y Almacenamiento en NVS por el ESP32):** CUANDO el ESP32 reciba el SSID y la contraseña a través de BLE, EL HARDWARE debe intentar conectarse a la red WiFi especificada; SI la conexión es exitosa, ENTONCES EL HARDWARE debe almacenar las credenciales en su memoria no volátil (NVS) y apagar inmediatamente el radio Bluetooth.
* **RF-07 (Comportamiento ante Fallo de Conexión WiFi):** SI la conexión WiFi del ESP32 falla utilizando las credenciales proporcionadas, ENTONCES EL HARDWARE debe reintentar un número limitado de veces y, en caso de persistir el fallo, reabrir automáticamente el servicio BLE en modo aprovisionamiento (`PDAM-Config-[MAC]`).
* **RF-08 (Notificación de Estado en la App):** EL SISTEMA debe reflejar en la interfaz de usuario el estado de la transmisión de credenciales y la confirmación de conexión exitosa recibida del dispensador.
* **RF-09 (Endpoint Backend para Reseteo de Credenciales y Modo BLE):** EL SERVIDOR (FastAPI) debe exponer un endpoint seguro (ej. `/api/v1/dispensers/{id}/reset-wifi` o comando equivalente) que permita enviar una orden de borrado de credenciales NVS al dispensador y forzar su reinicio en modo de aprovisionamiento BLE.

## Requisitos no funcionales

* **RNF-01 (Clean Architecture):** La lógica de comunicación BLE, gestión de estado con BLoC, repositorios y servicios de API deben mantener estricta separación de acuerdo con la Clean Architecture y las directrices de `docs/constitution.md`.
* **RNF-02 (Arquitectura Offline-First):** La sección de dispensadores y la gestión de dispositivos registrados deben operar correctamente sin conexión a internet, recurriendo a almacenamiento local (Isar) cuando el servidor no esté disponible.
* **RNF-03 (Seguridad en Transmisión Local):** La transmisión de credenciales por BLE se realiza en texto plano debido a la restricción de cercanía física obligatoria (usuario junto al dispositivo), cumpliendo con el protocolo estándar de aprovisionamiento IoT para ESP32.
* **RNF-04 (Estilo y Tema Global):** Toda la interfaz de la nueva sección "Dispensadores" y sus flujos BLE deben utilizar estrictamente la paleta de colores global y los temas de la aplicación móvil (Material Design 3), tanto en modo claro como oscuro.
* **RNF-05 (Idioma en Español):** Todos los textos de la interfaz de usuario, mensajes de estado, advertencias de 2.4GHz y errores deben estar redactados en perfecto español.
* **RNF-06 (Pruebas Automatizadas):** Todo componente nuevo (BLoC de BLE, repositorio, servicios FastAPI y lógica ESP32) debe contar con pruebas unitarias y de integración que verifiquen su correcto funcionamiento antes de su integración.

## Arquitectura de la solución

1. **Frontend (Flutter + BLoC + GoRouter + Isar):**
   - **`features/dispensers/`**: Nuevo módulo organizado en capas (`data`, `domain`, `presentation`).
   - **`presentation/`**: Vistas de listado de dispensadores, pantalla de escaneo BLE y formulario de aprovisionamiento WiFi, gestionadas mediante BLoC / Cubit.
   - **`data/services/ble_provisioning_service.dart`**: Wrapper sobre `flutter_blue_plus` para escaneo, conexión, descubrimiento de servicios GATT y escritura de características (SSID y Password).
   - **Navegación**: Integración en `GoRouter` añadiendo la pestaña/sección **"Dispensadores"**.

2. **Backend (FastAPI + SQLite/PostgreSQL):**
   - **`app/services/dispenser_service.py`** y endpoints asociados para registrar el estado del dispositivo y gestionar la orden de reseteo de credenciales WiFi (`reset-wifi`).

3. **Hardware (ESP32):**
   - **`src/services/ble_service.cpp` / `src/drivers/`**: Implementación de servidor GATT BLE con UUIDs específicos para configuración WiFi.
   - **`src/services/wifi_service.cpp`**: Conexión WiFi limitada estrictamente a **2.4GHz**, manejo de reconexión y almacenamiento persistente en **NVS** (`Preferences.h`).
   - **`main.cpp`**: Máquina de estados que inicializa BLE si no hay credenciales en NVS o si la conexión falla; apaga BLE al conectar exitosamente al WiFi.

## Casos de prueba requeridos

* **CP-01 (Escaneo BLE):** Verificar que la app detecta correctamente los dispositivos con prefijo `PDAM-Config-[MAC]` y filtra otros dispositivos Bluetooth ajenos.
* **CP-02 (Advertencia de 2.4GHz):** Comprobar que la UI muestra de forma visible y clara la advertencia sobre la incompatibilidad con redes de 5GHz.
* **CP-03 (Envío y Persistencia BLE):** Validar que la escritura de SSID y Password a través de las características GATT del ESP32 resulta en el almacenamiento exitoso en NVS y el apagado del radio BLE en el hardware.
* **CP-04 (Fallo de Red y Reapertura BLE):** Simular credenciales incorrectas y comprobar que el ESP32 reabre el modo BLE de aprovisionamiento automáticamente.
* **CP-05 (Navegación y Listado Offline):** Comprobar que la sección "Dispensadores" es accesible mediante GoRouter y muestra los dispensadores locales almacenados en Isar sin conexión.
* **CP-06 (Endpoint de Reseteo API):** Probar que el endpoint FastAPI procesa correctamente la solicitud de borrado de credenciales y reinicio del dispensador.
