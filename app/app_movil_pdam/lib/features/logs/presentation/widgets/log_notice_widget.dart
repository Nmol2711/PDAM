import 'package:flutter/material.dart';

/// Avisos de la pantalla de historial (RF-33, RF-34).
///
/// Un único componente con tres variantes: datos locales, lista vacía y error
/// con reintento. Los textos son los de la spec, sin emojis.
class LogNoticeWidget extends StatelessWidget {
  final _TipoAviso _tipo;
  final String? _mensaje;
  final VoidCallback? _onRetry;
  final bool _sinDatosLocales;

  const LogNoticeWidget.offline({super.key, bool sinDatosLocales = false})
    : _tipo = _TipoAviso.offline,
      _mensaje = null,
      _onRetry = null,
      _sinDatosLocales = sinDatosLocales;

  const LogNoticeWidget.empty({super.key})
    : _tipo = _TipoAviso.vacio,
      _mensaje = null,
      _onRetry = null,
      _sinDatosLocales = false;

  const LogNoticeWidget.error({
    super.key,
    required String message,
    required VoidCallback onRetry,
  }) : _tipo = _TipoAviso.error,
       _mensaje = message,
       _onRetry = onRetry,
       _sinDatosLocales = false;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;

    final (
      IconData icono,
      String titulo,
      String? detalle,
      Color fondo,
    ) = switch (_tipo) {
      _TipoAviso.offline => (
        Icons.cloud_off_outlined,
        'Datos sin conexión',
        'Total y páginas calculados sobre los datos locales',
        colores.secondaryContainer,
      ),
      _TipoAviso.vacio => (
        Icons.event_note_outlined,
        'No hay registros para los filtros seleccionados',
        null,
        colores.surfaceContainerHighest,
      ),
      _TipoAviso.error => (
        Icons.error_outline,
        _mensaje ?? 'No se pudo cargar el historial',
        null,
        colores.errorContainer,
      ),
    };

    return Card(
      elevation: 0,
      color: fondo,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 32, color: colores.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: textos.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (detalle != null) ...[
              const SizedBox(height: 4),
              Text(
                detalle,
                textAlign: TextAlign.center,
                style: textos.bodySmall,
              ),
            ],
            if (_sinDatosLocales) ...[
              const SizedBox(height: 4),
              Text(
                'No hay datos locales guardados',
                textAlign: TextAlign.center,
                style: textos.bodySmall,
              ),
            ],
            if (_tipo == _TipoAviso.error) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: _onRetry, child: const Text('Reintentar')),
            ],
          ],
        ),
      ),
    );
  }
}

enum _TipoAviso { offline, vacio, error }
