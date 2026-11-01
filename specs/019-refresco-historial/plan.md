# Plan 019 — Recarga manual y automática del historial

Spec: `specs/019-refresco-historial/spec.md` (aprobada). Sin backend, sin firmware, sin
dependencias nuevas.

## Enfoque

Tres bloques, en este orden:

1. **Dominio y BLoC.** Utilidad pura para la ventana de 4 s y el ajuste de página; evento
   de refresco con origen (manual/automático); estado con el origen del refresco en curso;
   generación de consulta para descartar resultados obsoletos; separación entre fallo de
   consulta y sin conexión. Todo con reloj inyectable.
2. **Vista.** Gesto de recarga con física siempre desplazable, refresco al activarse la
   pestaña y al reanudar la app, indicador único según el origen, sin tocar el panel de
   filtros ni la posición del scroll.
3. **Cierre.** `flutter analyze`, suite completa, verificación manual y `MEMORY.md`.

## Archivos

| Archivo | Cambio |
|---------|--------|
| `lib/features/logs/domain/utils/log_refresh_utils.dart` (nuevo) | `puedeRefrescarAutomatico(ultimoFin, ahora, ventana)` y `ajustarPagina(pagina, totalPaginas)`. Puras, con `ahora` como parámetro. |
| `lib/features/logs/presentation/bloc/log_event.dart` | Enum `LogRefreshOrigin { manual, automatico }` y evento `LogRefreshRequested(origin)`. |
| `lib/features/logs/presentation/bloc/log_state.dart` | Campo `refresco` (`LogRefreshOrigin?`), en `copyWith` y `props`. `isLoading` sigue siendo la bandera única de consulta en curso. |
| `lib/features/logs/presentation/bloc/log_bloc.dart` | Constructor con `ahora` y `ventanaRefresco` (por defecto `DateTime.now` y 4 s); handler de refresco; marca de fin del último automático; generación de consulta; ajuste de página con máximo una consulta extra; fallo limpia `isOffline` y éxito limpia `errorMessage`. |
| `lib/features/logs/presentation/views/logs_view.dart` | `RefreshIndicator` + `AlwaysScrollableScrollPhysics`; `WidgetsBindingObserver` y transición de `TickerMode`; barra lineal fuera de la lista y oculta en refresco manual; sin cambios en el panel de filtros. |
| `test/features/logs/domain/utils/log_refresh_utils_test.dart` (nuevo) | Ventana y ajuste de página. |
| `test/features/logs/presentation/bloc/log_bloc_test.dart` | Grupo nuevo de refresco (ventana, concurrencia, ajuste, fallo vs offline). |
| `test/features/logs/presentation/views/logs_view_test.dart` | Grupo nuevo de recarga (gesto, pestaña, ciclo de vida, diálogo, indicadores, scroll). |
| `MEMORY.md` | Solo en el cierre: decisiones y riesgos de la 019. |

No se toca `injection_container.dart`: los nuevos parámetros del BLoC tienen valor por
defecto.

## Algoritmo

```
al recibir LogRefreshRequested(origen):
  si hayRefrescoEnCurso: descartar sin tocar la marca
  si origen == automatico y no puedeRefrescarAutomatico(ultimoFinAutomatico, ahora()):
      descartar sin tocar la marca
  guardar instantánea (items, filtros, página, total, totalPages)
  consultar página actual con filtros actuales
  si la generación ya no es la vigente: salir sin emitir
  si falla: restaurar instantánea, errorMessage, isOffline = false, refresco = null
  si acierta: emitir página; si ajustarPagina(página, totalPages) != página:
      una sola consulta extra a la página ajustada (misma generación)
      si falla: restaurar instantánea, errorMessage
      si acierta: emitir
  al terminar (éxito o fallo) y si origen == automatico: ultimoFinAutomatico = ahora()
  refresco = null
```

- La carga inicial (`LogsRequested` con `hasLoaded == false`) fija `ultimoFinAutomatico` al
  terminar: por eso mostrarse la pestaña después no duplica (RF-3).
- Toda carga (refresco, filtro, página, reintento) incrementa la generación; los resultados
  de una generación anterior se descartan sin emitir (RF-4).
- El refresco no pide catálogo ni mascotas (fuera de alcance).

## Decisiones

| Decisión | Alternativa descartada | Porqué |
|----------|------------------------|--------|
| Reloj e intervalo inyectados en el BLoC | `DateTime.now()` interno | RNF-2: pruebas deterministas sin esperas reales; el valor por defecto mantiene DI intacta. |
| Generación de consulta para descartar | Paquete de concurrencia (`bloc_concurrency`) o transformer propio | Sin dependencias nuevas; el guardia cubre también la carrera entre refresco y cambio de filtro/página. |
| Una consulta extra acotada tras el ajuste de página | Bucle hasta encontrar página válida | RF-5 limita a una; evita cadenas si el total cambia durante el refresco. |
| Barra lineal fuera de la lista y oculta en manual | Mantener la barra como hijo de la lista | RF-4: el indicador no debe insertar ni desplazar contenido; el manual usa solo el spinner del gesto. |
| Marca de ventana al terminar, no al empezar | Marca al iniciar | RF-3/CP-13: evita encadenar refrescos cuando la consulta dura más de 4 s. |
| Detección de pestaña por transición de `TickerMode` + ciclo de vida | Escuchar solo `ModalRoute` o `initState` | `StatefulShellRoute.indexedStack` no desmonta la rama (MEMORY); el cierre de diálogos no genera transición y no refresca (CP-5). |
| Ajuste de página dentro del mismo refresco | Tratarlo como una carga nueva | No reinicia la ventana ni apila indicadores (RF-5). |

## Trazabilidad

| RF | Tarea | Pruebas |
|----|-------|---------|
| RF-1 | T1, T2 | BLoC: conserva filtros y página, no vacía la lista. Widget: gesto con lista vacía, sin barra lineal, sin estado vacío intermedio. |
| RF-2 | T1, T2 | BLoC: automático conserva filtros/página y ajusta. Widget: pestaña y reanudación refrescan; scroll y panel intactos; diálogo no refresca. |
| RF-3 | T1 | Ventana desde el fin, carga inicial como último automático, ignorada sin mover la marca, manual no la consume. |
| RF-4 | T1, T2 | BLoC: una consulta y un indicador, filtro/página descartan el refresco. Widget: indicador único y sin desplazar la lista. |
| RF-5 | T1 | Una consulta extra; fallo del ajuste restaura página, lista y filtros con error. |
| RF-6 | T1, T2 | Error con reintento y offline informativo sin reintento, nunca ambos; avisos ya existentes se mantienen. |
| RNF-1 a RNF-6 | T1–T3 | Tabla CP de la spec; analyze y suite completa en T3. |

## Riesgos

- **Concurrencia de eventos de bloc 9:** si los handlers se procesan en serie, el descarte es
  efectivo solo al terminar; la prueba debe fijar el estado final y el número de consultas,
  no el orden de emisión.
- **`RefreshIndicator` y animaciones:** MEMORY advierte de no usar `pumpAndSettle` con
  indicadores animados; usar `pump` con duraciones acotadas.
- **Reloj falso en pruebas de widget:** el BLoC se crea en el cuerpo del test (MEMORY), así
  que el reloj mutable debe pasarse en `crearBlocs`.
- **Mover la barra lineal fuera de la lista:** cambia la estructura del cuerpo; las pruebas
  existentes buscan el widget por tipo, pero hay que revisar que no dependan de su posición.
- **Plegado del panel (017 RF-11):** la prueba existente «se pliega al volver a la pestaña con
  el shell real» (`logs_view_test.dart:805-832`) espera hoy cero consultas; se adapta a «una
  consulta automática y panel plegado por 017», conservando sus aserciones de plegado.
- **Scroll:** conservar la posición exige no recrear la lista ni su controlador al refrescar.
