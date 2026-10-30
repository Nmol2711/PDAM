import 'package:app_movil_pdam/core/presentation/utils/settings_entry_visibility.dart';
import 'package:app_movil_pdam/core/presentation/widgets/main_navigation_shell.dart';
import 'package:app_movil_pdam/core/presentation/widgets/settings_entry_button.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// RF-01: una sola entrada al menú de configuración, decidida por ancho.
///
/// La función pura [debeMostrarEntrada] es la única fuente de verdad: por
/// debajo de 600 puntos vive en la cabecera de la pantalla principal y desde
/// 600 puntos solo en la barra del contenedor de navegación. Nunca hay dos.
void main() {
  group('debeMostrarEntrada (RF-01)', () {
    test('por debajo de 600 solo se muestra en la cabecera de la pantalla', () {
      for (final ancho in <double>[0, 320, 599, 599.99]) {
        expect(
          debeMostrarEntrada(ancho, UbicacionEntrada.cabeceraPantalla),
          isTrue,
          reason: 'ancho $ancho',
        );
        expect(
          debeMostrarEntrada(ancho, UbicacionEntrada.barraContenedor),
          isFalse,
          reason: 'ancho $ancho',
        );
      }
    });

    test('desde 600 solo se muestra en la barra del contenedor', () {
      for (final ancho in <double>[600, 600.01, 840, 1200]) {
        expect(
          debeMostrarEntrada(ancho, UbicacionEntrada.cabeceraPantalla),
          isFalse,
          reason: 'ancho $ancho',
        );
        expect(
          debeMostrarEntrada(ancho, UbicacionEntrada.barraContenedor),
          isTrue,
          reason: 'ancho $ancho',
        );
      }
    });

    test('nunca hay dos ubicaciones visibles para el mismo ancho', () {
      for (final ancho in <double>[320, 599.99, 600, 840]) {
        final cabecera = debeMostrarEntrada(
          ancho,
          UbicacionEntrada.cabeceraPantalla,
        );
        final barra = debeMostrarEntrada(
          ancho,
          UbicacionEntrada.barraContenedor,
        );
        expect(cabecera ^ barra, isTrue, reason: 'ancho $ancho');
      }
    });
  });

  group('SettingsEntryButton (RF-01)', () {
    Future<void> pumpButton(
      WidgetTester tester, {
      required double width,
      required UbicacionEntrada ubicacion,
      VoidCallback? onPressed,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            appBar: AppBar(
              actions: <Widget>[
                SettingsEntryButton(ubicacion: ubicacion, onPressed: onPressed),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('en 320 se dibuja en la cabecera con la etiqueta del catálogo', (
      tester,
    ) async {
      await pumpButton(
        tester,
        width: 320,
        ubicacion: UbicacionEntrada.cabeceraPantalla,
      );

      expect(find.byTooltip('Abrir configuración'), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('en 320 la barra del contenedor no dibuja entrada', (
      tester,
    ) async {
      await pumpButton(
        tester,
        width: 320,
        ubicacion: UbicacionEntrada.barraContenedor,
      );

      expect(find.byTooltip('Abrir configuración'), findsNothing);
    });

    testWidgets('en 600 la cabecera no dibuja entrada', (tester) async {
      await pumpButton(
        tester,
        width: 600,
        ubicacion: UbicacionEntrada.cabeceraPantalla,
      );

      expect(find.byTooltip('Abrir configuración'), findsNothing);
    });

    testWidgets('en 840 la barra del contenedor dibuja una sola entrada', (
      tester,
    ) async {
      await pumpButton(
        tester,
        width: 840,
        ubicacion: UbicacionEntrada.barraContenedor,
      );

      expect(find.byTooltip('Abrir configuración'), findsOneWidget);
    });

    testWidgets('la acción configurada se ejecuta al pulsar', (tester) async {
      var pulsado = false;
      await pumpButton(
        tester,
        width: 320,
        ubicacion: UbicacionEntrada.cabeceraPantalla,
        onPressed: () => pulsado = true,
      );

      await tester.tap(find.byTooltip('Abrir configuración'));

      expect(pulsado, isTrue);
    });
  });

  group('composición del contenedor con cuatro pantallas (RF-01)', () {
    const pantallas = <String>[
      '/inicio',
      '/mascotas',
      '/historial',
      '/dispositivos',
    ];

    Future<void> pumpShell(
      WidgetTester tester, {
      required double width,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: pantallas.first,
        routes: <RouteBase>[
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                MainNavigationShell(navigationShell: navigationShell),
            branches: <StatefulShellBranch>[
              for (final ruta in pantallas)
                StatefulShellBranch(
                  routes: <RouteBase>[
                    GoRoute(
                      path: ruta,
                      builder: (context, state) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Pantalla principal'),
                          actions: const <Widget>[
                            // La misma entrada que llevan las cuatro
                            // cabeceras reales: a 600 o más debe ocultarse.
                            SettingsEntryButton(
                              ubicacion: UbicacionEntrada.cabeceraPantalla,
                            ),
                          ],
                        ),
                        body: const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a 320 hay una entrada en la cabecera y ninguna en el '
        'contenedor', (tester) async {
      await pumpShell(tester, width: 320);

      expect(find.byTooltip('Abrir configuración'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(
        tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).items,
        hasLength(4),
      );
      expect(find.text('Configuración'), findsNothing);
    });

    testWidgets('a 600 hay una entrada en la barra y ninguna en las cuatro '
        'cabeceras', (tester) async {
      await pumpShell(tester, width: 600);

      expect(find.byTooltip('Abrir configuración'), findsOneWidget);

      final scaffold = tester.state<ScaffoldState>(
        find.byType(Scaffold).first,
      );
      scaffold.openDrawer();
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDrawer), findsOneWidget);
      expect(find.byType(NavigationDrawerDestination), findsNWidgets(4));
      expect(find.text('Configuración'), findsNothing);
    });

    testWidgets('a 840 hay una entrada en la barra y ninguna en las cuatro '
        'cabeceras', (tester) async {
      await pumpShell(tester, width: 840);

      expect(find.byTooltip('Abrir configuración'), findsOneWidget);
      expect(find.byType(NavigationDrawerDestination), findsNothing);
    });
  });
}
