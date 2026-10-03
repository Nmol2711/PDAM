# Plan Técnico: Sincronización Offline Avanzada y Gestión de Sesión

Este plan detalla la arquitectura técnica, componentes, funciones puras, algoritmos de resolución, gestión de interfaz y estrategia de pruebas para cumplir con la especificación `001-arquitecture-offline`, adhiriéndose estrictamente a la **Constitución de PDAM**.

---

## 1. Mapeo de Requisitos Funcionales (RF) a Componentes

| Requisito | Archivos / Componentes Afectados | Responsabilidad Técnica |
|---|---|---|
| **RF-01** (Login Online) | `AuthRemoteDatasource`, `AuthRepositoryImpl`, `AuthBloc` | Valida credenciales contra la API FastAPI y almacena de forma segura las credenciales y el token usando `flutter_secure_storage`. |
| **RF-02** (Login Offline) | `AuthLocalDatasource`, `AuthRepositoryImpl`, `AuthBloc` | Intercepta fallos de red o timeout (10s), valida credenciales contra `flutter_secure_storage` y permite acceso sin conexión manteniendo UI idéntica. |
| **RF-03** (Restricción cambio credenciales) | `AuthBloc`, `AuthRepositoryImpl` | Valida obligatoriamente conectividad antes de permitir operaciones de cambio de contraseña o credenciales. |
| **RF-04** (Sincronización temporal) | `SyncService` (nuevo), `IsarService`, Repositorios de Dominio | Compara marcas de tiempo locales y remotas aplicando el algoritmo con umbral de 5 minutos y prioridad al servidor. |
| **RF-05** (Gestión de fallos de sync) | `SyncService`, `ApiClient` / Interceptores | Reintenta cambios fallidos en el servidor y adopta el registro remoto ante persistencia de errores. |

---

## 2. Archivos a Crear o Modificar

### Backend (API FastAPI)
* **`api/app/schemas/sync_schema.py`** *(Nuevo)*: Define esquemas Pydantic para intercambio de marcas de tiempo y lotes de sincronización bidireccional.
* **`api/app/services/sync_service.py`** *(Nuevo)*: Lógica de backend para procesar lotes de sincronización y resolución de colisiones según la regla del registro más reciente.

### Frontend (Flutter App)
* **`app/app_movil_pdam/lib/core/offline/sync_service.dart`** *(Nuevo)*: Servicio central de sincronización en segundo plano que detecta conectividad y ejecuta la fusión bidireccional.
* **`app/app_movil_pdam/lib/features/auth/data/datasources/local/auth_local_datasource.dart`** *(Modificado)*: Gestión de almacenamiento y recuperación cifrada de credenciales vía `flutter_secure_storage`.
* **`app/app_movil_pdam/lib/features/auth/data/repositories_impl/auth_repositories_impl.dart`** *(Modificado)*: Orquestador de autenticación online/offline con timeout e interceptación de fallos de red.
* **`app/app_movil_pdam/lib/features/auth/presentation/bloc/auth_bloc.dart`** *(Modificado)*: Manejo de estados de autenticación sin conexión garantizando transparencia visual para el usuario.

---

## 3. Funciones Puras de Lógica (Dominio)

Para garantizar la pureza de la lógica de negocio y evitar efectos secundarios:

1. **`resolveConflict(LocalEntity local, RemoteEntity remote, int clockDriftThresholdMs)`**:
   * *Entrada*: Objeto local, objeto remoto y umbral de desfase (5 minutos = 300,000 ms).
   * *Salida*: Objeto ganador (`Entity`).
   * *Lógica*: Compara `abs(local.updatedAt - remote.updatedAt)`. Si el desfase es $\le$ umbral, retorna el de mayor `updatedAt`. Si el desfase supera el umbral o hay colisión exacta, retorna `remote` (prioridad servidor). Cubre **RF-04**.

2. **`validateCredentialsCache(String inputEmail, String inputPassword, String cachedEmail, String encryptedPasswordHash)`**:
   * *Entrada*: Credenciales ingresadas y credenciales seguras cacheadas.
   * *Salida*: Bolean (`true` si coinciden). Cubre **RF-02**.

3. **`isConnectionTimeout(Object exception)`**:
   * *Entrada*: Excepción de red de Dio.
   * *Salida*: Bolean indicando si fue timeout (10s) o fallo de red total. Cubre **RF-02**.

---

## 4. Algoritmo de Sincronización en Pseudocódigo

```text
FUNCTION synchronizeData():
    IF NOT networkChecker.hasConnection() THEN
        RETURN SyncResult.offline()
    END IF

    localPendingItems = isar.getUnsyncedItems()
    remoteItems = api.fetchRemoteChanges(lastSyncTimestamp)

    FOR item IN localPendingItems:
        remoteMatch = findItem(remoteItems, item.id)
        if remoteMatch EXISTS:
            winner = resolveConflict(item, remoteMatch, 300000) // 5 min umbral
            if winner IS remoteMatch:
                isar.saveLocal(remoteMatch)
            else:
                success = api.pushToServer(item)
                if NOT success:
                    // Fallo en servidor: adopta registro del servidor (RF-05)
                    serverItem = api.fetchItem(item.id)
                    isar.saveLocal(serverItem)
                end if
            end if
        else:
            success = api.pushToServer(item)
            if NOT success THEN
                MARK item AS syncFailed
            END IF
        end if
    END FOR

    FOR remoteItem IN remoteItems:
        localItem = isar.getLocal(remoteItem.id)
        if localItem NOT EXISTS or remoteItem.updatedAt > localItem.updatedAt:
            isar.saveLocal(remoteItem)
        end if
    END FOR

    updateLastSyncTimestamp()
    RETURN SyncResult.success()
END FUNCTION
```
*Cubre **RF-04** y **RF-05**.*

---

## 5. Integración con la Interfaz (UI)

* **Separación Lógica-Interfaz (Constitución - Principio 3):** Ninguna vista contiene lógica de sincronización ni cálculos de conflictos.
* **Manejo en BLoC:** `AuthBloc` y `SyncBloc` (o cubits asociados) emiten estados reactivos (`AuthAuthenticated`, `AuthOfflineAuthenticated`, `SyncInProgress`, `SyncSynced`).
* **Pintado en Pantalla:** Las pantallas (`LoginView`, `DashboardView`, `PetsView`, etc.) consumen los estados mediante `BlocBuilder`. Ante ausencia de red o inicio offline, muestran indicadores sutiles de modo offline ("Modo sin conexión") sin alterar la funcionalidad ni bloquear la interacción del usuario (**RF-02**, **RNF-01**).

---

## 6. Decisiones Técnicas y Alternativas Descartadas

1. **Decisión:** Uso de `flutter_secure_storage` para credenciales offline y **Isar** para datos locales relacionales.
   * *Alternativa descartada:* Guardar credenciales en texto plano en SharedPreferences o SQLite sin cifrar. (Descartada por vulnerar la Constitución - Principio 5 y RNF-02).
2. **Decisión:** Priorizar el servidor ante desfases horarios mayores a 5 minutos o colisiones exactas.
   * *Alternativa descartada:* Resolución manual interactiva por parte del usuario. (Descartada por complejidad innecesaria para un prototipo universitario y por la regla de Fuera de Alcance).

---

## 7. Estrategia de Tests (Modelo en V)

Conforme a la **Constitución de PDAM (Principio 2 y 4)**:

* **Pruebas Unitarias (Backend):** Tests en `pytest` (`api/tests/`) para validar las funciones puras de resolución de conflictos por marcas de tiempo y manejo de umbrales.
* **Pruebas Unitarias (Frontend):** Tests en `flutter test` para `resolveConflict` y validación de credenciales cacheadas.
* **Pruebas de Integración:** Verificación del flujo completo de inicio de sesión con timeout de 10s simulando caída de red, y sincronización bidireccional en Isar tras restablecer conectividad.
