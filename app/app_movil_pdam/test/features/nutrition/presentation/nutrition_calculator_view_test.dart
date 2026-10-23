import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/nutrition/domain/usecases/calculate_nutrition_usecase.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/bloc/nutrition_cubit.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/views/nutrition_calculator_view.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/widgets/nutrition_result_card.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/widgets/nutrition_snack_alert.dart';

/// Pruebas de widget de la calculadora nutricional (RF-4, RNF-2).
///
/// Verifican que la vista es un [StatelessWidget] que refleja los resultados de
/// dosificación y las alertas de snacks sin lógica de negocio: toda la
/// interacción se resuelve a través del [NutritionCubit].
void main() {
  Future<NutritionCubit> pumpView(WidgetTester tester) async {
    // Superficie ampliada para que todo el formulario y sus resultados queden
    // visibles sin necesidad de desplazarse en el viewport por defecto (800x600).
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = NutritionCubit(
      calculateNutritionUsecase: const CalculateNutritionUsecase(),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: BlocProvider<NutritionCubit>.value(
          value: cubit,
          child: const NutritionCalculatorView(),
        ),
      ),
    );
    return cubit;
  }

  Future<void> tapCalcular(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Calcular'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calcular'));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el resultado de dosificación al calcular', (tester) async {
    await pumpView(tester);

    await tester.enterText(
      find.byKey(const ValueKey('nutrition_body_weight')),
      '12.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('nutrition_caloric_density')),
      '4000',
    );

    await tapCalcular(tester);

    expect(find.byType(NutritionResultCard), findsOneWidget);
    expect(find.text('Resultado de dosificación'), findsOneWidget);
    expect(find.byType(NutritionSnackAlert), findsNothing);
  });

  testWidgets('muestra la alerta cuando los snacks superan el 10% del MER', (
    tester,
  ) async {
    await pumpView(tester);

    await tester.enterText(
      find.byKey(const ValueKey('nutrition_body_weight')),
      '12.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('nutrition_caloric_density')),
      '4000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('nutrition_snacks_kcal')),
      '200',
    );

    await tapCalcular(tester);

    expect(find.byType(NutritionSnackAlert), findsOneWidget);
    expect(find.text('Snacks por encima del límite'), findsOneWidget);
    expect(find.byType(NutritionResultCard), findsOneWidget);
  });

  testWidgets('muestra el error ante una entrada no válida sin resultado', (
    tester,
  ) async {
    await pumpView(tester);

    await tester.enterText(
      find.byKey(const ValueKey('nutrition_body_weight')),
      'abc',
    );
    await tester.enterText(
      find.byKey(const ValueKey('nutrition_caloric_density')),
      '4000',
    );

    await tapCalcular(tester);

    expect(find.byType(NutritionResultCard), findsNothing);
    expect(find.textContaining('peso corporal'), findsOneWidget);
  });
}
