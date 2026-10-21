# Spec 008 — Migración del Código de Arduino Sketch a PlatformIO para ESP32 con Arquitectura Modular

Estado: implementada

## Contexto y objetivo
El código actual del prototipo de dispensador de comida para mascotas basado en ESP32 se encuentra en un archivo único de Arduino sketch (`arduino/sketch_jul3a/sketch_jul3a.ino`). Para cumplir con los estándares de mantenibilidad, robustez y estructura modular definidos en el proyecto (según `AGENTS.md` y `docs/constitution.md`), se requiere migrar este código a PlatformIO bajo la estructura organizada por carpetas en el directorio `DispensadorESP32/src/` (`config/`, `drivers/`, `services/`, `tasks/`, y `main.cpp`). El código original en Arduino debe permanecer intacto como respaldo, asegurando que toda la funcionalidad existente (obtención de MAC por eFuse, máquina de estados, aprovisionamiento BLE de credenciales WiFi 2.4GHz, persistencia NVS, cliente HTTP con FastAPI, parseo JSON y control del servomotor MG966R) se mantenga operativa y estructurada de forma desacoplada.

## Usuarios
- **Desarrollador / Ingeniero de Hardware:** Usuario que compila, flasheo y depura el firmware del ESP32 utilizando PlatformIO con una estructura de código limpia y modular.
- **Mascota / Dueño:** Usuario final que recibe el beneficio del dispensador automatizado y conectado a la API.

## Historias de usuario
- HU-1. Como desarrollador, quiero estructurar el firmware del ESP32 en módulos independientes (`config`, `drivers`, `services`, `tasks`) para facilitar la escalabilidad y el mantenimiento del código de hardware.
- HU-2. Como desarrollador, quiero mantener el archivo `arduino/sketch_jul3a/sketch_jul3a.ino` intacto como respaldo histórico del prototipo inicial.
- HU-3. Como sistema, quiero inicializar el ESP32 obteniendo la MAC física por eFuse, configurar el servomotor MG966R y evaluar el estado inicial en NVS.
- HU-4. Como sistema, quiero gestionar el aprovisionamiento de credenciales WiFi (2.4GHz) mediante un servidor GATT BLE temporal cuando no existan credenciales almacenadas o falle la conexión.
- HU-5. Como sistema, quiero consultar periódicamente al backend de FastAPI mediante solicitudes HTTP GET y parsear la respuesta JSON para decidir si se activa el mecanismo de dispensación de alimento mediante el servomotor.

## Definiciones
- **Estructura Modular ESP32:** Organización del código fuente en `DispensadorESP32/src/` dividida en `config/`, `drivers/`, `services/`, `tasks/` y `main.cpp`.
- **Aprovisionamiento BLE:** Mecanismo mediante el cual el ESP32 levanta un servicio GATT Bluetooth Low Energy para recibir SSID y contraseña de WiFi desde la aplicación móvil Flutter.
- **NVS (Non-Volatile Storage):** Sistema de almacenamiento no volátil en el ESP32 utilizado para guardar de forma segura las credenciales WiFi y parámetros de configuración.

## Requisitos funcionales
- RF-01: EL SISTEMA mantiene el archivo original `arduino/sketch_jul3a/sketch_jul3a.ino` intacto y sin modificaciones como respaldo en el repositorio.
- RF-02: CUANDO se compila el proyecto en PlatformIO, EL SISTEMA utiliza la estructura de carpetas modular ubicada en `DispensadorESP32/src/` con los submódulos `config/`, `drivers/`, `services/`, `tasks/` y el punto de entrada `main.cpp`.
- RF-03: CUANDO el ESP32 arranca (`setup`), EL SISTEMA lee la dirección MAC física por eFuse, configura los temporizadores PWM y asocia el servomotor MG966R al pin GPIO 4.
- RF-04: CUANDO el sistema evalúa las credenciales en NVS (`STATE_CHECK_NVS`), SI existen credenciales guardadas, ENTONCES EL SISTEMA intenta conectar a la red WiFi 2.4GHz (`STATE_CONNECT_WIFI`); DE LO CONTRARIO, activa el modo de aprovisionamiento BLE (`STATE_BLE_PROVISIONING`).
- RF-05: MIENTRAS el ESP32 se encuentra en modo de aprovisionamiento BLE, EL SISTEMA anuncia un servidor GATT BLE (con UUIDs específicos y nombre `PDAM-Config-<MAC>`), recibe las credenciales enviadas por la app móvil, las almacena en NVS y desactiva la radio BLE para continuar con la conexión WiFi.
- RF-06: CUANDO el dispositivo se encuentra en estado normal (`STATE_NORMAL`), EL SISTEMA ejecuta un temporizador no bloqueante basado en `millis()` para consultar periódicamente al endpoint FastAPI del backend mediante peticiones HTTP GET.
- RF-07: CUANDO la respuesta HTTP del backend es exitosa (código 200) y el JSON indica `"serve": true`, EL SISTEMA ejecuta la tarea de dispensación activando el servomotor MG966R durante 10 segundos antes de detenerlo.
- RF-08: SI la conexión WiFi se pierde durante la operación normal, ENTONCES EL SISTEMA intenta reconectar de forma automática; SI la reconexión falla tras un número determinado de intentos, reinicia el modo de aprovisionamiento BLE.

## Requisitos no funcionales
- RNF-01: **Arquitectura de Hardware:** Cumplimiento estricto de la estructura de carpetas definida en `AGENTS.md` para el ESP32 (PlatformIO).
- RNF-02: **Idioma:** Documentación y descripciones de usuario en español; código fuente, nombres de clases/funciones y comentarios técnicos en formato estándar (inglés/estándar sin emojis).
- RNF-03: **Verificabilidad:** Compilación exitosa en PlatformIO (`pio run`) sin errores ni advertencias de sintaxis.

## Casos límite
- Recepción de credenciales BLE con cadenas vacías o incompletas (el sistema espera hasta recibir un SSID y contraseña válidos).
- Pérdida intermitente de la señal WiFi durante la consulta periódica (gestión de reconexión sin reinicio abrupto del microcontrolador).
- Respuesta HTTP con errores de parseo JSON (manejo de excepciones de deserialización con ArduinoJson sin interrumpir el bucle principal).

## Fuera de alcance
- Modificación de la lógica funcional del protocolo BLE o del comportamiento del servidor FastAPI (se mantiene idéntica a la versión probada en el sketch original).
- Integración de sensores físicos adicionales no especificados en el código original.

## Criterios de finalización
- Estructura de carpetas en `DispensadorESP32/src/` creada correctamente y separando responsabilidades (`config`, `drivers`, `services`, `tasks`, `main.cpp`).
- Código original de Arduino preservado intacto en `arduino/sketch_jul3a/sketch_jul3a.ino`.
- Compilación exitosa en PlatformIO (`pio run`) sin errores de compilación.

## Dudas abiertas
- Ninguna.
