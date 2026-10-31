import 'package:app_movil_pdam/core/presentation/widgets/in_app_notification_banner.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _titulo = 'Título del aviso';
const String _mensaje = 'Mensaje del aviso';

/// Cociente de contraste WCAG entre dos colores opacos.
double _contraste(Color fondo, Color texto) {
  final l1 = fondo.computeLuminance();
  final l2 = texto.computeLuminance();
  final alto = l1 > l2 ? l1 : l2;
  final bajo = l1 > l2 ? l2 : l1;
  return (alto + 0.05) / (bajo + 0.05);
}

Future<void> _montar(
  WidgetTester tester,
  ThemeData tema,
  InAppNotificationBanner banner,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: tema,
      home: Scaffold(body: banner),
    ),
  );
}

BoxDecoration _decoracion(WidgetTester tester) {
  final contenedor = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(InAppNotificationBanner),
          matching: find.byType(Container),
        )
        .first,
  );
  return contenedor.decoration! as BoxDecoration;
}

Color _colorTexto(WidgetTester tester, String texto) =>
    tester.widget<Text>(find.text(texto)).style!.color!;

void main() {
  group('RF-04: banner de aviso con los roles del tema', () {
    testWidgets('éxito: relleno success y contenido onSuccess legible', (
      tester,
    ) async {
      await _montar(
        tester,
        AppTheme.lightTheme,
        const InAppNotificationBanner(
          title: _titulo,
          message: _mensaje,
          type: InAppNotificationType.success,
        ),
      );

      final semantica = AppTheme.lightTheme.extension<AppSemanticColors>()!;
      final decoracion = _decoracion(tester);
      final contenido = _colorTexto(tester, _titulo);

      expect(decoracion.color, semantica.success);
      expect(contenido, semantica.onSuccess);
      expect(_colorTexto(tester, _mensaje), semantica.onSuccess);
      expect(
        _contraste(decoracion.color!, contenido),
        greaterThanOrEqualTo(4.5),
      );
      final borde = decoracion.border! as Border;
      expect(borde.top.color, semantica.success);
    });

    testWidgets('alerta: relleno alert y contenido onAlert legible', (
      tester,
    ) async {
      await _montar(
        tester,
        AppTheme.lightTheme,
        const InAppNotificationBanner(
          title: _titulo,
          message: _mensaje,
          type: InAppNotificationType.warning,
        ),
      );

      final semantica = AppTheme.lightTheme.extension<AppSemanticColors>()!;
      final decoracion = _decoracion(tester);
      final contenido = _colorTexto(tester, _titulo);

      expect(decoracion.color, semantica.alert);
      expect(contenido, semantica.onAlert);
      expect(_colorTexto(tester, _mensaje), semantica.onAlert);
      expect(
        _contraste(decoracion.color!, contenido),
        greaterThanOrEqualTo(4.5),
      );
      final borde = decoracion.border! as Border;
      expect(borde.top.color, semantica.alert);
    });

    testWidgets(
      'información: tertiaryContainer con su contenido y borde de acento',
      (tester) async {
        await _montar(
          tester,
          AppTheme.lightTheme,
          const InAppNotificationBanner(
            title: _titulo,
            message: _mensaje,
            type: InAppNotificationType.info,
          ),
        );

        final esquema = AppTheme.lightTheme.colorScheme;
        final decoracion = _decoracion(tester);

        expect(decoracion.color, esquema.tertiaryContainer);
        expect(_colorTexto(tester, _titulo), esquema.onTertiaryContainer);
        expect(_colorTexto(tester, _mensaje), esquema.onTertiaryContainer);
        expect(
          _contraste(decoracion.color!, _colorTexto(tester, _titulo)),
          greaterThanOrEqualTo(4.5),
        );
        final borde = decoracion.border! as Border;
        expect(borde.top.color, esquema.tertiary);
      },
    );

    testWidgets('el aviso usa el radio de 8 de los tokens', (tester) async {
      await _montar(
        tester,
        AppTheme.lightTheme,
        const InAppNotificationBanner(
          title: _titulo,
          message: _mensaje,
          type: InAppNotificationType.info,
        ),
      );

      expect(_decoracion(tester).borderRadius, BorderRadius.circular(8));
    });

    testWidgets('la acción del aviso es un TextButton secundario', (
      tester,
    ) async {
      var pulsaciones = 0;
      await _montar(
        tester,
        AppTheme.lightTheme,
        InAppNotificationBanner(
          title: _titulo,
          message: _mensaje,
          type: InAppNotificationType.success,
          actionLabel: 'Más detalles',
          onAction: () => pulsaciones++,
        ),
      );

      expect(find.widgetWithText(TextButton, 'Más detalles'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Más detalles'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Más detalles'), findsNothing);
      await tester.tap(find.text('Más detalles'));
      expect(pulsaciones, 1);
    });

    testWidgets('en oscuro usa los pares del tema oscuro', (tester) async {
      final semantica = AppTheme.darkTheme.extension<AppSemanticColors>()!;
      final esquema = AppTheme.darkTheme.colorScheme;

      final pares = <InAppNotificationType, List<Color>>{
        InAppNotificationType.success: <Color>[
          semantica.success,
          semantica.onSuccess,
        ],
        InAppNotificationType.warning: <Color>[
          semantica.alert,
          semantica.onAlert,
        ],
        InAppNotificationType.info: <Color>[
          esquema.tertiaryContainer,
          esquema.onTertiaryContainer,
        ],
      };

      for (final caso in pares.entries) {
        await _montar(
          tester,
          AppTheme.darkTheme,
          InAppNotificationBanner(
            title: '${caso.key}',
            message: _mensaje,
            type: caso.key,
          ),
        );

        final decoracion = _decoracion(tester);
        expect(decoracion.color, caso.value[0], reason: '${caso.key}');
        expect(
          _colorTexto(tester, '${caso.key}'),
          caso.value[1],
          reason: '${caso.key}',
        );
        expect(
          _contraste(decoracion.color!, caso.value[1]),
          greaterThanOrEqualTo(4.5),
          reason: '${caso.key}',
        );
      }
    });
  });
}
