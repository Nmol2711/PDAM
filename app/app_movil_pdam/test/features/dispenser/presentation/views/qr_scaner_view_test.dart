import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/qr_scaner_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contraste(Color fondo, Color texto) {
  final l1 = fondo.computeLuminance();
  final l2 = texto.computeLuminance();
  final alto = l1 > l2 ? l1 : l2;
  final bajo = l1 > l2 ? l2 : l1;
  return (alto + 0.05) / (bajo + 0.05);
}

void main() {
  testWidgets('RF-04: el QR inválido usa error/onError y es legible', (
    tester,
  ) async {
    late BuildContext contexto;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              contexto = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    mostrarErrorQr(contexto);
    await tester.pump();

    final esquema = AppTheme.lightTheme.colorScheme;
    final aviso = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(aviso.backgroundColor, esquema.error);

    final texto = tester.widget<Text>(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Código QR inválido para el sistema PDAM'),
      ),
    );
    expect(texto.style?.color, esquema.onError);
    expect(
      _contraste(esquema.error, esquema.onError),
      greaterThanOrEqualTo(4.5),
    );
  });
}
