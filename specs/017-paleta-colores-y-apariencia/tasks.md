# Tareas — Spec 017: paleta de colores, tema y apariencia global

Cada tarea es una sesión y deja el repositorio en verde. Tests primero (en rojo), después
la implementación, después la suite. Ninguna tarea toca backend, firmware, dominio ni
BLoC. Comando base: `cd app/app_movil_pdam && flutter test` y `flutter analyze`.

## Tareas

- [x] **T1. Tokens de color, forma, espaciado y tema claro/oscuro.**
  - Requisitos: RF-01, RF-02, RF-03, RF-04, RF-07, RF-08, RF-09, RF-14 · RNF-03, RNF-05, RNF-07.
  - Archivos: `lib/core/theme/app_colors.dart`, `app_theme.dart`; nuevos `app_shape.dart`, `app_spacing.dart`, `app_semantic_colors.dart`; pruebas `test/core/theme/app_theme_test.dart`, `test/core/theme/app_contrast_test.dart`.
  - Contenido: HEX crudos `light*`/`dark*` de todas las tablas; `ColorScheme` explícito con todas las ranuras; `secondary` y su contenedor repiten el verde; `tertiary` es el azul; CTA fuera del esquema; `AppSemanticColors` con CTA, éxito, alerta y contenidos; `AppRadii` 8/12; `AppSpacing` 4–32 y semánticos; `ThemeData` con tarjetas (superficie, borde `outline`, elevación 0), barras, botones, campos, diálogos, hojas, menús, aviso emergente, chip, FAB, botones de icono, divisorias y cursores. Se conservan los campos antiguos de `AppColors` como alias temporales para compilar.
  - Constitución: 2 (tokens y ranuras con prueba), 3 (tema en capa compartida), 4 (contraste y forma probados), 6 (sin textos nuevos).
  - Tests primero: `app_theme_test` comprueba cada HEX y ranura en ambos modos, la ausencia de CTA en el esquema, la extensión, los radios 8/12 y los valores de espaciado; `app_contrast_test` recalcula WCAG de los pares de la spec. Ejecutar también `test/features/settings/settings_contrast_test.dart`.
  - Hecho cuando: los dos temas exponen los valores exactos de la spec; ningún `ColorScheme` cae en el morado por defecto; `settings_contrast_test` pasa; `flutter test test/core/theme test/features/settings/settings_contrast_test.dart`, la suite completa y `flutter analyze` quedan en verde.

- [x] **T2. Retirar los consumidores de `AppColors` y añadir el botón CTA.**
  - Requisitos: RF-03, RF-04, RF-05, RF-06 · RNF-05, RNF-06.
  - Archivos: `lib/core/theme/app_colors.dart` (eliminar alias); `lib/core/presentation/widgets/in_app_notification_banner.dart`; nuevos `lib/core/presentation/widgets/app_cta_button.dart` y `test/core/presentation/widgets/app_cta_button_test.dart`; `lib/features/dispenser/presentation/widgets/device_card_widget.dart`, `dispenser_food_progress_bar.dart`; `lib/features/dispenser/presentation/views/dispensers_page.dart`; prueba `test/core/theme/app_colors_usage_test.dart`.
  - Contenido: banner de aviso usa éxito/alerta/acento y contenidos del tema; tarjeta, barra de comida y página de dispositivos usan `Theme.of(context).colorScheme` y la extensión; `AppCtaButton` lee `AppSemanticColors` y construye un `FilledButton` con radio 8, sin tocar el resto de botones; se eliminan los nombres `primaryGreen`, `purpleBackgroud`, `primaryPurple`, `darkCard`, etc.
  - Constitución: 3 (widgets sin lógica), 4 (pruebas de widget), 6 (sin nombres ni colores heredados).
  - Tests primero: `app_cta_button_test` comprueba color CTA/contenido y radio; `app_colors_usage_test` falla si `AppColors.` aparece fuera de `lib/core/theme/` o si quedan nombres heredados.
  - Hecho cuando: no hay usos de `AppColors` fuera de `lib/core/theme/` ni nombres morados; el botón CTA solo se pinta con el widget compartido; suite y análisis en verde.

- [x] **T3. Widget compartido del ojo en los siete campos de contraseña.**
  - Requisitos: RF-10 · RNF-05, RNF-06, RNF-08.
  - Archivos: nuevo `lib/core/presentation/widgets/password_visibility_field.dart`; `lib/features/auth/presentation/views/login_view.dart`, `register_view.dart`; `lib/features/settings/presentation/views/update_profile_view.dart`, `lib/features/settings/presentation/widgets/delete_account_dialog.dart`; `lib/features/dispenser/presentation/views/wifi_provisioning_page.dart`; nueva `test/core/presentation/widgets/password_visibility_field_test.dart` y ajustes en las pruebas de esas cinco pantallas.
  - Contenido: widget con `FocusNode` y escucha del controlador; ojo visible con foco o contenido; texto oculto por defecto; etiqueta alterna «Mostrar contraseña»/«Ocultar contraseña»; no altera texto, cursor, error ni validación; recibe `onChanged`, `onSubmitted`, autocorrección y sugerencias; se elimina el `setState` de visibilidad de las vistas principales y el `_CampoPassword` privado. Los siete campos son: inicio de sesión, registro, confirmación de registro, «Contraseña nueva», «Confirmar contraseña nueva», contraseña actual de la baja y contraseña WiFi.
  - Constitución: 3 (estado dentro del widget, no en la vista), 4 (prueba del widget y de cada pantalla), 5 (sin persistir credenciales), 6.
  - Tests primero: oculto/mostrado, foco, contenido, error que permanece, baja vacía que no habilita confirmación, siete usos y etiquetas. Ejecutar `settings_contrast_test` para confirmar que no se añaden `TextStyle`, `fontSize`, `Colors.` ni `Color(0x` en configuración/cuenta.
  - Hecho cuando: los siete campos usan el widget compartido; ninguna vista principal guarda estado de visibilidad; las pruebas de login, registro, perfil, baja y WiFi pasan; suite y análisis en verde.

- [x] **T4. Autenticación con tema global.**
  - Requisitos: RF-03, RF-04, RF-07, RF-08, RF-09, RF-13, RF-14.
  - Archivos: `lib/features/auth/presentation/views/login_view.dart`, `register_view.dart`; ajustes en sus pruebas de vista.
  - Contenido: snackbars con `error`/`success` y contenidos del tema; textos secundarios con `onSurfaceVariant`; spinner con `onPrimary`; se eliminan `shape`, `padding` y `styleFrom` locales; separaciones de `AppSpacing`; campos y botones heredan radio 8.
  - Constitución: 3 (vistas solo componen), 4 (pruebas de widget), 6.
  - Tests primero: adaptar login/registro a las nuevas formas; comprobar radio 8 en el botón y en los campos, color de snackbar desde el esquema y ausencia de desbordes a 320 con texto 1.3.
  - Hecho cuando: las dos pantallas no contienen literales de color ni radios propios; las pruebas de auth pasan; suite y análisis en verde.

- [x] **T5. Panel y nutrición sin literales.**
  - Requisitos: RF-03, RF-04, RF-06, RF-07, RF-08, RF-09, RF-13, RF-14.
  - Archivos: `lib/features/dashboard/presentation/views/dashboard_view.dart`; widgets `dashboard_header.dart`, `dashboard_hero_card.dart`, `dashboard_chart_card.dart`, `dashboard_metrics_grid.dart`; `lib/features/nutrition/presentation/views/nutrition_calculator_view.dart`, widgets `nutrition_result_card.dart`, `nutrition_snack_alert.dart`; pruebas de dashboard y nutrición.
  - Contenido: hero y acciones a `primary`; datos, gráfica y métricas informativas a `tertiary`; éxito/alerta solo en confirmaciones o avisos; se eliminan `#6C63FF`, `#0066FF`, `#00C853`, `#FFB300`, `#00B8D4`; radios y espaciados de tokens.
  - Constitución: 3 (el cálculo sigue en el Cubit), 4 (pruebas de widget), 6.
  - Tests primero: comprobar que las acciones rápidas y métricas usan `primary`/`tertiary`, que no aparece el morado y que las cifras siguen viniendo del estado; sin desbordes a 320.
  - Hecho cuando: dashboard y nutrición no contienen literales; prueba de entrada nutricional y widgets siguen pasando; suite y análisis en verde.

- [x] **T6. Mascotas: tokens, radios y CTA de creación.**
  - Requisitos: RF-03, RF-04, RF-05, RF-06, RF-07, RF-08, RF-09, RF-13, RF-14.
  - Archivos: `lib/features/pets/presentation/views/pets_view.dart`, `pet_detail_view.dart`, `create_pet_view.dart`, `edit_pet_view.dart`, `guided_schedule_form_view.dart`; widgets `pet_item.dart`, `pet_nutritional_summary_card.dart`, `generated_schedules_list_widget.dart`; pruebas de mascotas.
  - Contenido: `Colors.green/red/blue/orange/cyan/grey` y `Colors.white` pasan a roles y contenidos; «Guardar Mascota» y «Generar Plan Automático» usan `AppCtaButton`; «Actualizar Mascota» sigue en `primary`; estados activo/inactivo usan `primaryContainer` y `surfaceContainerHighest` con sus contenidos; FAB con radio 8; sin `styleFrom(shape)` locales.
  - Constitución: 3, 4, 5 (sin tocar datos de mascota), 6.
  - Tests primero: crear mascota y generar horarios usan CTA; editar usa principal; FAB y tarjetas con radio 8; sin literales; pruebas existentes de lista, detalle y formularios.
  - Hecho cuando: las ocho pantallas/widgets no contienen literales; las pruebas de mascotas pasan; suite y análisis en verde.

- [x] **T7. Dispositivos y aprovisionamiento con tokens.**
  - Requisitos: RF-03, RF-04, RF-07, RF-08, RF-09, RF-13, RF-14.
  - Archivos: `lib/features/dispenser/presentation/views/dispensers_page.dart`, `wifi_provisioning_page.dart`, `ble_scan_page.dart`, `register_dispenser_view.dart`, `qr_scaner_view.dart`; widgets `device_card_widget.dart`, `dispenser_food_progress_bar.dart`, `register_dispenser_form_widget.dart`; pruebas de dispositivos y aprovisionamiento.
  - Contenido: chip de unidad con radio 8 y sin píldora; progreso normal con `primary` y crítico con `alert`, con su contenido; avisos de éxito/error con `success`/`error`; textos de apoyo con `onSurfaceVariant`; velo del QR con `scrim` y franja de instrucciones con `inverseSurface`/`onInverseSurface`; radios y espaciados de tokens; se conserva el campo de contraseña compartido de T3.
  - Constitución: 3, 4, 6.
  - Tests primero: chip con radio 8, progreso con color de estado y contenido, snackbars desde el esquema, QR legible y sin literales; pruebas existentes de dispositivos, WiFi, BLE, QR y registro.
  - Hecho cuando: las ocho pantallas/widgets usan solo tokens; las pruebas del grupo pasan; suite y análisis en verde.

- [x] **T8. Configuración y cuenta con radios y espaciados de tokens.**
  - Requisitos: RF-03, RF-07, RF-08, RF-09, RF-13, RF-14 · RNF-05, RNF-06.
  - Archivos: `lib/features/settings/presentation/views/settings_view.dart`, `profile_view.dart`, `update_profile_view.dart`, `delete_account_view.dart`; widgets `settings_menu_tile.dart`, `appearance_mode_dialog.dart`, `delete_account_dialog.dart`, `profile_notice.dart`; pruebas de configuración.
  - Contenido: radios 20/16/12/10 pasan a 8/12 desde tokens; separaciones a `AppSpacing`; sin `TextStyle`, `fontSize`, `Colors.` ni `Color(0x`; se mantiene el campo de contraseña compartido.
  - Constitución: 3, 4, 6.
  - Tests primero: `settings_contrast_test` sigue verde; adaptar pruebas de vistas a las nuevas formas; comprobar 320/600/840 y texto 1.3 en las pantallas del menú.
  - Hecho cuando: configuración y cuenta solo usan tokens; `settings_contrast_test` y las pruebas del grupo pasan; suite y análisis en verde.

- [x] **T9. Historial: panel plegable y adaptación de la suite.**
  - Requisitos: RF-11, RF-12 · RNF-01, RNF-05.
  - Archivos: `lib/features/logs/presentation/views/logs_view.dart`, `widgets/log_filters_bar.dart`; `test/features/logs/presentation/views/logs_view_test.dart`.
  - Contenido: `_filtersExpanded` local, plegado por defecto y no persistido; botón con icono y texto «Filtros»; panel con los cuatro filtros y «Limpiar filtros» solo al abrir; permanece abierto al filtrar, paginar, recargar o reintentar; se pliega al reentrar; sin contador. No se toca el BLoC ni `LogFilters`.
  - Constitución: 3 (estado de presentación en la vista, no en el BLoC), 4 (pruebas de widget), 6.
  - Tests primero: añadir pruebas de plegado/despliegue, ciclo de vida y ausencia de contador; adaptar las 9 aserciones que hoy buscan campos o «Limpiar filtros» sin abrir, usando un helper que pulse «Filtros» antes de interactuar.
  - Hecho cuando: la suite del historial pasa completa; el filtrado, la paginación y los textos no cambian; `logs_view_layering_test` sigue verde; suite y análisis en verde.

- [x] **T10. Barrido final, pruebas estáticas y cierre.**
  - Requisitos: RF-01 a RF-14 · RNF-01 a RNF-08.
  - Archivos: todo `lib/features/`, `lib/core/presentation/` y `lib/core/theme/`; nuevas `test/core/theme/no_color_literals_test.dart`, `test/core/theme/spacing_scale_test.dart` y `test/core/presentation/responsive_theme_test.dart`; pruebas de vistas que lo requieran.
  - Contenido: eliminar literales, radios y `styleFrom` restantes en historial, core, nutrición, mascotas y dispositivos; sustituir por tokens según la tabla del plan; eliminar nombres heredados del morado; recorrer 320/600/840, vertical/horizontal y texto 1.3; comprobar contraste y el diff sin `api/` ni `DispensadorESP32/`.
  - Constitución: 2 (trazabilidad final), 3, 4 (suite completa), 5, 6.
  - Tests primero: `no_color_literals_test` recorre `lib/` salvo `app_colors.dart` y falla con `Color(0x`, `Colors.` (salvo `transparent`) o nombres heredados; `spacing_scale_test` valida `EdgeInsets` y huecos contra la escala; `responsive_theme_test` falla con desbordes o pares bajo umbral.
  - Hecho cuando: los tests estáticos y responsive pasan; `flutter test` completo pasa; `flutter analyze` no reporta errores; no hay desbordes a 320/600/840 con texto 1.3; ningún archivo de backend o firmware aparece en el diff; la spec queda implementada.
