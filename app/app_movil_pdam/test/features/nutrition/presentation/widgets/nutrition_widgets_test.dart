import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_result.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/widgets/nutrition_result_card.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/widgets/nutrition_snack_alert.dart';

/// Pruebas de widget de los componentes de presentación de nutrición (RF-4).
///
/// Verifican que la tarjeta muestra las métricas WSAVA con el formato esperado
/// y que la alerta de snacks comunica el exceso con texto e icono, sin depender
/// únicamente del color (RNF-5).
void main() {
  const result = NutritionResult(
    species: 'canino',
    bodyWeight: 12.5,
    mealsPerDay: 2,
    rerKcal: 465.3508909826865,
    merKcal: 744.5614255722985,
    variabilityMinKcal: 521.1929979006089,
    variabilityMaxKcal: 967.9298532439881,
    snackLimitKcal: 74.45614255722985,
    snacksKcal: 200.0,
    exceedsSnackLimit: true,
    finalRationKcal: 544.5614255722985,
    dailyRationGrams: 136.14035639307463,
    rationPerMealGrams: 68.07017819653731,
  );

  Future<void> pumpWidget(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  testWidgets('NutritionResultCard muestra las métricas WSAVA formateadas', (
    tester,
  ) async {
    await pumpWidget(tester, const NutritionResultCard(result: result));

    expect(find.text('Resultado de dosificación'), findsOneWidget);
    expect(find.text('Energía en reposo (RER)'), findsOneWidget);
    expect(find.text('465.4 kcal/día'), findsOneWidget);
    expect(find.text('Energía de mantenimiento (MER)'), findsOneWidget);
    expect(find.text('744.6 kcal/día'), findsOneWidget);
    expect(find.text('521.2 – 967.9 kcal/día'), findsOneWidget);
    expect(find.text('Ración diaria'), findsOneWidget);
    expect(find.text('136.1 g/día'), findsOneWidget);
    expect(find.text('Ración por comida (2 comidas)'), findsOneWidget);
    expect(find.text('68.1 g'), findsOneWidget);
    expect(find.text('Límite de snacks (10% del MER)'), findsOneWidget);
    expect(find.text('74.5 kcal/día'), findsOneWidget);
    expect(find.text('Snacks ingresados'), findsOneWidget);
    expect(find.text('200.0 kcal/día'), findsOneWidget);
  });

  testWidgets('NutritionSnackAlert describe el exceso con texto e icono', (
    tester,
  ) async {
    await pumpWidget(tester, const NutritionSnackAlert(result: result));

    expect(find.text('Snacks por encima del límite'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.textContaining('(200.0 kcal)'), findsOneWidget);
    expect(find.textContaining('(74.5 kcal)'), findsOneWidget);
    expect(find.textContaining('Reduce los snacks'), findsOneWidget);
  });

  testWidgets('RF-07 y RF-14: la tarjeta usa superficie, borde y radios del '
      'tema con datos en tertiary', (tester) async {
    await pumpWidget(tester, const NutritionResultCard(result: result));
    final esquema = AppTheme.lightTheme.colorScheme;

    final material = tester.widget<Material>(
      find
          .descendant(of: find.byType(Card), matching: find.byType(Material))
          .first,
    );
    expect(material.color, esquema.surface);
    expect(material.elevation, 0);
    final forma = material.shape! as RoundedRectangleBorder;
    expect(forma.borderRadius, BorderRadius.circular(8));
    expect(forma.side.color, esquema.outline);

    final rellenos = tester.widgetList<Padding>(
      find.descendant(of: find.byType(Card), matching: find.byType(Padding)),
    );
    expect(
      rellenos.any(
        (relleno) =>
            relleno.padding == const EdgeInsets.all(AppSpacing.cardPadding),
      ),
      isTrue,
    );

    final valor = tester.widget<Text>(find.text('465.4 kcal/día'));
    expect(valor.style?.color, esquema.tertiary);
    final etiqueta = tester.widget<Text>(find.text('Energía en reposo (RER)'));
    expect(etiqueta.style?.color, esquema.onSurfaceVariant);
  });

  testWidgets('RF-04 y RF-14: la alerta de snacks usa el rol alert con su '
      'contenido', (tester) async {
    await pumpWidget(tester, const NutritionSnackAlert(result: result));
    final semantica = AppTheme.lightTheme.extension<AppSemanticColors>()!;

    final contenedor = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(NutritionSnackAlert),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoracion = contenedor.decoration! as BoxDecoration;
    expect(decoracion.color, semantica.alert);
    expect(decoracion.borderRadius, BorderRadius.circular(8));

    final titulo = tester.widget<Text>(
      find.text('Snacks por encima del límite'),
    );
    expect(titulo.style?.color, semantica.onAlert);

    final l1 = semantica.alert.computeLuminance();
    final l2 = semantica.onAlert.computeLuminance();
    final alto = l1 > l2 ? l1 : l2;
    final bajo = l1 > l2 ? l2 : l1;
    expect((alto + 0.05) / (bajo + 0.05), greaterThanOrEqualTo(4.5));
  });
}
