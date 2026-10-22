# Plan Técnico — Spec 009: Corrección y Validación Robusta de Credenciales WiFi y Sincronización en App y ESP32

## 1. Resumen de Arquitectura y Componentes Afectados

La presente spec aborda tres ejes críticos del sistema PDAM (Frontend Flutter, Backend FastAPI y Firmware ESP32) para garantizar la robustez, seguridad y trazabilidad en el aprovisionamiento y validación de redes WiFi, alineado estrictamente con `docs/constitution.md` y `AGENTS.md`:

1. **Frontend (Flutter + BLoC + `flutter_secure_storage` + Isar):**
   - **Capa de Datos (`features/dispensers/data/`):** Refactorización del almacenamiento local y remoto (`dispensers_local_datasource.dart`, `dispensers_repository_impl.dart`) para integrar `flutter_secure_storage` en el resguardo de credenciales y tokens sensibles, eliminando falsos errores de guardado.
   - **Capa de Presentación (`features/dispensers/presentation/`):** Actualización de `DispensersBloc`, `DispensersState`, `DispensersEvent` y la vista `WifiProvisioningPage` para reflejar de manera inmediata en el listado de dispositivos que las credenciales WiFi han sido registradas exitosamente.

2. **Firmware ESP32 (`DispensadorESP32/`):**
   - **Servicios de Red (`src/services/wifi_service.cpp` / `.h` y `src/services/api_service.cpp` / `.h`):**
     - Inclusión de la validación HTTP obligatoria (método GET al endpoint raíz `/` esperando código de estado `200`) para aprobar la conexión a la red WiFi.
     - Implementación de la rutina de limpieza automática del almacenamiento NVS (`Preferences`) en el arranque inicial tras una nueva carga de código o flasheo (`first_boot`).
   - **Tareas y Máquina de Estados (`src/tasks/dispenser_task.cpp` / `.h` y `src/main.cpp`):**
     - Integración del flujo de validación HTTP tras la conexión WiFi local (`WIFI_STA`), gestionando reintentos y fallback a aprovisionamiento BLE en caso de fallo (status != 200).
     - Verificación e inicialización limpia de NVS en `setup()` a través de `main.cpp`.

---

## 2. Algoritmos en Pseudocódigo

### A. Validación HTTP GET a `/` esperando Status 200 en ESP32 (`wifi_service.cpp`)
```cpp
bool WifiService::validateServerConnectivity(const String& serverHost) {
    HTTPClient http;
    String endpoint = String("http://") + serverHost + "/";
    http.begin(endpoint);
    http.setTimeout(4000); // Timeout de 4 segundos
    int httpCode = http.GET();
    http.end();
    
    // RF-02: Se aprueba la red únicamente si el servidor responde con 200 OK
    if (httpCode == 200) {
        return true;
    }
    return false;
}

bool WifiService::connectAndValidateWiFi(const String& ssid, const String& password, const String& serverHost) {
    WiFi.begin(ssid.c_str(), password.c_str());
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 25) {
        delay(500);
        attempts++;
    }
    
    if (WiFi.status() == WL_CONNECTED) {
        if (validateServerConnectivity(serverHost)) {
            saveCredentialsToNVS(ssid, password);
            return true;
        } else {
            WiFi.disconnect();
            return false; // Rechaza la red por fallo en validación HTTP
        }
    }
    return false;
}
```

### B. Limpieza de Credenciales en Inicialización NVS tras Flasheo (`wifi_service.cpp` / `main.cpp`)
```cpp
void WifiService::checkAndWipeNVSOnFirstBoot() {
    Preferences systemPrefs;
    systemPrefs.begin("pdam_system", false);
    bool isFirstBoot = systemPrefs.getBool("first_boot_flash", true);
    
    if (isFirstBoot) {
        // RF-03: Borrado limpio de almacenamiento interno NVS de credenciales
        Preferences wifiPrefs;
        wifiPrefs.begin("pdam_wifi", false);
        wifiPrefs.clear();
        wifiPrefs.end();
        
        systemPrefs.putBool("first_boot_flash", false);
    }
    systemPrefs.end();
}
```

---

## 3. Decisiones Técnicas y Alternativas Descartadas

* **Decisión 1:** Uso de `flutter_secure_storage` para el almacenamiento en la app móvil.
  - *Alternativa descartada:* Guardar credenciales en texto plano en Isar o SharedPreferences. Descartado por violar la constitución del proyecto (Protección de Datos Sensibles - RNF-02).
* **Decisión 2:** Validación HTTP obligatoria al endpoint raíz (`/`) devolviendo status `200` antes de aprobar el WiFi en el ESP32.
  - *Alternativa descartada:* Considerar válida la conexión tan pronto como `WiFi.status() == WL_CONNECTED`. Descartado porque el ESP32 puede estar conectado a una red cautiva o sin salida a internet hacia el backend, generando falsos positivos (RF-02).
* **Decisión 3:** Rutina automática de limpieza NVS mediante indicador `first_boot_flash` en `Preferences` al iniciar el ESP32.
  - *Alternativa descartada:* Requerir borrado manual mediante comandos seriales. Descartado por no ser amigable ni automatizable durante el flashear de desarrollo y producción (RF-03).

---

## 4. Estrategia de Tests y Trazabilidad (RF a Pruebas)

| Requisito Funcional | Componente Afectado | Tipo de Prueba | Herramienta / Framework | Caso de Prueba / Validación |
|---------------------|---------------------|----------------|--------------------------|-----------------------------|
| **RF-01** | App Móvil (`DispensersBloc`, `DispensersRepository`) | Prueba Unitaria / Widget | `flutter_test` | CP-01: Guardado seguro con `flutter_secure_storage` y actualización sin errores en UI. |
| **RF-02** | Firmware ESP32 (`WifiService`, `ApiService`) | Prueba de Integración / Hardware | PlatformIO Unit / Test Suite | CP-02: Validación HTTP GET a `/` exigiendo status 200 para confirmar la red. |
| **RF-03** | Firmware ESP32 (`WifiService`, `Preferences`) | Prueba Unitaria en Hardware | PlatformIO Test | CP-03: Borrado limpio de NVS ante reinicio posterior a flasheo (`first_boot_flash`). |
| **RNF-01/02**| App / ESP32 | Análisis estático y pruebas | `flutter analyze`, `pio run` | CP-04: Cero hardcoding de secretos y separación de Clean Architecture. |
| **RNF-03** | App Móvil | Inspección visual / Tests | `flutter_test` | CP-05: Mensajes de estado y UI en perfecto español. |
