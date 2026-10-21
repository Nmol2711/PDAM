# Tasks 008 — Migración del Código de Arduino Sketch a PlatformIO para ESP32

- [x] **T1. Creación de la estructura de carpetas modular en `DispensadorESP32/src/`.** RF-02, RNF-01
  - Hecho cuando: Se han creado los directorios `config/`, `drivers/`, `services/` y `tasks/` dentro de `DispensadorESP32/src/`.

- [x] **T2. Migración del módulo de configuración (`config/config.h`).** RF-02, RNF-02
  - Hecho cuando: Se crea `config/config.h` conteniendo los UUIDs de BLE, constantes de pines (`servoPin = 4`) y configuraciones globales extraídas del sketch original.

- [x] **T3. Migración del driver del servomotor (`drivers/servo_driver.h` y `drivers/servo_driver.cpp`).** RF-03, RNF-02
  - Hecho cuando: Se implementan las funciones de inicialización de temporizadores PWM, asociación al Pin 4 y control del servomotor MG966R en la capa de drivers.

- [x] **T4. Migración de los servicios de conectividad y almacenamiento (`services/wifi_service.h`, `services/wifi_service.cpp`, `services/api_service.h`, `services/api_service.cpp`).** RF-04, RF-05, RF-07, RNF-02
  - Hecho cuando: Se encapsulan la gestión de NVS (`Preferences`), la conexión WiFi 2.4GHz, el servidor BLE de aprovisionamiento con callbacks y el cliente HTTP con `ArduinoJson`.

- [x] **T5. Migración de la máquina de estados y temporizadores (`tasks/dispenser_task.h`, `tasks/dispenser_task.cpp` y actualización de `main.cpp`).** RF-03, RF-06, RF-07, RF-08, RNF-02
  - Hecho cuando: Se implementa la máquina de estados (`STATE_CHECK_NVS`, `STATE_CONNECT_WIFI`, `STATE_BLE_PROVISIONING`, `STATE_NORMAL`), el temporizador no bloqueante basado en `millis()` y el punto de entrada limpio en `main.cpp`.

- [x] **T6. Verificación de compilación en PlatformIO y validación del respaldo.** RF-01, RNF-03
  - Hecho cuando: Se ejecuta `pio run` obteniendo compilación exitosa sin errores y se verifica que `arduino/sketch_jul3a/sketch_jul3a.ino` permanece intacto.
