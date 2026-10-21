# Plan 008 — Migración del Código de Arduino Sketch a PlatformIO para ESP32 con Arquitectura Modular

## Estructura de Archivos y Responsabilidades (`DispensadorESP32/src/`)

Para cumplir con la arquitectura modular de hardware definida en `AGENTS.md` (Sección 3) y la constitución del proyecto (`docs/constitution.md`), el código del sketch monolítico se refactorizará en los siguientes módulos bajo `DispensadorESP32/src/`:

1. **`config/config.h`**:
   - Constantes de configuración globales.
   - UUIDs del servicio y características BLE (`SERVICE_UUID`, `CHARACTERISTIC_UUID_SSID`, `CHARACTERISTIC_UUID_PASS`).
   - Pin del servomotor (`servoPin = 4`).
   - URL base de la API y constantes de temporización.

2. **`drivers/servo_driver.h` y `drivers/servo_driver.cpp`**:
   - Inicialización de temporizadores PWM con `ESP32PWM::allocateTimer()`.
   - Control del servomotor MG966R (`myServo`), adjuntando al pin 4 y ejecutando la rotación para dispensación (10 segundos).

3. **`services/wifi_service.h` y `services/wifi_service.cpp`**:
   - Gestión de NVS mediante la librería `Preferences` (`pdam_wifi`).
   - Conexión y gestión de la red WiFi 2.4GHz en modo `WIFI_STA`.
   - Configuración y levantamiento del servidor GATT BLE (`PDAM-Config-<MAC>`) para el aprovisionamiento de credenciales desde la app Flutter.

4. **`services/api_service.h` y `services/api_service.cpp`**:
   - Cliente HTTP (`HTTPClient`) para consultar el endpoint del backend FastAPI con la dirección MAC del dispositivo.
   - Parseo de respuestas JSON utilizando `ArduinoJson` para evaluar la clave booleana `serve`.

5. **`tasks/dispenser_task.h` y `tasks/dispenser_task.cpp`**:
   - Máquina de estados del dispositivo (`STATE_CHECK_NVS`, `STATE_CONNECT_WIFI`, `STATE_BLE_PROVISIONING`, `STATE_NORMAL`).
   - Lógica de temporización no bloqueante basada en `millis()` (intervalo de 20 segundos) para consultas periódicas y reconexión WiFi robusta.

6. **`main.cpp`**:
   - Punto de entrada principal limpio que inicializa la consola serial, lee la MAC por eFuse, inicializa el driver del servo y ejecuta la máquina de estados en el bucle principal (`loop`).

## Mapeo Exacto del Código de Arduino (`sketch_jul3a.ino`) a los Nuevos Módulos

| Componente en Sketch Monolítico (`sketch_jul3a.ino`) | Nuevo Módulo / Archivo en PlatformIO |
| :--- | :--- |
| `#include` de librerías y UUIDs BLE | `config/config.h` |
| Inicialización de Servo, pines y PWM | `drivers/servo_driver.cpp` / `.h` |
| `Preferences` (NVS) y `WiFi` / BLE Server | `services/wifi_service.cpp` / `.h` |
| `HTTPClient` y `StaticJsonDocument` | `services/api_service.cpp` / `.h` |
| `enum DeviceState`, lógica de estados y `millis()` | `tasks/dispenser_task.cpp` / `.h` |
| `setup()` y `loop()` | `main.cpp` |

## Cobertura de Requisitos Funcionales (RF)

- **RF-01**: Cubierto al mantener intacto `arduino/sketch_jul3a/sketch_jul3a.ino`.
- **RF-02**: Cubierto por la organización modular en `DispensadorESP32/src/` (`config/`, `drivers/`, `services/`, `tasks/`, `main.cpp`).
- **RF-03**: Cubierto en `main.cpp` y `servo_driver.cpp` (lectura eFuse MAC y asignación de temporizadores PWM en Pin 4).
- **RF-04 & RF-05**: Cubierto en `wifi_service.cpp` (verificación NVS, conexión WiFi 2.4GHz y aprovisionamiento GATT BLE).
- **RF-06 & RF-07**: Cubierto en `api_service.cpp` y `dispenser_task.cpp` (consulta HTTP GET periódica no bloqueante y activación de servo por 10s cuando `serve == true`).
- **RF-08**: Cubierto en `dispenser_task.cpp` (gestión de pérdida de señal WiFi y reintento de reconexión / fallback a BLE).

## Decisiones y Alternativas Descartadas

- **Decisión**: Mantener bibliotecas estándar (`WiFi`, `HTTPClient`, `ESP32Servo`, `Preferences`, `BLEDevice`, `ArduinoJson`, `esp_mac`) sin introducir dependencias adicionales.
  - *Alternativa descartada*: Reescribir el stack de red con sockets de bajo nivel (descartado por innecesario y propenso a errores).
- **Decisión**: Estructura de carpetas explícita en `src/` (`config`, `drivers`, `services`, `tasks`) acorde a `AGENTS.md`.
  - *Alternativa descartada*: Mantener todo en un solo archivo `.ino` o `.cpp` (descartado por violar los estándares de mantenibilidad y arquitectura del proyecto).

## Estrategia de Tests y Validación

Dado que el firmware corre en microcontrolador físico ESP32, la validación se realiza mediante:
1. **Verificación de Compilación estricta**: Ejecución exitosa de `pio run` en PlatformIO para asegurar que todos los headers (`.h`) y archivos fuente (`.cpp`) enlazan correctamente sin errores de compilación ni advertencias.
2. **Resguardo Intacto**: Comprobación de que el archivo `arduino/sketch_jul3a/sketch_jul3a.ino` no ha sido modificado.
