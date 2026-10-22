# Plan Técnico — Spec 010: Corrección Crítica de Aprovisionamiento, Persistencia Isar, NVS, Filtrado y Ciclo BLE

## 1. Arquitectura y Componentes Afectados

1. **Frontend (Flutter + Isar + BLoC + BleProvisioningService):**
   - `app/app_movil_pdam/lib/features/dispensers/data/datasources/dispensers_local_datasource.dart`: Gestión de base de datos Isar con operaciones de upsert para evitar `IsarError: Unique index violated`.
   - `app/app_movil_pdam/lib/features/dispensers/data/repositories/dispensers_repository_impl.dart`: Implementación de consultas filtrando estrictamente por `petId != null`.
   - `app/app_movil_pdam/lib/features/dispensers/presentation/bloc/dispensers_bloc.dart`: Gestión de estados y reactividad para actualizar el estado visual de credenciales WiFi y listados.
   - `app/app_movil_pdam/lib/features/dispensers/data/services/ble_provisioning_service.dart`: Control del ciclo de vida del escáner BLE, limpieza de streams y reinicio de conexiones.
   - `app/app_movil_pdam/lib/features/dispensers/presentation/views/ble_scan_page.dart`: Interfaz de usuario para reintentar escaneos y mostrar estatus WiFi.

2. **Firmware ESP32 (C++):**
   - `DispensadorESP32/src/services/wifi_service.cpp` (y `src/main.cpp`): Rutina de borrado NVS infalible basada en la detección de cambio de build (`__DATE__ __TIME__`).

---

## 2. Algoritmos en Pseudocódigo

### A. Operación de Upsert en Isar (`DispensersLocalDatasource`)
```dart
Future<void> saveOrUpdateDispenser(LocalDispensers dispenser) async {
  await isar.writeTxn(() async {
    final existing = await isar.localDispensers
        .filter()
        .macAddressEqualTo(dispenser.macAddress)
        .or()
        .idEqualTo(dispenser.id)
        .findFirst();
        
    if (existing != null) {
      dispenser.internalId = existing.internalId;
    }
    await isar.localDispensers.put(dispenser);
  });
}
```

### B. Filtrado Estricto por `petId != null`
```dart
Future<List<DispenserEntity>> getAssociatedDispensers() async {
  final localList = await isar.localDispensers
      .filter()
      .petIdIsNotNull()
      .findAll();
  return localList.map((e) => e.toEntity()).toList();
}
```

### C. Reinicio de Escáner BLE (`BleProvisioningService`)
```dart
Future<void> restartScan() async {
  await _scanSubscription?.cancel();
  _scanSubscription = null;
  if (_isScanning) {
    await FlutterBluePlus.stopScan();
    _isScanning = false;
  }
  _devicesController.add([]);
  await startScan();
}
```

### D. Detección de Build y Borrado NVS en ESP32 (`wifi_service.cpp`)
```cpp
void checkAndClearNvsOnNewBuild() {
    Preferences prefs;
    prefs.begin("sys_meta", false);
    String lastBuild = prefs.getString("build_stamp", "");
    String currentBuild = String(__DATE__) + " " + String(__TIME__);
    
    if (lastBuild != currentBuild) {
        Preferences wifiPrefs;
        wifiPrefs.begin("wifi_config", false);
        wifiPrefs.clear();
        wifiPrefs.end();
        
        prefs.putString("build_stamp", currentBuild);
    }
    prefs.end();
}
```

---

## 3. Decisiones Técnicas y Alternativas Descartadas

- **Decisión 1:** Implementación de Upsert basado en clave única (MAC/ID) en Isar.
  - *Alternativa descartada:* Eliminar toda la tabla e insertar todo de nuevo. Descartado por destruir datos offline pendientes de sincronización.
- **Decisión 2:** Filtrado a nivel de consulta Isar (`petIdIsNotNull()`).
  - *Alternativa descartada:* Filtrar en memoria en el BLoC o UI. Descartado por ineficiencia con grandes volúmenes y violación de Clean Architecture.
- **Decisión 3:** Cancelación explícita de suscripciones BLE antes de reiniciar el escaneo.
  - *Alternativa descartada:* Forzar reinicio de la app móvil. Descartado por pésima experiencia de usuario.

---

## 4. Estrategia de Tests y Trazabilidad

| Requisito Funcional | Componente Afectado | Tipo de Prueba | Herramienta / Framework | Criterio de Validación |
|---------------------|---------------------|----------------|--------------------------|------------------------|
| **RF-01** | `DispensersLocalDatasource` | Unitaria | `flutter_test` | Upsert sin error `IsarError: Unique index violated`. |
| **RF-02** | `wifi_service.cpp` | Hardware / PlatformIO | PlatformIO | Borrado infalible de NVS en nuevo build. |
| **RF-03** | `DispensersRepositoryImpl` | Unitaria / Widget | `flutter_test` | Retorna únicamente dispensadores con `petId != null`. |
| **RF-04** | `DispensersBloc` / UI | Widget Test | `flutter_test` | Actualización reactiva del estado de credenciales WiFi. |
| **RF-05** | `BleProvisioningService` | Unitaria | `flutter_test` | Reinicio limpio del escáner BLE sin bloqueos. |
