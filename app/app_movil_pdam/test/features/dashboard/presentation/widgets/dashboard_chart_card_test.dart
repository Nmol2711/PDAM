import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/widgets/dashboard_chart_card.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gráfico semanal del panel (RF-9, RNF-1, RNF-2): siete posiciones fijas,
/// cero sin barra ni fondo, resaltado por `todayIndex` y semana vacía.
void main() {
  Future<void> montar(
    WidgetTester tester, {
    required List<double> serie,
    required int todayIndex,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DashboardChartCard(
              weeklyDispensed: serie,
              todayIndex: todayIndex,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('dibuja siete posiciones etiquetadas de lunes a domingo', (
    tester,
  ) async {
    await montar(
      tester,
      serie: const [10, 0, 20, 0, 30, 0, 40],
      todayIndex: 0,
    );

    final grafica = tester.widget<BarChart>(find.byType(BarChart));
    final grupos = grafica.data.barGroups;

    expect(grupos, hasLength(7));
    for (var i = 0; i < 7; i++) {
      expect(grupos[i].x, i);
    }
    for (final etiqueta in ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom']) {
      expect(find.text(etiqueta), findsOneWidget);
    }
  });

  testWidgets('un día en 0 no pinta barra ni fondo de barra', (tester) async {
    await montar(
      tester,
      serie: const [10, 0, 20, 0, 30, 0, 40],
      todayIndex: 0,
    );

    final grafica = tester.widget<BarChart>(find.byType(BarChart));

    expect(grafica.data.barGroups[1].barRods, isEmpty);
    expect(grafica.data.barGroups[3].barRods, isEmpty);
    expect(grafica.data.barGroups[5].barRods, isEmpty);
  });

  testWidgets('un día con valor pinta barra y su fondo', (tester) async {
    await montar(
      tester,
      serie: const [10, 0, 20, 0, 30, 0, 40],
      todayIndex: 0,
    );

    final grafica = tester.widget<BarChart>(find.byType(BarChart));
    final barra = grafica.data.barGroups[2].barRods.single;

    expect(barra.toY, 20);
    expect(barra.backDrawRodData.show, isTrue);
    expect(barra.backDrawRodData.toY, grafica.data.maxY);
    expect(grafica.data.barGroups[0].barRods.single.toY, 10);
    expect(grafica.data.barGroups[6].barRods.single.toY, 40);
  });

  testWidgets('resalta solo la posición todayIndex, no el día del equipo', (
    tester,
  ) async {
    // `todayIndex` se separa del día real del equipo para demostrar que el
    // resaltado no depende del reloj del dispositivo.
    final indiceHoy = (DateTime.now().weekday - 1 + 3) % 7;
    await montar(
      tester,
      serie: const [20, 20, 20, 20, 20, 20, 20],
      todayIndex: indiceHoy,
    );

    final esquema = AppTheme.lightTheme.colorScheme;
    final grafica = tester.widget<BarChart>(find.byType(BarChart));
    final grupos = grafica.data.barGroups;

    for (var i = 0; i < grupos.length; i++) {
      final barra = grupos[i].barRods.single;
      if (i == indiceHoy) {
        expect(barra.color, esquema.tertiary);
      } else {
        expect(barra.color, esquema.tertiary.withValues(alpha: 0.5));
        expect(barra.color!.a, lessThan(1.0));
      }
    }

    final resaltadas = grupos
        .expand((grupo) => grupo.barRods)
        .where((barra) => barra.color!.a == 1.0);
    expect(resaltadas, hasLength(1));
  });

  testWidgets('una semana en 0 muestra el mensaje y no el gráfico', (
    tester,
  ) async {
    await montar(
      tester,
      serie: const [0, 0, 0, 0, 0, 0, 0],
      todayIndex: 2,
    );

    expect(find.byType(BarChart), findsNothing);
    expect(find.text('Sin dispensaciones esta semana'), findsOneWidget);
    expect(find.text('Dispensación Semanal (g)'), findsOneWidget);
  });

  testWidgets('una lista vacía no lanza y se trata como semana vacía', (
    tester,
  ) async {
    await montar(tester, serie: const <double>[], todayIndex: 0);

    expect(tester.takeException(), isNull);
    expect(find.byType(BarChart), findsNothing);
    expect(find.text('Sin dispensaciones esta semana'), findsOneWidget);
  });

  testWidgets('una serie con longitud distinta de 7 no lanza', (tester) async {
    await montar(tester, serie: const [10, 20], todayIndex: 1);

    expect(tester.takeException(), isNull);
    expect(find.byType(BarChart), findsNothing);
    expect(find.text('Sin dispensaciones esta semana'), findsOneWidget);
  });

  testWidgets('calcula maxY con margen y un intervalo horizontal seguro', (
    tester,
  ) async {
    await montar(
      tester,
      serie: const [10, 20, 0, 0, 0, 0, 0],
      todayIndex: 1,
    );

    final grafica = tester.widget<BarChart>(find.byType(BarChart));
    expect(grafica.data.maxY, closeTo(26, 0.0001));
    expect(grafica.data.gridData.horizontalInterval, closeTo(6.5, 0.0001));

    await montar(
      tester,
      serie: const [0.5, 0, 0, 0, 0, 0, 0],
      todayIndex: 0,
    );

    final graficaBaja = tester.widget<BarChart>(find.byType(BarChart));
    expect(graficaBaja.data.maxY, 1);
    expect(graficaBaja.data.gridData.horizontalInterval, greaterThan(0));
  });
}
