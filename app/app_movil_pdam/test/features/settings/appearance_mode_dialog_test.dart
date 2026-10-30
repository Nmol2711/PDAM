import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/core/theme/theme_cubit.dart';
import 'package:app_movil_pdam/features/account/domain/entity/appearance_mode.dart';
import 'package:app_movil_pdam/features/account/presentation/utils/appearance_mode_theme.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/appearance_mode_dialog.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage implements StorageService {
  _FakeStorage({Map<String, String>? valores}) : valores = {...?valores};

  final Map<String, String> valores;

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async {
    valores[key] = value;
    return const Right(null);
  }

  @override
  Future<Either<Failures, String?>> getString(String key) async =>
      Right(valores[key]);

  @override
  Future<Either<Failures, void>> deleteString(String key) async {
    valores.remove(key);
    return const Right(null);
  }
}

/// RF-22, RF-23 y RF-24: el diálogo «Modo de apariencia» ofrece exactamente
/// Claro, Oscuro y Automático, marca el activo, aplica el cambio al instante en
/// toda la aplicación —también con el diálogo abierto— y no cambia nada si se
/// cierra sin elegir.
///
/// El `MaterialApp` del arnés toma `themeMode` del `ThemeCubit`, igual que
/// `main.dart`, de modo que la prueba falla si la aplicación dejara de aplicar
/// el modo elegido.
void main() {
  Future<ThemeCubit> pumpHost(
    WidgetTester tester, {
    ThemeMode modo = ThemeMode.system,
    Brightness plataforma = Brightness.light,
    double width = 420,
    double height = 900,
    double textScaler = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Brillo del sistema para el modo Automático.
    tester.platformDispatcher.platformBrightnessTestValue = plataforma;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final themeCubit = ThemeCubit(
      storageService: _FakeStorage(
        valores: <String, String>{'user_theme_mode': codigoDeModo(modo)},
      ),
    );
    addTearDown(themeCubit.close);
    await themeCubit.loadTheme();

    await tester.pumpWidget(
      BlocProvider<ThemeCubit>.value(
        value: themeCubit,
        // Mismo cableado que `main.dart`: el tema de la aplicación sale del
        // cubit, no de un valor fijo del arnés (RF-22).
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) => MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScaler)),
              child: child!,
            ),
            home: Builder(
              builder: (context) {
                final activo = AppearanceMode.desdeCodigo(
                  codigoDeModo(themeMode),
                );
                return Scaffold(
                  body: Container(
                    key: const Key('host_fondo'),
                    color: Theme.of(context).scaffoldBackgroundColor,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('Modo activo: ${activo.etiqueta}'),
                        TextButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (context) =>
                                const AppearanceModeDialog(),
                          ),
                          child: const Text('Abrir diálogo'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return themeCubit;
  }

  Future<void> abrirDialogo(WidgetTester tester) async {
    await tester.tap(find.text('Abrir diálogo'));
    await tester.pumpAndSettle();
  }

  ListTile opcion(WidgetTester tester, String codigo) =>
      tester.widget<ListTile>(find.byKey(Key('appearance_mode_$codigo')));

  /// Brillo que ve un widget del árbol de la aplicación.
  Brightness brilloDe(WidgetTester tester, Finder finder) =>
      Theme.of(tester.element(finder)).brightness;

  /// Color de fondo que pinta el anfitrión con el tema activo.
  Color? fondo(WidgetTester tester) =>
      tester.widget<Container>(find.byKey(const Key('host_fondo'))).color;

  testWidgets('RF-24: muestra el título y exactamente tres opciones', (
    tester,
  ) async {
    await pumpHost(tester);
    await abrirDialogo(tester);

    expect(find.text('Modo de apariencia'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(3));
    expect(find.text('Claro'), findsOneWidget);
    expect(find.text('Oscuro'), findsOneWidget);
    expect(find.text('Automático'), findsOneWidget);
  });

  testWidgets('RF-24: marca el modo activo del dispositivo', (tester) async {
    await pumpHost(tester, modo: ThemeMode.dark);
    await abrirDialogo(tester);

    expect(opcion(tester, 'dark').selected, isTrue);
    expect(opcion(tester, 'light').selected, isFalse);
    expect(opcion(tester, 'system').selected, isFalse);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('RF-22: elegir aplica el cambio al instante en toda la '
      'aplicación con el diálogo abierto', (tester) async {
    final themeCubit = await pumpHost(
      tester,
      modo: ThemeMode.system,
      plataforma: Brightness.light,
    );
    await abrirDialogo(tester);

    final dialogo = find.byType(AppearanceModeDialog);
    expect(brilloDe(tester, dialogo), Brightness.light);
    expect(fondo(tester), AppTheme.lightTheme.scaffoldBackgroundColor);

    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();

    // El cubit cambió y, sobre todo, la aplicación lo aplicó: el diálogo sigue
    // abierto y su contexto ya ve el tema oscuro, igual que el resto del árbol.
    expect(themeCubit.state, ThemeMode.dark);
    expect(find.text('Modo de apariencia'), findsOneWidget);
    expect(brilloDe(tester, dialogo), Brightness.dark);
    expect(
      brilloDe(tester, find.byKey(const Key('host_fondo'))),
      Brightness.dark,
    );
    expect(fondo(tester), AppTheme.darkTheme.scaffoldBackgroundColor);
    expect(opcion(tester, 'dark').selected, isTrue);
    expect(opcion(tester, 'system').selected, isFalse);
    expect(find.text('Modo activo: Oscuro'), findsOneWidget);
  });

  testWidgets('RF-22 y RF-23: Automático sigue el brillo oscuro del sistema', (
    tester,
  ) async {
    final themeCubit = await pumpHost(
      tester,
      modo: ThemeMode.light,
      plataforma: Brightness.dark,
    );
    await abrirDialogo(tester);

    final dialogo = find.byType(AppearanceModeDialog);
    expect(brilloDe(tester, dialogo), Brightness.light);

    await tester.tap(find.text('Automático'));
    await tester.pumpAndSettle();

    expect(themeCubit.state, ThemeMode.system);
    expect(find.text('Modo de apariencia'), findsOneWidget);
    expect(brilloDe(tester, dialogo), Brightness.dark);
    expect(fondo(tester), AppTheme.darkTheme.scaffoldBackgroundColor);
    expect(find.text('Modo activo: Automático'), findsOneWidget);
  });

  testWidgets('RF-22 y RF-23: Automático sigue el brillo claro del sistema', (
    tester,
  ) async {
    final themeCubit = await pumpHost(
      tester,
      modo: ThemeMode.dark,
      plataforma: Brightness.light,
    );
    await abrirDialogo(tester);

    final dialogo = find.byType(AppearanceModeDialog);
    expect(brilloDe(tester, dialogo), Brightness.dark);

    await tester.tap(find.text('Automático'));
    await tester.pumpAndSettle();

    expect(themeCubit.state, ThemeMode.system);
    expect(brilloDe(tester, dialogo), Brightness.light);
    expect(fondo(tester), AppTheme.lightTheme.scaffoldBackgroundColor);
  });

  testWidgets('RF-22: cerrar sin elegir no cambia el modo', (tester) async {
    final themeCubit = await pumpHost(tester, modo: ThemeMode.light);
    await abrirDialogo(tester);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.text('Modo de apariencia'), findsNothing);
    expect(themeCubit.state, ThemeMode.light);
    expect(find.text('Modo activo: Claro'), findsOneWidget);
    expect(brilloDe(tester, find.byKey(const Key('host_fondo'))),
        Brightness.light);
  });

  testWidgets('RNF-02: el contenido respeta el padding horizontal del tema y '
      'queda alineado con el título', (tester) async {
    await pumpHost(tester);
    await abrirDialogo(tester);

    final titulo = tester.getTopLeft(find.text('Modo de apariencia')).dx;
    final primeraOpcion = tester.getTopLeft(find.byType(ListTile).first).dx;

    // El contenido conserva el margen horizontal del tema: las opciones
    // arrancan alineadas con el título y no pegadas al borde del diálogo.
    expect(titulo, greaterThan(0));
    expect(primeraOpcion, closeTo(titulo, 0.1));
  });

  testWidgets('RNF-02: a 320 puntos con texto al 130 % no hay desbordamientos '
      'y las tres opciones siguen accionables', (tester) async {
    final themeCubit = await pumpHost(
      tester,
      width: 320,
      height: 480,
      textScaler: 1.3,
    );
    await abrirDialogo(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ListTile), findsNWidgets(3));
    _esperarOpcionesVisibles(tester, 320, 480);

    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(themeCubit.state, ThemeMode.dark);
  });

  testWidgets('RNF-02: a 600 puntos con texto al 130 % no hay desbordamientos '
      'y las tres opciones siguen accionables', (tester) async {
    final themeCubit = await pumpHost(
      tester,
      width: 600,
      height: 800,
      textScaler: 1.3,
    );
    await abrirDialogo(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ListTile), findsNWidgets(3));
    _esperarOpcionesVisibles(tester, 600, 800);

    await tester.tap(find.text('Automático'));
    await tester.pumpAndSettle();
    expect(themeCubit.state, ThemeMode.system);
  });

  testWidgets('RNF-02: a 840 puntos en horizontal con texto al 130 % no hay '
      'desbordamientos y las tres opciones siguen accionables', (tester) async {
    final themeCubit = await pumpHost(
      tester,
      width: 840,
      height: 400,
      textScaler: 1.3,
    );
    await abrirDialogo(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ListTile), findsNWidgets(3));
    _esperarOpcionesVisibles(tester, 840, 400);

    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();
    expect(themeCubit.state, ThemeMode.light);
  });
}

/// Comprueba que las tres opciones caben en la pantalla y son accionables.
void _esperarOpcionesVisibles(WidgetTester tester, double width, double height) {
  for (final codigo in <String>['light', 'dark', 'system']) {
    final rect = tester.getRect(find.byKey(Key('appearance_mode_$codigo')));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(width));
    expect(rect.bottom, lessThanOrEqualTo(height));
    expect(
      tester.widget<ListTile>(find.byKey(Key('appearance_mode_$codigo'))).enabled,
      isTrue,
    );
  }
}
