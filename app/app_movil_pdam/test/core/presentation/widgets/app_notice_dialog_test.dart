import 'dart:io';

import 'package:app_movil_pdam/core/presentation/widgets/app_notice_dialog.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

// Pruebas de widget del componente de aviso reutilizable `AppNoticeDialog`
// (RF-09 · RNF-01 a RNF-07 · CL-13).
//
// El componente vive en `core` y no puede depender del módulo de dispensadores
// (RNF-02), por eso sus parámetros son primitivos: tono, icono, título,
// descripción y etiqueta de la acción.

const String _tituloAviso = 'Este dispensador ya está registrado';
const String _mensajeAviso =
    'Esa dirección ya está vinculada a otro registro del sistema. '
    'Escanea el código QR del dispensador correcto o revisa con qué cuenta '
    'está vinculado.';
const String _accionAviso = 'Entendido';

/// Mensaje largo para comprobar que el contenido se desplaza en lugar de
/// desbordarse cuando la fuente está ampliada (RNF-06, CL-13).
const String _mensajeLargo =
    'La dirección del dispensador no tiene un formato válido. Revisa que tenga '
    'doce caracteres hexadecimales, como en el ejemplo AA:BB:CC:DD:EE:FF, y '
    'recuerda que los separadores pueden ser dos puntos, guiones o espacios. '
    'Si el problema continúa después de corregirla, escanea de nuevo el código '
    'QR del dispositivo y comprueba que el dispenser que estas usando es el que '
    'corresponde a tu mascota.';

/// Monta la pantalla y abre el aviso. Devuelve nada: deja el diálogo en pantalla.
Future<void> _abrirAviso(
  WidgetTester tester, {
  required AppNoticeTone tone,
  required IconData icon,
  String title = _tituloAviso,
  String message = _mensajeAviso,
  String actionLabel = _accionAviso,
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => AppNoticeDialog.show(
                context,
                tone: tone,
                icon: icon,
                title: title,
                message: message,
                actionLabel: actionLabel,
              ),
              child: const Text('Abrir aviso'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Abrir aviso'));
  await tester.pumpAndSettle();
}

void main() {
  group('Contenido del aviso (RF-09)', () {
    testWidgets('muestra el título, la descripción y la etiqueta de la acción', (
      WidgetTester tester,
    ) async {
      await _abrirAviso(
        tester,
        tone: AppNoticeTone.warning,
        icon: Icons.warning_amber_rounded,
      );

      expect(find.byType(AppNoticeDialog), findsOneWidget);
      expect(find.text(_tituloAviso), findsOneWidget);
      expect(find.text(_mensajeAviso), findsOneWidget);
      expect(find.text(_accionAviso), findsOneWidget);
    });

    testWidgets('los tonos info y warning usan iconos distintos (RNF-05)', (
      WidgetTester tester,
    ) async {
      await _abrirAviso(
        tester,
        tone: AppNoticeTone.info,
        icon: Icons.wifi_off_rounded,
      );
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

      // Se cierra y se vuelve a abrir con el otro tono.
      await tester.tap(find.text(_accionAviso));
      await tester.pumpAndSettle();
      await _abrirAviso(
        tester,
        tone: AppNoticeTone.warning,
        icon: Icons.warning_amber_rounded,
      );

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
    });

    testWidgets('la acción principal cierra el aviso (RNF-03)', (
      WidgetTester tester,
    ) async {
      await _abrirAviso(
        tester,
        tone: AppNoticeTone.warning,
        icon: Icons.warning_amber_rounded,
      );
      expect(find.byType(AppNoticeDialog), findsOneWidget);

      await tester.tap(find.text(_accionAviso));
      await tester.pumpAndSettle();

      expect(find.byType(AppNoticeDialog), findsNothing);
      expect(find.text('Abrir aviso'), findsOneWidget);
    });
  });

  group('Legibilidad y adaptabilidad (RNF-06, CL-13)', () {
    testWidgets(
      'con textScaler 2.0 en 320 dp no hay excepción de layout',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _abrirAviso(
          tester,
          tone: AppNoticeTone.warning,
          icon: Icons.warning_amber_rounded,
          message: _mensajeLargo,
          textScaler: const TextScaler.linear(2.0),
        );

        expect(find.byType(AppNoticeDialog), findsOneWidget);
        expect(find.text(_tituloAviso), findsOneWidget);
        expect(find.text(_accionAviso), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'El diálogo no debe desbordarse.');

        // CL-13: la acción sigue accesible aunque el contenido no quepa entero.
        final Rect rectAccion = tester.getRect(
          find.descendant(
            of: find.byType(AppNoticeDialog),
            matching: find.byType(FilledButton),
          ),
        );
        expect(rectAccion.height, greaterThanOrEqualTo(48.0));
        expect(rectAccion.bottom, lessThanOrEqualTo(480.0));
        expect(
          find.descendant(
            of: find.byType(AppNoticeDialog),
            matching: find.byType(SingleChildScrollView),
          ),
          findsWidgets,
          reason: 'La descripción larga debe poder desplazarse, nunca recortarse.',
        );
      },
    );

    testWidgets('el ancho del contenido está acotado en pantalla ancha', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _abrirAviso(
        tester,
        tone: AppNoticeTone.info,
        icon: Icons.wifi_off_rounded,
      );

      expect(
        tester.getSize(find.text(_mensajeAviso)).width,
        lessThanOrEqualTo(420.0),
        reason: 'RNF-06: el contenido se acota para no estirarse en pantallas grandes.',
      );
    });
  });

  group('Estilo y tema (RNF-03, RNF-04)', () {
    testWidgets('usa los colores del tema en vez de colores fijos', (
      WidgetTester tester,
    ) async {
      await _abrirAviso(
        tester,
        tone: AppNoticeTone.warning,
        icon: Icons.warning_amber_rounded,
      );

      final ColorScheme colors = AppTheme.lightTheme.colorScheme;

      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundColor,
        colors.errorContainer,
      );
      expect(tester.widget<Icon>(find.byType(Icon)).color, colors.onErrorContainer);
      expect(
        find.widgetWithText(AlertDialog, _accionAviso),
        findsOneWidget,
        reason: 'RNF-03: AlertDialog de Material 3 con la acción principal.',
      );
    });

    testWidgets('se ve correctamente con Brightness.dark (RNF-04)', (
      WidgetTester tester,
    ) async {
      await _abrirAviso(
        tester,
        tone: AppNoticeTone.warning,
        icon: Icons.warning_amber_rounded,
        theme: AppTheme.darkTheme,
      );

      expect(find.byType(AppNoticeDialog), findsOneWidget);
      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundColor,
        AppTheme.darkTheme.colorScheme.errorContainer,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Accesibilidad (RNF-07)', () {
    testWidgets('el botón tiene al menos 48 dp de alto y nombre accesible', (
      WidgetTester tester,
    ) async {
      await _abrirAviso(
        tester,
        tone: AppNoticeTone.warning,
        icon: Icons.warning_amber_rounded,
      );

      // Se mide el botón del aviso, no el de la pantalla que queda detrás.
      final Finder botonAccion = find.descendant(
        of: find.byType(AppNoticeDialog),
        matching: find.byType(FilledButton),
      );

      expect(botonAccion, findsOneWidget);
      expect(tester.getSize(botonAccion).height, greaterThanOrEqualTo(48.0));

      final SemanticsNode nodoBoton = tester.getSemantics(botonAccion);
      expect(nodoBoton.label, contains(_accionAviso));
      expect(nodoBoton.flagsCollection.isButton, isTrue);
      // La etiqueta no puede anunciarse dos veces: el `FilledButton` ya expone
      // su texto, así que ningún `Semantics` extra debe repetirlo.
      expect(find.bySemanticsLabel(_accionAviso), findsOneWidget);
    });

    testWidgets('el icono del aviso tiene descripción accesible coherente', (
      WidgetTester tester,
    ) async {
      await _abrirAviso(
        tester,
        tone: AppNoticeTone.warning,
        icon: Icons.warning_amber_rounded,
      );
      expect(find.bySemanticsLabel('Advertencia'), findsWidgets);

      await tester.tap(find.text(_accionAviso));
      await tester.pumpAndSettle();

      await _abrirAviso(
        tester,
        tone: AppNoticeTone.info,
        icon: Icons.wifi_off_rounded,
      );
      expect(find.bySemanticsLabel('Información'), findsWidgets);
    });
  });

  group('Reutilización (RNF-01, RNF-02)', () {
    test('el componente no importa nada del módulo de dispensadores', () {
      final String fuente = File(
        'lib/core/presentation/widgets/app_notice_dialog.dart',
      ).readAsStringSync();

      expect(
        fuente.contains('features/dispenser'),
        isFalse,
        reason: 'RNF-02: el aviso de `core` no puede depender del feature.',
      );
    });
  });
}