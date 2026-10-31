# MEMORY.md — PDAM

## Estado actual
* **Specs 001–017 aprobadas.** La 017 (apariencia) está implementada y cerrada; la 015, cerrada. La 016 (solo
  firmware) mantiene T9 pendiente de las pruebas físicas (a)–(d) y de la no regresión física de la 013;
  `pruebas/endpoint-fijo-hx711` sigue sin merge.
* **Cifras:** `flutter test` 897/897 y `flutter analyze` 0 errores; `pytest` 685 passed (848 subtests);
  `pio test -e native` 230/230; `pio run` SUCCESS (RAM 19,7 %, Flash 64,5 %).
* **Documentación:** diagrama de los 7 procesos en `docs/informes/informe-diagrama-flujo-sistema-2026-10-30.md`;
  `docs/docs-diagramas/Diagrama-Flujo.md` sigue desactualizado.

## Decisiones clave
* 017 — tokens claro/oscuro en un único archivo de HEX; `ColorScheme` explícito (secundario repite verde,
  terciario azul); CTA fuera del esquema (`AppSemanticColors` + botón propio); tarjetas `surface` + borde
  `outline` + elevación 0.
* 017 — radio 8 en controles, tarjetas, chip, FAB y aviso; 12 en diálogos, hojas y menús; escala
  4/8/12/16/20/24/32; cursor en `textSelectionTheme` (`ThemeData.cursorColor` ya no existe).
* 017 — ojo en un `PasswordVisibilityField` compartido con estado propio y siete campos; panel del historial
  plegable en `LogFiltersBar` (estado local, no BLoC) y `TickerMode` al ocultar la rama de
  `StatefulShellRoute.indexedStack`.
* 017 — pruebas estáticas `no_color_literals`, `spacing_scale` y `responsive_theme`; QR verificado por su
  banda presentacional.
* 016 — `scale_guard_utils`/`dispensing_utils` como única lógica pura; asentamiento a 5 Hz;
  `decideDispenseEntry` antes del factor y sin tocar servo sin asentamiento.
* 015 — `SessionEvents` es el canal único interceptor→`AuthBloc`; el 401 limpia token, tipo, credenciales y
  perfil y conserva mascotas, horarios, historial y `user_theme_mode`; la baja ordena marca → token →
  credenciales → perfil → Isar acotado → borrar marca.
* 015 — `debeMostrarEntrada(ancho, ubicacion)` decide cabecera (<600) o barra (>=600), nunca ambas;
  `ThemeCubit` solo emite el modo.
* Stock: descuento al cerrar con éxito con `UPDATE` relativo y `rowcount` (tope 5000); entrega incompleta o
  reporte tardío no descuentan. Firmware: timeout 10 s, reintentos 5/15 s, pendiente en NVS.

## Errores a evitar
* `gramos_medidos`: un `SENSOR_UNAVAILABLE` no prueba `incrementAvailable = false`; hace falta
  `NOT_REACHED`/`SENSOR_FAILURE`. El mutante que quita `incrementAvailable &&` pasaba.
* `StatefulShellRoute.indexedStack` mantiene las ramas montadas: ocultar una pestaña no desmonta; usar
  `TickerMode` o estado local para reiniciar el plegado.
* No comparar `AppColors` consigo mismo en pruebas: un token sustituido por su alias no detecta el cambio;
  comparar el HEX/rol esperado.
* El contraste se mide sobre el fondo compuesto real (crema, superficie, velo), no sobre blanco;
  éxito/alerta sobre crema son 2,20:1 y 1,80:1.
* No volcar estados completos en `AppBlocObserver`; no usar `RadioListTile`; no limpiar la sesión desde el
  interceptor; no crear `DioClient` sin `SessionEvents`.
* No crear BLoC en `setUp` de un `testWidgets` ni usar `pumpAndSettle` con indicadores animados.

## Deuda aceptada y riesgos
* 017: QR probado por banda; heurísticas de las pruebas estáticas (case-insensitive, `fromRGBO`, lista blanca
  18/180/220 solo con `child`); erratas WCAG corregidas; emojis `⚠️` ×2 y `💧` retirados por decisión.
* `workspace.json` de Obsidian es ajeno al repositorio; no versionarlo.
* Marca de baja sin identidad y dispensadores con `petRemoteId == null` se borran siempre: perfil local único.
* Intermitencia preexistente de las dos pruebas de rendimiento con umbral ≤100 ms: fallan por carga, no por
  regresión.
