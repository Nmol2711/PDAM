import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Banda de aviso sobre el visor del QR (RF-03, RF-04, RF-14).
///
/// Con [withScrim] pinta el velo del escáner con el color de velo del tema y
/// coloca el mensaje sobre una banda `inverseSurface` con su contenido.
class ScannerNoticeBand extends StatelessWidget {
  const ScannerNoticeBand({
    super.key,
    required this.message,
    this.withScrim = false,
  });

  final String message;
  final bool withScrim;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final banda = Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sectionGap),
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: esquema.inverseSurface,
        borderRadius: AppRadii.cardRadius,
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: esquema.onInverseSurface),
      ),
    );

    if (!withScrim) {
      return Center(child: banda);
    }

    return Container(
      color: esquema.scrim.withValues(alpha: 0.7),
      child: Center(child: banda),
    );
  }
}
