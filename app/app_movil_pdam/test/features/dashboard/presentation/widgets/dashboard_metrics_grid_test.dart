import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/widgets/dashboard_metrics_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Métricas del panel (RF-10, RF-12): porcentaje entero, «—» sin programado y
/// gramos sin decimales, sin valores inventados por la vista.
void main() {
  Future<void> montar(
    WidgetTester tester, {
    required double dispensado,
    required double programado,
  }) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DashboardMetricsGrid(
              totalPets: 2,
              sterilizedPets: 1,
              foodDispensedToday: dispensado,
              foodTargetToday: programado,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('sin programado muestra «—» en el cumplimiento', (tester) async {
    await montar(tester, dispensado: 120, programado: 0);

    expect(find.text('Cumplimiento de lo programado'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('muestra el porcentaje redondeado como entero', (tester) async {
    await montar(tester, dispensado: 150, programado: 300);

    expect(find.text('50%'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
  });

  testWidgets('muestra los gramos sin decimales', (tester) async {
    await montar(tester, dispensado: 149.6, programado: 300);

    expect(find.text('150'), findsOneWidget);
    expect(find.text('149.6'), findsNothing);
  });

  testWidgets('redondea el porcentaje al entero más cercano', (tester) async {
    await montar(tester, dispensado: 100, programado: 300);

    expect(find.text('33%'), findsOneWidget);
  });
}
