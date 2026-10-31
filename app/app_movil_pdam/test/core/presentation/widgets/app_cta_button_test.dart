import 'package:app_movil_pdam/core/presentation/widgets/app_cta_button.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cociente de contraste WCAG entre dos colores opacos.
double _contraste(Color fondo, Color texto) {
  final l1 = fondo.computeLuminance();
  final l2 = texto.computeLuminance();
  final alto = l1 > l2 ? l1 : l2;
  final bajo = l1 > l2 ? l2 : l1;
  return (alto + 0.05) / (bajo + 0.05);
}

Future<void> _montar(WidgetTester tester, ThemeData tema, Widget boton) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: tema,
      home: Scaffold(body: Center(child: boton)),
    ),
  );
}

FilledButton _boton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  group('RF-05: botón CTA de creación o compra', () {
    testWidgets('en claro pinta el CTA y su contenido con texto legible', (
      tester,
    ) async {
      var pulsaciones = 0;
      await _montar(
        tester,
        AppTheme.lightTheme,
        AppCtaButton(
          onPressed: () => pulsaciones++,
          child: const Text('Guardar Mascota'),
        ),
      );

      final semantica = AppTheme.lightTheme.extension<AppSemanticColors>()!;
      final boton = _boton(tester);
      final fondo = boton.style!.backgroundColor!.resolve(<WidgetState>{});
      final texto = boton.style!.foregroundColor!.resolve(<WidgetState>{});

      expect(fondo, semantica.cta);
      expect(texto, semantica.onCta);
      expect(_contraste(fondo!, texto!), greaterThanOrEqualTo(4.5));
      expect(find.text('Guardar Mascota'), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      expect(pulsaciones, 1);
    });

    testWidgets('en oscuro toma el CTA oscuro de la extensión', (tester) async {
      await _montar(
        tester,
        AppTheme.darkTheme,
        AppCtaButton(onPressed: () {}, child: const Text('Comprar')),
      );

      final semantica = AppTheme.darkTheme.extension<AppSemanticColors>()!;
      final boton = _boton(tester);
      expect(
        boton.style!.backgroundColor!.resolve(<WidgetState>{}),
        semantica.cta,
      );
      expect(
        boton.style!.foregroundColor!.resolve(<WidgetState>{}),
        semantica.onCta,
      );
    });

    testWidgets('usa el radio de control de 8 puntos', (tester) async {
      await _montar(
        tester,
        AppTheme.lightTheme,
        AppCtaButton(onPressed: () {}, child: const Text('Guardar Mascota')),
      );

      final forma =
          AppTheme.lightTheme.filledButtonTheme.style!.shape!.resolve(
                <WidgetState>{},
              )!
              as RoundedRectangleBorder;
      expect(forma.borderRadius, BorderRadius.circular(8));
    });

    testWidgets('deshabilitado conserva un contraste legible', (tester) async {
      await _montar(
        tester,
        AppTheme.lightTheme,
        const AppCtaButton(onPressed: null, child: Text('Guardar Mascota')),
      );

      final esquema = AppTheme.lightTheme.colorScheme;
      final boton = _boton(tester);
      expect(boton.onPressed, isNull);
      final fondo = boton.style!.backgroundColor!.resolve(<WidgetState>{
        WidgetState.disabled,
      });
      final texto = boton.style!.foregroundColor!.resolve(<WidgetState>{
        WidgetState.disabled,
      });

      expect(fondo, esquema.surfaceContainerHighest);
      expect(texto, esquema.onSurfaceVariant);
      expect(_contraste(fondo!, texto!), greaterThanOrEqualTo(4.5));
    });

    testWidgets('admite un icono opcional junto al texto', (tester) async {
      await _montar(
        tester,
        AppTheme.lightTheme,
        AppCtaButton(
          onPressed: () {},
          icon: Icons.add_shopping_cart,
          child: const Text('Añadir al carrito'),
        ),
      );

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);
      expect(find.text('Añadir al carrito'), findsOneWidget);
    });

    testWidgets('sin la extensión del tema usa los valores claros', (
      tester,
    ) async {
      await _montar(
        tester,
        ThemeData(useMaterial3: true),
        AppCtaButton(onPressed: () {}, child: const Text('Guardar Mascota')),
      );

      expect(
        _boton(tester).style!.backgroundColor!.resolve(<WidgetState>{}),
        AppSemanticColors.light.cta,
      );
    });
  });
}
