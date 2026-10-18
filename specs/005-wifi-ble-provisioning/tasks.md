# Tareas — Spec 005: Aprovisionamiento WiFi por Bluetooth (BLE) para Dispensadores ESP32

- [x] **T1 [RF-09]: Backend — Definir modelos y esquemas Pydantic**
  - **Descripción:** Crear los esquemas de validación Pydantic para el registro de dispensadores y la solicitud de reseteo de credenciales WiFi (`reset-wifi`) en `api/app/schemas/dispenser.py`.
  - **Validación Constitución:** Alineado con Clean Architecture y principios de validación estricta de datos de la API.
  - **Hecho cuando:** Los esquemas Pydantic validan correctamente los datos de entrada y salida, y Pylint/Flake8 no reportan errores.

- [x] **T2 [RF-09]: Backend — Implementar servicio y endpoint FastAPI**
  - **Descripción:** Desarrollar `api/app/services/dispenser_service.py` y el endpoint `/api/v1/dispensers/{id}/reset-wifi` en el router de FastAPI para gestionar la orden de borrado de NVS y reinicio del dispensador. Incluir pruebas unitarias con `pytest`.
  - **Validación Constitución:** Cobertura obligatoria de pruebas unitarias en backend (Principio de Política de Tests).
  - **Hecho cuando:** Las pruebas de `pytest` para el endpoint pasan exitosamente (100% verde).

- [x] **T3 [RF-06, RF-07]: Hardware — Implementar gestión WiFi (2.4GHz) y NVS en ESP32**
  - **Descripción:** Desarrollar `arduino/sketch_jul3a/sketch_jul3a.ino` utilizando la biblioteca `Preferences.h` para el almacenamiento persistente de credenciales en la NVS y asegurando la conexión exclusiva a redes de **2.4GHz**.
  - **Validación Constitución:** Respeto estricto de las limitaciones técnicas del hardware ESP32 y código estructurado en C++.
  - **Hecho cuando:** El ESP32 lee y escribe correctamente credenciales en NVS y se conecta a redes de 2.4GHz con mecanismo de fallback ante fallos.

- [x] **T4 [RF-06, RF-07]: Hardware — Implementar servidor GATT BLE y máquina de estados**
  - **Descripción:** Desarrollar `arduino/sketch_jul3a/sketch_jul3a.ino` para inicializar el servidor GATT BLE con el prefijo `PDAM-Config-[MAC]`, recibir características de SSID y Password, aplicarlas al servicio WiFi, y apagar el radio BLE al conectar con éxito o reabrirlo si falla la conexión.
  - **Validación Constitución:** Fiabilidad y robustez del prototipo de hardware.
  - **Hecho cuando:** El servidor BLE anuncia correctamente el dispositivo, recibe credenciales, configura la NVS y apaga la radio Bluetooth al conectar al WiFi.

- [ ] **T5 [RF-06, RF-07]: Hardware — Pruebas unitarias de firmware ESP32**
  - **Descripción:** Configurar y ejecutar las pruebas unitarias y de compilación con PlatformIO (`pio test`) para los servicios WiFi y BLE del ESP32.
  - **Validación Constitución:** Principio de política de tests en todos los módulos (Backend, App y Hardware).
  - **Hecho cuando:** La compilación y las pruebas con PlatformIO completan sin errores.

- [x] **T6 [RF-01, RNF-01, RNF-02]: Frontend — Estructura Clean Architecture y GoRouter**
  - **Descripción:** Crear la estructura de carpetas para `app/app_movil_pdam/lib/features/dispensers/` (`domain`, `data`, `presentation`), definir entidades, contratos de repositorios, y registrar la nueva sección "Dispensadores" en `GoRouter`.
  - **Validación Constitución:** Arquitectura Limpia y separación estricta de responsabilidades.
  - **Hecho cuando:** La nueva ruta `/dispensers` es accesible desde la navegación principal y compila sin errores.

- [x] **T7 [RF-02, RF-02.1, RF-03, RF-05]: Frontend — Implementar servicio BLE de aprovisionamiento con verificación de estado, filtrado robusto y cancelación**
  - **Descripción:** Desarrollar `app/app_movil_pdam/lib/features/dispensers/data/services/ble_provisioning_service.dart` utilizando `flutter_blue_plus` para:
    1. **Verificar el estado del Bluetooth** (`FlutterBluePlus.adapterStateNow`) e indicar/solicitar su activación si está desactivado.
    2. **Filtrar robustamente** los dispositivos escaneados por el prefijo `PDAM-Config-*` (incluyendo variantes con corchetes, guiones y asteriscos).
    3. **Controlar la cancelación del escaneo en tiempo real** mediante `FlutterBluePlus.stopScan()`.
    4. Ejecutar la conexión GATT y la escritura de características de SSID y Password.
  - **Validación Constitución:** Código limpio, manejo robusto de excepciones de red/Bluetooth y nombres descriptivos en inglés técnico.
  - **Hecho когда:** El servicio BLE verifica el adaptador, ejecuta el escaneo filtrado, permite detenerlo fluidamente y transmite correctamente las credenciales.

- [x] **T8 [RF-02.1, RF-04, RF-08, RNF-04, RNF-05]: Frontend — Desarrollar UI de Dispensadores y Formulario BLE con advertencia 2.4GHz y control de cancelación**
  - **Descripción:** Desarrollar las vistas (`dispensers_page.dart`, `ble_scan_page.dart` con botón interactivo de parada/cancelación de escaneo, `wifi_provisioning_page.dart`) y el BLoC correspondiente (`dispenser_bloc.dart`). Asegurar que el formulario incluya una advertencia prominente de que **solo se soportan redes de 2.4GHz**, utilizando la paleta de colores global, temas Material Design 3 y textos en español.
  - **Validación Constitución:** Separación lógica-interfaz (cero lógica en vistas), uso de temas globales, textos en español, y diseño responsive.
  - **Hecho cuando:** La interfaz permite buscar, cancelar el escaneo en tiempo real, conectar y aprovisionar el dispensador mostrando claramente la advertencia de 2.4GHz.

- [x] **T9 [RNF-02, RNF-06]: Frontend — Persistencia Isar (Offline-First) y Pruebas Unitarias**
  - **Descripción:** Implementar la capa de datos local con Isar para almacenar dispensadores registrados y garantizar el funcionamiento Offline-First. Escribir pruebas unitarias y de widgets con `flutter_test` y `bloc_test`.
  - **Validación Constitución:** Arquitectura Offline-First y cobertura obligatoria de pruebas de frontend.
  - **Hecho cuando:** `flutter test` pasa al 100% (todos los tests del módulo de dispensadores en verde).

- [x] **T10 [General]: Verificación integral y validación de la Constitución PDAM**
  - **Descripción:** Ejecutar la suite completa de pruebas de la API (`pytest`), la aplicación móvil (`flutter test`) y verificar el cumplimiento de todas las reglas de la constitución y AGENTS.md. Actualizar `MEMORY.md`.
  - **Validación Constitución:** Trazabilidad estricta bajo el Modelo en V y verificación de todos los principios innegociables.
  - **Hecho cuando:** Todos los tests pasan correctamente, `MEMORY.md` está actualizado y la spec 005 está lista para aprobación final de código.
