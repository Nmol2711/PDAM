# Plan 022 — Resumen y gráfico del panel con datos reales

Spec: `specs/022-dashboard-summary-real/spec.md` (aprobada, 206 líneas). Alcance:
`api/` y `app/app_movil_pdam/`. Sin firmware, sin dependencias nuevas y sin cambios en el
esquema del servidor. Cumple `docs/constitution.md` (trazabilidad RF→prueba, lógica fuera
de las vistas, tests por capa, textos en español) y `AGENTS.md` (Clean Architecture,
Offline-First, temas globales).

## Enfoque

Tres bloques en orden de dependencia:

1. **Backend.** Dominio puro del panel (día local, semana, sumas y ocurrencias, con
   `ahora` y zona como parámetros), servicio que consulta `pets`, `dispensers`,
   `schedules` y `logs`, y endpoint que solo compone el contrato.
2. **Datos de la app.** Contrato con `today_index` y `calculated_at`, caché Isar nueva
   del último resumen, repositorio con prioridad remoto → caché → locales, y estados de
   error sin textos de excepción.
3. **Presentación.** Vista sin valores por defecto, aviso sin conexión con la fecha del
   servidor, gráfico de siete posiciones sin barras inventadas y porcentaje como valor
   derivado de dominio.

## Archivos

### Backend

| Archivo | Cambio |
|---------|--------|
| `api/app/domain/panel.py` (nuevo) | `RegistroDispensado`, `ResumenPanel`, `gramos_de_registro(medidos, descontados)`, `rango_semana_local(ahora, zona)`, `calcular_resumen(...)`. Puras, sin SQLAlchemy ni FastAPI; `ahora` y `zona` son parámetros. RF-1 a RF-5, RF-11. |
| `api/app/services/dashboard_service.py` (nuevo) | `resumen(db, *, user_id, ahora, zona=None)`: consulta mascotas, dispensadores activos, horarios de esas mascotas y `logs` del usuario desde el inicio de la semana; mapea a `RegistroDispensado` y delega el cálculo. RF-1 a RF-7, RF-11. |
| `api/app/schemas/schemas.py` | `DashboardSummary` conserva los siete campos y añade `today_index: int` y `calculated_at: str` (ISO 8601 UTC con `Z`). RF-6. |
| `api/app/api/endpoints/dashboard.py` | Reescrito: llama a `dashboard_service.resumen` con `tiempo.ahora_utc()` y devuelve el esquema; desaparecen las constantes y multiplicadores. RF-1 a RF-7. |
| `api/tests/test_panel_domain.py` (nuevo) | Dominio: día local, semana, medianoche, domingo 23:59, lunes 00:00, días futuros, gramos por registro y tope de completadas. |
| `api/tests/test_dashboard_summary.py` (nuevo) | Endpoint con datos reales de hoy y semana, sin actividad, sin mascotas, dispensador inactivo, registro futuro y usuario ajeno. RF-1 a RF-7, RF-10, RF-11, RNF-3. |
| `api/tests/test_dashboard_performance.py` (nuevo, T8) | p95 de 100 consultas consecutivas con 10 000 registros, sobre una base temporal propia y autocontenida. RNF-4. |

### App móvil — datos y estado

| Archivo | Cambio |
|---------|--------|
| `lib/features/dashboard/domain/entities/dashboard_summary.dart` | Añade `todayIndex`, `calculatedAt` (nullable solo para el resumen local sin caché) e `isFromCache`; `copyWith` y `props`. RF-6, RF-7, RF-12. |
| `lib/features/dashboard/data/models/dashboard_summary_model.dart` | `fromJson` estricto, sin `?? 300.0`: ausencia de `today_index`/`calculated_at` lanza `FormatException`, y los numéricos ausentes valen 0. RF-6, RF-12. |
| `lib/core/offline/models/local_dashboard_summary.dart` + `.g.dart` (nuevos) | Colección `LocalDashboardSummary` con clave única fija `ultimo`, los siete campos, `calculatedAt`, `todayIndex` y `cachedAt`. Autorizada por RNF-3. |
| `lib/features/dashboard/data/datasources/dashboard_local_datasource.dart` (nuevo) | `guardar(DashboardSummary)` y `leer()`, con la colección anterior; sin lógica de presentación. RF-7, RF-8. |
| `lib/core/offline/isar_service.dart` | Registra `LocalDashboardSummarySchema` en las dos aperturas de `Isar.open`. RNF-3. |
| `lib/features/dashboard/data/repositories/dashboard_repository_impl.dart` | Remoto → guarda caché (fallo de guardado no rompe la respuesta) → devuelve; si falla el remoto, caché con `isFromCache`; si no hay caché, mascotas y castradas de `LocalPet` y ceros; si también falla lo local, `Left`. Sin `n * 50` ni series literales. RF-7, RF-8, RF-12. |
| `lib/core/di/injection_container.dart` | Registra el datasource local y lo inyecta en `DashboardRepositoryImpl`. |
| `lib/features/dashboard/presentation/bloc/dashboard_cubit.dart` | `DashboardLoaded(summary, errorMessage?)`; `loadSummary` conserva el resumen visible si falla un refresco; error inicial con copy fijo en español; método de reintento. RF-8, RNF-1. |

### App móvil — presentación

| Archivo | Cambio |
|---------|--------|
| `lib/features/dashboard/domain/utils/dashboard_metrics.dart` (nuevo) | `porcentajeCumplimiento(dispensado, programado) -> int?` (null si programado ≤ 0, acotado 0–100, entero) y `formatearGramos(double)` sin decimales. RF-10, RNF-2. |
| `lib/features/dashboard/presentation/views/dashboard_view.dart` | Sin `300.0` ni `0` prefijados: estados de carga, error con reintento y contenido; aviso de datos sin conexión con la fecha de `calculatedAt`. RF-7, RF-8, RF-12. |
| `lib/features/dashboard/presentation/widgets/dashboard_chart_card.dart` | Recibe `weeklyDispensed` y `todayIndex` (la vista pasa `todayIndex` y elimina `dailyTarget`); siete grupos con etiqueta; valor 0 sin barra ni fondo de barra; resalta solo `todayIndex`; mensaje «Sin dispensaciones esta semana» si todo es 0. RF-9. |
| `lib/features/dashboard/presentation/widgets/dashboard_metrics_grid.dart` | Usa `porcentajeCumplimiento`; «—» sin programado; gramos sin decimales; etiqueta «Cumplimiento de lo programado». RF-10. |

### Pruebas de la app

- `test/features/dashboard/data/models/dashboard_summary_model_test.dart`
- `test/features/dashboard/data/repositories/dashboard_repository_impl_test.dart`
- `test/features/dashboard/domain/utils/dashboard_metrics_test.dart`
- `test/features/dashboard/presentation/bloc/dashboard_cubit_test.dart`
- `test/features/dashboard/presentation/widgets/dashboard_chart_card_test.dart`
- `test/features/dashboard/presentation/widgets/dashboard_metrics_grid_test.dart`
- `test/features/dashboard/presentation/views/dashboard_view_test.dart`

Se usan dobles escritos a mano, como en el resto del proyecto (no hay `mocktail` ni
`bloc_test` en `pubspec.yaml`). Las pruebas de caché abren Isar con
`IsarService.init(directory: tempDir.path)` y cierran en `tearDown`, siguiendo las pruebas
de cuenta existentes.

## Funciones puras

| Función | Responsabilidad | RF |
|---|---|---|
| `gramos_de_registro(medidos, descontados)` | Medidos, si no descontados, si no 0 | RF-2, RF-5 |
| `tiene_gramos(medidos, descontados)` | Al menos uno no nulo; un 0 cuenta como dato | RF-2, RF-4 |
| `rango_semana_local(ahora, zona)` | Inicio UTC de la semana, inicio y fin UTC del día local de hoy y `today_index` (0 lunes); cada límite con el desfase vigente en ese instante (horario de verano) | RF-5, RF-6, RF-11 |
| `calcular_resumen(total_mascotas, mascotas_castradas, gramos_horarios, registros, ahora, zona)` | Sumas de hoy, ocurrencias, programado, serie de siete posiciones y topes | RF-2 a RF-5, RF-7, RF-11 |
| `porcentajeCumplimiento(dispensado, programado)` | Entero 0–100 o null | RF-10 |
| `formatearGramos(gramos)` | Texto sin decimales | RF-10 |

## Algoritmo

```
RESUMEN(user_id, ahora, zona):
  inicio_semana_utc, inicio_dia_utc, fin_dia_utc, indice_hoy = rango_semana_local(ahora, zona)
  mascotas = mascotas del usuario
  horarios = horarios de mascotas con dispensador vinculado y activo
  registros = logs del usuario con event_type = feeding_dispensed
              y created_at entre inicio_semana_utc y fin_dia_utc
  resumen = calcular_resumen(
      total_mascotas=len(mascotas),
      castradas=cuenta(reproductive_status),
      gramos_horarios=[h.amount],
      registros=mapear(registros),
      ahora, zona)
  calculated_at = a_texto_utc(ahora)

CALCULAR_RESUMEN(...):
  hoy_local = fecha local de ahora
  dict_dias = {0..6: 0}
  completadas = 0; gramos_hoy = 0
  para cada registro:
      fecha_local = fecha local del instante, con el desfase vigente en ese instante
      si fecha_local > hoy_local: continuar          // días posteriores a hoy
      idx = fecha_local.weekday()
      gramos = gramos_de_registro(medidos, descontados)
      dict_dias[idx] += gramos
      si fecha_local == hoy_local:
          gramos_hoy += gramos
          si outcome == "success" y tiene_gramos(medidos, descontados):
              completadas += 1
  ocurrencias = len(gramos_horarios)
  completadas = min(completadas, ocurrencias)
  pendientes = max(0, ocurrencias - completadas)
  serie = [dict_dias[i] para i in 0..6]               // futuros quedan 0
  programado = sum(gramos_horarios)
```

El filtro de fechas de `logs` usa el índice `ix_logs_user_id_created_at`; el rango va
desde el inicio de la semana hasta el fin del día local de hoy, ambos en UTC, con el
desfase vigente en cada límite (RNF-4, RNF-8). Un registro de hoy con hora posterior a
`ahora` entra en la consulta y cuenta; uno de mañana queda fuera del rango y, además, se
descarta por fecha local.

## Decisiones

| Decisión | Alternativa descartada | Porqué |
|----------|------------------------|--------|
| Cálculo puro en `domain/panel.py` con `ahora` y `zona` inyectados | Calcular en el endpoint o en el servicio con `datetime.now()` | RNF-2: pruebas deterministas de medianoche, domingo y lunes; el servicio solo consulta. |
| Resumen del servidor como fuente y caché local como respaldo | Calcular el resumen en la app con horarios locales | Offline-First sin duplicar el motor: la app no puede saber qué se dispensó sin la tabla de logs. |
| Caché tipada en colección Isar nueva con clave fija | Guardar JSON crudo o reutilizar `LocalProfile` | RNF-3 autoriza la colección; tipada permite regenerar `g.dart` y validar campos. |
| `calculated_at` como texto ISO 8601 UTC con `Z` | `datetime` serializado por Pydantic | Evita ambigüedad de zona en respuestas y caché, igual que el contrato del historial de 014. |
| Fallo de guardado de caché no invalida la respuesta | Devolver error si no se puede cachear | El usuario debe ver datos frescos aunque falle Isar. |
| Refresco fallido conserva el resumen visible | Sustituirlo por la caché o por ceros | Precedente de 019: no degradar lo mostrado; la caché puede ser más vieja que lo visible. |
| Porcentaje en utilidad de dominio de la app | Calcularlo dentro del widget | RNF-2 y RNF-5 del proyecto: la vista no contiene reglas. |
| Sin respaldo por reloj del dispositivo para `today_index` | Usar `DateTime.now().weekday` si falta el campo | RF-6 y RF-11: la posición viene del servidor o de la caché; la caché nace con el campo. |
| Prueba de rendimiento autocontenida | Medir sobre la `test.db` compartida | p95 medido de 59,3 ms con 10 000 registros y base temporal propia; no depende de otras suites (RNF-4). |

## Estrategia de tests

1. **Dominio backend (T1).** Casos con zona fija (`timezone(timedelta(hours=-5))`):
   registro a las 00:00 local, domingo 23:59, lunes 00:00 que cambia de semana, registro
   de hoy con hora posterior al cálculo (se incluye) y registro de mañana (se excluye),
   fallo con medidos, éxito sin medidos con descontados, éxito sin gramos (no completa),
   más éxitos con gramos que horarios y sin horarios. Un caso con `ZoneInfo` de la stdlib
   en una zona con horario de verano comprueba que cada límite usa el desfase vigente en
   ese instante.
2. **Endpoint (T2).** Base `test.db` con `SessionLocal`, como `test_logs_query.py`; se
   siembran mascotas, dispensadores activos/inactivos, horarios y logs con `created_at`
   relativo a `ahora_utc()`; se comprueba el JSON completo, `today_index` y que
   `calculated_at` termina en `Z`. Usuario ajeno sin filas.
3. **Datos app (T3, T4).** Modelo sin `300`; repositorio con datasource remoto falso:
   remoto guarda caché, remoto falla y hay caché, remoto falla sin caché y hay mascotas,
   ambos fallan; caché corrupta o incompleta se descarta.
4. **Estado (T5).** Carga inicial correcta, error inicial con copy fijo, refresco fallido
   conserva resumen y expone `errorMessage`, reintento limpia el error.
5. **Presentación (T6, T7).** Widget del gráfico con siete etiquetas, sin barra ni fondo
   en 0, resaltado por `todayIndex`, mensaje de semana vacía; grid con «—» y porcentaje
   entero; vista con aviso sin conexión y su fecha, error con reintento y sin cifras por
   defecto.
6. **Cierre (T8).** `pytest` completo, incluida la prueba p95 del resumen con base
   temporal propia, `flutter test` completo, `flutter analyze`, verificación manual en el
   móvil y `MEMORY.md`.

## Trazabilidad

| RF | Tareas | Pruebas |
|----|--------|---------|
| RF-1, RF-2 | T1, T2 | Dominio: sumas por medidos/descontados; endpoint: hoy real y usuario ajeno. |
| RF-3 | T1, T2 | Dominio: programado solo con horarios dispensables; endpoint: dispensador inactivo. |
| RF-4 | T1, T2 | Dominio: tope de completadas y pendientes no negativo; endpoint: más éxitos que horarios. |
| RF-5 | T1, T2 | Dominio: siete posiciones, futuros en 0, semana vacía; endpoint: serie real. |
| RF-6 | T2, T3 | Endpoint: `today_index` y `calculated_at`; modelo: parseo estricto y ausencia. |
| RF-7 | T2, T4 | Endpoint sin datos; repositorio: caché con y sin resumen, locales y ceros. |
| RF-8 | T4, T5, T6 | Repositorio: fallos; cubit: conserva resumen y error fijo; vista: aviso y reintento. |
| RF-9 | T7 | Widget: siete posiciones, 0 sin barra ni fondo, resaltado y semana vacía. |
| RF-10 | T6, T7 | Utilidad y grid: entero, «—», gramos sin decimales. |
| RF-11 | T1, T2 | Dominio: medianoche, domingo 23:59, lunes 00:00; endpoint: `calculated_at` UTC. |
| RF-12 | T3, T6 | Modelo y vista sin `300.0`, sin meta ni completadas prefijadas. |
| RNF-1, RNF-2 | T1, T5, T6 | Copy fijo, utilidades puras y vistas sin reglas. |
| RNF-3 | T2, T4 | Sin dependencias; caché local autorizada. |
| RNF-4 | T8 | p95 de 100 consultas con 10 000 registros en base temporal propia (`test_dashboard_performance.py`). |

## Riesgos

- **Zona del equipo de pruebas:** usar siempre una zona fija inyectada; nunca depender de
  la zona local de la máquina que ejecuta `pytest`. Cada límite UTC de la semana y del día
  se calcula con el desfase vigente en ese instante, no con el de `ahora`, para soportar
  el horario de verano; se prueba con `ZoneInfo` de la stdlib en una zona con DST.
- **`created_at` naive en SQLite:** el servicio compara en UTC naive; no mezclar instantes
  con zona en la consulta.
- **Caché Isar nueva:** requiere `dart run build_runner build --delete-conflicting-outputs`
  y registrar el esquema en las dos aperturas de `IsarService`; olvidar la segunda rompe
  la recuperación tras corrupción.
- **Datos locales viejos:** la caché no existe antes de esta spec; una base local con
  colecciones previas debe migrar sin perder mascotas ni horarios.
- **`DashboardSummary` estricto:** un servidor sin los campos nuevos provoca error de
  parseo; backend y app se despliegan juntos (RF-6).
- **`fl_chart`:** un `toY: 0` con `backDrawRodData` sigue pintando fondo; la prueba debe
  comprobar el número de barras de fondo visibles, no solo el valor.
- **Pruebas de dashboard existentes:** `dashboard_theme_test.dart` y
  `dashboard_nutrition_entry_test.dart` montan la vista con el cubit real; revisar que no
  dependan del estado inicial con cifras prefijadas.
