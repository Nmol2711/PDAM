# Plan Técnico: Dirección MAC Única por Dispensador y Aviso Reutilizable al Usuario

Plan técnico de `specs/003-mac-unica-dispensador/spec.md`, adherence a `docs/constitution.md`, a `AGENTS.md` (arquitectura limpia, offline-first, tema global, español) y a las lecciones de `MEMORY.md`.

---

## 0. Respuestas a las dudas abiertas (decisiones tomadas)

### DO-1. Dispensadores pendientes de versiones previas → **limpiar localmente al consultar, con registro en log** (decisión del usuario)

Se **eliminan de Isar** en el momento en que el usuario consulta sus dispensadores. No se conservan como lectura, no se incluyen en ningún lote de sincronización, no generan ninguna marca de pendiente y **no se muestran**. Por cada registro eliminado se escribe en el log local la línea exacta:

```
dispensador huérfano eliminado - MAC:<mac_address>
```

Identificación del huérfano: el predicado puro `isLegacyLocalOrphan({required int? remoteId, required bool isSynced})` → `remoteId == null && !isSynced` (ver sección 3.4).

Por qué se limpia en vez de conservar:

1. **Conservar no aporta nada utilizable.** Un huérfano nunca pasó por la validación de unicidad del servidor: su MAC pudo ser inválida o haber sido reasignada a otra persona. Mostrarlo como un dispensador válido mente sobre el estado real del vínculo.
2. **No se puede sincronizar (RF-15).** `POST /sync` (`process_sync_batch`) no crea ni valida registros; el alta real solo pasa por `POST /dispensers`, que exige la clave secreta del QR y es el único camino que devuelve un conflicto accionable (RF-03, RF-10). Un huérfano enviado por el canal de sincronización crearía un dispensador fuera de ese camino.
3. **No se puede volver a validar.** La credencial `remoteId` que falta es irrecuperable: sin ella no hay forma de preguntar al servidor por ese registro. El camino correcto es que el usuario registre de nuevo el dispensador **con conexión**, que sí valida (RF-13).
4. **La limpieza es quirúrgica, no destructiva.** Solo se borran filas de `localDispensers` que cumplen el predicado; nunca se toca `localPets`, `localSchedules`, `localLogs` ni el almacenamiento seguro de sesión (RF-20). Esto respeta `MEMORY.md` ("nunca vaciar bases de datos locales") y la arquitectura Offline-First de `AGENTS.md`, que siguen intactas para todo lo demás.

Cuándo se ejecuta exactamente: dentro del datasource local (`LocalDispenserDatasourceImpl.getLocalDispenserByPet`), que es el punto por el que la app lee los dispensadores del usuario desde la pantalla de detalle de la mascota, tanto con conexión como sin ella (`getDispenserByPet` cae a la fuente local cuando el servidor no responde). Así la limpieza:

* ocurre también **offline**, donde el huérfano es más probable que se muestre;
* no requiere ninguna pantalla nueva ni ninguna llamada de red;
* cubre por construcción la futura "lista de dispensadores del usuario", porque ambas lecturas pasan por el mismo datasource local.

Secuencia dentro del método (sección 3.4): **primero** se consultan y eliminan los huérfanos (con log), **después** se lee el dispensador solicitado. Por eso un huérfano consultado para esa mascota devuelve `null` en lugar de un registro no validado (RF-19).

Detalle de coste: la limpieza hace una consulta de solo lectura (`remoteIdIsNull() AND isSyncedEqualTo(false)`) y solo abre una transacción de escritura si hay huérfanos; en el caso normal no escribe nada (CL-18).

*Alternativas descartadas:* *(a) Conservar como lectura local*, descartada por los puntos 1 y 3; *(b) intentar sincronizarlos*, descartada por el punto 2 y por RF-15; *(c) vaciar toda la colección `localDispensers` o llamar a `IsarService.clearAllData()`*, descartada por RF-20 y por la lección registrada en `MEMORY.md`; *(d) añadir un campo booleano `isLegacyOrphan` a `LocalDispenser`*, descartada porque exige regenerar `local_dispenser.g.dart` con `build_runner` y una migración de esquema Isar (cambio del formato de datos guardados → requiere aprobación según `AGENTS.md`) sin aportar información que el predicado `remoteId == null && !isSynced` ya da: al eliminarse el camino que crea registros pendientes (RF-15), ese predicado no puede volver a cumplirse por registros nuevos.

### DO-2. Formato canónico de la MAC → **texto original + columna normalizada autoritativa** (enfoque aprobado por el usuario)

- `dispensers.mac_address` conserva **el texto recibido** tal como lo introdujo o escaneó el usuario. No cambia lo que se ve en la app ni lo que devuelve la API.
- `dispensers.mac_normalized` almacena la forma canónica (12 hex, sin separadores, mayúsculas) y lleva **índice único**. Es el único campo usado para comparar y para la garantía de unicidad.

Por qué:

1. **La garantía de RF-01/RF-07 la da el índice único, no el `WHERE`.** Una comparación por texto es frágil por definición (es el defecto que esta spec corrige); con columna normalizada e índice único, dos peticiones concurrentes con la misma MAC se resuelven en la base de datos y solo una gana.
2. **El ESP32 manda la MAC con su propio formato** en `GET /dispensers/check-taks/{address_mac}`. Normalizar en el servidor mantiene el firmware intacto (fuera de alcance) y cumple RF-08 hacia el hardware.
3. **No se reescribe lo que ya funciona**: la validación de alta actual ya obligaba a mayúsculas con dos puntos, así que el backfill no cambia valores visibles; solorellena la columna nueva.
4. **Forzar un formato único guardado** obligaría a reescribir lo que el usuario ve y a una migración destructiva si dos filas ya difieren solo en formato. Se descarta por ambas razones.

La migración rellena `mac_normalized` y crea el índice único en el mismo listener `connect` que ya usa `database.py` para el `ALTER TABLE` de `logs` (precedente existente, sin framework de migraciones). **Si detecta dos filas que colisionan al normalizar, aborta con un error explícito en lugar de borrar datos**; la base de desarrollo actual tiene 2 filas, sin colisión.

⚠️ **Requiere tu aprobación explícita antes de ejecutar T2**: es un cambio de esquema de base de datos y un cambio del formato de datos guardados (`AGENTS.md` → *Pregunta antes*).

### DO-3. Alcance de la exigencia de conexión → **solo registro y cambio de MAC**

Activación, desactivación, consulta, eliminación, mascotas, horarios y logs siguen operando sin conexión (RF-17). Razón: ninguna de esas operaciones crea un vínculo de MAC ni cambia una dirección, así que no puede producir el conflicto que esta spec previene; exigirlas en línea sería una regresión de Offline-First sin ganancia de integridad y tocaría funcionalidades fuera del alcance declarado.

### DO-4. Privacidad del aviso de conflicto → **siempre genérico**

El mensaje nunca menciona mascota, usuario ni identificador del dispensador en conflicto, y el cuerpo de error del servidor tampoco los incluye (CL-14). Beneficio adicional: el endpoint no se convierte en un oráculo que permita a un usuario comprobar si otra persona tiene un dispositivo concreto. En el caso 2 (mi propio dispensador, dirección de otro) el texto sigue siendo válido porque la acción sugerida —verificar la dirección e intentar de nuevo— no depende de a quién pertenezca.

### DO-5. Códigos de respuesta HTTP de los rechazos → **409 para conflictos de MAC, 400 para el resto** (decisión del usuario)

| Motivo del rechazo | Código HTTP | `detail.code` | Spec |
|---|---|---|---|
| MAC ya registrada en el alta | **409 Conflict** | `mac_already_registered` | RF-03, AC-1 |
| MAC en uso en la modificación | **409 Conflict** | `mac_in_use` | RF-04, AC-1 |
| Formato de MAC inválido | **400 Bad Request** | `mac_invalid_format` | RF-06, AC-2 |
| La mascota ya tiene un dispensador | **400 Bad Request** | `pet_already_has_dispenser` | AC-3 |

Por qué: 409 es el código semántico correcto para "el estado actual del recurso entra en conflicto con la petición" y separa, de un vistazo y sin depender del texto, los dos casos de la especificación de los errores de datos de la petición. Además evita el problema actual, donde un 422 de Pydantic (el `@field_validator('validate_mac')` de `DispenserAssociation`, que además exigía mayúsculas y dos puntos) es indistinguible de un conflicto para el cliente. El cliente **no** compara el texto: clasifica por `detail.code` (AC-4).

Consecuencia técnica: se retira el validador de Pydantic (que hoy devuelve 422) y el formato se valida en `mac_service`, que sí puede devolver el `400` + `mac_invalid_format` de AC-2.

### DO-6. Interfaz de edición de la dirección MAC → **pospuesta** (decisión del usuario)

No se crea pantalla, campo ni flujo nuevo para editar la MAC de un dispensador ya vinculado. Cuando la mascota ya tiene dispensador, el campo muestra la información del dispensador vinculado y su pulsación ofrece desactivar o eliminar **solo con conexión**; ese comportamiento de interfaz pertenece a una iteración posterior y queda **fuera de alcance** (AC-6).

Consecuencia para esta iteración: RF-04, RF-11 y RF-14 se cubren en servidor, dominio, datos y BLoC mediante el caso de uso `updateDispenserMac` y sus pruebas automatizadas; el aviso del caso 2 **no** se valida de forma manual en dispositivo porque no existe forma de dispararlo desde la interfaz. Los criterios de verificación manual se reducen a tres avisos (alta, formato inválido y falta de conexión).

---

## 1. Mapeo de Requisitos (RF/RNF) a Componentes

| Requisito | Componente / Archivo | RF cubierto |
|---|---|---|
| RF-01, RF-07 | `mac_normalized` con `UNIQUE` + `IntegrityError` en `dispenser_service` | Unicidad real en base de datos, no solo comprobación previa |
| RF-02, RF-08 | `mac_service.normalize_mac` (Python) y `lib/utils/mac_normalizer.dart` (Dart); `check_pending_task` normaliza la MAC entrante | Una sola forma normalizada en toda comparación |
| RF-03 | `create_new_dispenser` valida formato y unicidad normalizada → **409** `mac_already_registered` | Alta rechazada sin persistir |
| RF-04 | `update_dispenser` valida unicidad normalizada de la nueva MAC → **409** `mac_in_use` | Modificación rechazada sin tocar datos |
| RF-05 | `update_dispenser` compara `mac_normalized` antes de decidir | Sin falso positivo por formato |
| RF-06 | `mac_service.validate_mac_or_raise` → **400** `mac_invalid_format`; se **retira** el validador regex de `DispenserAssociation` | Error distinguible del conflicto (hoy 422 vs 400 mezclados) |
| RF-09, RNF-01, RNF-02 | `AppNoticeDialog` en `core/presentation/widgets` | Componente reutilizable, sin dependencia del feature |
| RF-10, RF-11, RF-12 | `dispenser_notice_mapper` (presentación) + `dispenser_bloc` | Título/descripción por caso |
| RF-13 | `DispenserRepositoryImpl.associateDispenser`: pre-chequeo de conexión + clasificación de fallo de red; **se elimina el fallback offline** | Sin registro local ni marca de pendiente |
| RF-14 | `DispenserRepositoryImpl.updateDispenserMac`: misma política | El dispensador conserva su MAC anterior |
| RF-15 | Se elimina el bloque `isSynced: false` y el bloque de dispensadores de `SyncService.synchronizePendingData`; `sync_service.process_sync_batch` ignora ítems `type == 'dispenser'` | No hay nuevos pendientes ni envío como nuevos |
| RF-16 | Códigos de error + mensajes genéricos; ninguna respuesta incluye `pet_id`, `user_id` ni `id` | Privacidad mínima |
| RF-17 | No se tocan `activate/dasactivate/get/deleteDispenser` ni los features de mascotas, horarios y logs | Offline preservado |
| RF-18 | `LocalDispenserDatasourceImpl._purgeLegacyLocalOrphans()` invocada desde `getLocalDispenserByPet`: query de huérfanos, borrado en `writeTxn` y `log('dispensador huérfano eliminado - MAC:<mac>')` | Limpieza local con traza de la MAC |
| RF-19 | El borrado ocurre **antes** de leer el dispensador, así que un huérfano devuelve `null`; el lote de `SyncService` ya no consulta `localDispensers` | No se muestra ni se envía |
| RF-20 | El borrado usa el predicado `isLegacyLocalOrphan` sobre filas de `localDispensers`; ninguna otra colección se toca | Offline-First preservado |
| AC-1..AC-5 | `mac_service` lanza `HTTPException(409/400, detail={"code","message"})`; `dispenser_remote_datasource` extrae `detail.code` | Contrato de error único y clasificable |
| RNF-03, RNF-04 | `AppNoticeDialog` con `AlertDialog` MD3, `colorScheme` del tema y `AppColors` solo como acento | Estilo global, claro y oscuro |
| RNF-05 | Las cuatro condiciones de error usan el diálogo; se elimina el `SnackBar` rojo de `RegisterDispenserView` | Sin avisos brutos |
| RNF-06 | `ConstrainedBox` de ancho máximo, `SingleChildScrollView`, `Flexible` y `mainAxisSize.min` | Legible en pantalla estrecha y fuente ampliada |
| RNF-07 | `FilledButton` con altura mínima 48 dp, `Semantics(label:)` en icono y botón | Accesibilidad |
| RNF-08 | `mac_normalizer_test.dart` (Dart) y `test_dispenser_mac.py` (Python) con los formatos de CL-1..CL-3 | Equivalencia demostrada |
| RNF-09 | Matriz de trazabilidad de la sección 7 | RF → prueba → componente |

---

## 2. Archivos a crear o modificar

### 2.1 Backend (FastAPI + SQLite)

**Crear**

* **`api/app/services/mac_service.py`** — normalización y validación de MAC. Funciones puras, sin acceso a la base de datos.
* **`api/tests/test_dispenser_mac.py`** — pruebas unitarias e integración (patrón `unittest` + `TestClient` + `unittest.mock.patch` de `api/tests/`, con `SECRET_KEY` y `DATABASE_URL` de prueba fijados antes de importar `app.main`).

**Modificar**

* **`api/app/db/database.py`** — en el listener `connect` existente: añadir la columna `mac_normalized` si falta, rellenar valores normalizados y crear `CREATE UNIQUE INDEX ux_dispensers_mac_normalized`. Aborta con `RuntimeError` si detecta colisiones.
* **`api/app/models/models.py`** — `Dispenser.mac_normalized = Column(String, nullable=True, unique=True, index=True)`. `mac_address` se mantiene sin cambios (texto original).
* **`api/app/schemas/schemas.py`** — retirar el `@field_validator('validate_mac')` de `DispenserAssociation` (devuelve 422 genérico de Pydantic y además exige mayúsculas y dos puntos, lo que contradice RF-02) y dejar el formato a `mac_service`. `Dispenser` (respuesta) no cambia: sigue devolviendo `mac_address` original.
* **`api/app/services/dispenser_service.py`** — validación con forma normalizada en `create_new_dispenser` y `update_dispenser` (409 en los conflictos, 400 en formato y en `pet_already_has_dispenser`), captura de `sqlalchemy.exc.IntegrityError` como conflicto, y `check_pending_task` comparando por forma normalizada. `exist_dispensar` pasa a recibir la forma normalizada.
* **`api/app/services/sync_service.py`** — los ítems con `data.type == 'dispenser'` se omiten de la respuesta (el servidor nunca registra dispensadores por lote).

**No se toca** `api/app/api/endpoints/dispenser.py` (los errores nacen en el servicio), ni el firmware, ni la validación 1-a-1 mascota/dispensador ya existente.

### 2.2 Frontend (Flutter, arquitectura limpia)

**Crear**

* **`lib/utils/mac_normalizer.dart`** — `normalizeMac(String)` e `isValidNormalizedMac(String)`, funciones puras espejo del backend.
* **`lib/core/error/api_exception.dart`** — `ApiException` con `code` y `message` para distinguir casos por código, no por texto.
* **`lib/core/presentation/widgets/app_notice_dialog.dart`** — `AppNoticeTone { info, warning }` y `AppNoticeDialog` (MD3). No importa nada de `features/dispenser` (RNF-02).
* **`lib/features/dispenser/presentation/widgets/dispenser_notice_mapper.dart`** — `appNoticeFor(Failures)` devuelve los parámetros del diálogo (tono, icono, título, mensaje, botón). Solo presentación: elige texto, no decide lógica.

**Modificar**

* **`lib/core/error/failures.dart`** — añadir `MacAlreadyRegisteredFailures`, `MacInUseFailures`, `InvalidMacFormatFailures`, `ConnectivityRequiredFailures`.
* **`lib/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart`** — extraer `code` del error y lanzar `ApiException`; añadir `updateDispenserMac(dispenserId, petId, mac)`; `deleteDispenserByPet` se adapta al nuevo tipo de excepción sin cambiar su comportamiento.
* **`lib/features/dispenser/data/datasource/local/local_dispenser_datasource.dart`** — añadir el predicado puro `isLegacyLocalOrphan({required int? remoteId, required bool isSynced})`; `saveLocalDispenser` deja de aceptar `isSynced` como libre elección y siempre guarda `isSynced = true`; `getLocalDispenserByPet` llama primero a `_purgarHuérfanosLocales()` (consulta + borrado + log) y después lee el dispensador (RF-18, RF-19).
* **`lib/features/dispenser/data/repositories_impl/dispenser_repository_impl.dart`** — **se elimina el fallback offline** de `associateDispenser` (nada de guardar con `isSynced: false`); se inyecta `SyncService` para el pre-chequeo de conexión; nuevo `updateDispenserMac`. Sin cambios en `getDispenserByPet` (la limpieza ocurre en el datasource local que ya usa), `activate`, `dasactivate` y `delete`.
* **`lib/features/dispenser/domain/repository/dispenser_repositories.dart`** — añadir `updateDispenserMac` al contrato.
* **`lib/features/dispenser/domain/use_case/update_dispenser_mac_uc.dart`** — caso de uso de RF-04/RF-14.
* **`lib/core/offline/sync_service.dart`** — eliminar por completo el bloque de dispensadores del lote (deja de consultar `localDispensers`); ningún `LocalDispenser` entra en el payload.
* **`lib/features/dispenser/presentation/bloc/dispenser_bloc.dart` / `dispenser_event.dart` / `dispenser_state.dart`** — estados de fallo tipados (`MacConflict`, `MacInUse`, `InvalidMac`, `OfflineBlocked`) en lugar de un `DispenserFailure(message)` genérico; el bloc no contiene textos.
* **`lib/features/dispenser/presentation/views/register_dispenser_view.dart`** — sustituir los `SnackBar` de error por `AppNoticeDialog` vía el mapper. El `SnackBar` de éxito se conserva (no es un caso de RNF-05).
* **`lib/core/di/injection_container.dart`** — registrar `UpdateDispenserMacUc` y pasar `SyncService` al repositorio.

**No se toca**: `register_dispenser_form_widget.dart` salvo que el test de widget demuestre un problema real de legibilidad; features de mascotas, horarios, logs y autenticación.

### 2.3 Pruebas

**Crear**: `api/tests/test_dispenser_mac.py`, `test/utils/mac_normalizer_test.dart`, `test/core/presentation/widgets/app_notice_dialog_test.dart`, `test/features/dispenser/presentation/widgets/dispenser_notice_mapper_test.dart`, `test/features/dispenser/presentation/bloc/dispenser_bloc_test.dart`.
**Modificar**: `test/features/dispenser/data/repositories/dispenser_repository_impl_test.dart` (el caso "offline guarda con `isSynced: false`" contradice RF-13 y se sustituye por "offline no escribe nada y devuelve `ConnectivityRequiredFailures`"), `test/core/offline/sync_service_test.dart` (el lote no contiene dispensadores), `test/features/dispenser/data/datasource/local/local_dispenser_datasource_test.dart` (predicado de huérfano y purga al leer: huérfano eliminado + log, huérfano no mostrado, mascotas/horarios/logs intactos, segunda consulta sin borrados).
No hay `bloc_test` ni `mocktail` en `pubspec.yaml`: los tests de BLoC usan `flutter_test` con dobles escritos a mano, como el `auth_bloc_test.dart` existente. **No se añaden dependencias.**

---

## 3. Funciones puras y algoritmos

### 3.1 Backend `app/services/mac_service.py`

```
SEPARADORES = {":", "-", ".", " "}

normalize_mac(raw: str) -> str:
    limpia = ''.join(c for c in raw if c not in SEPARADORES)
    return limpia.upper()

is_valid_normalized_mac(valor: str) -> bool:
    return re.fullmatch(r'[0-9A-F]{12}', valor) is not None

validate_mac_or_raise(raw: str) -> str:
    norm = normalize_mac(raw)
    if not is_valid_normalized_mac(norm):
        raise HTTPException(400, detail={"code": "mac_invalid_format",
            "message": "La dirección del dispensador no tiene un formato válido. "
                       "Debe tener 12 caracteres hexadecimales, por ejemplo AA:BB:CC:DD:EE:FF."})
    return norm
```

`create_new_dispenser(raw_mac, pet_id)`:

```
norm = validate_mac_or_raise(raw_mac)                  # RF-06 → 400 mac_invalid_format
if existe_por_normalizada(db, norm):                   # RF-03
    raise 409 {"code": "mac_already_registered", "message": GENÉRICO}
if mascota_ya_tiene_dispensador(pet_id):               # regla 1-a-1 existente, sin cambios
    raise 400 {"code": "pet_already_has_dispenser", ...}  # mensaje actual, sin datos ajenos
try:
    insertar(mac_address = raw_mac, mac_normalized = norm, pet_id = pet_id)
except IntegrityError:                                 # RF-07: carrera resuelta por la BD
    raise 409 {"code": "mac_already_registered", "message": GENÉRICO}
```

`update_dispenser(dispenser_id, update)`:

```
if update.mac_address is not None:
    norm = validate_mac_or_raise(update.mac_address)          # RF-06 también en modificación
    if norm != dispenser.mac_normalized:                      # RF-05
        otro = existe_por_normalizada(db, norm, excluir=dispenser_id)
        if otro: raise 409 {"code": "mac_in_use", "message": GENÉRICO_2}
        dispenser.mac_normalized = norm
        dispenser.mac_address  = update.mac_address          # texto original
try: commit
except IntegrityError: raise 409 {"code": "mac_in_use", ...}   # RF-07
```

`check_pending_task(mac_del_firmware)` → busca por `normalize_mac(mac_del_firmware)` (RF-08). No cambia el firmware.

Mensajes (idénticos para los dos casos de conflicto, sin datos ajenos — RF-16):

* `mac_already_registered`: "Este dispensador ya está registrado en el sistema. Escanea el código QR del dispensador correcto o revisa con qué cuenta está vinculado."
* `mac_in_use`: "La dirección indicada ya está siendo usada por otro dispensador. Verifica la dirección e inténtalo de nuevo."
* `mac_invalid_format`: "La dirección del dispensador no tiene un formato válido. Debe tener 12 caracteres hexadecimales, por ejemplo AA:BB:CC:DD:EE:FF."

Contrato de error (DO-5, AC-4): cuerpo `{"detail": {"code": "...", "message": "..."}}` con **409** para `mac_already_registered` y `mac_in_use`, y **400** para `mac_invalid_format` y `pet_already_has_dispenser`. `code` es el identificador estable que consume la app; `message` es la copia en español. El cliente nunca compara `message`.

### 3.2 Frontend `lib/utils/mac_normalizer.dart`

Espejo exacto de 3.1 con la misma lista de separadores y el mismo `RegExp(r'^[0-9A-F]{12}$')`. La paridad Python/Dart se verifica con el mismo conjunto de formatos de CL-1..CL-3 en ambos lenguajes.

### 3.3 Clasificación de fallos (`data` layer, sin lógica en vistas)

```
esFalloDeRed(Object e) -> bool:
    return e es DioException && (e.type ∈ {connectionTimeout, sendTimeout,
           receiveTimeout, connectionError, badCertificate} || e.response == null)

associateDispenser(mac, petId, key):
    if not await connectivity.hasConnection():                 # pre-chequeo (UX: aviso inmediato)
        return Left(ConnectivityRequiredFailures('...'))
    try:
        remoto = await remote.associateDispenser(mac, petId, key)   # envía el texto original
        await local.saveLocalDispenser(remoto)                     # siempre isSynced = true
        return Right(remoto)
    on ApiException catch (e):
        return Left(mapCodigoAFallo(e.code, e.message))             # RF-03/04/06
    catch (e):
        return Left(esFalloDeRed(e) ? ConnectivityRequiredFailures(...) : ServerFailures(...))
    # NINGÚN camino escribe en Isar cuando falla: no hay registro local ni marca de pendiente (RF-13, RF-15)
```

El datasource remoto mapea el contrato de DO-5 sin mirar el texto:

```
extraerApiException(DioException e) -> ApiException:
    status = e.response?.statusCode
    code   = (e.response?.data?['detail']?['code'])   // objeto {code, message}
    if code == null:                                   // detalle que aún no es objeto (p.ej. 403/404/422)
        return ApiException(code: 'server_error', message: _extractErrorMessage(e), status: status)
    return ApiException(code: code, message: e.response.data['detail']['message'], status: status)

mapCodigoAFallo(ApiException e) -> Failures:
    'mac_already_registered'    -> MacAlreadyRegisteredFailures(e.message)   # 409
    'mac_in_use'                -> MacInUseFailures(e.message)               # 409
    'mac_invalid_format'        -> InvalidMacFormatFailures(e.message)       # 400
    'pet_already_has_dispenser' -> ServerFailures(e.message)                 # 400
    _                           -> ServerFailures(e.message)
```

`deleteDispenserByPet` se adapta al nuevo tipo de excepción conservando su comportamiento actual (borra local y devuelve `Right(true)` si el servidor falla), sin reinterpretar `detail`.

El pre-chequeo de conexión es una mejora de experiencia (evita esperar timeouts); la garantía real es que **el único camino que escribe en Isar es el éxito del servidor**, por lo que un fallo de red mal clasificado no puede crear un registro pendiente.

`updateDispenserMac(dispenserId, petId, mac)` aplica la misma estructura: si falla, no se toca el datasource local y la fila conserva su MAC anterior (RF-14).

### 3.4 Limpieza de huérfanos locales (DO-1, RF-18, RF-19, RF-20)

```
isLegacyLocalOrphan({required int? remoteId, required bool isSynced}) -> bool:
    return remoteId == null && !isSynced            # función pura, sin Isar (test trivial)
```

En `LocalDispenserDatasourceImpl`:

```
Future<List<LocalDispenser>> _findLegacyLocalOrphans(Isar isar) -> List<LocalDispenser>:
    return isar.localDispensers.filter()
        .remoteIdIsNull()
        .and().isSyncedEqualTo(false)
        .findAll()                                # solo lectura, sin transacción de escritura

Future<void> _purgeLegacyLocalOrphans(Isar isar) -> void:
    huerfanos = await _findLegacyLocalOrphans(isar)
    if huerfanos.isEmpty: return                  # CL-18: caso normal, no se escribe nada
    await isar.writeTxn(() async {
        for (h in huerfanos) {
            await isar.localDispensers.delete(h.id)
            log('dispensador huérfano eliminado - MAC:${h.macAddress}',
                name: 'pdam.dispenser')           # log local, nunca red (RF-18)
        }
    })

Future<Dispenser?> getLocalDispenserByPet(int petId):
    isar = await _getIsar()
    await _purgeLegacyLocalOrphans(isar)           # ANTES de leer → un huérfano devuelve null
    local = await isar.localDispensers.filter().petRemoteIdEqualTo(petId).findFirst()
    ...                                          # resto igual que hoy (RF-17)
```

Detalles de diseño:

* **Orden:** purga antes de la lectura. Si se hiciera después, el huérfano de esa mascota ya habría sido mostrado/devuelto una vez (RF-19).
* **Log:** se usa `dart:developer`'s `log` con `name: 'pdam.dispenser'` y el texto literal `dispensador huérfano eliminado - MAC:<mac_address>`. Es diagnóstico interno, no texto de interfaz, así que no pasa por el mapper de copy ni necesita traducción (constitución, principio 6: los textos visibles van en español, y este ya lo está). No se añade ninguna dependencia.
* **Coste:** una consulta de lectura por cada lectura de dispensador; la transacción de escritura solo se abre si hay huérfanos.
* **Offline:** la purga no toca la red, de modo que también se aplica cuando el servidor no responde (justo el escenario donde el registro heredado se mostraría).
* **Nunca se vacía Isar:** solo se borran filas de `localDispensers` que cumplen el predicado. `localPets`, `localSchedules`, `localLogs` y el almacenamiento seguro de sesión no se abren ni se modifican (RF-20).
* **`SyncService.synchronizePendingData`:** deja de consultar `localDispensers`; el huérfano ya no puede llegar al payload porque, además, la lectura local lo elimina (RF-15, RF-19). Se conserva el filtro por predicado en la prueba del lote como documentación del contrato.

### 3.5 Componente de aviso `AppNoticeDialog` (MD3, reutilizable)

Firma: `AppNoticeDialog.show(context, tone: AppNoticeTone.info | .warning, icon: IconData, title: String, message: String, actionLabel: String)`. Sin tipos del feature (RNF-02).

Construcción (skills `mobile-android-design` y `flutter-build-responsive-layout`):

* `AlertDialog` de Material 3 con `icon: CircleAvatar`/`Icon` en `colorScheme.primaryContainer` (info) o `colorScheme.errorContainer` (warning) → el significado lo transmiten **ícono + título**, no solo el color (RNF-05).
* Contenido en `Column(mainAxisSize: MainAxisSize.min)` con `Flexible` para la descripción y `SingleChildScrollView` interno: sin desbordes con `textScaler` ampliado (RNF-06, CL-13).
* Ancho acotado con `ConstrainedBox(maxWidth: 420)` + `insetPadding` adaptativo: bien en móvil y en pantallas grandes (RNF-06).
* Textos con `Theme.of(context).textTheme.titleMedium/titleSmall/bodyMedium` y colores `onSurface`/`onSurfaceVariant`; `AppColors` solo como acento. Sin colores hardcodeados → funciona en claro y oscuro (RNF-04).
* Acción principal `FilledButton` con `minimumSize: Size(64, 48)` y `Semantics` en icono y botón (RNF-07). El cierre usa la misma acción.
* Si el texto no cabe, el diálogo sigue siendo desplazable: nunca se recorta.

---

## 4. Clean Architecture (constitución, principio 3)

* **Dominio**: `mac_normalizer.dart` (utilidad pura compartida), `update_dispenser_mac_uc.dart`, contrato del repositorio.
* **Datos**: `ApiException`, `Failures` tipadas, datasource remoto (traduce código → fallo), datasource local (predicado de huérfano + purga), repositorio (decide online vs offline).
* **Presentación**: `DispenserBloc` (solo estados, sin copy), `dispenser_notice_mapper` (copy), `AppNoticeDialog` (presentación pura en `core`, reutilizable), `RegisterDispenserView` (solo enruta estado → diálogo).

Cero lógica de validación de MAC, de red o de Isar en `RegisterDispenserView`. La purga de huérfanos vive en la capa de datos (datasource local) porque es una decisión sobre el almacenamiento local, no de presentación; la vista que la dispara es `pet_detail_view`, que **no cambia**.

---

## 5. Decisiones técnicas y alternativas descartadas

1. **Unicidad por índice único en `mac_normalized` en lugar de solo comprobación previa.**
   *Descartada:* consultar `WHERE mac_address = ?` y confiar en la comprobación (deja la carrera de RF-07 abierta y repite el defecto que la spec corrige).
2. **Guardar el texto original más la forma normalizada, en lugar de un único formato canónico guardado.**
   *Descartada:* un solo formato guardado obliga a migrar filas existentes de forma potencialmente destructiva y cambia lo que el usuario ve; el firmware seguiría mandando su propio formato.
3. **Pre-chequeo de conectividad con `SyncService.hasConnection()` reutilizado, en lugar de una abstracción nueva `ConnectivityService`.**
   *Descartada:* crear un contrato y una implementación solo para un método evita el churn de un archivo nuevo y de DI, y `SyncService.hasConnection()` ya envuelve `connectivity_plus`. La clasificación de `DioException` en la capa de datos es la garantía real, así que el pre-chequeo es solo UX.
4. **Errores con `code` en `detail`, en lugar de parsear el texto en el cliente.**
   *Descartada:* comparar textos (`"ya está registrada"`) se rompe con cualquier ajuste de copy y además permite que un 422 de Pydantic se confunda con un conflicto (RF-06).
5. **Identificar y limpiar los huérfanos por el predicado `remoteId == null && !isSynced`, en lugar de un campo nuevo en Isar.**
   *Descartada:* campo nuevo implica regenerar el `.g.dart` y migrar el esquema Isar sin ganar información. *Descartada:* conservarlos como lectura local, porque un registro que nunca pasó la validación de unicidad no puede usarse ni mostrarse como válido, y su `remoteId` es irrecuperable. *Descartada:* vaciar la colección completa o llamar a `clearAllData()`, por RF-20 y por la lección de `MEMORY.md`.
6. **Limpiar los huérfanos al consultar los dispensadores del usuario (datasource local), en lugar de al arrancar la app o dentro del lote de sincronización.**
   *Descartada:* al arrancar, porque obliga a tocar el arranque de la aplicación (empieza a escribir en Isar antes de que el usuario haga nada y afecta al login offline, que `MEMORY.md` documenta como delicado); *descartada:* dentro de `synchronizePendingData`, porque la sincronización solo corre con conexión y requiere que el lote no esté vacío, mientras que el huérfano se muestra justamente sin conexión. La lectura local de dispensadores es el punto que se ejecuta siempre, con y sin red.
7. **Retirar el validador regex de `DispenserAssociation` y validar el formato en `mac_service`.**
   *Descartada:* dejarlo produce un 422 con detalle de Pydantic que la app no puede clasificar como "formato inválido" (RF-06 exige que sea distinguible del conflicto) y además exige mayúsculas y dos puntos, contradiciendo RF-02.
8. **Mensajes de conflicto siempre genéricos, sin indicar si el conflicto es del mismo usuario.**
   *Descartada:* variante "es tu propio dispensador" porque contradice RF-16/CL-14 y convierte el endpoint en un oráculo de datos ajenos (DO-4).
9. **409 para los dos conflictos de MAC y 400 para formato y para el resto de validaciones de la petición.**
   *Descartada:* mantener todo en 400, porque no permite distinguir por el código entre "ya está en uso" (colisión de estado) y "la escribiste mal" (error de la petición), que es exactamente lo que RF-06 exige; y *descartada:* 422 para el formato, porque FastAPI lo reserva a la validación de esquema y aquí la validación es de negocio.
10. **No crear una pantalla, campo ni flujo de edición de la MAC (DO-6).**
    *Descartada para esta spec:* el usuario prefiere que, cuando la mascota ya tiene dispensador, el campo se transforme en información del dispensador vinculado cuya pulsación permita desactivar o eliminar solo con conexión. Eso es un rediseño de la pantalla de dispensador ya vinculado, explícitamente fuera de alcance (AC-6); RF-04/RF-14 quedan cubiertos en servidor, dominio, datos y BLoC con el caso de uso `updateDispenserMac` y sus pruebas.

---

## 6. Estrategia de pruebas (constitución, principio 4)

### 6.1 Backend (`pytest`)

`api/tests/test_dispenser_mac.py`:

* **Unitarias de `mac_service`**: `normalize_mac` con `:`/`-`/`.`/espacios/sin separadores/mayúsculas/minúsculas (CL-1, CL-2, CL-3); `is_valid_normalized_mac` con 11 hex, 13 hex, `g`, vacío, `None` (CL-7); paridad con el conjunto de formatos de Dart.
* **Integración `POST /dispensers`**: alta correcta guarda `mac_address` original y `mac_normalized` canónica; `aa:bb:cc:dd:ee:ff` contra `AA:BB:CC:DD:EE:FF` existente → **409** `mac_already_registered` (CL-1); `AABBCCDDEEFF` → **409** mismo código (CL-2); guiones/puntos → **409** (CL-3); formato inválido → **400** `mac_invalid_format` (CL-7); mascota que ya tiene dispensador → **400** `pet_already_has_dispenser` (AC-3); **el mensaje no contiene nombre de mascota, email ni `id`** (CL-14); **dos usuarios con la misma MAC: exactamente uno 201 y el otro 409 `mac_already_registered`, y una sola fila en la BD** (CL-6, RF-07).
* **Integración `PUT /dispensers/{id}`**: misma MAC con otro formato → 200 y sin cambios (CL-4, RF-05); MAC de otro dispensador → **409** `mac_in_use` y **el dispensador conserva su MAC anterior** (CL-5); formato inválido en modificación → **400** `mac_invalid_format`; reintento tras conflicto → mismo código y sin filas parciales (CL-12).
* **Integración del firmware (`RF-08`):** `check_pending_task` (endpoint `check-taks-test/{address_mac}`; el `check-taks/{address_mac}` de producción tiene hoy la respuesta fija `{"serve": true, "amount": 50}` y no llega al servicio — **no se modifica**, es firmware/producto fuera de alcance) encuentra el dispensador cuando el ESP32 manda la MAC con guiones o minúsculas.
* **Integración `DELETE /dispensers/{pet_id}`**: tras eliminar, la MAC queda libre y puede volver a registrarse (CL-11).
* **`POST /sync`**: un lote con `type == 'dispenser'` no crea ningún dispensador (RF-15).
* **Restricción de BD**: `UNIQUE` sobre `mac_normalized` verificado con una inserción directa que viola la restricción.

### 6.2 Frontend (`flutter test`)

* **`mac_normalizer_test.dart`**: mismos formatos que Python, con tabla de 8 entradas (`:`, `-`, `.`, espacios, sin separadores, minúsculas, mayúsculas, mezcla) y aserciones de equivalencia cruzada (RF-02, RNF-08).
* **`dispenser_repository_impl_test.dart` (modificado)**: offline → `Left(ConnectivityRequiredFailures)` **y `localDatasource.savedDispenser == null`** (RF-13, RF-15, CL-8); online con conflicto → `Left(MacAlreadyRegisteredFailures)`; online con formato inválido → `Left(InvalidMacFormatFailures)`; online correcto → `Right` + guardado con `isSynced = true`; `updateDispenserMac` offline → `Left` y **el datasource local no recibe escritura** (RF-14, CL-9); `getDispenserByPet`/`activate`/`dasactivate`/`delete` conservan su comportamiento actual (CL-10).
* **`dispenser_bloc_test.dart`**: cada evento emite el estado tipado correcto; ante fallo de MAC no se emite estado de éxito; `QrCodeDetectedEvent` sigue funcionando.
* **`app_notice_dialog_test.dart`**: contenido y `FilledButton` presentes; `info` y `warning` con iconos distintos; aparece y se cierra con la acción; sin excepciones de layout con `textScaler` 2.0 en superficie de 320 dp; `ConstrainedBox` limita el ancho en superficie ancha; funciona con `Brightness.dark`; botón con altura ≥ 48 dp y `Semantics` presentes (RNF-03, RNF-06, RNF-07).
* **`dispenser_notice_mapper_test.dart`**: cada `Failures` produce el título y mensaje correctos, siempre genéricos (RF-10, RF-11, RF-12, RF-16); un fallo desconocido cae en un aviso informativo por defecto.
* **Widget del flujo**: `RegisterDispenserView` con bloc que emite cada uno de los cuatro estados muestra el diálogo con el texto esperado y **no muestra ningún `SnackBar` rojo** (RNF-05).
* **`sync_service_test.dart` (modificado)**: el payload enviado no contiene ningún ítem `type == 'dispenser'` y `synchronizePendingData` ni siquiera consulta `localDispensers`, aunque haya un huérfano en Isar (RF-15, RF-19).
* **`local_dispenser_datasource_test.dart` (modificado)**:
  * `isLegacyLocalOrphan` es `true` para `remoteId == null && !isSynced` y `false` en cualquier otro caso.
  * Con un huérfano en Isar (`remoteId == null, isSynced == false`), `getLocalDispenserByPet` de esa mascota devuelve `null` y la fila ha desaparecido (RF-19, CL-15).
  * Con el huérfano presente, el log emite `dispensador huérfano eliminado - MAC:<mac>` con la MAC tal como estaba guardada (RF-18, CL-17). Para no depender de la salida real del log en tests, el método se estructura con el registro en una función inyectable o se comprueba el efecto (fila borrada) más una prueba aislada del formateador del mensaje.
  * Un `LocalDispenser` con `remoteId != null` o `isSynced == true` **no** se borra (no es huérfano).
  * Tras la purga, los datos de mascotas, horarios y logs siguen presentes y disponibles (RF-20, CL-16).
  * Una segunda llamada consecutiva no borra nada ni vuelve a registrar (CL-18).
* **Regresión**: `pytest` completo (los 24 tests existentes) y `flutter test` completo (los 43 tests existentes) deben seguir en verde; los únicos tests que cambian de aserción son el de fallback offline (anulado por esta spec) y los de sincronización de dispensadores (eliminados por RF-15).

### 6.3 Verificación manual (fuera de `flutter test`)

**Tres** avisos en dispositivo o emulador real: conflicto en alta, formato inválido y falta de conexión; en pantalla pequeña y con tamaño de fuente ampliado; más la comprobación de que el resto de la app sigue operando sin conexión (CL-10). El aviso del caso 2 (conflicto al cambiar la MAC) **no se valida manualmente en esta iteración** porque no hay interfaz para dispararlo (DO-6, AC-6): su cobertura es la automatizada de `PUT /dispensers/{id}` (409 `mac_in_use`), de `updateDispenserMac` en el repositorio y del mapper. Se pregunta al usuario antes de cerrar la spec (criterio de finalización de la spec).

---

## 7. Matriz de trazabilidad RF → prueba → componente (RNF-09)

| RF | Prueba | Componente |
|---|---|---|
| RF-01 | `test_dispenser_mac`::{test_alta_mac_equivalente_rechazada, test_dos_usuarios_misma_mac} | `mac_normalized` UNIQUE |
| RF-02 | `mac_normalizer_test`, `test_normalize_mac_*` | `mac_service.normalize_mac`, `mac_normalizer.dart` |
| RF-03 | `test_alta_mac_ya_registrada` (409 + `mac_already_registered`) | `create_new_dispenser` |
| RF-04 | `test_cambio_mac_en_uso_rechazado` (409 + `mac_in_use`) | `update_dispenser` |
| RF-05 | `test_cambio_misma_mac_otro_formato_ok` | `update_dispenser` |
| RF-06 | `test_mac_invalida_por_tamano`, `..._por_caracteres` (400 + `mac_invalid_format`) | `validate_mac_or_raise` |
| RF-07 | `test_dos_usuarios_misma_mac`, `test_indice_unico_mac_normalized` | `IntegrityError` + índice |
| RF-08 | `test_check_taks_normaliza_mac`, `mac_normalizer_test` | `check_pending_task`, `mac_service` |
| RF-09 | `app_notice_dialog_test` | `AppNoticeDialog` |
| RF-10 | `dispenser_notice_mapper_test`, `test_widget_aviso_caso_1` | mapper + vista |
| RF-11 | `dispenser_notice_mapper_test`, `test_widget_aviso_caso_2` | mapper + vista |
| RF-12 | `dispenser_notice_mapper_test`, `test_widget_aviso_formato` | mapper + vista |
| RF-13 | `test_offline_no_escribe_local`, `test_widget_aviso_offline` | repositorio + bloc |
| RF-14 | `test_update_mac_offline_no_escribe` | `updateDispenserMac` |
| RF-15 | `test_sync_no_envia_dispensers`, `test_offline_no_escribe_local` | `SyncService`, repositorio |
| RF-16 | `test_mensaje_conflicto_no_revela_datos`, `test_mensaje_generico` | servicio + mapper |
| RF-17 | `test_operaciones_offline_conservadas` | repositorio (sin cambios) |
| RF-18 | `test_huerfano_se_elimina_al_consultar`, `test_log_incluye_mac_huerfano`, `test_mac_huerfano_en_cualquier_formato` | `_purgeLegacyLocalOrphans`, `isLegacyLocalOrphan` |
| RF-19 | `test_huerfano_no_se_muestra`, `test_sync_no_envia_dispensers` | `getLocalDispenserByPet`, `SyncService` |
| RF-20 | `test_purga_no_toca_otros_datos` | `_purgeLegacyLocalOrphans` (alcance de la consulta) |
| AC-1, AC-2, AC-3 | `test_codigos_http_por_motivo` (409/409/400/400 con su `detail.code`) | `mac_service`, `dispenser_service` |
| AC-4, AC-5 | `test_datasource_extrae_detail_code`, `test_validar_formato_no_devuelve_422` | `dispenser_remote_datasource`, `schemas.py` |
| AC-6 | Cobertura automatizada de RF-04/RF-11/RF-14; sin prueba de UI de edición de MAC | `updateDispenserMac` |
| RNF-01 | Inspección de código + `dispenser_bloc_test` | separación de capas |
| RNF-02 | `app_notice_dialog_test` (sin imports del feature) | `AppNoticeDialog` |
| RNF-03 | `test_dialogo_md3_tema_oscuro` | `AppNoticeDialog` |
| RNF-04 | `test_dialogo_usa_colores_del_tema` | `AppNoticeDialog` |
| RNF-05 | `test_widget_no_muestra_snackbar_rojo` | `RegisterDispenserView` |
| RNF-06 | `test_dialogo_fuente_ampliada_sin_desborde`, `test_dialogo_ancho_acotado` | `AppNoticeDialog` |
| RNF-07 | `test_dialogo_accesibilidad` | `AppNoticeDialog` |
| RNF-08 | `mac_normalizer_test` + `test_normalize_mac_*` | ambos normalizadores |
| RNF-09 | Esta matriz | — |

---

## 8. Aprobaciones requeridas antes de ejecutar (AGENTS.md → *Pregunta antes*)

1. **Esquema de base de datos**: nueva columna `dispensers.mac_normalized` + índice único + backfill (DO-2, ya aprobado).
2. **Archivos nuevos**: `api/app/services/mac_service.py`, `api/tests/test_dispenser_mac.py`, `lib/utils/mac_normalizer.dart`, `lib/core/error/api_exception.dart`, `lib/core/presentation/widgets/app_notice_dialog.dart`, `lib/features/dispenser/presentation/widgets/dispenser_notice_mapper.dart` y los 5 archivos de test del frontend. La limpieza de huérfanos **no** requiere archivos nuevos: cabe en `local_dispenser_datasource.dart`.
3. **Contrato de API**: `detail` pasa de texto a objeto `{code, message}` y los conflictos de MAC pasan de 400 a **409** (DO-5). Afecta a `dispenser_remote_datasource._extractErrorMessage`, que se adapta.
4. **No se añaden dependencias** ni se regenera Isar (no hay cambios en `LocalDispenser`; el predicado `remoteId == null && !isSynced` ya es consultable con los filtros generados).

## 9. Preguntas abiertas

Ninguna. Las dudas de la spec están resueltas y registradas en la sección 0: DO-1 a DO-4 más las dos decisiones nuevas tomadas en esta iteración (DO-5 códigos HTTP y DO-6 interfaz de edición pospuesta). Resumen: huérfanos se limpian con log, formato canónico aprobado, alcance de conexión definido, privacidad genérica, códigos 409/400 fijados y la interfaz de edición de la MAC pospuesta (AC-6).

Nota para la iteración posterior: cuando se implemente el campo de dispensador vinculado (desactivar/eliminar solo con conexión), habrá que definir su copy en español y reutilizar `AppNoticeDialog`, sin tocar el motor de MAC ya cerrado por esta spec.
