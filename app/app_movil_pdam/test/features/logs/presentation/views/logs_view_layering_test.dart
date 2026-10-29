import 'dart:io';

import 'package:app_movil_pdam/features/logs/presentation/widgets/log_pagination_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Prueba de la separación lógica/interfaz de RNF-5 (spec 014, T10).
///
/// La vista del historial solo compone widgets y emite eventos: no calcula
/// totales, páginas ni descuentos, y no accede a repositorios ni datasources.
/// La comprobación de fuentes detecta si alguien reintroduce esa lógica en la
/// capa de presentación; la de widget verifica que los totales se muestran tal
/// como llegan del estado, sin recalcularlos.
void main() {
  final vista = File('lib/features/logs/presentation/views/logs_view.dart');

  test('la vista no contiene cálculos de negocio ni acceso a datos', () {
    expect(vista.existsSync(), isTrue, reason: 'Falta ${vista.path}');
    final codigo = vista.readAsStringSync();

    // Cálculos de totales/páginas: pertenecen al dominio y al BLoC.
    for (final patron in <RegExp>[
      RegExp(r'\bceil\b'),
      RegExp(r'\bmath\.'),
      RegExp(r'~/'),
      RegExp(r'\btotal(?:Pages)?\s*[-+*/%]'),
      RegExp(r'\btotal(?:Pages)?\s*='),
    ]) {
      expect(
        patron.hasMatch(codigo),
        isFalse,
        reason: 'La vista no debe calcular totales (${patron.pattern})',
      );
    }

    // Sin paddings condicionados por datos de negocio.
    expect(
      RegExp(r'EdgeInsets[^\n]*\?').hasMatch(codigo),
      isFalse,
      reason: 'La vista no debe condicionar el layout a datos de negocio',
    );

    // Sin dependencias de datos: solo BLoC, widgets y entidades de presentación.
    expect(codigo.contains('/data/'), isFalse);
    expect(codigo.contains('repository'), isFalse);
    expect(codigo.contains('GetLogsUc'), isFalse);
    expect(codigo.contains('Dio'), isFalse);

    // La vista emite eventos; no ejecuta la consulta ni el filtrado.
    expect(codigo.contains('bloc.add('), isTrue);
  });

  testWidgets('los totales del estado se muestran sin recalcularlos', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LogPaginationBar(
            page: 7,
            totalPages: 99,
            total: 137,
            onPrevious: null,
            onNext: null,
          ),
        ),
      ),
    );

    expect(find.text('Página 7 de 99'), findsOneWidget);
    expect(find.text('137 registros'), findsOneWidget);
  });
}
