import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/utils/log_time_utils.dart';
import 'package:flutter/material.dart';

/// Tarjeta de un registro del historial (RF-33, RF-41).
///
/// Muestra fecha y hora, etiqueta del evento, etiquetas de resultado y causa,
/// mascota, MAC parcial y, en los dispensados, los gramos solicitados, medidos
/// y descontados. Todos los colores salen del tema global.
class LogItemWidget extends StatelessWidget {
  final ActivityLog log;

  const LogItemWidget({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: colores.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    log.etiquetaEvento,
                    style: textos.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _fechaHora(log),
                  style: textos.bodySmall?.copyWith(
                    color: colores.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (log.outcomeLabel != null)
                  _Etiqueta(
                    texto: log.outcomeLabel!,
                    esFallo: log.outcome == 'failure',
                  ),
                if (log.causeLabel != null) _Etiqueta(texto: log.causeLabel!),
                if (log.dispenserMacMasked != null)
                  _Etiqueta(
                    texto: log.dispenserMacMasked!,
                    icono: Icons.router_outlined,
                  ),
              ],
            ),
            if (log.petId != null) ...[
              const SizedBox(height: 8),
              Text(
                _mascota(log),
                style: textos.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (log.esDispensado && _tieneGramos) ...[
              const SizedBox(height: 6),
              Text(
                _gramos,
                style: textos.bodySmall?.copyWith(
                  color: colores.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _tieneGramos =>
      log.requestedGrams != null ||
      log.measuredGrams != null ||
      log.discountedGrams != null;

  String get _gramos {
    return 'Solicitados: ${_formatearGramos(log.requestedGrams)}'
        ' · Medidos: ${_formatearGramos(log.measuredGrams)}'
        ' · Descontados: ${_formatearGramos(log.discountedGrams)}';
  }

  String _formatearGramos(double? gramos) {
    if (gramos == null) return 'No disponible';
    final numero = gramos % 1 == 0
        ? gramos.toStringAsFixed(0)
        : gramos.toStringAsFixed(1);
    return '$numero g';
  }

  String _mascota(ActivityLog log) {
    final nombre = log.petName;
    if (nombre != null && nombre.isNotEmpty) return 'Mascota: $nombre';
    return 'Mascota #${log.petId}';
  }

  String _fechaHora(ActivityLog log) => formatearFechaHoraLocal(log.createdAt);
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final IconData? icono;
  final bool esFallo;

  const _Etiqueta({required this.texto, this.icono, this.esFallo = false});

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final fondo = esFallo
        ? colores.errorContainer
        : (icono == null
              ? colores.surfaceContainerHighest
              : colores.secondaryContainer);
    final frente = esFallo
        ? colores.onErrorContainer
        : (icono == null
              ? colores.onSurfaceVariant
              : colores.onSecondaryContainer);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 14, color: frente),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: frente),
            ),
          ),
        ],
      ),
    );
  }
}
