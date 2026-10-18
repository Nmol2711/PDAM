# Plan Técnico — Spec 005: Aprovisionamiento WiFi por Bluetooth (BLE) para Dispensadores ESP32

## 1. Resumen de Arquitectura y Componentes Afectados

La implementación del aprovisionamiento WiFi por BLE abarca tres capas principales del sistema PDAM, respetando estrictamente la Clean Architecture, el enfoque Offline-First y las directrices de `docs/constitution.md` y `AGENTS.md`:

1. **Backend (FastAPI + SQLite):**
   - **Componentes afectados:** `api/app/services/dispenser_service.py`, `api/app/routers/dispenser.py` (o equivalente), modelos ORM y esquemas Pydantic.
   - **Responsabilidad:** Gestionar el registro de dispensadores y exponer un endpoint seguro (`/api/v1/dispensers/{id}/reset-wifi`) para solicitar el reseteo de credenciales en la NVS del dispositivo y forzar su reinicio en modo aprovisionamiento BLE.

2. **Hardware (ESP32 / PlatformIO):**
   - **Componentes afectados:** `arduino/sketch_jul3a/src/services/wifi_service.cpp`, `arduino/sketch_jul3a/src/services/ble_service.cpp`, `arduino/sketch_jul3a/src/main.cpp`.
   - **Responsabilidad:** Gestionar la conectividad WiFi estrictamente en **2.4GHz**, almacenar credenciales en la memoria no volátil (**NVS** vía `Preferences.h`), exponer un servidor GATT BLE (`PDAM-Config-[MAC]`) para recibir SSID y Password, y apagar el radio Bluetooth una vez establecida la conexión WiFi exitosa.

3. **Frontend (Flutter + BLoC + GoRouter + Isar):**
   - **Componentes afectados:** `app/app_movil_pdam/lib/features/dispensers/` (Clean Architecture: `domain`, `data`, `presentation`), integración en `GoRouter`, y almacenamiento local con Isar (`Offline-First`).
   - **Responsabilidad:** Proveer una sección dedicada "Dispensadores" en la navegación principal, verificar el estado del Bluetooth (`FlutterBluePlus.adapterStateNow`), escanear dispositivos BLE cercanos con filtrado robusto por prefijo `PDAM-Config-*`, permitir la cancelación del escaneo en tiempo real (`FlutterBluePlus.stopScan()`), mostrar advertencias técnicas sobre la limitación de redes de **2.4GHz**, enviar credenciales mediante características GATT, y reflejar el estado de conexión.

---

## 2. Fases de Implementación

### Fase 1: Backend (FastAPI)
- **Modelos y Esquemas:** Creación/Actualización de esquemas Pydantic para la entidad Dispensador y el comando de reseteo WiFi.
- **Servicios y Endpoints:** Implementación de la lógica de negocio en `dispenser_service.py` y el endpoint protegido para ordenar el reseteo de credenciales NVS.
- **Funciones puras / validaciones:** Validación estricta de parámetros de entrada en esquemas Pydantic.

### Fase 2: Hardware (ESP32)
- **Servicio WiFi (2.4GHz):** Configuración de la interfaz WiFi limitándose a la banda de 2.4GHz y gestión de reconexión/fallback.
- **NVS (Preferences):** Lectura y escritura segura de credenciales en memoria flash.
- **Servidor GATT BLE:** Inicialización del servicio BLE con UUIDs definidos, emisión de beacons con prefijo `PDAM-Config-[MAC]`, recepción de características de SSID y Password, y desactivación automática del radio BLE al conectar con éxito al WiFi.

### Fase 3: Frontend (Flutter)
- **Estructura Clean Architecture (`features/dispensers/`):**
  - `domain/entities/dispenser.dart`, `domain/repositories/dispenser_repository.dart`, `domain/usecases/`
  - `data/models/dispenser_model.dart`, `data/datasources/dispenser_local_datasource_isar.dart`, `data/datasources/dispenser_remote_datasource.dart`, `data/repositories/dispenser_repository_impl.dart`, `data/services/ble_provisioning_service.dart` (incluyendo verificación de estado de Bluetooth con `FlutterBluePlus.adapterStateNow`, filtrado robusto por prefijo `PDAM-Config-*`, y control de cancelación mediante `FlutterBluePlus.stopScan()`).
  - `presentation/bloc/dispenser_bloc.dart`, `presentation/views/dispensers_page.dart`, `presentation/views/ble_scan_page.dart` (con botón de parada/cancelación en tiempo real), `presentation/views/wifi_provisioning_page.dart`
- **Integración GoRouter:** Añadir la ruta `/dispensers` y sus subrutas en la navegación principal.
- **Offline-First con Isar:** Persistencia local de dispensadores registrados para disponibilidad sin conexión.
- **UI & Tema:** Uso de paleta de colores global, componentes limpios (sin lógica de negocio en vistas), advertencia clara de 2.4GHz, y textos completamente en español.

---

## 3. Decisiones Técnicas y Alternativas Descartadas

* **Decisión 1:** Uso de `flutter_blue_plus` para la gestión BLE en Flutter.
  - *Alternativa descartada:* Bibliotecas BLE discontinuadas o propietarias complejas. `flutter_blue_plus` ofrece mantenimiento activo, soporte multiplataforma robusto y control preciso de características GATT, así como manejo nativo de estado de adaptador (`adapterStateNow`), parada de escaneo (`stopScan()`) y filtrado por nombre publicitado.
* **Decisión 2:** Transmisión de credenciales WiFi en texto plano sobre canal GATT BLE local.
  - *Alternativa descartada:* Cifrado asimétrico complejo en microcontrolador de recursos limitados (ESP32) para aprovisionamiento inicial. Se justifica por la restricción física obligatoria (el usuario debe estar a menos de 5 metros del dispositivo), cumpliendo con el estándar de la industria IoT (Wi-Fi Provisioning BLE).
* **Decisión 3:** Restricción estricta a redes de 2.4GHz en el ESP32 y advertencia prominente en la App.
  - *Alternativa descartada:* Intentar autodetectar bandas o ignorar la limitación física del chip ESP32 (que no soporta radiofrecuencia de 5GHz), lo que provocaría fallos silenciosos de conexión. La advertencia explícita previene frustración en el usuario.

---

## 4. Estrategia de Pruebas y Trazabilidad (RF a Pruebas)

| Requisito Funcional | Componente Afectado | Tipo de Prueba | Herramienta / Framework | Caso de Prueba Asociado |
|---------------------|---------------------|----------------|--------------------------|-------------------------|
| **RF-01** | Frontend (GoRouter / Navigation) | Prueba de Widget / Integración | `flutter test` | CP-05 |
| **RF-02** | Frontend (BLE Service / BLoC - Estado BT & Filtrado `PDAM-Config-*`) | Prueba Unitaria / Mock BLE | `flutter_test`, Mockito | CP-01 |
| **RF-02.1**| Frontend (BLE Service / UI - Cancelación de Escaneo) | Prueba de Widget / Integración | `flutter test` | CP-01 |
| **RF-03** | Frontend (BLE Service) | Prueba de Integración / Mock | `flutter test` | CP-01 |
| **RF-04** | Frontend (UI / Provisioning View) | Prueba de Widget | `flutter test` | CP-02 |
| **RF-05** | Frontend (BLE Service) | Prueba de Integración | `flutter test` | CP-03 |
| **RF-06** | Hardware (ESP32 WiFi & NVS) | Prueba de Hardware | PlatformIO (`pio test`) | CP-03 |
| **RF-07** | Hardware (ESP32 State Machine) | Prueba de Hardware | PlatformIO (`pio test`) | CP-04 |
| **RF-08** | Frontend (BLoC / UI State) | Prueba Unitaria (BLoC) | `bloc_test`, `flutter test` | CP-03, CP-04 |
| **RF-09** | Backend (FastAPI Endpoint) | Prueba de API / Backend | `pytest` | CP-06 |
| **RNF-02** | Frontend (Isar Local Storage) | Prueba Unitaria / Integración | `flutter test` | CP-05 |
