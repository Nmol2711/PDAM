import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/scanner_notice_band.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contraste(Color fondo, Color texto) {
  final l1 = fondo.computeLuminance();
  final l2 = texto.computeLuminance();
  final alto = l1 > l2 ? l1 : l2;
  final bajo = l1 > l2 ? l2 : l1;
  return (alto + 0.05) / (bajo + 0.05);
}

Future<void> _pump(WidgetTester tester, {required bool conVelo}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: ScannerNoticeBand(
          message: 'No se pudo iniciar la cámara:\nCAMERA_ERROR',
          withScrim: conVelo,
        ),
      ),
    ),
  );
}

Container _banda(WidgetTester tester, ColorScheme esquema) =>
    tester.widget<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color ==
                esquema.inverseSurface,
      ),
    );

void main() {
  testWidgets('RF-04 y RF-14: la banda usa inverseSurface y su contenido', (
    tester,
  ) async {
    await _pump(tester, conVelo: false);
    final esquema = AppTheme.lightTheme.colorScheme;

    final banda = _banda(tester, esquema);
    final decoracion = banda.decoration! as BoxDecoration;
    expect(decoracion.color, esquema.inverseSurface);
    expect(decoracion.borderRadius, BorderRadius.circular(8));

    final texto = tester.widget<Text>(find.textContaining('No se pudo'));
    expect(texto.style?.color, esquema.onInverseSurface);
    expect(
      _contraste(esquema.inverseSurface, esquema.onInverseSurface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.color == esquema.scrim.withValues(alpha: 0.7),
      ),
      findsNothing,
    );
  });

  testWidgets('RF-04: el velo del QR usa scrim al 70 %', (tester) async {
    await _pump(tester, conVelo: true);
    final esquema = AppTheme.lightTheme.colorScheme;

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.color == esquema.scrim.withValues(alpha: 0.7),
      ),
      findsOneWidget,
    );
    expect(_banda(tester, esquema), isNotNull);
  });
}
