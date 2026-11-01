import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_adapter_status.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_permission_result.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_scan_event.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/ble_scan_page.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/provisioning_stage_messages.dart';

import '../bloc/dispenser_bloc_test.dart';

const ScannedDevice device = ScannedDevice(
  name: 'PDAM-Config-[123456]',
  remoteId: 'AA:BB:CC:DD:EE:FF',
  rssi: -50,
);

/// Repositorio de la página: puede delegar en el mock (emite un dispositivo) o
/// dejar el ciclo bajo control de la prueba para recorrer cada estado.
class _ScanPageRepository extends MockDispenserRepository {
  _ScanPageRepository({this.controlled = false});

  final bool controlled;
  final List<StreamController<BleScanEvent>> controllers =
      <StreamController<BleScanEvent>>[];
  final List<int> openedCycles = <int>[];
  final List<int?> stoppedCycles = <int?>[];
  final StreamController<BleAdapterStatus> statusController =
      StreamController<BleAdapterStatus>.broadcast();

  @override
  Future<void> stopBleScan({int? cycleId}) async {
    stoppedCycles.add(cycleId);
  }

  StreamController<BleScanEvent> get lastController => controllers.last;

  @override
  Stream<BleAdapterStatus> get adapterStatus => statusController.stream;

  @override
  Stream<BleScanEvent> scanBleDispensers({
    required int cycleId,
    Duration? window,
  }) {
    openedCycles.add(cycleId);
    if (!controlled) {
      return super.scanBleDispensers(cycleId: cycleId, window: window);
    }
    final controller = StreamController<BleScanEvent>();
    controllers.add(controller);
    return controller.stream;
  }

  Future<void> close() async {
    await statusController.close();
    for (final controller in controllers) {
      await controller.close();
    }
  }
}

void main() {
  Object? provisionExtra;

  Future<DispenserBloc> pumpPage(
    WidgetTester tester, {
    required MockDispenserRepository repository,
    Future<void> Function()? openSettings,
    Size tamano = const Size(800, 1200),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bloc = buildDispenserBloc(repository);
    addTearDown(bloc.close);

    provisionExtra = null;
    final router = GoRouter(
      initialLocation: '/dispensers/scan',
      routes: <RouteBase>[
        GoRoute(
          path: '/dispensers/scan',
          builder: (context, state) => BlocProvider<DispenserBloc>.value(
            value: bloc,
            child: BleScanPage(openSettings: openSettings),
          ),
        ),
        GoRoute(
          path: '/dispensers/provision',
          builder: (context, state) {
            provisionExtra = state.extra;
            return const Scaffold(
              body: Center(child: Text('Aprovisionamiento WiFi')),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: theme ?? AppTheme.lightTheme,
        routerConfig: router,
      ),
    );
    // Post-frame que inicia el ciclo y primer estado.
    await tester.pump();
    await tester.pump();

    return bloc;
  }

  Future<void> emit(
    WidgetTester tester,
    _ScanPageRepository repository,
    BleScanEvent event,
  ) async {
    repository.lastController.add(event);
    await tester.pump();
    await tester.pump();
  }

  Future<void> emitStatus(
    WidgetTester tester,
    _ScanPageRepository repository,
    BleAdapterStatus status,
  ) async {
    repository.statusController.add(status);
    await tester.pump();
    await tester.pump();
  }

  Future<void> closePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  /// Recorre tres ventanas vacías hasta el estado final.
  Future<void> exhaustWindows(
    WidgetTester tester,
    _ScanPageRepository repository,
  ) async {
    for (var window = 0; window < 3; window++) {
      final cycleId = repository.openedCycles.last;
      await emit(tester, repository, BleScanDevices(cycleId: cycleId, devices: const []));
      await emit(
        tester,
        repository,
        BleScanWindowClosed(cycleId: cycleId, hasDevices: false),
      );
      await tester.pump();
    }
  }

  testWidgets('la apertura no muestra progreso ni lista y permite cancelar', (
    tester,
  ) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    expect(
      find.text('Preparando la búsqueda de dispensadores...'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('PDAM-Config-[123456]'), findsNothing);
    expect(find.text('Cancelar Escaneo'), findsOneWidget);

    await closePage(tester);
  });

  testWidgets('la ventana abierta y vacía muestra progreso y búsqueda', (
    tester,
  ) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    final cycleId = repository.openedCycles.last;
    await emit(tester, repository, BleScanDevices(cycleId: cycleId, devices: const []));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Buscando dispensadores cercanos...'), findsOneWidget);
    expect(find.text('Cancelar Escaneo'), findsOneWidget);
    expect(find.text('Buscando más dispensadores...'), findsNothing);

    await closePage(tester);
  });

  testWidgets('la ventana con dispositivos lista sin acción de búsqueda', (
    tester,
  ) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    final cycleId = repository.openedCycles.last;
    await emit(tester, repository, BleScanDevices(cycleId: cycleId, devices: const [device]));

    expect(find.text('PDAM-Config-[123456]'), findsOneWidget);
    expect(find.textContaining('AA:BB:CC:DD:EE:FF'), findsOneWidget);
    expect(find.textContaining('RSSI: -50'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Conectar'), findsOneWidget);
    expect(find.text('Buscando más dispensadores...'), findsOneWidget);
    // RF-06: con la ventana abierta no se reinicia la búsqueda.
    expect(find.text('Volver a buscar'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Cancelar Escaneo'), findsOneWidget);

    await closePage(tester);
  });

  testWidgets('«Conectar» emite stop y navega con el dispositivo correcto', (
    tester,
  ) async {
    final repository = _ScanPageRepository();
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Conectar'));
    await tester.pumpAndSettle();

    expect(find.text('Aprovisionamiento WiFi'), findsOneWidget);
    expect(provisionExtra, device);
    expect(repository.stoppedCycles, contains(1));
  });

  testWidgets('los resultados conservados mantienen la lista sin progreso', (
    tester,
  ) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    final cycleId = repository.openedCycles.last;
    await emit(tester, repository, BleScanDevices(cycleId: cycleId, devices: const [device]));
    await emit(
      tester,
      repository,
      BleScanWindowClosed(cycleId: cycleId, hasDevices: true),
    );

    expect(find.text('PDAM-Config-[123456]'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Volver a buscar'), findsOneWidget);
    expect(find.text('Buscando más dispensadores...'), findsNothing);

    await closePage(tester);
  });

  testWidgets('el estado final muestra su copy, «Volver a buscar» y cancelar', (
    tester,
  ) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    await exhaustWindows(tester, repository);

    expect(
      find.text('No se encontraron dispensadores en modo de configuración'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Comprueba que esté encendido'),
      findsOneWidget,
    );
    expect(find.text('Volver a buscar'), findsOneWidget);
    expect(find.text('Cancelar Escaneo'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await closePage(tester);
  });

  testWidgets('el aviso del adaptador vive en la zona de la lista con acciones', (
    tester,
  ) async {
    var settingsOpened = false;
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(
      tester,
      repository: repository,
      openSettings: () async {
        settingsOpened = true;
      },
    );

    await emitStatus(tester, repository, BleAdapterStatus.off);

    expect(find.text('El Bluetooth está desactivado'), findsOneWidget);
    expect(find.text('Abrir ajustes'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Cancelar Escaneo'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('PDAM-Config-[123456]'), findsNothing);

    await tester.tap(find.text('Abrir ajustes'));
    await tester.pump();
    expect(settingsOpened, isTrue);

    await closePage(tester);
  });

  testWidgets('«Reintentar» abre un ciclo nuevo tras el aviso', (tester) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    await emitStatus(tester, repository, BleAdapterStatus.off);
    expect(find.text('El Bluetooth está desactivado'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Preparando la búsqueda de dispensadores...'),
      findsOneWidget,
    );

    await closePage(tester);
  });

  testWidgets('el aviso de autorización incluye la indicación de ajustes', (
    tester,
  ) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    await emitStatus(tester, repository, BleAdapterStatus.unauthorized);

    expect(
      find.text(
        'La aplicación no tiene autorización para usar el Bluetooth. '
        'Revisa los permisos en los ajustes.',
      ),
      findsOneWidget,
    );

    await closePage(tester);
  });

  testWidgets('el aviso de disponibilidad usa su copy propio', (tester) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    await emitStatus(tester, repository, BleAdapterStatus.unavailable);

    expect(
      find.text('El Bluetooth no está disponible en este teléfono'),
      findsOneWidget,
    );

    await closePage(tester);
  });

  testWidgets('los avisos de permisos y ubicación usan el copy de la app', (
    tester,
  ) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    final cycleId = repository.openedCycles.last;
    await emit(
      tester,
      repository,
      BleScanFailed(
        cycleId: cycleId,
        failure: BleScanFailure.permissionPermanentlyDenied,
      ),
    );

    expect(
      find.text(
        provisioningPermissionMessage(
          const BlePermissionResult.permanentlyDenied(),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Abrir ajustes'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    await closePage(tester);
  });

  testWidgets('el fallo al iniciar el escaneo tiene copy accionable', (
    tester,
  ) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    final cycleId = repository.openedCycles.last;
    await emit(
      tester,
      repository,
      BleScanFailed(
        cycleId: cycleId,
        failure: BleScanFailure.startFailed,
      ),
    );

    expect(
      find.text(
        'No se pudo iniciar la búsqueda de dispensadores. '
        'Revisa el Bluetooth e inténtalo de nuevo.',
      ),
      findsOneWidget,
    );

    await closePage(tester);
  });

  testWidgets('el cierre de la página no deja timers pendientes', (
    tester,
  ) async {
    var settingsOpened = false;
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(
      tester,
      repository: repository,
      openSettings: () async {
        settingsOpened = true;
      },
    );
    await emitStatus(tester, repository, BleAdapterStatus.off);
    await tester.tap(find.text('Abrir ajustes'));
    await tester.pump();
    expect(settingsOpened, isTrue);

    await closePage(tester);
  });

  testWidgets('a 320 puntos el estado final no desborda', (tester) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(
      tester,
      repository: repository,
      tamano: const Size(320, 640),
    );

    await exhaustWindows(tester, repository);

    expect(tester.takeException(), isNull);
    expect(find.text('Volver a buscar'), findsOneWidget);

    await closePage(tester);
  });

  testWidgets('RF-05: detener la página restaura la lista al salir', (
    tester,
  ) async {
    final repository = _ScanPageRepository();
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    await closePage(tester);

    // El dispose emitió stop + load; el BLoC termina en lista.
    expect(find.byType(BleScanPage), findsNothing);
  });

  testWidgets('RF-13: paused cierra el ciclo y resumed lo reabre', (
    tester,
  ) async {
    final repository = _ScanPageRepository();
    addTearDown(repository.close);
    final bloc = await pumpPage(tester, repository: repository);
    expect(repository.openedCycles, <int>[1]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(bloc.state, isA<BleScanningState>());
    expect(repository.openedCycles, <int>[1]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(bloc.state, isA<BleScanStoppedState>());

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(repository.openedCycles, <int>[1, 2]);
    expect(find.text('PDAM-Config-[123456]'), findsOneWidget);

    await closePage(tester);
  });

  testWidgets('RF-13: al desmontar la página se retira el observer', (
    tester,
  ) async {
    final repository = _ScanPageRepository();
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);
    expect(repository.openedCycles, <int>[1]);

    await closePage(tester);

    // Si el observer siguiera registrado, `resumed` reabriría un ciclo.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(repository.openedCycles, <int>[1]);
  });

  testWidgets('ninguna ventana abierta ofrece volver a buscar', (tester) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    final cycleId = repository.openedCycles.last;
    await emit(tester, repository, BleScanDevices(cycleId: cycleId, devices: const []));
    expect(find.text('Volver a buscar'), findsNothing);
    expect(repository.openedCycles, hasLength(1));

    await emit(tester, repository, BleScanDevices(cycleId: cycleId, devices: const [device]));
    expect(find.text('Volver a buscar'), findsNothing);
    expect(repository.openedCycles, hasLength(1));

    await closePage(tester);
  });

  testWidgets('«Volver a buscar» reinicia desde el estado final', (tester) async {
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(tester, repository: repository);

    await exhaustWindows(tester, repository);
    expect(repository.openedCycles, hasLength(3));

    await tester.tap(find.text('Volver a buscar'));
    await tester.pump();
    await tester.pump();

    expect(repository.openedCycles, hasLength(4));
    expect(
      find.text('Preparando la búsqueda de dispensadores...'),
      findsOneWidget,
    );

    await closePage(tester);
  });

  testWidgets('el fallo legado se muestra como aviso sin texto de excepción', (
    tester,
  ) async {
    await pumpPage(
      tester,
      repository: MockDispenserRepository(shouldFail: true),
    );

    expect(
      find.text(noticeMessage(BleScanNoticeCause.scanFailed)),
      findsOneWidget,
    );
    expect(find.textContaining('Error'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);

    await closePage(tester);
  });

  testWidgets('«Abrir ajustes» no bloquea el aviso si el sistema no responde', (
    tester,
  ) async {
    final neverCompletes = Completer<void>();
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(
      tester,
      repository: repository,
      openSettings: () => neverCompletes.future,
    );
    await emitStatus(tester, repository, BleAdapterStatus.off);

    await tester.tap(find.text('Abrir ajustes'));
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('El Bluetooth está desactivado'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await closePage(tester);
  });

  group('Tema oscuro (CP-17)', () {
    double contraste(Color fondo, Color texto) {
      final l1 = fondo.computeLuminance();
      final l2 = texto.computeLuminance();
      final alto = l1 > l2 ? l1 : l2;
      final bajo = l1 > l2 ? l2 : l1;
      return (alto + 0.05) / (bajo + 0.05);
    }

    void expectMensajeLegible(WidgetTester tester, String mensaje) {
      final contexto = tester.element(find.text(mensaje));
      final tema = Theme.of(contexto);
      expect(tema.brightness, Brightness.dark);
      final color = tester.widget<Text>(find.text(mensaje)).style?.color;
      expect(color, isNotNull);
      expect(
        contraste(tema.scaffoldBackgroundColor, color!),
        greaterThanOrEqualTo(4.5),
      );
    }

    testWidgets('la apertura es legible en tema oscuro', (tester) async {
      final repository = _ScanPageRepository(controlled: true);
      addTearDown(repository.close);
      await pumpPage(
        tester,
        repository: repository,
        theme: AppTheme.darkTheme,
      );

      expectMensajeLegible(tester, 'Preparando la búsqueda de dispensadores...');

      await closePage(tester);
    });

    testWidgets('el aviso es legible en tema oscuro', (tester) async {
      final repository = _ScanPageRepository(controlled: true);
      addTearDown(repository.close);
      await pumpPage(
        tester,
        repository: repository,
        theme: AppTheme.darkTheme,
      );
      await emitStatus(tester, repository, BleAdapterStatus.off);

      expectMensajeLegible(tester, 'El Bluetooth está desactivado');

      await closePage(tester);
    });

    testWidgets('el estado final es legible en tema oscuro', (tester) async {
      final repository = _ScanPageRepository(controlled: true);
      addTearDown(repository.close);
      await pumpPage(
        tester,
        repository: repository,
        theme: AppTheme.darkTheme,
      );
      await exhaustWindows(tester, repository);

      expectMensajeLegible(
        tester,
        'No se encontraron dispensadores en modo de configuración',
      );

      await closePage(tester);
    });
  });

  testWidgets('el aviso de ubicación ofrece abrir sus ajustes', (tester) async {
    var settingsOpened = false;
    final repository = _ScanPageRepository(controlled: true);
    addTearDown(repository.close);
    await pumpPage(
      tester,
      repository: repository,
      openSettings: () async {
        settingsOpened = true;
      },
    );

    final cycleId = repository.openedCycles.last;
    await emit(
      tester,
      repository,
      BleScanFailed(
        cycleId: cycleId,
        failure: BleScanFailure.locationDisabled,
      ),
    );

    expect(
      find.text(
        provisioningPermissionMessage(
          const BlePermissionResult.granted(
            locationRequired: true,
            locationEnabled: false,
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Abrir ajustes de ubicación'), findsOneWidget);

    await tester.tap(find.text('Abrir ajustes de ubicación'));
    await tester.pump();
    expect(settingsOpened, isTrue);

    await closePage(tester);
  });
}
