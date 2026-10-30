# Plan — Spec 015: gestión de usuario básica y menú de configuración

Spec de referencia: `specs/015-gestion-usuario-configuracion/spec.md` (revisión 5, 2026-10-30; 25 RF, 10 RNF, catálogos de mensajes, errores y estados).
Estado del plan: aprobado e implementado (T1–T10 y correcciones finales, 2026-10-30). Las correcciones de esta ronda no cambian el alcance.
Alcance: `api/` y `app/app_movil_pdam/`. El firmware no se toca: la baja solo cambia qué MAC están registradas y el rechazo `mac_no_registrada` ya existe en la 014.
Cumplimiento: `docs/constitution.md` (FastAPI + SQLite, Flutter + BLoC + GoRouter + Isar, trazabilidad RF→prueba, lógica fuera de las vistas, tests en todas las capas, sin datos sensibles, textos en español) y `AGENTS.md` (Clean Architecture, Offline-First, temas globales, sin dependencias nuevas).

## 0. Línea base

- La app ya guarda token, correo y contraseña cifrados (`TokenConstant`) y el modo de apariencia en `user_theme_mode`.
- `GET /users/me` existe y devuelve `id`, `email`, `is_active`; el token usa `sub = email`, que es justo lo que hay que sustituir.
- `UserRepositoriesImpl.currentUser()` devuelve hoy `usuario@offline.com` cuando falla la red: es el dato de relleno que RF-07 y RF-08 prohíben y se elimina.
- El control de tema vive en `DashboardHeader` y se traslada al menú (RF-04).
- Nada de lo anterior se reescribe más allá de lo que exige esta spec (RNF-08).

## 1. Arquitectura de la solución

- **Dominio backend** (`api/app/domain/cuenta.py`, `api/app/domain/token.py`): normalización, validación, plan de actualización, etiquetas, claims. Sin SQLAlchemy, sin FastAPI y con `ahora` como parámetro.
- **Servicios backend** (`api/app/services/user_service.py`, `api/app/services/account_service.py`): registro, consulta, actualización condicional y baja transaccional.
- **API** (`api/app/api/endpoints/users.py`, `auth.py`, `api/deps.py`): contratos, dependencias de identidad y traducción de errores a `detail={code,message}`.
- **Persistencia** (`api/app/models/models.py`, `api/app/db/database.py`): `users.public_id`, tabla `revoked_tokens` y migración idempotente.
- **App móvil**: feature `account` (dominio puro, datos remotos/locales, BLoC) y feature `settings` (menú, perfil, actualización, baja y diálogo de modo); entrada única compartida y limpieza local con marca de baja pendiente.
- **Offline-First acotado**: solo la consulta del perfil cae a caché; las mutaciones exigen conexión y nunca se encolan (RF-13, RF-20).

## 2. Backend: archivos y responsabilidades

### 2.1 Dominio puro (nuevo)

- `api/app/domain/cuenta.py`: `ERRORES_CUENTA` con los códigos y mensajes exactos de la spec (`invalid_email`, `weak_password`, `password_too_long`, `empty_update`, `email_already_registered`, `invalid_password`, `invalid_credentials`, `unauthorized`, `conflict`, `server_error`); `normalizar_correo`, `es_correo_valido`, `longitud_en_bytes`, `validar_password_nueva`, `resolver_actualizacion`, `etiqueta_estado`, `inicial_de_correo`. RF-06, RF-11, RF-12, RF-17, RF-21, RNF-01.
- `api/app/domain/token.py`: `nuevo_jti()`, `construir_claims(public_id, jti, ahora, minutos)`, `claims_utilizables(payload, ahora, revocados)`, `debe_revocar_token_anterior(correo_actual, correo_nuevo)`, constante `MINUTOS_TOKEN` leída de `settings` por el llamador. RF-10, RF-19, RNF-06.

### 2.2 Modelos, esquemas y migración

- `api/app/models/models.py`: `User.public_id` (`String`, único, indexado, obligatorio en bases nuevas); `RevokedToken` (`id`, `jti` único, `public_id` indexado, `expires_at`, `revoked_at`). No se añaden columnas a mascotas, dispensadores ni logs.
- `api/app/schemas/account.py` (nuevo): `AccountProfile` (`id`, `email`, `is_active`; `id` se conserva por compatibilidad y no se muestra), `AccountUpdateRequest` (todos los campos opcionales y sin validadores que respondan 422), `AccountUpdateResponse` (`email`, `is_active`, `access_token: Optional[str]`, `token_type: Optional[str]`), `AccountDeleteRequest` (`password: Optional[str]`), `AccountDeleteResponse` (`deleted: bool`).
- `api/app/schemas/schemas.py`: `UserCreate` deja de validar con `EmailStr` y con longitud en Pydantic; el servicio aplica el catálogo. `User` se mantiene para el registro.
- `api/app/db/database.py`: `_migrar_public_id(conexion, cursor)` añade la columna si falta, rellena cada fila con `uuid4().hex`, verifica que no hay nulos ni duplicados y crea `ux_users_public_id`; `_crear_tabla_tokens_revocados` se apoya en `create_all` y en `CREATE TABLE IF NOT EXISTS` para bases existentes. Se invoca en el listener `connect` antes de `create_all`, con el patrón de `BASES_MIGRADAS`. RF-10, RF-19, RNF-09.

### 2.3 Servicios

- `api/app/services/user_service.py`: `obtener_usuario_por_public_id`, `obtener_usuario_por_correo_normalizado` (compara `lower(trim(email))`), `crear_usuario` normaliza y valida con el dominio, asigna `public_id` y traduce `IntegrityError` a `email_already_registered`. RF-11, RF-12, RF-19.
- `api/app/services/account_service.py` (nuevo):
  - `actualizar_cuenta(db, user, solicitud, ahora)` valida, aplica `UPDATE users ... WHERE id=:id AND hashed_password=:hash_previo AND email=:correo_previo`, comprueba `rowcount` (0 → `conflict`), revoca el `jti` usado, purga los tokens revocados ya caducados y emite token nuevo solo si el correo cambia; una sola transacción. RF-10, RF-11, RF-12, RF-14, RF-21, RNF-09.
  - `eliminar_cuenta(db, public_id, password, ahora)` verifica la contraseña, borra en orden y confirma una sola vez; si la cuenta no existe devuelve éxito sin verificar contraseña (idempotencia). RF-17, RF-18, RF-19, RF-21, RNF-09.
  - `contar_huerfanos(db, user_id, public_id)` verifica cero filas tras el borrado dentro de la misma transacción.
- `api/app/core/security.py`: `crear_token_acceso(public_id, jti, expires_delta)` firma `sub=public_id` y `jti`; se conserva `verify_password` y `get_password_hash`.

### 2.4 API

- `api/app/api/deps.py`: `get_current_identity` decodifica el token, valida claims y devuelve `Identidad(public_id, jti)` **sin** exigir que la cuenta exista; `get_current_user` usa la identidad, consulta por `public_id`, comprueba `revoked_tokens` y responde 401 `unauthorized` con el cuerpo del catálogo. `CurrentUser` sigue existiendo para el resto de rutas. RF-05, RF-18, RF-19.
- `api/app/api/endpoints/users.py`: `GET /users/me` (perfil), `PATCH /users/me` (actualización) y `DELETE /users/me` (baja con contraseña en el cuerpo). La baja usa `get_current_identity`, no `get_current_user`. RF-06, RF-10, RF-18.
- `api/app/api/endpoints/auth.py`: login con correo normalizado y rechazo 401 `invalid_credentials`; el token se emite con `public_id` y `jti`. RF-19.

### 2.5 Pruebas backend

- `api/tests/test_account_domain.py`, `test_account_migration.py`, `test_account_profile_api.py`, `test_account_update.py`, `test_account_deletion.py`, `test_account_identity.py`, `test_account_errors.py`.
- Se adaptan `test_api_basic.py` y `test_protected_routes.py` al token por `public_id` y al cuerpo de error nuevo; el resto de suites de 001–014 no se toca (RNF-08).

## 3. App móvil: archivos y responsabilidades

### 3.1 Dominio (nuevo, sin Flutter, sin Dio, sin Isar)

- `lib/features/account/domain/entity/user_profile.dart`: `UserProfile(email, isActive)` inmutable, `copyWith`, `==`.
- `lib/features/account/domain/entity/account_update.dart`: `AccountUpdate(correo, passwordNueva)` y `AccountUpdateResult(profile, tokenNuevo)`.
- `lib/features/account/domain/entity/appearance_mode.dart`: enum `claro`, `oscuro`, `automatico` con `codigo` (`light`/`dark`/`system`) y `etiqueta`; `aThemeMode()` vive en presentación (ver §12).
- `lib/features/account/domain/utils/account_validators.dart`: validaciones de cliente y utilidades de presentación (tabla §4).
- `lib/features/account/domain/repository/account_repository.dart`: contrato `getProfile`, `updateProfile`, `deleteAccount`, `cachedProfile`.
- `lib/features/account/domain/usecase/get_profile_uc.dart`, `update_profile_uc.dart`, `delete_account_uc.dart`: una responsabilidad cada uno.

### 3.2 Datos

- `lib/features/account/data/models/user_profile_model.dart`: `fromJson`/`toJson` del contrato de §5.
- `lib/features/account/data/datasource/remote/account_remote_datasource.dart`: `GET`, `PATCH` y `DELETE /users/me`; traduce `detail.code` a `AccountFailure(code, message)` y distingue red/timeout de rechazo de negocio.
- `lib/features/account/data/datasource/local/local_profile_datasource.dart`: lee, guarda y borra `LocalProfile`.
- `lib/core/offline/models/local_profile.dart` (+ `.g.dart` regenerado con `build_runner`): `accountKey` único (correo normalizado), `email`, `isActive`, `updatedAt`. Solo guarda datos recibidos del servidor.
- `lib/features/account/data/repository_impl/account_repository_impl.dart`: remoto → caché; si falla la red, caché; si no hay caché, `NoCachedProfileFailure`; un 401 `unauthorized` se propaga como `UnauthorizedFailure` y nunca se responde con caché. Las mutaciones no escriben nada si no hay conexión. RF-07, RF-08, RF-13, RF-20.

### 3.3 Estado y presentación

- `lib/features/account/presentation/bloc/account_bloc.dart`, `account_event.dart`, `account_state.dart`: `ProfileRequested`, `ProfileRetryRequested`, `ProfileUpdateSubmitted`, `AccountDeletionRequested`, `AccountMessageConsumed`; estado con `profile`, `isOffline`, `isSubmitting`, `isLoadingProfile`, `fieldErrors` y `message`; el token nuevo no viaja en el estado porque el BLoC lo persiste con `RegisterTokenUc`.
- `lib/features/settings/presentation/views/settings_view.dart`: título «Configuración» y exactamente cuatro filas en el orden de RF-02; sin cierre de sesión y sin las tres opciones de apariencia como filas.
- `lib/features/settings/presentation/views/profile_view.dart`: correo, estado y avatar con la inicial; aviso de caché o mensaje de RF-08 con «Reintentar».
- `lib/features/settings/presentation/views/update_profile_view.dart`: formulario de RF-09, errores por campo y confirmación de RF-10.
- `lib/features/settings/presentation/views/delete_account_view.dart`: advertencia, listado de datos y apertura del diálogo destructivo.
- `lib/features/settings/presentation/widgets/settings_menu_tile.dart`, `appearance_mode_dialog.dart`, `delete_account_dialog.dart`, `profile_notice.dart`: componentes sin lógica; reciben estado y emiten eventos.
- `lib/core/presentation/widgets/settings_entry_button.dart`: entrada única con icono fijo y etiqueta accesible «Abrir configuración»; se dibuja solo si `debeMostrarEntrada` lo indica para su ubicación.
- `lib/core/theme/theme_cubit.dart`: se conserva; el diálogo y la cuarta fila leen y escriben con `setTheme`. RF-22, RF-23, RF-24.

### 3.4 Core, router y arranque

- `lib/core/router/app_router.dart`: rutas `/settings`, `/settings/profile`, `/settings/update`, `/settings/delete` fuera del `StatefulShellRoute`; el guard existente redirige a `/login` sin sesión y el cierre de sesión desmonta menú, pantallas y diálogo. RF-05.
- `lib/core/presentation/widgets/main_navigation_shell.dart`: con 600 puntos o más, la barra superior incluye la entrada y las cabeceras de las pantallas no la muestran.
- `lib/features/dashboard/presentation/widgets/dashboard_header.dart`: pierde `onThemeToggle` y gana la entrada al menú cuando el ancho es menor que 600; saludo y cierre de sesión intactos. RF-04.
- `lib/features/pets/presentation/views/pets_view.dart`, `lib/features/logs/presentation/views/logs_view.dart`, `lib/features/dispenser/presentation/views/dispensers_page.dart`: añaden la entrada en `AppBar.actions` con la misma regla de ancho.
- `lib/core/services/pending_deletion_store.dart` (nuevo): escribe, lee y borra la marca de baja pendiente en `flutter_secure_storage` (`TokenConstant.keyPendingDeletion`).
- `lib/core/services/account_local_cleaner.dart` (nuevo): escribe la marca, borra token, tipo de token, credenciales y perfil cacheado, vacía las colecciones de la cuenta en Isar y borra la marca al terminar; nunca toca `user_theme_mode`. Expone `limpiarSiPendiente()` para el arranque y `limpiarPorSesionExpirada()` para el 401, que borra token, tipo, credenciales y perfil cacheado sin marca, sin colecciones y sin tema. RF-18, RF-19, RNF-10.
- `lib/features/auth/presentation/bloc/auth_bloc.dart` y `auth_state.dart`: estados `AuthSessionExpired` y `AuthAccountDeleted`; escucha el aviso del interceptor y bloquea el acceso sin conexión si hay marca pendiente.
- `lib/features/auth/data/repositories_impl/user_repositories_impl.dart`: elimina `usuario@offline.com`, compara correos normalizados y usa el correo real cacheado como identidad de sesión; sin perfil cacheado no inventa estado.
- `lib/core/network/auth_interceptor.dart`: ante 401 solo notifica `SessionEvents`; `AuthBloc` ejecuta la limpieza de sesión antes de emitir `AuthSessionExpired` (RF-19). No interpreta el éxito de la baja como sesión inválida.
- `lib/core/constant/token_constant.dart`: añade `keyPendingDeletion` y `keyCachedProfile` si se usa clave dedicada.
- `lib/core/di/injection_container.dart`, `lib/core/constant/api_constant.dart` y `lib/main.dart`: registro de datasources, repositorio, casos de uso y `AccountBloc`; limpieza pendiente antes de `runApp`.

### 3.5 Pruebas móviles

- `test/features/account/domain/account_validators_test.dart`, `appearance_mode_test.dart`.
- `test/features/account/data/local_profile_datasource_test.dart`, `account_remote_datasource_test.dart`, `account_repository_impl_test.dart`.
- `test/features/account/presentation/account_bloc_test.dart`.
- `test/features/settings/settings_view_test.dart`, `profile_view_test.dart`, `update_profile_view_test.dart`, `delete_account_view_test.dart`, `appearance_mode_dialog_test.dart`, `settings_responsive_test.dart`.
- `test/core/presentation/settings_entry_visibility_test.dart`, `test/core/services/account_local_cleaner_test.dart`, `test/core/network/auth_interceptor_test.dart`.

## 4. Funciones puras

| Función | Responsabilidad | RF |
|---|---|---|
| `normalizar_correo(texto) -> str` | `strip` y minúsculas; no toca espacios interiores | RF-11, RF-12, RF-19 |
| `es_correo_valido(correo) -> bool` | Formato con una sola `@`, dominio con punto y sin espacios interiores | RF-11 |
| `longitud_en_bytes(texto) -> int` | Bytes UTF-8 para el límite de 72 | RF-11, RNF-06 |
| `validar_password_nueva(password) -> str \| None` | `weak_password` con menos de 8 caracteres, `password_too_long` con más de 72 bytes, en ese orden | RF-11 |
| `resolver_actualizacion(correo_actual, correo_nuevo, password_nueva) -> PlanActualizacion` | Precedencia `invalid_email` → `empty_update` → `weak_password` → `password_too_long`; decide si cambia correo, contraseña o ambos | RF-11 |
| `etiqueta_estado(is_active) -> str` | «Activa» / «Inactiva» | RF-06 |
| `inicial_de_correo(correo) -> str` | Primera letra en mayúsculas del correo normalizado | RF-06 |
| `nuevo_jti() -> str` | Identificador irrepetible del token | RF-10 |
| `construir_claims(public_id, jti, ahora, minutos) -> dict` | `sub`, `jti`, `iat`, `exp` | RF-10, RF-19 |
| `claims_utilizables(payload, ahora, revocados) -> bool` | Firma ya verificada, `exp` futuro y `jti` no revocado | RF-05, RF-19 |
| `debe_revocar_token_anterior(correo_actual, correo_nuevo) -> bool` | Solo si el correo cambia | RF-10 |
| `normalizarCorreo(String) -> String` | Espejo en Dart de la normalización | RF-11, RF-19 |
| `esCorreoValido(String) -> bool` | Misma regla que el servidor | RF-11 |
| `bytesUtf8(String) -> int` | `utf8.encode(texto).length` | RF-11 |
| `validarFormularioPerfil({correoActual, correo, passwordNueva, confirmacion}) -> Map<CampoPerfil, String>` | Devuelve **todos** los errores de cliente a la vez, con el texto exacto del catálogo y en el orden de precedencia | RF-11 |
| `etiquetaEstado(bool) -> String` | «Activa» / «Inactiva» | RF-06 |
| `inicialDeCorreo(String) -> String` | Inicial del avatar | RF-06 |
| `codigoDeModo(ThemeMode) / modoDesdeCodigo(String?)` | Persistencia y lectura de `light`/`dark`/`system` | RF-23, RF-24 |
| `debeMostrarEntrada(ancho, ubicacion) -> bool` | `< 600` en cabecera de pantalla, `>= 600` solo en la barra del contenedor; nunca ambas | RF-01 |

## 5. Contrato de la API

### 5.1 `GET /users/me` (token)

```json
{"id": 7, "email": "user@x.com", "is_active": true}
```
`id` se conserva por compatibilidad y no se muestra en Perfil. 401 `unauthorized` si el token no vale o la cuenta ya no existe. RF-06, RF-07, RF-19.

### 5.2 `PATCH /users/me` (token)

```json
{"email": "nuevo@x.com", "new_password": "unaClaveLarga"}
```
Ambos opcionales; la confirmación no viaja al servidor. 200:
```json
{"email": "nuevo@x.com", "is_active": true, "access_token": "eyJ...", "token_type": "bearer"}
```
`access_token` y `token_type` son `null` cuando el correo no cambia. Errores 400 `invalid_email`, `empty_update`, `weak_password`, `password_too_long`, `email_already_registered`; 401 `unauthorized`; 500 `conflict` (actualización simultánea) y `server_error` (fallo de escritura). Nunca 422. El correo vacío se rechaza en el cliente sin petición; si una petición directa llega con el correo vacío, el servidor la rechaza con `invalid_email` como salvaguarda del contrato, sin que la aplicación use nunca esa respuesta (nota del catálogo en `spec.md`). RF-10 a RF-14, RF-21.

### 5.3 `DELETE /users/me` (token)

```json
{"password": "claveActual"}
```
200 `{"deleted": true}`. 400 `invalid_password`; 401 `unauthorized` solo con token inválido o caducado; 500 `server_error`. Si la cuenta ya no existe, responde 200 aunque el token corresponda a la cuenta eliminada. Nunca `conflict` ni `pet_has_dispenser`. RF-17 a RF-21.

### 5.4 Catálogo de errores

Se implementa una vez en `domain/cuenta.py`, con los diez códigos y sus mensajes literales; todo rechazo de negocio usa `detail={code,message}`. Prueba transversal: ningún rechazo responde 422, ningún código citado por un RF falta del catálogo y `unauthorized` no aparece en el login.

## 6. Modelo de datos y migración

| Tabla | Cambio |
|---|---|
| `users` | `public_id VARCHAR NOT NULL UNIQUE`; índice `ux_users_public_id`; `email` se guarda normalizado en altas y actualizaciones |
| `revoked_tokens` | `id`, `jti VARCHAR UNIQUE`, `public_id VARCHAR` indexado, `expires_at DATETIME`, `revoked_at DATETIME` |
| `pets`, `dispensers`, `schedules`, `dispensing_queue`, `dispensing_orders`, `refill_operations`, `logs` | sin cambios de esquema; solo se borran sus filas en la baja |

Migración: si `users` existe y le falta `public_id`, se añade, se rellena con `uuid4().hex` por fila, se comprueba que no hay nulos ni duplicados y se crea el índice único; es idempotente y aborta sin borrar datos si encuentra una anomalía. `revoked_tokens` se crea con `create_all` o `CREATE TABLE IF NOT EXISTS`. Los tokens antiguos con `sub=email` dejan de valer y el usuario vuelve a iniciar sesión: es la consecuencia asumida del cambio de identidad.

## 7. Flujos

### 7.1 Actualización de perfil

```
ACTUALIZAR(user, solicitud, ahora):
  plan = resolver_actualizacion(user.email, solicitud.email, solicitud.new_password)
  si plan.error → 400 {code, message}            // sin cambios
  normalizado = normalizar_correo(plan.correo_nuevo)
  si normalizado != user.email y existe otra cuenta con lower(trim(email)) = normalizado
      → 400 email_already_registered             // sin cambios, ni correo ni contraseña
  abrir transacción:
    UPDATE users SET email=:normalizado, hashed_password=:nuevo_hash
      WHERE id=:id AND email=:email_previo AND hashed_password=:hash_previo
    si rowcount == 0 → rollback → 500 conflict
    si el correo cambia:
        INSERT revoked_tokens(jti_actual, user.public_id, exp_actual, ahora)
        token_nuevo = crear_token_acceso(user.public_id, nuevo_jti())
    commit
  devolver {email, is_active, access_token: token_nuevo o null}
```

### 7.2 Baja de cuenta

```
ELIMINAR(identidad, password, ahora):
  user = buscar por public_id
  si user is None → 200 {deleted: true}            // idempotencia, sin verificar contraseña
  si !verify_password(password, user.hashed_password) → 400 invalid_password
  abrir transacción:
    DELETE dispensing_queue   WHERE dispenser_id IN (SELECT id FROM dispensers WHERE pet_id IN (...))
                                 OR schedule_id IN (SELECT id FROM schedules WHERE pet_id IN (...))
    DELETE dispensing_orders  WHERE user_id = :user_id OR pet_id IN (...) OR dispenser_id IN (...)
    DELETE refill_operations  WHERE user_id = :user_id OR dispenser_id IN (...)
    DELETE logs               WHERE user_id = :user_id OR pet_id IN (...) OR dispenser_id IN (...)
    DELETE dispensers         WHERE pet_id IN (SELECT id FROM pets WHERE user_id = :user_id)
    DELETE schedules          WHERE pet_id IN (SELECT id FROM pets WHERE user_id = :user_id)
    DELETE pets               WHERE user_id = :user_id
    DELETE revoked_tokens     WHERE public_id = :public_id
    DELETE users              WHERE id = :user_id
    si contar_huerfanos(...) > 0 → rollback → 500 server_error
    commit
  200 {deleted: true}
```
El orden respeta las claves foráneas (`dispensing_queue` antes que dispensadores y horarios; `dispensers` y `schedules` antes que `pets`). El borrado de las tablas sin clave foránea usa los mismos predicados que `contar_huerfanos` (propietario, mascota y dispensador), de modo que una fila migrada con `user_id` nulo pero con la mascota o el dispensador de la cuenta también se borra y la comprobación posterior da cero. Un fallo en cualquier punto revierte todo (RNF-09).

### 7.3 Perfil sin conexión

```
CARGAR_PERFIL():
  intentar GET /users/me
    éxito → guardar LocalProfile(correo normalizado, is_active) → mostrar
    401 unauthorized → propagar UnauthorizedFailure → AuthBloc cierra sesión y va a /login
    red/timeout → leer LocalProfile
        existe → mostrar con «Estás viendo datos guardados en este dispositivo.»
        no existe → mostrar «No hay datos de tu cuenta guardados en este dispositivo...» + Reintentar
```

### 7.4 Limpieza local y marca de baja pendiente

```
ELIMINAR_CUENTA_EN_LA_APP(password):
  si no hay conexión → aviso de conexión, sin cambios
  llamar DELETE /users/me
    invalid_password → error junto al campo, sin cambios
    server_error → mensaje con reintento, sin cambios
    éxito (incluida cuenta ya inexistente):
      escribir marca de baja pendiente
      borrar token, tipo, credenciales y perfil cacheado
      vaciar colecciones de la cuenta en Isar (mascotas, horarios, logs, dispensadores)
      borrar la marca
      si algo falla → conservar la marca, mensaje de RNF-10 y cierre de sesión en memoria
      AuthAccountDeleted → /login con «Tu cuenta y todos tus datos se eliminaron de forma definitiva.»
```
Al arrancar, `limpiarSiPendiente()` reintenta la limpieza antes de `runApp`; mientras la marca exista, el login sin conexión con esas credenciales se rechaza.

### 7.5 Sesión rechazada (401)

```
SESION_RECHAZADA():
  el interceptor detecta un 401 de una petición autenticada distinta de la baja
  notifica SessionEvents.sesionExpirada (no toca el almacenamiento)
  AuthBloc:
    limpiarPorSesionExpirada() → borra token, tipo, credenciales cifradas y perfil cacheado
      (sin marca de baja pendiente, sin colecciones Isar y sin user_theme_mode)
    emite AuthSessionExpired → /login con «La sesión no es válida. Vuelve a iniciar sesión.»
```

Las mascotas, horarios e historial locales se conservan y se resincronizan al volver a iniciar sesión (RF-19).

## 8. Decisiones justificadas y alternativas descartadas

1. **Identidad `public_id` en el token (elegido).** Un token de una cuenta eliminada no revive si el correo se registra de nuevo (RF-19). Se descarta `sub=email`: reutilizar el correo rehabilita tokens antiguos.
2. **Revocación por `jti` en `revoked_tokens` (elegido).** Permite invalidar solo el token de la petición al cambiar el correo y dejar intactos los demás dispositivos (RF-10). Se descarta una columna `token_version` en `users`: revocaría todas las sesiones y sería un cierre remoto, fuera de alcance.
3. **`DELETE /users/me` con la contraseña en el cuerpo (elegido).** Es la operación que describe la spec y evita una ruta de acción artificial. Se descarta `POST /users/me/deletion`: duplicaría semántica sin ventaja.
4. **Dependencia `get_current_identity` para la baja (elegido).** Permite responder 200 cuando la cuenta ya no existe (RF-18). Se descarta usar `get_current_user`: devolvería 401 y rompería la idempotencia.
5. **Borrado explícito y ordenado en una transacción (elegido).** `user_id` no tiene FK en órdenes, reabastecimientos y logs, y las FK anulables no bastan (RNF-09). Se descarta confiar en `ON DELETE CASCADE`: dejaría filas huérfanas y no cubre las tablas sin FK.
6. **Actualización con `UPDATE ... WHERE` y `rowcount` (elegido).** Detecta la actualización simultánea y responde `conflict` sin estados intermedios (RF-21). Se descarta leer y escribir con el ORM: dos peticiones podrían pisarse sin aviso.
7. **Perfil cacheado real en Isar (elegido).** RF-07 y RF-08 exigen datos del servidor o nada. Se descarta mantener `usuario@offline.com` y cualquier relleno.
8. **Marca de baja pendiente en almacenamiento seguro (elegido).** Sobrevive al reinicio y a la limpieza de Isar (RNF-10). Se descarta una bandera en Isar: la propia limpieza la borraría y el fallo quedaría invisible.
9. **Una sola entrada decidida por ancho con función pura (elegido).** Garantiza que nunca hay dos entradas y es verificable (RF-01). Se descarta duplicar el botón y ocultarlo con dos `if` en árbol: se desincroniza con el breakpoint.
10. **Validación de cliente en dominio puro que devuelve todos los errores (elegido).** Cumple RF-11 y RNF-03 y se prueba sin widgets. Se descarta validar en la vista o parar en el primer error.
11. **Mutaciones sin cola offline (elegido).** El servidor es la fuente de verdad de la cuenta (RF-13, RF-20). Se descarta reutilizar el outbox de reabastecimiento: una baja o un cambio de contraseña no se pueden diferir sin mentir al usuario.
12. **Limpieza local con lista explícita de claves (elegido).** Conserva `user_theme_mode` (RF-23). Se descarta `clearAllData()` sin más: borraría la preferencia de apariencia.
13. **401 centralizado en el interceptor con aviso a `AuthBloc` (elegido).** El interceptor solo detecta y avisa; `AuthBloc` limpia la sesión (token, tipo, credenciales y perfil cacheado) y cierra con el mensaje del catálogo (RF-05, RF-19). Se descarta repetir la comprobación en cada repositorio y se descarta limpiar desde la capa de red, que no conoce el estado de sesión.
14. **Límite de 72 bytes explícito (elegido).** Evita que dos contraseñas distintas compartan prefijo y se acepten indistintamente (RF-11). Se descarta confiar en el truncado silencioso de bcrypt.
15. **Diálogo de apariencia en lugar de subpantalla (elegido, decisión de la spec).** Mantiene cuatro filas y aplica el cambio al instante (RF-24). Se descarta una quinta ruta de apariencia.
16. **Texto de error del servidor tomado del catálogo, no del cuerpo libre (elegido).** Garantiza los mensajes exactos y evita variantes (RNF-01). Se descarta mostrar `detail` como cadena arbitraria.

## 9. Estrategia de tests y comandos

### 9.1 Backend — unitarias puras (`unittest`, sin DB)

- Normalización: mayúsculas, espacios exteriores, espacios interiores, cadena vacía, unicode.
- Formato de correo: válidos, sin `@`, doble `@`, sin dominio, con espacio interior.
- Contraseña: 7/8/9 caracteres, exactamente 72 bytes, 73 bytes, multibyte en el límite.
- `resolver_actualizacion`: una prueba por fila de la matriz de RF-11 y por cada caso de precedencia.
- Claims: `exp` futuro, pasado, `jti` revocado, `jti` ausente, `sub` ausente.
- Etiquetas e inicial: `is_active` verdadero y falso, correo con mayúsculas.

### 9.2 Backend — integración con SQLite (`test.db`)

- Migración: base legada sin `public_id`; se rellena, es única, es idempotente y no toca otras columnas.
- Perfil: 200 con el correo normalizado; 401 sin token, con token inválido, caducado y de cuenta eliminada.
- Actualización: solo correo, solo contraseña, ambas; token nuevo guardado y token anterior rechazado; otro token de la misma cuenta sigue valiendo; correo duplicado normalizado; `conflict` con escritura condicional fallida; contraseña anterior rechazada en el login.
- Baja: borrado total con mascotas, dispensadores, horarios, cola, órdenes, reabastecimientos y logs; recuento cero de huérfanos; MAC posterior rechazada con `mac_no_registrada`; correo libre y registro nuevo sin datos ni sesiones heredadas; `invalid_password` sin cambios; idempotencia con token de cuenta eliminada; dos bajas simultáneas con éxito; fallo inyectado que revierte todo.
- Contrato: cada código del catálogo devuelve `detail={code,message}`, ningún rechazo responde 422 y `invalid_credentials` solo aparece en el login.

### 9.3 App móvil (`flutter test`)

- Validadores: matriz de RF-11 completa, errores simultáneos, textos exactos y normalización.
- Modelo y datasource remoto: contrato de §5, `access_token` nulo, traducción de códigos y de red.
- Caché: guarda solo respuestas del servidor, lee con aviso, sin caché muestra RF-08, 401 no devuelve caché.
- BLoC: carga, reintento, actualización con token nuevo, errores por campo, baja con marca, fallo de limpieza.
- Widgets: menú con título y cuatro filas en orden, sin cierre de sesión, cuarta fila con el modo activo, diálogo con tres opciones y marca de la activa, perfil con avatar y estado, formulario con correo precargado, diálogo de baja con acción deshabilitada sin contraseña, avisos de conexión.
- Responsive: 320, 600 y 840 puntos, vertical y horizontal, escalado 1.3, sin desbordamientos ni recortes (RNF-02); entrada única en cada ancho (RF-01).
- Contraste: cálculo sobre los colores de `AppTheme` en claro y oscuro, 4.5:1 y 3:1 (RF-25).
- Limpieza local: se borran token, credenciales, perfil y colecciones; se conserva `user_theme_mode`; la marca se escribe antes y se borra al final; con marca pendiente no hay login sin conexión.
- Regresión: suites de 001–014 en verde (RNF-08); `flutter analyze` sin errores.

### 9.4 Comandos

```
cd api && source venv/bin/activate && pytest
cd api && uvicorn app.main:app --reload --port 8000 --host 0.0.0.0
cd app/app_movil_pdam && flutter test
cd app/app_movil_pdam && flutter analyze
cd app/app_movil_pdam && dart run build_runner build --delete-conflicting-outputs
```

## 10. Mapa RF/RNF → parte del plan

| Requisito | Dónde se implementa | Prueba principal |
|---|---|---|
| RF-01 | `settings_entry_button`, `main_navigation_shell`, cabeceras de las cuatro pantallas, `debeMostrarEntrada` | widget a 320/600/840 con una sola entrada |
| RF-02 | `settings_view` | widget de título, orden y cuatro filas |
| RF-03 | `app_router`, `settings_view` | navegación de las cuatro filas y regreso |
| RF-04 | `dashboard_header` | widget sin control de tema y con saludo, cierre y entrada |
| RF-05 | `app_router`, `auth_interceptor`, `auth_bloc` | guard, cierre con menú abierto y 401 `unauthorized` |
| RF-06 | `profile_view`, `etiqueta_estado`, `inicial_de_correo` | widget de datos y estados |
| RF-07 | `account_repository_impl`, `local_profile_datasource` | caché con aviso, 401 sin caché |
| RF-08 | `profile_view`, `account_repository_impl` | mensaje sin caché y reintento |
| RF-09 | `update_profile_view`, `get_profile_uc` | correo precargado desde servidor y caché |
| RF-10 | `account_service.actualizar_cuenta`, `account_bloc`, `auth_local_datasource` | token nuevo, token anterior rechazado y refresco |
| RF-11 | `account_validators`, `cuenta.resolver_actualizacion` | matriz completa en Dart y en API |
| RF-12 | `account_service`, `user_service` | duplicado normalizado sin cambios |
| RF-13 | `account_bloc`, `account_remote_datasource` | sin conexión no aplica ni encola |
| RF-14 | `account_service`, `auth_local_datasource` | contraseña anterior rechazada y credenciales locales |
| RF-15 | `update_profile_view`, `app_router` | cancelar sin cambios |
| RF-16 | `delete_account_view`, `delete_account_dialog` | advertencia, listado y acción deshabilitada |
| RF-17 | `account_service.eliminar_cuenta` | `invalid_password` sin cambios |
| RF-18 | `account_service`, `account_local_cleaner` | borrado total, idempotencia y limpieza local |
| RF-19 | `token`, `deps`, `auth.py`, `auth_bloc`, `account_local_cleaner` | token de cuenta eliminada, nuevo registro y limpieza de sesión en el 401 |
| RF-20 | `account_bloc` | baja sin conexión sin cambios |
| RF-21 | `account_service`, `account_bloc` | `server_error`, reintento y dos bajas simultáneas |
| RF-22 | `theme_cubit`, `appearance_mode_dialog` | cambio inmediato y cierre sin elegir |
| RF-23 | `theme_cubit`, `account_local_cleaner` | persistencia tras reinicio y tras la baja |
| RF-24 | `appearance_mode_dialog`, `settings_view` | diálogo con tres opciones y modo en la cuarta fila |
| RF-25 | `app_theme`, widgets nuevos | contraste calculado en ambos modos |
| RNF-01 | catálogos y textos de widgets | recorrido de textos sin emojis |
| RNF-02 | widgets con `LayoutBuilder` y textos flexibles | responsive 320/600/840 y escalado 1.3 |
| RNF-03 | vistas sin lógica, `account_bloc` | prueba de que la vista solo emite eventos |
| RNF-04 | `domain/cuenta`, `domain/token`, `account_validators` | imports del dominio sin framework ni red |
| RNF-05 | todas las capas | tabla RF→prueba y suites completas |
| RNF-06 | `security`, `token`, `account_local_cleaner` | ningún texto ni log con contraseña o token |
| RNF-07 | `pubspec.yaml`, `requirements.txt` | revisión de dependencias sin cambios |
| RNF-08 | suites 001–014 | ejecución completa sin fallos nuevos |
| RNF-09 | `account_service`, transacción de baja | fallo inyectado sin estados intermedios |
| RNF-10 | `pending_deletion_store`, `account_local_cleaner` | marca antes y después, reinicio y bloqueo offline |

## 11. Orden de implementación y riesgos

1. Migración `public_id` y `revoked_tokens` (T1).
2. Dominio de cuenta y token (T2).
3. Contrato `/users/me` de consulta y actualización (T3).
4. Baja transaccional e idempotente (T4).
5. Dominio y datos de la app (T5).
6. BLoC de cuenta y sesión (T6).
7. Menú, perfil y entrada única (T7).
8. Actualización de perfil y diálogo de modo de apariencia (T8).
9. Baja en la app, limpieza local con marca, responsive y contraste (T9).
10. Validación global y trazabilidad (T10).

Riesgos de secuencia: T1 debe ir antes de arrancar la API con tokens nuevos; T4 depende de T2 y de la dependencia de identidad; T7 y T8 dependen del contrato congelado de T3 y T4; T8 no puede probarse sin T6; el cambio de identidad del token invalida sesiones existentes en desarrollo y exige volver a iniciar sesión una vez.

## 12. Desviaciones de implementación (T10 y correcciones finales)

La implementación se separó del plan en estos puntos; se documentan para que plan y código coincidan:

1. `aThemeMode()` y `codigoDeModo()` viven en `lib/features/account/presentation/utils/appearance_mode_theme.dart` (no en `lib/features/settings/presentation/utils/`), porque `ThemeMode` es de Flutter y el dominio debe quedar libre del framework (RNF-04).
2. `contar_huerfanos` recibe instantáneas de identificadores (`pet_ids`, `dispenser_ids`, `schedule_ids`) capturadas antes del borrado; tras borrar, las subconsultas devolverían cero y no detectarían huérfanos.
3. Archivos tocados no listados en el plan: `lib/core/network/dio_client.dart` (retirada de `LogInterceptor` por RNF-06), `lib/features/auth/data/datasources/remote/auth_remote_datasource.dart` (marcador de petición pública + `detail.code`), `lib/features/auth/presentation/views/login_view.dart` (mensajes de sesión inválida y cuenta eliminada), `lib/features/account/presentation/utils/appearance_mode_theme.dart`, `lib/features/settings/presentation/widgets/delete_account_dialog.dart`, `lib/core/services/account_local_cleaner.dart` y `lib/features/account/presentation/bloc/account_state.dart` (`isLoadingProfile`).
4. `AccountBloc` ya no recibe `PendingDeletionStore` ni `DeleteTokenUc`: la marca y el token pasan a `AccountLocalCleaner`.
5. El registro (`register_view.dart`) normaliza el correo al enviar y usa los validadores del dominio (`esCorreoValido`, `validarPasswordRegistro`, `MensajesCuenta.passwordsNoCoinciden`), con `_CampoPassword` como widget propio para no usar `setState` en la vista principal (RF-03, RF-12, RNF-03).
6. `users.public_id` queda anulable en la migración de una base existente (`ALTER TABLE users ADD COLUMN public_id VARCHAR`) aunque `models.py` lo declare `nullable=False` y la tabla nueva lo cree `NOT NULL`. Es una limitación de SQLite: `ADD COLUMN ... NOT NULL` exige un valor constante por defecto y la identidad se rellena fila a fila con `uuid4().hex`. La migración verifica cero nulos y cero duplicados antes de crear `ux_users_public_id`, de modo que el resultado observable es el del plan (`VARCHAR NOT NULL UNIQUE`) y una anomalía aborta sin borrar datos.
7. `lib/features/settings/` solo tiene `presentation/`: es una feature de composición pura (menú, perfil, actualización, baja y diálogo de apariencia) que consume el dominio, los datos y el estado de `lib/features/account/` y el `ThemeCubit` global. No tiene capas `data/` ni `domain/` propias y no es un olvido de la estructura.
8. `revoked_tokens` se purga de forma oportunista: al insertar una revocación nueva (cambio de correo) se borran en la misma transacción las filas con `expires_at < ahora`, que ya no pueden aceptarse porque `claims_utilizables` rechaza su `exp`. No se purga en cada petición autenticada para no convertir una lectura en escritura.
9. El 401 no lo limpia el interceptor: `AuthBloc` ejecuta `AccountLocalCleaner.limpiarPorSesionExpirada()` antes de emitir `AuthSessionExpired` (RF-19). `AccountState` ya no transporta `tokenNuevo`: el BLoC lo persiste con `RegisterTokenUc` y el estado no guarda credenciales de sesión. `DioClient` exige `SessionEvents` para que el aviso de un 401 nunca caiga en un canal que nadie escucha.
