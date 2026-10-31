import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/dispenser_food_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contraste(Color fondo, Color texto) {
  final l1 = fondo.computeLuminance();
  final l2 = texto.computeLuminance();
  final alto = l1 > l2 ? l1 : l2;
  final bajo = l1 > l2 ? l2 : l1;
  return (alto + 0.05) / (bajo + 0.05);
}

Color _compuesto(Color frente, Color fondo) {
  final alfa = frente.a;
  int canal(double arriba, double abajo) =>
      ((arriba * alfa + abajo * (1 - alfa)) * 255).round().clamp(0, 255);
  return Color.fromARGB(
    255,
    canal(frente.r, fondo.r),
    canal(frente.g, fondo.g),
    canal(frente.b, fondo.b),
  );
}

Future<void> _pump(WidgetTester tester, double gramos) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: DispenserFoodProgressBar(currentFoodGrams: gramos)),
    ),
  );
}

void main() {
  testWidgets('RF-04 y RF-14: el progreso normal usa primary', (tester) async {
    await _pump(tester, 2500);
    final esquema = AppTheme.lightTheme.colorScheme;

    final barra = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(barra.valueColor!.value, esquema.primary);
    expect(find.textContaining('Atención'), findsNothing);
  });

  testWidgets('RF-04 y RF-14: el progreso crítico usa alert con su contenido', (
    tester,
  ) async {
    await _pump(tester, 500);
    final esquema = AppTheme.lightTheme.colorScheme;
    final semantica = AppTheme.lightTheme.extension<AppSemanticColors>()!;

    final barra = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(barra.valueColor!.value, semantica.alert);

    final aviso = tester.widget<Text>(
      find.textContaining('Atención: Nivel crítico'),
    );
    expect(aviso.style?.color, esquema.onSurface);

    final contenedor = tester.widget<Container>(
      find
          .ancestor(
            of: find.byType(LinearProgressIndicator),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoracion = contenedor.decoration! as BoxDecoration;
    final borde = decoracion.border! as Border;
    expect(borde.top.color, esquema.outline);
    final bordeVisible = _compuesto(esquema.outline, esquema.surface);
    expect(
      _contraste(esquema.surface, bordeVisible),
      greaterThanOrEqualTo(3.0),
    );
  });
}
