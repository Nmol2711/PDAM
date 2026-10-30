# MEMORY.md — PDAM

## Estado actual
* **Specs 001–015 cerradas.** La 014 quedó implementada y validada el 2026-10-30 (repetición de
  P-T9-B aprobada); la 015 se cerró con T1–T10 y correcciones finales. La rama
  `pruebas/endpoint-fijo-hx711` sigue sin merge.
* **Cifras:** `pytest` 685 pruebas y 848 subpruebas; `flutter test` 737/737; `flutter analyze` 0 errores
  (103 avisos); 25 RF y 10 RNF de la 015 con prueba existente.

## Decisiones clave
* Cuenta 015: `SessionEvents` es el canal único interceptor→`AuthBloc`; el interceptor solo avisa. Un 401
  cierra sesión solo si la petición no es pública, no es la baja y su `detail.code` es nulo o `unauthorized`.
* 401 (RF-19): `AuthBloc` ejecuta `AccountLocalCleaner.limpiarPorSesionExpirada()` antes de emitir
  `AuthSessionExpired`: borra token, tipo, credenciales cifradas y perfil cacheado; conserva mascotas,
  horarios, historial y `user_theme_mode`; no escribe la marca de baja.
* Baja 015 (RF-18/RNF-09): orden `marca → token/tipo → credenciales → perfil → Isar → borrar marca`; Isar se
  acota a `default_user` + correo y `petRemoteId`, nunca `clear()`. El `DELETE` usa los mismos predicados que
  `contar_huerfanos` (`user_id`, `pet_id`, `dispenser_id`), así una fila `logs(user_id=NULL, pet_id=…)` de
  base migrada se borra y la baja responde 200. `revoked_tokens` purga los caducados al revocar.
* Correo vacío: el cliente lo rechaza sin petición; una petición directa se rechaza con `invalid_email`
  como salvaguarda del contrato y la app nunca usa esa respuesta (nota en `spec.md` y §5.2 del plan).
* Entrada única: `debeMostrarEntrada(ancho, ubicacion)` decide cabecera (`<600`) o barra del contenedor
  (`>=600`), nunca ambas; filas 2 y 3 a `/settings/update` y `/settings/delete`, fila 4 abre el diálogo.
* Perfil 015: credenciales cifradas vía `AuthLocalDatasource.updateCachedCredentials`; el token lo guarda el
  BLoC con `RegisterTokenUc` (no viaja en `AccountState`); `_sesionValida` se revalida tras cada `await`.
* Apariencia 015: `ThemeCubit` guarda en `user_theme_mode` (`light`/`dark`/`system`), clave independiente de
  la cuenta; `aThemeMode()`/`codigoDeModo()` viven en `account/presentation/utils`, fuera del dominio.
* Orden con ID y estados pendiente/cerrada; el stock se descuenta al cerrar con éxito, nunca al entregar;
  descuento y reabastecimiento son `UPDATE` relativos con `rowcount` (tope 5000), plazo de 5 min + 1 s.
* MAC parcial `**:AB:1F`; filtros ISO con `Z`; errores `detail={code,message}`; `Schedule.time` local y
  órdenes UTC; reabastecimiento deduplicado por `(user_id, operation_id)`; mascota con dispensador 409
  `pet_has_dispenser`. Firmware: timeout 10 s, reintentos 5/15 s, pendiente en NVS, descarte de 2xx/4xx.

## Errores a evitar
* No volcar estados ni errores completos en `AppBlocObserver` (solo `runtimeType`); mostrar siempre el
  catálogo. No usar `RadioListTile` ni persistir credenciales fuera del almacén cifrado.
* No tratar un 401 público (login/registro) ni el de `DELETE /users/me` como sesión expirada, ni llamar a
  `PendingDeletionStore.clear()` antes de limpiar. No ignorar los `Either` de `deleteString` en la baja.
* No limpiar la sesión desde el interceptor: la limpieza del 401 vive en `AuthBloc`. No crear `DioClient`
  sin `SessionEvents` ni volver a poner `tokenNuevo` en `AccountState`.
* No crear un BLoC en `setUp` de un `testWidgets` ni usar `pumpAndSettle` con indicadores animados; conectar
  `themeMode` al `ThemeCubit` y medir contraste sobre `surfaceContainerLow`, no `cardColor`.

## Deuda aceptada y riesgos
* Marca de baja sin identidad: si la limpieza falla y luego se inicia sesión CON conexión con otra cuenta, el
  reintento de arranque borra sus datos y limpia la marca; aceptado por el perfil local único.
* Dispensadores con `petRemoteId == null` (`account_local_cleaner.dart:229-232`) se borran siempre, aunque
  fueran de otra cuenta: se asume una sola cuenta; bloquear sin conexión excede RNF-10.
* Entrega incompleta o reporte tardío no descuentan stock; la ventana de 10 min de `encolar_comida` no
  recupera ocurrencias si el proceso cae; cliente sin `operation_id` duplica; typo `/dispenserscheck-taks/{mac}`.
* Incidente 2026-10-30 (013): línea base 0,0 g inestable y 364,66 g para 17,27 g; ciclo anulado en
  desarrollo (orden 6 y su log borrados, stock 4614,93 g; copia en `/tmp/opencode/pdam-antes-limpieza-2026-10-30.db`).
* **Spec 016 aprobada el 2026-10-30**, pendiente de implementación; plan y tareas en `specs/016-…/`
  (validación de línea base y plausibilidad del dispensado, derivada del incidente del 2026-10-30).
* Intermitencia preexistente de las dos pruebas de rendimiento con umbral ≤100 ms: fallan por carga, no por regresión.
