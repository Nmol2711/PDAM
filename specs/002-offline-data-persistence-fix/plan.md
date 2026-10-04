# Plan Técnico: Corrección y Robustecimiento de Persistencia de Datos Offline en Isar

Este plan detalla la arquitectura técnica, componentes, funciones puras, algoritmos de almacenamiento en Isar, gestión de sincronización bidireccional, soporte offline para el dispensador y operación silenciosa en UI para cumplir con la especificación `002-offline-data-persistence-fix`, adhiriéndose estrictamente a la **Constitución de PDAM**.

---

## 1. Mapeo de Requisitos Funcionales (RF) a Componentes

| Requisito | Archivos / Componentes Afectados | Responsabilidad Técnica |
|---|---|---|
| **RF-01** (Persistencia local de mascotas) | `LocalPetDatasource`, `PetRepositoryImpl` | Almacena y persiste de forma atómica los datos de mascotas en el esquema Isar `LocalPet`. |
| **RF-02** (Lectura offline de mascotas) | `LocalPetDatasource`, `PetRepositoryImpl`, `PetBloc` | Lee y carga la lista de mascotas desde Isar en $\le$ 100 ms ante ausencia de red o reinicio. |
| **RF-03** (Persistencia y lectura de horarios) | `LocalScheduleDatasource`, `ScheduleRepositoryImpl`, `ScheduleBloc` | Garantiza escritura y recuperación en Isar de horarios de alimentación en $\le$ 100 ms. |
| **RF-04** (Registro y persistencia de logs) | `LocalLogDatasource`, `LogRepositoryImpl`, `LogBloc` | Persiste localmente en Isar los logs de actividad y dispensación para trazabilidad offline. |
| **RF-05** (Sincronización bidireccional) | `SyncService`, `SyncConflictResolver`, Repositorios | Sincroniza cambios pendientes de dominio al recuperar red mediante Last-Write-Wins (umbral 5 min, prioridad servidor). |
| **RF-06** (Creación optimista de horarios offline) | `ScheduleBloc`, `ScheduleRepositoryImpl`, `LocalScheduleDatasource` | Actualiza de forma optimista el BLoC y persiste localmente el horario manual sin requerir reinicio. |
| **RF-07** (Soporte offline dispensador y MAC) | `LocalDispenserDatasource`, `DispenserRepositoryImpl`, `LocalDispenser` | Intercepta `DioException` al registrar MAC, guarda en Isar con `isSynced = false` y marca para sincronización. |
| **RF-08** (Operación offline silenciosa en UI) | Vistas principales (`PetsView`, `ScheduleView`, `LogsView`, `RegisterDispenserView`), BLoCs | Suprime alertas intrusivas y errores de red al cargar datos exitosamente desde la caché local de Isar. |

---

## 2. Archivos a Crear o Modificar (Frontend Flutter)

### Capa de Datos (Data)
* **`app/app_movil_pdam/lib/core/offline/models/local_dispenser.dart`** *(Nuevo/Modificado)*: Esquema Isar para almacenar la configuración del dispensador y la dirección MAC offline con flag `isSynced`.
* **`app/app_movil_pdam/lib/features/dispenser/data/datasource/local/local_dispenser_datasource.dart`** *(Nuevo)*: Datasource local Isar para operaciones CRUD y persistencia de MAC/dispensador offline.
* **`app/app_movil_pdam/lib/features/dispenser/data/repositories_impl/dispenser_repository_impl.dart`** *(Modificado)*: Interceptación de `DioException`, almacenamiento local con `isSynced = false` y sincronización posterior.
* **`app/app_movil_pdam/lib/features/pets/data/datasource/local/local_schedule_datasource.dart`** *(Modificado)*: Transacciones atómicas y soporte para horarios creados offline.
* **`app/app_movil_pdam/lib/features/pets/data/repository_impl/schedule_repository_impl.dart`** *(Modificado)*: Escritura optimista e inmediata en Isar para horarios manuales.

### Capa de Presentación (BLoC y UI)
* **`app/app_movil_pdam/lib/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart`** *(Modificado)*: Emisión optimista de estado al crear horarios offline sin esperas de red.
* **`app/app_movil_pdam/lib/features/dispenser/presentation/bloc/dispenser_bloc.dart`** *(Modificado)*: Soporte offline para registro de MAC y manejo transparente de errores.
* **Vistas principales (`PetsView`, `ScheduleView`, `LogsView`, `RegisterDispenserView`)** *(Modificado)*: Supresión de Snackbars o alertas intrusivas de error de red cuando los datos se cargan correctamente de Isar.

### Capa Core (Offline y Sincronización)
* **`app/app_movil_pdam/lib/core/offline/isar_service.dart`** *(Modificado)*: Registro del esquema `LocalDispenserSchema`, manejo seguro de excepciones de almacenamiento y migración.
* **`app/app_movil_pdam/lib/core/offline/sync_service.dart`** *(Modificado)*: Sincronización de dispensadores/MAC pendientes junto con mascotas, horarios y logs.

---

## 3. Funciones Puras y Algoritmos

1. **`resolveConflict(LocalEntity local, RemoteEntity remote, int clockDriftThresholdMs)`**:
   * Compara timestamps UTC. Si diferencia $\le$ umbral (5 min), retorna la de mayor `updatedAt`. Si supera el umbral o hay colisión, retorna `remote` (prioridad servidor). Cubre **RF-05**.

2. **`isNetworkException(Object exception)`**:
   * Identifica si una excepción proviene de fallos de red (`DioException` con tipo connectionTimeout, sendTimeout, receiveTimeout, connectionError o status 5xx). Cubre **RF-07** y **RF-08**.

3. **`applyOptimisticScheduleCreation(List<Schedule> currentSchedules, Schedule newSchedule)`**:
   * Retorna una nueva lista con el horario insertado ordenadamente y sin duplicados, garantizando actualización inmediata en UI (BLoC). Cubre **RF-06**.

---

## 4. Arquitectura Limpia e Integración con UI

* **Separación Estricta (Constitución - Principio 3):** Las vistas no contienen lógica de red ni de base de datos; delegan exclusivamente en BLoCs y Casos de Uso.
* **Offline-First $\le$ 100 ms (RNF-02):** Lecturas directas desde Isar mediante índices optimizados.
* **Transparencia Silenciosa (RF-08):** Cuando Isar retorna datos válidos offline, los BLoCs emiten estados de éxito sin propagar avisos de red molestos.

---

## 5. Decisiones Técnicas y Alternativas Descartadas

1. **Decisión:** Interceptar `DioException` en el repositorio del dispensador para persistir la MAC localmente con `isSynced = false`.
   * *Alternativa descartada:* Lanzar excepción no controlada que crashea la vista de registro. (Descartada por violar la experiencia offline-first).
2. **Decisión:** Actualización optimista del BLoC de horarios antes de la respuesta de red.
   * *Alternativa descartada:* Esperar confirmación de la API para mostrar el horario en la UI. (Descartada por generar latencia perceptible e inconsistencia offline).

---

## 6. Estrategia de Tests (Modelo en V)

* **Pruebas Unitarias (Datasources & Repositories):** Validar CRUD en Isar para `LocalDispenser`, `LocalSchedule`, `LocalPet` y `LocalLog`.
* **Pruebas Unitarias (BLoCs):** Validar creación optimista en `ScheduleBloc` y manejo de `DioException` en `DispenserBloc`.
* **Pruebas de Integración:** Comprobar el flujo completo offline (crear horario, registrar MAC sin red, carga silenciosa desde Isar y sincronización posterior al reconectar).
