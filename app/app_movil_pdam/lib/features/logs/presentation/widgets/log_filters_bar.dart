import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:app_movil_pdam/features/logs/domain/utils/log_time_utils.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:flutter/material.dart';

/// Barra plegable de los cuatro filtros combinables del historial
/// (RF-27 a RF-31, RF-11 y RF-12).
///
/// El estado de plegado es de presentación y vive en este widget, no en la
/// vista principal (AGENTS.md): la vista solo compone y emite eventos. Cada
/// entrada a la pantalla crea una instancia nueva y empieza plegada; mientras
/// la pantalla siga montada, filtrar, paginar, recargar o reintentar no la
/// recrea, así que el panel permanece abierto.
class LogFiltersBar extends StatefulWidget {
  final LogFilters filters;
  final LogCatalog catalog;
  final List<Pet> pets;
  final ValueChanged<LogFilters> onFiltersChanged;
  final VoidCallback onClear;

  const LogFiltersBar({
    super.key,
    required this.filters,
    required this.catalog,
    required this.pets,
    required this.onFiltersChanged,
    required this.onClear,
  });

  @override
  State<LogFiltersBar> createState() => _LogFiltersBarState();
}

class _LogFiltersBarState extends State<LogFiltersBar> {
  bool _expanded = false;

  /// Último estado de visibilidad de la rama según `TickerMode`. El shell
  /// `StatefulShellRoute.indexedStack` desactiva `TickerMode` al ocultar la
  /// pestaña; al plegarse ahí se cumple «se pliega al reentrar» aunque el
  /// historial siga montado.
  bool _wasVisible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (!visible && _wasVisible) {
      // Se asigna antes del build que sigue a la dependencia; no hace falta
      // `setState` (y llamarlo aquí sería durante la fase de construcción).
      _expanded = false;
    }
    _wasVisible = visible;
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('logs_filters_toggle'),
              onPressed: _toggle,
              icon: const Icon(Icons.filter_alt_outlined, size: 18),
              label: const Text('Filtros'),
            ),
          ),
        ),
        if (_expanded)
          Container(
            color: colores.surfaceContainerHighest.withValues(alpha: 0.3),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: _panel(),
          ),
      ],
    );
  }

  Widget _panel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        // En un móvil estrecho cada campo ocupa una fila completa para que
        // nada se desborde (RF-33).
        final anchoCampo = ancho < 400 ? ancho : (ancho - AppSpacing.sm) / 2;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SizedBox(width: anchoCampo, child: _filtroMascota()),
                SizedBox(width: anchoCampo, child: _filtroEvento()),
                SizedBox(width: anchoCampo, child: _filtroResultado()),
                SizedBox(width: anchoCampo, child: _filtroFecha(context)),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.filters.hasActiveFilters
                    ? widget.onClear
                    : null,
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: const Text('Limpiar filtros'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _filtroMascota() {
    final seleccionada =
        widget.pets.any((pet) => pet.id == widget.filters.petId)
        ? widget.filters.petId
        : null;

    return DropdownButtonFormField<int?>(
      initialValue: seleccionada,
      isExpanded: true,
      decoration: _decoracion('Mascota'),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('Todas las mascotas', overflow: TextOverflow.ellipsis),
        ),
        ...widget.pets.map(
          (pet) => DropdownMenuItem<int?>(
            value: pet.id,
            child: Text(pet.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (valor) {
        widget.onFiltersChanged(
          valor == null
              ? widget.filters.copyWith(clearPetId: true)
              : widget.filters.copyWith(petId: valor),
        );
      },
    );
  }

  Widget _filtroEvento() {
    final seleccionado =
        widget.catalog.eventTypes.any(
          (entrada) => entrada.code == widget.filters.eventType,
        )
        ? widget.filters.eventType
        : null;

    return DropdownButtonFormField<String?>(
      initialValue: seleccionado,
      isExpanded: true,
      decoration: _decoracion('Tipo de evento'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Todos los tipos', overflow: TextOverflow.ellipsis),
        ),
        ...widget.catalog.eventTypes.map(
          (entrada) => DropdownMenuItem<String?>(
            value: entrada.code,
            child: Text(entrada.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (valor) {
        widget.onFiltersChanged(
          valor == null
              ? widget.filters.copyWith(clearEventType: true)
              : widget.filters.copyWith(eventType: valor),
        );
      },
    );
  }

  Widget _filtroResultado() {
    final seleccionado =
        widget.catalog.outcomes.any(
          (entrada) => entrada.code == widget.filters.outcome,
        )
        ? widget.filters.outcome
        : null;

    return DropdownButtonFormField<String?>(
      initialValue: seleccionado,
      isExpanded: true,
      decoration: _decoracion('Resultado'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Todos los resultados', overflow: TextOverflow.ellipsis),
        ),
        ...widget.catalog.outcomes.map(
          (entrada) => DropdownMenuItem<String?>(
            value: entrada.code,
            child: Text(entrada.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (valor) {
        widget.onFiltersChanged(
          valor == null
              ? widget.filters.copyWith(clearOutcome: true)
              : widget.filters.copyWith(outcome: valor),
        );
      },
    );
  }

  Widget _filtroFecha(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _elegirRango(context),
      icon: const Icon(Icons.calendar_today, size: 18),
      label: Text(_etiquetaRango, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
    );
  }

  String get _etiquetaRango {
    final desde = widget.filters.fromDate;
    final hasta = widget.filters.toDate;
    if (desde == null && hasta == null) return 'Rango de fechas';
    if (desde != null && hasta != null) {
      return '${formatearFechaCorta(desde)} - ${formatearFechaCorta(hasta)}';
    }
    if (desde != null) return 'Desde ${formatearFechaCorta(desde)}';
    return 'Hasta ${formatearFechaCorta(hasta!)}';
  }

  Future<void> _elegirRango(BuildContext context) async {
    final hoy = DateTime.now();
    final ultimoDia = DateTime(hoy.year, hoy.month, hoy.day);
    final desde = widget.filters.fromDate;
    final hasta = widget.filters.toDate;

    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: ultimoDia,
      initialDateRange: desde != null && hasta != null && !hasta.isBefore(desde)
          ? DateTimeRange(start: desde, end: hasta)
          : null,
      helpText: 'Rango de fechas',
    );

    if (rango == null) return;
    widget.onFiltersChanged(
      widget.filters.copyWith(fromDate: rango.start, toDate: rango.end),
    );
  }

  InputDecoration _decoracion(String etiqueta) {
    return InputDecoration(labelText: etiqueta, isDense: true);
  }
}
