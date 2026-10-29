import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:app_movil_pdam/features/logs/domain/utils/log_time_utils.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:flutter/material.dart';

/// Barra de los cuatro filtros combinables del historial (RF-27 a RF-31).
///
/// No conoce el BLoC ni calcula zonas horarias: emite los filtros elegidos y la
/// vista los envía al estado.
class LogFiltersBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;

    return Container(
      color: colores.surfaceContainerHighest.withValues(alpha: 0.3),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          // En un móvil estrecho cada campo ocupa una fila completa para que
          // nada se desborde (RF-33).
          final anchoCampo = ancho < 400 ? ancho : (ancho - 8) / 2;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
                  onPressed: filters.hasActiveFilters ? onClear : null,
                  icon: const Icon(Icons.filter_alt_off, size: 18),
                  label: const Text('Limpiar filtros'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filtroMascota() {
    final seleccionada = pets.any((pet) => pet.id == filters.petId)
        ? filters.petId
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
        ...pets.map(
          (pet) => DropdownMenuItem<int?>(
            value: pet.id,
            child: Text(pet.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (valor) {
        onFiltersChanged(
          valor == null
              ? filters.copyWith(clearPetId: true)
              : filters.copyWith(petId: valor),
        );
      },
    );
  }

  Widget _filtroEvento() {
    final seleccionado =
        catalog.eventTypes.any((entrada) => entrada.code == filters.eventType)
        ? filters.eventType
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
        ...catalog.eventTypes.map(
          (entrada) => DropdownMenuItem<String?>(
            value: entrada.code,
            child: Text(entrada.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (valor) {
        onFiltersChanged(
          valor == null
              ? filters.copyWith(clearEventType: true)
              : filters.copyWith(eventType: valor),
        );
      },
    );
  }

  Widget _filtroResultado() {
    final seleccionado =
        catalog.outcomes.any((entrada) => entrada.code == filters.outcome)
        ? filters.outcome
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
        ...catalog.outcomes.map(
          (entrada) => DropdownMenuItem<String?>(
            value: entrada.code,
            child: Text(entrada.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (valor) {
        onFiltersChanged(
          valor == null
              ? filters.copyWith(clearOutcome: true)
              : filters.copyWith(outcome: valor),
        );
      },
    );
  }

  Widget _filtroFecha(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _elegirRango(context),
      icon: const Icon(Icons.calendar_today, size: 18),
      label: Text(_etiquetaRango, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.centerLeft,
      ),
    );
  }

  String get _etiquetaRango {
    final desde = filters.fromDate;
    final hasta = filters.toDate;
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
    final desde = filters.fromDate;
    final hasta = filters.toDate;

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
    onFiltersChanged(
      filters.copyWith(fromDate: rango.start, toDate: rango.end),
    );
  }

  InputDecoration _decoracion(String etiqueta) {
    return InputDecoration(
      labelText: etiqueta,
      isDense: true,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    );
  }
}
