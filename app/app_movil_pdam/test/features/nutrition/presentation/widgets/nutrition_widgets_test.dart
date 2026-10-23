import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
