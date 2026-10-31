# Plan — Spec 017: paleta de colores, tema y apariencia global

Spec: `specs/017-paleta-colores-y-apariencia/spec.md` (aprobada, revisión 4).
Alcance: solo `app/app_movil_pdam`. Backend y firmware intactos.
Base: `flutter test` 737/737 y `flutter analyze` sin errores (MEMORY.md).
Cumplimiento: `docs/constitution.md` (trazabilidad, lógica fuera de vistas, tests) y
`AGENTS.md` (temas globales, español, sin `setState` en vistas principales).

## 1. Enfoque

1. **Núcleo primero:** tokens crudos de color, forma y espaciado; `ThemeData` claro y
   oscuro con `ColorScheme` explícito y componentes temáticos; pruebas de tema.
2. **Migración por grupos:** se sustituyen literales y se retiran estilos locales
   (`shape`, `padding`, `backgroundColor`) para que el tema gobierne. Cada tarea deja la
   app compilando y la suite en verde.
3. **Cierre:** barrido estático de literales y radios, adaptación de la suite del
   historial y validación responsive.

`app_colors.dart` se reescribe como **único archivo de HEX**: constantes `light*` y
`dark*` para todos los tokens de la spec. No se conserva una sola paleta estática porque
claro y oscuro tienen valores distintos y el tema debe poder probarlos. Durante T1 se
mantienen los campos antiguos como alias temporales para no romper la compilación; T2
migra sus cuatro consumidores y los elimina. Alternativa descartada: conservar los
nombres antiguos y retocar valores; impediría el modo oscuro y dejaría el morado.

El CTA **no ocupa `secondary`**. Vive en una extensión de tema (`AppSemanticColors`) y se
aplica solo con un botón compartido; así no se propaga a FAB, chips ni navegación.

## 2. Archivos afectados

| Área | Archivos | Cambio |
| --- | --- | --- |
| Tema | `lib/core/theme/app_colors.dart`, `app_theme.dart`; nuevos `app_shape.dart`, `app_spacing.dart`, `app_semantic_colors.dart` | Tokens claro/oscuro, `ColorScheme` completo, radios, espaciados y extensión CTA/éxito/alerta |
| Compartidos | `lib/core/presentation/widgets/in_app_notification_banner.dart`, `app_notice_dialog.dart`, `main_navigation_shell.dart`, `settings_entry_button.dart`; nuevos `app_cta_button.dart`, `password_visibility_field.dart` | Sin colores literales, radios y espaciados de tokens; botón CTA y campo de contraseña reutilizables |
| Auth | `lib/features/auth/presentation/views/login_view.dart`, `register_view.dart` | Colores, radios, espaciados y snackbars; usa el campo compartido |
| Panel | `lib/features/dashboard/presentation/views/dashboard_view.dart`; widgets `dashboard_header.dart`, `dashboard_hero_card.dart`, `dashboard_chart_card.dart`, `dashboard_metrics_grid.dart` | Hero y acciones a `primary`; datos a `tertiary`; fuera `#6C63FF`, `#0066FF`, `#00C853`, `#FFB300`, `#00B8D4` |
| Nutrición | `lib/features/nutrition/presentation/views/nutrition_calculator_view.dart`; widgets `nutrition_result_card.dart`, `nutrition_snack_alert.dart` | Tokens y radios; sin literales |
| Mascotas | `lib/features/pets/presentation/views/pets_view.dart`, `pet_detail_view.dart`, `create_pet_view.dart`, `edit_pet_view.dart`, `guided_schedule_form_view.dart`; widgets `pet_item.dart`, `pet_nutritional_summary_card.dart`, `generated_schedules_list_widget.dart` | Tokens, radios, espaciados; CTA en «Guardar Mascota» y «Generar Plan Automático» |
| Dispositivos | `lib/features/dispenser/presentation/views/dispensers_page.dart`, `wifi_provisioning_page.dart`, `ble_scan_page.dart`, `register_dispenser_view.dart`, `qr_scaner_view.dart`; widgets `device_card_widget.dart`, `dispenser_food_progress_bar.dart`, `register_dispenser_form_widget.dart` | Tokens, chip/FAB/aviso con radio 8; barra de comida con éxito/alerta |
| Configuración | `lib/features/settings/presentation/views/settings_view.dart`, `profile_view.dart`, `update_profile_view.dart`, `delete_account_view.dart`; widgets `settings_menu_tile.dart`, `appearance_mode_dialog.dart`, `delete_account_dialog.dart`, `profile_notice.dart` | Radios y espaciados de tokens; sin estilos literales (restricción vigente) |
| Historial | `lib/features/logs/presentation/views/logs_view.dart`; widgets `log_filters_bar.dart`, `log_item_widget.dart`, `log_notice_widget.dart`, `log_pagination_bar.dart` | Panel plegable con estado local; radios y espaciados |
| Pruebas | nuevos `test/core/theme/app_theme_test.dart`, `app_contrast_test.dart`, `app_colors_usage_test.dart`, `no_color_literals_test.dart`, `spacing_scale_test.dart`, `test/core/presentation/responsive_theme_test.dart`; nuevos `test/core/presentation/widgets/app_cta_button_test.dart`, `password_visibility_field_test.dart`; adaptación de `test/features/logs/presentation/views/logs_view_test.dart`; pruebas de vista de cada grupo | Tokens, contraste, forma, literales, ojo, responsive y panel |

## 3. Decisiones técnicas

### 3.1 Tokens y `ColorScheme`

- `AppColors` expone solo HEX por modo (`lightPrimary`, `darkOnSurface`, etc.), incluidos
  contenidos, error, bordes y contenedor de acento. Ningún otro archivo declara HEX;
  las variantes alfa se permiten sobre un token.
- `AppTheme` construye dos `ColorScheme` explícitos con todas las ranuras de la spec
  (incluidas `surfaceContainer*`, `outline`, `outlineVariant`, `inverse*`, `surfaceTint`,
  `scrim`, `shadow`). `secondary` y `secondaryContainer` repiten el verde; `tertiary` es
  el azul; el CTA queda fuera.
- `ThemeData` fija además `scaffoldBackgroundColor`, `canvasColor`, `cardTheme`
  (superficie + borde `outline` + elevación 0, radio 8), `appBarTheme` (principal sobre
  contenido), `navigationBarTheme`/`bottomNavigationBarTheme`, `filledButtonTheme`,
  `outlinedButtonTheme`, `textButtonTheme`, `inputDecorationTheme`, `dialogTheme`,
  `bottomSheetTheme`, `popupMenuTheme`, `snackBarTheme`, `chipTheme`,
  `floatingActionButtonTheme`, `iconButtonTheme`, `dividerTheme`,
  `progressIndicatorTheme`, `iconTheme`, `cursorColor` y el estilo de la barra de estado
  según el color principal. El texto toma `onSurface` y `onSurfaceVariant` del esquema.
- Alternativa descartada: `ColorScheme.fromSeed`. Añade tonos no aprobados y no permite
  fijar los contenidos exactos.

### 3.2 CTA, éxito y alerta

- `AppSemanticColors` es una `ThemeExtension` con `cta`, `onCta`, `success`, `onSuccess`,
  `alert`, `onAlert`, adjunta a ambos temas, con `copyWith` y `lerp`.
- `AppCtaButton` (widget compartido) lee la extensión y construye el `FilledButton` de
  creación/compra con radio 8; hoy se usa en «Guardar Mascota» y «Generar Plan
  Automático». Los demás `FilledButton` heredan `primary` del tema. Si la extensión no
  está disponible, usa los valores claros como respaldo para no romper pruebas aisladas.
- Alternativa descartada: asignar terracota a `secondary`; se propagaría a FAB, chips,
  indicadores y contenedores de toda la app.

### 3.3 Forma y espaciado

- `AppRadii.base = 8`, `control = 8`, `card = 8`, `dialog = 12`; las hojas y menús usan
  `dialog`. Todo `BorderRadius` de widget sale de aquí o del tema; no quedan valores
  literales.
- `AppSpacing` define 4, 8, 12, 16, 20, 24, 32 y los semánticos `page = 16`,
  `pageWide = 24`, `fieldGap = 16`, `cardPadding = 16`, `sectionGap = 24`. Las
  dimensiones fijas (iconos, avatares, 48 de accesibilidad, trazo 1) no se tocan.

### 3.4 Ojo de contraseña

- `PasswordVisibilityField` en `lib/core/presentation/widgets/`: `StatefulWidget` con
  `FocusNode` propio, escucha del `TextEditingController`, `obscureText` y `suffixIcon`.
  Muestra el ojo si hay foco o texto; etiqueta `Mostrar contraseña`/`Ocultar contraseña`;
  recibe `label`, `validator`, `errorText`, `enabled`, `onChanged`, `onSubmitted`,
  `autocorrect`, `enableSuggestions`, `keyboardType`, `textInputAction` y `key`.
- No valida ni envía; conserva texto, cursor y error. Sustituye `_CampoPassword` de
  registro, el estado `_obscurePassword` de login y WiFi, y los campos de actualización y
  baja. Vive fuera de `settings` y `account/presentation` para no romper la prueba de
  estilos.

### 3.5 Panel de filtros

- `_LogsViewState` gana `bool _filtersExpanded = false`; no se persiste.
- `LogFiltersBar` recibe `expanded` y `onToggle`, dibuja un botón con icono y texto
  «Filtros» y solo muestra los cuatro campos y «Limpiar filtros» cuando está expandido.
- El BLoC, los eventos y `LogFilters` no cambian. Alternativa descartada: estado en el
  BLoC; añadiría estado de presentación a la lógica.

### 3.6 Barrido de literales

- Regla: acción/identidad → `primary`; dato informativo, enlace o gráfica → `tertiary`;
  confirmación → `success`; recordatorio/aviso → `alert`; fallo/destructivo → `error`;
  texto de apoyo → `onSurfaceVariant`; contenido sobre relleno → token `on*`.
- Se eliminan `FilledButton.styleFrom(shape/padding)` locales que pisan el tema y los
  `Colors.white` sobre rellenos. `Colors.transparent` se permite.
- `#6C63FF` y `#0066FF` no se sustituyen por otro literal: pasan a `primary` o
  `tertiary` según la regla anterior.

## 4. Riesgos y mitigación

| Riesgo | Mitigación |
| --- | --- |
| `settings_contrast_test` mide `cardTheme`, `textTheme` y `outline` | T1 los fija y ejecuta esa prueba antes de cerrar |
| Las 9 aserciones de `logs_view_test` buscan filtros sin desplegar | T9 abre el panel antes de interactuar; no se debilita ninguna |
| `logs_view_layering_test` prohíbe `EdgeInsets... ?` | El plegado usa un booleano y widgets separados, no padding condicional |
| `register_dispenser_view_test` compara con `Colors.red` | El error pasa a `error` del esquema; sigue sin ser `Colors.red` |
| Cambios de tema afectan a 737 pruebas | T1 ejecuta la suite completa; cada tarea vuelve a ejecutarla |
| Desbordes a 320/600/840 y texto 1.3 | T10 y pruebas de vista por grupo; sin cambios de estructura |
| El CTA se filtra a otros botones | Prueba de que no está en `ColorScheme` y solo lo usa `AppCtaButton` |

## 5. Estrategia de pruebas

- **Tema (T1):** valor exacto de cada token y ranura en claro/oscuro; CTA ausente del
  esquema; extensión con sus seis colores; radios 8/12; escala de espaciado; contraste
  WCAG de los pares de la spec.
- **Estáticas (T10):** `no_color_literals_test` recorre `lib/` salvo el archivo de tokens:
  prohíbe `Color(0x`, `Colors.` (salvo `Colors.transparent`) y nombres heredados;
  `spacing_scale_test` valida `EdgeInsets` y huecos contra la escala, con las excepciones
  de la spec.
- **Widget por grupo (T4–T8):** se conservan las pruebas existentes de textos, eventos y
  navegación; se añade una comprobación de forma/color de los controles principales y se
  amplían los casos de 320/600/840 cuando el grupo tenga layout propio.
- **Ojo (T3):** siete campos, etiquetas, foco/contenido, error, baja vacía y widget
  compartido; se adaptan las pruebas de login, registro, perfil, baja y WiFi.
- **Historial (T9):** panel plegado al entrar, apertura/cierre, permanencia al filtrar,
  paginar y reintentar, plegado al reentrar, sin contador y espacio liberado; se adaptan
  las 9 aserciones existentes.
- **Cierre (T10):** `flutter analyze` sin errores, `flutter test` completo, pruebas de
  320/600/840 vertical/horizontal con texto 1.3 y diff de rutas sin `api/` ni
  `DispensadorESP32/`.

## 6. Trazabilidad

| Requisito | Archivos | Tareas |
| --- | --- | --- |
| RF-01, RF-02, RF-03, RF-07, RF-14 | `app_colors`, `app_theme`, `app_semantic_colors`; todas las vistas | T1, T2, T10 |
| RF-04 | `app_theme`, `app_semantic_colors`, `app_cta_button`; dashboard y mascotas | T1, T2, T5, T6, T10 |
| RF-05, RF-06 | `app_theme`, `app_cta_button`, dashboard, formularios de creación | T1, T2, T5, T6, T10 |
| RF-08, RF-09 | `app_shape`, `app_spacing`; todas las vistas | T1, T4–T10 |
| RF-10 | `password_visibility_field`; login, registro, perfil, baja y WiFi | T3, T4, T7, T8 |
| RF-11, RF-12 | `logs_view`, `log_filters_bar` | T9 |
| RF-13 | Todas las vistas listadas | T2, T4–T10 |
| RNF-01 | Suite existente y `theme_cubit` intacto | T1–T10 |
| RNF-02 | Sin archivos de backend ni firmware | T10 (diff de rutas) |
| RNF-03 | Tokens y contrastes | T1, T10 |
| RNF-04 | Pruebas responsive | T10 |
| RNF-05 | Pruebas por capa | T1–T10 |
| RNF-06 | Widgets compartidos y vistas sin lógica | T2, T3, T9 |
| RNF-07 | Sin dependencias ni tipografías | T1, T10 |
| RNF-08 | Campo de contraseña sin persistencia | T3 |
