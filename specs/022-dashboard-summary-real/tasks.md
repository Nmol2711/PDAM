# Tareas 022 — Resumen y gráfico del panel con datos reales

Orden: T1 → T8. Tests primero en cada tarea. Comandos desde la raíz del repositorio.

- [x] **T1. Dominio puro del panel: día local, semana en curso, gramos y ocurrencias.**
  RF-1, RF-2, RF-3, RF-4, RF-5, RF-11 · RNF-2
  - Archivos: `api/app/domain/panel.py` (nuevo), `api/tests/test_panel_domain.py` (nuevo).
  - Incluye `RegistroDispensado`, `ResumenPanel`, `gramos_de_registro`,
    `rango_semana_local` y `calcular_resumen` con `ahora` y `zona` como parámetros.
  - Constitución: lógica pura fuera de endpoints y vistas (principio 3), trazabilidad
    RF→prueba (principio 2) y determinismo sin reloj real.
  - Hecho cuando: `cd api && pytest tests/test_panel_domain.py` en verde y cubre
    medianoche local, domingo 23:59, lunes 00:00 con cambio de semana, registro futuro,
    fallo con medidos, éxito sin medidos, tope de completadas y semana vacía.
  - Depende de: nada.

- [x] **T2. Servicio y endpoint del resumen con el contrato nuevo.**
  RF-1, RF-2, RF-3, RF-4, RF-5, RF-6, RF-7, RF-10, RF-11 · RNF-3, RNF-4, RNF-8
  - Archivos: `api/app/services/dashboard_service.py` (nuevo),
    `api/app/api/endpoints/dashboard.py`, `api/app/schemas/schemas.py`,
    `api/tests/test_dashboard_summary.py` (nuevo).
  - Incluye consulta de mascotas, horarios de mascotas con dispensador activo y logs
    `feeding_dispensed` desde el inicio de semana; `DashboardSummary` con `today_index` y
    `calculated_at`; se eliminan constantes y multiplicadores.
  - Constitución: consultas en servicio y contrato en esquema (principios 1 y 3); el
    endpoint no calcula; fechas UTC (RNF-8); sin cambios de esquema de BD.
  - Hecho cuando: `cd api && pytest tests/test_panel_domain.py tests/test_dashboard_summary.py`
    en verde, con hoy y semana reales, sin actividad, sin mascotas, dispensador inactivo,
    registro futuro, usuario ajeno, `today_index` correcto y `calculated_at` con sufijo
    `Z`; y `python -c "import app.main"` sin error.
  - Depende de: T1.

- [x] **T3. Contrato de la app: entidad y modelo estrictos, sin cifras por defecto.**
  RF-6, RF-12
  - Archivos: `lib/features/dashboard/domain/entities/dashboard_summary.dart`,
    `lib/features/dashboard/data/models/dashboard_summary_model.dart`,
    `test/features/dashboard/data/models/dashboard_summary_model_test.dart` (nuevo).
  - Incluye `todayIndex`, `calculatedAt` nullable solo para el resumen local e
    `isFromCache`; `fromJson` sin `?? 300.0` y sin respaldo por reloj del dispositivo.
  - Constitución: entidad en dominio y parseo en datos (principio 3); sin datos
    sensibles; el texto de error es fijo.
  - Hecho cuando: `cd app/app_movil_pdam && flutter test test/features/dashboard/data/models`
    en verde, incluyendo respuesta completa, numéricos ausentes en 0 y ausencia de
    `today_index`/`calculated_at` como error de formato.
  - Depende de: T2.

- [x] **T4. Caché local del último resumen y repositorio offline honesto.**
  RF-7, RF-8, RF-12 · RNF-3
  - Archivos: `lib/core/offline/models/local_dashboard_summary.dart` y `.g.dart`,
    `lib/features/dashboard/data/datasources/dashboard_local_datasource.dart` (nuevo),
    `lib/features/dashboard/data/repositories/dashboard_repository_impl.dart`,
    `lib/core/offline/isar_service.dart`, `lib/core/di/injection_container.dart`,
    `test/features/dashboard/data/repositories/dashboard_repository_impl_test.dart` (nuevo).
  - Incluye clave única `ultimo`, guardado tras respuesta remota, lectura como respaldo,
    locales (`LocalPet`) y ceros sin caché, y `Left` si también falla lo local; se
    eliminan `n * 50` y la serie literal.
  - Constitución: offline-first (AGENTS.md), colección nueva autorizada por RNF-3 y sin
    tocar colecciones existentes; repositorio sin lógica de presentación.
  - Hecho cuando: `cd app/app_movil_pdam && dart run build_runner build --delete-conflicting-outputs`
    regenera `local_dashboard_summary.g.dart` y
    `flutter test test/features/dashboard/data` pasa con remoto exitoso (guarda caché),
    remoto fallido con caché, remoto fallido sin caché con mascotas locales y ambos
    fallos.
  - Depende de: T3.

- [x] **T5. Estado del panel: error con copy fijo, conserva lo visible y reintento.**
  RF-8 · RNF-1, RNF-2
  - Archivos: `lib/features/dashboard/presentation/bloc/dashboard_cubit.dart`,
    `test/features/dashboard/presentation/bloc/dashboard_cubit_test.dart` (nuevo).
  - Incluye `DashboardLoaded(summary, errorMessage?)`, error inicial con texto fijo en
    español y método de reintento; nunca se emite `e.toString()` ni el mensaje del fallo.
  - Constitución: textos en español y sin textos de excepción (RNF-01 del proyecto);
    estado en BLoC, no en la vista.
  - Hecho cuando: `cd app/app_movil_pdam && flutter test test/features/dashboard/presentation/bloc`
    pasa con carga correcta, error inicial con copy fijo, refresco fallido que conserva
    el resumen y reintento que limpia el error.
  - Depende de: T4.

- [x] **T6. Vista y métricas sin valores inventados; aviso sin conexión y reintento.**
  RF-7, RF-8, RF-10, RF-12 · RNF-1, RNF-2
  - Archivos: `lib/features/dashboard/domain/utils/dashboard_metrics.dart` (nuevo),
    `lib/features/dashboard/presentation/views/dashboard_view.dart`,
    `lib/features/dashboard/presentation/widgets/dashboard_metrics_grid.dart`,
    `test/features/dashboard/domain/utils/dashboard_metrics_test.dart` (nuevo),
    `test/features/dashboard/presentation/widgets/dashboard_metrics_grid_test.dart`
    (nuevo), `test/features/dashboard/presentation/views/dashboard_view_test.dart` (nuevo).
  - Incluye estados de carga, error y contenido; aviso de datos sin conexión con la fecha
    de `calculatedAt`; porcentaje entero con «—» sin programado y gramos sin decimales.
  - Constitución: vistas solo presentan estado; utilidad pura en dominio; textos en
    español; sin `setState` de negocio.
  - Hecho cuando: `cd app/app_movil_pdam && flutter test test/features/dashboard`
    pasa con ausencia de `300.0`, aviso sin conexión con fecha del servidor, error con
    reintento, «—» y porcentaje redondeado; `flutter analyze` sin errores en el feature.
  - Depende de: T5.

- [x] **T7. Gráfico semanal real: siete posiciones, cero sin barra y semana vacía.**
  RF-9 · RNF-1, RNF-2
  - Archivos:
    `lib/features/dashboard/presentation/widgets/dashboard_chart_card.dart`,
    `test/features/dashboard/presentation/widgets/dashboard_chart_card_test.dart`
    (nuevo).
  - Incluye parámetros `weeklyDispensed` y `todayIndex`, retirada de `dailyTarget`,
    siete etiquetas, resaltado por `todayIndex` y mensaje «Sin dispensaciones esta
    semana».
  - Constitución: widget sin reglas de negocio, textos en español y sin emojis; colores
    del tema global.
  - Hecho cuando: `cd app/app_movil_pdam && flutter test test/features/dashboard/presentation/widgets/dashboard_chart_card_test.dart`
    pasa con siete posiciones, día en 0 sin barra ni fondo, resaltado del día correcto y
    semana vacía sin gráfico.
  - Depende de: T6.

- [x] **T8. Cierre: regresión, verificación manual y memoria.**
  RF-1 a RF-12 · RNF-1 a RNF-5
  - Archivos: `MEMORY.md` (cierre) y ajustes mínimos que exija la regresión.
  - Incluye `pytest` completo, `flutter test` completo, `flutter analyze`, prueba de 100
    consultas consecutivas del resumen con 10 000 logs y checklist manual en el móvil
    (cifras reales, aviso sin conexión, error con reintento, gráfico).
  - Constitución: tests en todas las capas y verificación manual previa a cerrar
    (AGENTS.md); sin dependencias nuevas.
  - Hecho cuando: `cd api && pytest` y `cd app/app_movil_pdam && flutter test` en verde,
    `flutter analyze` sin errores, p95 por debajo de 500 ms y checklist manual
    documentado en `MEMORY.md` junto con las decisiones de la 022.
  - Depende de: T7.
  - Verificación manual confirmada por el usuario el 2026-11-01.
