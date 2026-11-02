import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:app_movil_pdam/core/presentation/widgets/password_visibility_field.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_permission_result.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/provisioning_stage.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/wifi_provisioning_page.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/device_card_widget.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/provisioning_stage_messages.dart';

import '../../presentation/bloc/dispenser_bloc_test.dart';

double _contraste(Color fondo, Color texto) {
  final l1 = fondo.computeLuminance();
  final l2 = texto.computeLuminance();
  final alto = l1 > l2 ? l1 : l2;
  final bajo = l1 > l2 ? l2 : l1;
  return (alto + 0.05) / (bajo + 0.05);
}

void main() {
  testWidgets(
    'WifiProvisioningPage displays 2.4GHz warning and form elements in Spanish',
    (WidgetTester tester) async {
      final mockDevice = const ScannedDevice(
        name: 'PDAM-Config-[123456]',
        remoteId: 'AA:BB:CC:DD:EE:FF',
        rssi: -45,
      );

      final mockRepo = MockDispenserRepository();
      final dispensersBloc = buildDispenserBloc(mockRepo);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: dispensersBloc,
            child: WifiProvisioningPage(device: mockDevice),
          ),
        ),
      );

      // Verify 2.4GHz prominent warning text (RF-04 & RNF-05)
      expect(
        find.textContaining('SOLO es compatible con redes WiFi de 2.4GHz'),
        findsOneWidget,
      );
      expect(find.text('Nombre de red WiFi (SSID - 2.4GHz)'), findsOneWidget);
      expect(find.text('Contraseña WiFi'), findsOneWidget);
      expect(find.text('Enviar Credenciales y Conectar'), findsOneWidget);

      dispensersBloc.close();
    },
  );

  testWidgets('RF-10: la contraseña WiFi usa el ojo compartido', (
    WidgetTester tester,
  ) async {
    const mockDevice = ScannedDevice(
      name: 'PDAM-Config-[123456]',
      remoteId: 'AA:BB:CC:DD:EE:FF',
      rssi: -45,
    );
    final dispensersBloc = buildDispenserBloc(MockDispenserRepository());
    addTearDown(dispensersBloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: dispensersBloc,
          child: const WifiProvisioningPage(device: mockDevice),
        ),
      ),
    );

    expect(find.byType(PasswordVisibilityField), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), 'claveWiFi');
    await tester.pump();
    expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);

    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();

    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byType(PasswordVisibilityField),
              matching: find.byType(TextField),
            ),
          )
          .obscureText,
      isFalse,
    );
  });

  testWidgets(
    'DeviceCardWidget oculta conexión y estado de WiFi pero conserva el reset (RF-1, RF-2)',
    (WidgetTester tester) async {
      const dispenser = Dispenser(
        id: 1,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Dispensador 1',
        isActive: true,
        wifiSsid: 'HomeWiFi',
        currentFoodGrams: 5000.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceCardWidget(dispenser: dispenser, onResetWifi: () {}),
          ),
        ),
      );

      expect(find.text('Estado de WiFi:'), findsNothing);
      expect(find.textContaining('Red:'), findsNothing);
      expect(
        find.text('Aún no se han proporcionado las credenciales de wifi'),
        findsNothing,
      );
      expect(find.text('Conectado'), findsNothing);
      expect(find.text('Desconectado'), findsNothing);
      expect(find.text('Resetear WiFi'), findsOneWidget);
    },
  );

  testWidgets(
    'DeviceCardWidget no muestra el reset si no se proporciona (RF-1)',
    (WidgetTester tester) async {
      const dispenser = Dispenser(
        id: 1,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Dispensador 1',
        isActive: true,
        currentFoodGrams: 5000.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DeviceCardWidget(dispenser: dispenser)),
        ),
      );

      expect(find.text('Resetear WiFi'), findsNothing);
      expect(find.text('Estado de WiFi:'), findsNothing);
    },
  );

  const device = ScannedDevice(
    name: 'PDAM-Config-[123456]',
    remoteId: 'AA:BB:CC:DD:EE:FF',
    rssi: -45,
  );

  Future<DispenserBloc> pumpWifi(
    WidgetTester tester, {
    Size tamano = const Size(800, 1200),
    double textScaler = 1.0,
    MockDispenserRepository? repositorio,
    Future<void> Function()? openSettings,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bloc = buildDispenserBloc(repositorio ?? MockDispenserRepository());
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaler)),
          child: child!,
        ),
        home: BlocProvider<DispenserBloc>.value(
          value: bloc,
          child: WifiProvisioningPage(
            device: device,
            openSettings: openSettings,
          ),
        ),
      ),
    );
    await tester.pump();
    return bloc;
  }

  testWidgets('RF-08: el SSID hereda el radio 8 del tema', (tester) async {
    await pumpWifi(tester);

    final decorador = tester.widget<InputDecorator>(
      find.descendant(
        of: find.byType(TextFormField).first,
        matching: find.byType(InputDecorator),
      ),
    );
    final borde = decorador.decoration.border! as OutlineInputBorder;
    expect(borde.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('RF-04: el aviso de 2.4 GHz usa alert/onAlert y es legible', (
    tester,
  ) async {
    await pumpWifi(tester);
    final semantica = AppTheme.lightTheme.extension<AppSemanticColors>()!;

    final aviso = find.textContaining('SOLO es compatible con redes WiFi');
    final texto = tester.widget<Text>(aviso);
    expect(texto.style?.color, semantica.onAlert);

    final contenedor = tester.widget<Container>(
      find.ancestor(of: aviso, matching: find.byType(Container)).first,
    );
    final decoracion = contenedor.decoration! as BoxDecoration;
    expect(decoracion.color, semantica.alert);
    expect(
      _contraste(semantica.alert, semantica.onAlert),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('RF-09: la tarjeta de dispositivo rellena 16 también en ancho', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const dispenser = Dispenser(
      id: 1,
      macAddress: 'AA:BB:CC:DD:EE:FF',
      name: 'Dispensador 1',
      isActive: true,
      currentFoodGrams: 5000.0,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: DeviceCardWidget(dispenser: dispenser)),
      ),
    );

    final rellenos = tester
        .widgetList<Padding>(
          find.descendant(
            of: find.byType(DeviceCardWidget),
            matching: find.byType(Padding),
          ),
        )
        .where(
          (relleno) =>
              relleno.padding == const EdgeInsets.all(AppSpacing.cardPadding),
        );
    expect(rellenos.length, 1);
  });

  testWidgets('RF-09: la tarjeta de dispositivo usa gutter 16 y 24', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final caso in <({double ancho, double gutter})>[
      (ancho: 400, gutter: AppSpacing.page),
      (ancho: 800, gutter: AppSpacing.pageWide),
    ]) {
      tester.view.physicalSize = Size(caso.ancho, 900);
      tester.view.devicePixelRatio = 1.0;

      const dispenser = Dispenser(
        id: 1,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        name: 'Dispensador 1',
        isActive: true,
        currentFoodGrams: 5000.0,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: DeviceCardWidget(dispenser: dispenser)),
        ),
      );

      final tarjeta = tester.widget<Card>(find.byType(Card).first);
      expect(
        tarjeta.margin,
        EdgeInsets.symmetric(horizontal: caso.gutter, vertical: AppSpacing.sm),
        reason: 'ancho ${caso.ancho}',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });

  testWidgets('RF-09: el relleno de pantalla es 16 y 24 desde 600', (
    tester,
  ) async {
    await pumpWifi(tester, tamano: const Size(400, 1200));
    var scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      scroll.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.page,
      ),
    );

    await pumpWifi(tester, tamano: const Size(600, 1200));
    scroll = tester.widget<SingleChildScrollView>(
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

  testWidgets('RNF-02: a 320 puntos con texto al 130 % no desborda', (
    tester,
  ) async {
    await pumpWifi(tester, tamano: const Size(320, 1200), textScaler: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('Enviar Credenciales y Conectar'), findsOneWidget);
  });

  testWidgets('RF-04: el éxito del aprovisionamiento usa success/onSuccess', (
    tester,
  ) async {
    final bloc = buildDispenserBloc(MockDispenserRepository());
    addTearDown(bloc.close);
    final router = GoRouter(
      initialLocation: '/wifi',
      routes: <RouteBase>[
        GoRoute(
          path: '/wifi',
          builder: (context, state) => BlocProvider<DispenserBloc>.value(
            value: bloc,
            child: const WifiProvisioningPage(device: device),
          ),
        ),
        GoRoute(
          path: '/dispensers',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Dispositivos'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'RedCasa');
    await tester.enterText(find.byType(TextFormField).at(1), 'claveWiFi');
    await tester.pump();
    await tester.tap(find.text('Enviar Credenciales y Conectar'));
    await tester.pumpAndSettle();

    final semantica = AppTheme.lightTheme.extension<AppSemanticColors>()!;
    final aviso = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(aviso.backgroundColor, semantica.success);
    final texto = tester.widget<Text>(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Dispensador conectado y configurado exitosamente'),
      ),
    );
    expect(texto.style?.color, semantica.onSuccess);
  });

  testWidgets('RF-19: un fallo por etapa muestra su mensaje y habilita el botón', (
    tester,
  ) async {
    final bloc = await pumpWifi(
      tester,
      repositorio: MockDispenserRepository(shouldFail: true),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'RedCasa');
    await tester.enterText(find.byType(TextFormField).at(1), 'claveWiFi');
    await tester.pump();
    await tester.tap(find.text('Enviar Credenciales y Conectar'));
    await tester.pumpAndSettle();

    expect(bloc.state, isA<ProvisioningFailureState>());
    final failure = (bloc.state as ProvisioningFailureState).failure;
    expect(failure.stage, ProvisioningStage.conexion);
    expect(find.text(provisioningFailureMessage(failure)), findsOneWidget);
    expect(find.textContaining('Acércalo al teléfono'), findsOneWidget);

    // El estado terminal no es "en progreso": el botón vuelve a estar activo.
    final boton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(boton.onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('RF-17: la denegación permanente muestra el aviso de permisos', (
    tester,
  ) async {
    const failure = ProvisioningException(
      stage: ProvisioningStage.conexion,
      permission: BlePermissionResult.permanentlyDenied(),
    );
    final bloc = await pumpWifi(
      tester,
      repositorio: MockDispenserRepository(provisioningError: failure),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'RedCasa');
    await tester.enterText(find.byType(TextFormField).at(1), 'claveWiFi');
    await tester.pump();
    await tester.tap(find.text('Enviar Credenciales y Conectar'));
    await tester.pumpAndSettle();

    expect(bloc.state, isA<ProvisioningFailureState>());
    expect(
      find.text(provisioningPermissionMessage(failure.permission!)),
      findsOneWidget,
    );
    expect(find.textContaining('permisos'), findsOneWidget);

    final boton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(boton.onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('RF-17: la denegación recuperable permite reintentar', (
    tester,
  ) async {
    const failure = ProvisioningException(
      stage: ProvisioningStage.conexion,
      permission: BlePermissionResult.denied(),
    );
    final bloc = await pumpWifi(
      tester,
      repositorio: MockDispenserRepository(provisioningError: failure),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'RedCasa');
    await tester.enterText(find.byType(TextFormField).at(1), 'claveWiFi');
    await tester.pump();
    await tester.tap(find.text('Enviar Credenciales y Conectar'));
    await tester.pumpAndSettle();

    expect(bloc.state, isA<ProvisioningFailureState>());
    expect(
      find.text(provisioningPermissionMessage(failure.permission!)),
      findsOneWidget,
    );
    expect(find.textContaining('Vuelve a intentarlo'), findsOneWidget);

    final boton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(boton.onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  group('Catálogo de etapas del aprovisionamiento (RF-19 a RF-21)', () {
    test('los seis literales son los de la spec', () {
      expect(
        provisioningStageMessage(ProvisioningStage.conexion),
        'No se pudo conectar con el dispensador. Acércalo al teléfono y '
        'vuelve a intentarlo.',
      );
      expect(
        provisioningStageMessage(ProvisioningStage.descubrimiento),
        'El dispensador no respondió al iniciar la configuración. Vuelve a '
        'intentarlo.',
      );
      expect(
        provisioningStageMessage(ProvisioningStage.escritura),
        'No se pudieron enviar las credenciales al dispensador. Vuelve a '
        'intentarlo.',
      );
      expect(
        provisioningStageMessage(ProvisioningStage.desconexion),
        'La configuración se envió, pero el dispensador no confirmó el '
        'cierre de la conexión. Vuelve a intentarlo.',
      );
      expect(
        provisioningStageMessage(ProvisioningStage.conexion_perdida),
        'Se perdió la conexión con el dispensador. Acércalo al teléfono y '
        'vuelve a intentarlo.',
      );
      expect(
        provisioningStageMessage(ProvisioningStage.presupuesto_agotado),
        'La configuración tardó demasiado y se canceló. Vuelve a intentarlo.',
      );
    });

    test('los permisos y la ubicación tienen su copy', () {
      expect(
        provisioningPermissionMessage(
          const BlePermissionResult.permanentlyDenied(),
        ),
        'La aplicación no tiene autorización para usar el Bluetooth. '
        'Revisa los permisos en los ajustes.',
      );
      expect(
        provisioningPermissionMessage(const BlePermissionResult.denied()),
        contains('permiso de Bluetooth'),
      );
      expect(
        provisioningPermissionMessage(
          const BlePermissionResult.granted(
            locationRequired: true,
            locationEnabled: false,
          ),
        ),
        'Activa la ubicación del teléfono para configurar el dispensador.',
      );
    });
  });

  testWidgets('RF-19: el fallo de escritura usa el copy de su etapa y el error del tema', (
    tester,
  ) async {
    const failure = ProvisioningException(stage: ProvisioningStage.escritura);
    await pumpWifi(
      tester,
      repositorio: MockDispenserRepository(provisioningError: failure),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'RedCasa');
    await tester.enterText(find.byType(TextFormField).at(1), 'claveWiFi');
    await tester.pump();
    await tester.tap(find.text('Enviar Credenciales y Conectar'));
    await tester.pumpAndSettle();

    expect(
      find.text(provisioningStageMessage(ProvisioningStage.escritura)),
      findsOneWidget,
    );
    final esquema = Theme.of(
      tester.element(find.byType(WifiProvisioningPage)),
    ).colorScheme;
    final aviso = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(aviso.backgroundColor, esquema.error);
  });

  testWidgets('RF-17: la denegación permanente ofrece abrir ajustes', (
    tester,
  ) async {
    var settingsOpened = false;
    const failure = ProvisioningException(
      stage: ProvisioningStage.conexion,
      permission: BlePermissionResult.permanentlyDenied(),
    );
    final bloc = await pumpWifi(
      tester,
      repositorio: MockDispenserRepository(provisioningError: failure),
      openSettings: () async {
        settingsOpened = true;
      },
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'RedCasa');
    await tester.enterText(find.byType(TextFormField).at(1), 'claveWiFi');
    await tester.pump();
    await tester.tap(find.text('Enviar Credenciales y Conectar'));
    await tester.pumpAndSettle();

    expect(bloc.state, isA<ProvisioningFailureState>());
    expect(
      find.text(provisioningPermissionMessage(failure.permission!)),
      findsOneWidget,
    );
    expect(find.text('Abrir ajustes'), findsOneWidget);

    await tester.tap(find.text('Abrir ajustes'));
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);

    // El botón sigue habilitado: el fallo es terminal, no "en progreso".
    final boton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(boton.onPressed, isNotNull);
  });

  testWidgets('RNF-01: el error legado no muestra el texto de la excepción', (
    tester,
  ) async {
    final bloc = await pumpWifi(
      tester,
      repositorio: MockDispenserRepository(shouldFail: true),
    );

    bloc.add(const ResetWifiEvent(dispenserId: 'AA:BB:CC:DD:EE:FF'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo completar la operación. Vuelve a intentarlo.'),
      findsOneWidget,
    );
    expect(find.textContaining('Error al resetear'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });
}
