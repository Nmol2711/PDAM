import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
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
  Future<NutritionCubit> pumpView(
    WidgetTester tester, {
    Size tamano = const Size(800, 2400),
    double textScaler = 1.0,
  }) async {
    // Superficie ampliada para que todo el formulario y sus resultados queden
    // visibles sin necesidad de desplazarse en el viewport por defecto (800x600).
    tester.view.physicalSize = tamano;
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaler)),
          child: child!,
        ),
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

  testWidgets('muestra el resultado de dosificación al calcular', (
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

  testWidgets('RF-08: el botón y los campos heredan el radio 8 del tema', (
    tester,
  ) async {
    await pumpView(tester);
    final esquema = Theme.of(
      tester.element(find.byType(NutritionCalculatorView)),
    ).colorScheme;

    final botonFinder = find.widgetWithText(FilledButton, 'Calcular');
    final boton = tester.widget<FilledButton>(botonFinder);
    expect(boton.style, isNull, reason: 'el botón no debe llevar estilo local');
    final material = tester
        .widgetList<Material>(
          find.descendant(of: botonFinder, matching: find.byType(Material)),
        )
        .firstWhere((widget) => widget.color == esquema.primary);
    expect(
      (material.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(8),
    );

    final decorador = tester.widget<InputDecorator>(
      find.descendant(
        of: find.byKey(const ValueKey('nutrition_body_weight')),
        matching: find.byType(InputDecorator),
      ),
    );
    final borde = decorador.decoration.border! as OutlineInputBorder;
    expect(borde.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('RNF-02: a 320 puntos con texto al 130 % no desborda', (
    tester,
  ) async {
    await pumpView(tester, tamano: const Size(320, 2400), textScaler: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('Calcular'), findsOneWidget);
  });

  testWidgets('RF-09: a 400 puntos el relleno de pantalla es 16', (
    tester,
  ) async {
    await pumpView(tester, tamano: const Size(400, 2400));

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      scroll.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.page,
      ),
    );
  });

  testWidgets('RF-09: desde 600 puntos el relleno de pantalla es 24', (
    tester,
  ) async {
    await pumpView(tester, tamano: const Size(600, 2400));

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      scroll.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageWide,
        vertical: AppSpacing.page,
      ),
    );
  });
}
