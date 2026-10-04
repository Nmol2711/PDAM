import 'dart:async';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/presentation/widgets/app_notice_dialog.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/activate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/associate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/dasactivate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/delete_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/get_dispenser_by_pet_uc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/register_dispenser_view.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Prueba de widget del flujo de registro: cada motivo de rechazo se muestra con
// el diálogo reutilizable `AppNoticeDialog` y nunca con un `SnackBar` rojo
// (RF-09 a RF-13 · RNF-05).
//
// Los cuatro motivos que se comprueban son los del contrato de error de la
// spec: conflicto de alta (RF-10), dirección en uso (RF-11), formato inválido
// (RF-12) y falta de conexión (RF-13). El caso de dirección en uso se dispara
// por el mismo camino público (el evento de alta) porque la interfaz de edición
// de MAC está pospuesta (DO-6/AC-6).

const int petIdDePrueba = 7;
const String mensajeDelServidor =
    'El dispensador 7777 de RayoSecreto (dueno.secreto@pdam.test) ya está registrado.';

// Copy esperado de cada aviso (títulos y mensajes genéricos, sin datos ajenos).
const String tituloMacYaRegistrada = 'Este dispensador ya está registrado';
const String mensajeMacYaRegistrada =
    'Esa dirección ya está vinculada a otro registro del sistema. '
    'Escanea el código QR del dispensador correcto o revisa con qué cuenta está vinculado.';
const String tituloMacEnUso = 'Esa dirección ya está en uso';
const String mensajeMacEnUso =
    'La dirección indicada pertenece a otro dispensador. '
    'Verifica la dirección del dispositivo e inténtalo de nuevo.';
const String tituloFormatoInvalido = 'La dirección no es válida';
const String mensajeFormatoInvalido =
    'Revisa la dirección del dispensador: debe tener 12 caracteres hexadecimales, '
    'por ejemplo AA:BB:CC:DD:EE:FF.';
const String tituloSinConexion = 'Necesitas conexión a internet';
const String mensajeSinConexion =
    'El registro del dispensador se valida con el servidor. '
    'Conéctate a internet e inténtalo de nuevo.';

/// Repositorio mínimo: solo la respuesta del alta importa en esta prueba. El
/// resto de operaciones no se ejercitan aquí (RF-17).
class _FakeDispenserRepository implements DispenserRepositories {
  _FakeDispenserRepository({required this.respuestaAlta});

  Either<Failures, Dispenser> respuestaAlta;

  @override
  Future<Either<Failures, Dispenser>> associateDispenser(
    String macAddress,
    int petId,
    String secretKeyQr,
  ) async => respuestaAlta;

  @override
  Future<Either<Failures, Map<String, dynamic>>> checkPendingTask(
    String macAddress,
  ) async => const Right(<String, dynamic>{});

  @override
  Future<Either<Failures, bool>> activateDispenser(
    int dispenserId,
    int petId,
  ) async => const Right(true);

  @override
  Future<Either<Failures, bool>> dasactivateDispenser(
    int dispenserId,
    int petId,
  ) async => const Right(true);

  @override
  Future<Either<Failures, bool>> deleteDispenser(int petIf) async => const Right(true);

  @override
  Future<Either<Failures, Dispenser>> getDispenserByPet(
    int petId,
  ) async => Left(LocalStorageFailures('Sin dispensador local'));

  @override
  Future<Either<Failures, Dispenser>> updateDispenserMac(
    int dispenserId,
    int petId,
    String macAddress,
  ) async => Left(ServerFailures(mensajeDelServidor));
}

/// Monta un `MaterialApp.router` con la vista de registro sobre una pantalla
/// inicial, para que `context.pop()` tenga a dónde volver.
Future<({DispenserBloc bloc, _FakeDispenserRepository repositorio})>
_pumpVistaRegistro(WidgetTester tester) async {
  final _FakeDispenserRepository repositorio = _FakeDispenserRepository(
    respuestaAlta: Left(ServerFailures(mensajeDelServidor)),
  );

  final DispenserBloc bloc = DispenserBloc(
    associateUseCase: AssociateDispenserUc(repository: repositorio),
    getDispenserByPetUseCase: GetDispenserByPetUc(repository: repositorio),
    activateUseCase: ActivateDispenserUc(repository: repositorio),
    deactivateUseCase: DesactivateDispenserUc(repository: repositorio),
    deleteDispenserUseCase: DeleteDispenserUc(repository: repositorio),
  );
  addTearDown(bloc.close);

  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) => const Scaffold(
          body: Center(child: Text('Detalle de la mascota')),
        ),
      ),
      GoRoute(
        path: '/registro',
        name: 'register_dispenser',
        builder: (BuildContext context, GoRouterState state) =>
            BlocProvider<DispenserBloc>.value(
              value: bloc,
              child: const RegisterDispenserView(petId: petIdDePrueba),
            ),
      ),
      GoRoute(
        path: '/escaner',
        name: 'qr_scanner',
        builder: (BuildContext context, GoRouterState state) => const Scaffold(
          body: Center(child: Text('Escáner QR')),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  );
  unawaited(router.push('/registro'));
  await tester.pumpAndSettle();

  return (bloc: bloc, repositorio: repositorio);
}

/// Lanza el alta, que es el camino público de los cuatro rechazos.
Future<void> _solicitarVinculacion(
  WidgetTester tester,
  DispenserBloc bloc,
) async {
  bloc.add(
    AssociateDispenserEvent(
      macAddress: 'AA:BB:CC:DD:EE:FF',
      petId: petIdDePrueba,
      secretKeyQr: 'clave-del-qr',
    ),
  );
  await tester.pumpAndSettle();
}

/// RNF-05: el color rojo no puede ser el único indicador del error, así que en
/// los cuatro rechazos no debe aparecer ningún `SnackBar` rojo.
void _esperarSinSnackBarRojo(WidgetTester tester) {
  final List<SnackBar> barras = tester.widgetList<SnackBar>(find.byType(SnackBar)).toList();
  for (final SnackBar barra in barras) {
    expect(
      barra.backgroundColor,
      isNot(Colors.red),
      reason: 'Los rechazos se muestran con el diálogo, no con un SnackBar rojo.',
    );
  }
}

void _esperarAviso(WidgetTester tester, {
  required String titulo,
  required String mensaje,
  required IconData icono,
}) {
  expect(find.byType(AppNoticeDialog), findsOneWidget);
  expect(find.text(titulo), findsOneWidget);
  expect(find.text(mensaje), findsOneWidget);
  expect(find.byIcon(icono), findsOneWidget);
  _esperarSinSnackBarRojo(tester);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('conflicto de alta muestra el aviso de MAC ya registrada (RF-10)', (
    WidgetTester tester,
  ) async {
    final ({DispenserBloc bloc, _FakeDispenserRepository repositorio}) escena =
        await _pumpVistaRegistro(tester);
    escena.repositorio.respuestaAlta = Left(
      MacAlreadyRegisteredFailures(mensajeDelServidor),
    );

    await _solicitarVinculacion(tester, escena.bloc);

    _esperarAviso(
      tester,
      titulo: tituloMacYaRegistrada,
      mensaje: mensajeMacYaRegistrada,
      icono: Icons.warning_amber_rounded,
    );

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.byType(AppNoticeDialog), findsNothing);
    expect(find.byType(RegisterDispenserView), findsOneWidget);
  });

  testWidgets('dirección en uso muestra su propio aviso (RF-11)', (
    WidgetTester tester,
  ) async {
    final ({DispenserBloc bloc, _FakeDispenserRepository repositorio}) escena =
        await _pumpVistaRegistro(tester);
    escena.repositorio.respuestaAlta = Left(MacInUseFailures(mensajeDelServidor));

    await _solicitarVinculacion(tester, escena.bloc);

    _esperarAviso(
      tester,
      titulo: tituloMacEnUso,
      mensaje: mensajeMacEnUso,
      icono: Icons.warning_amber_rounded,
    );
  });

  testWidgets('formato inválido muestra un aviso distinto al de conflicto (RF-12)', (
    WidgetTester tester,
  ) async {
    final ({DispenserBloc bloc, _FakeDispenserRepository repositorio}) escena =
        await _pumpVistaRegistro(tester);
    escena.repositorio.respuestaAlta = Left(
      InvalidMacFormatFailures(mensajeDelServidor),
    );

    await _solicitarVinculacion(tester, escena.bloc);

    _esperarAviso(
      tester,
      titulo: tituloFormatoInvalido,
      mensaje: mensajeFormatoInvalido,
      icono: Icons.warning_amber_rounded,
    );
    expect(find.text(tituloMacYaRegistrada), findsNothing);
  });

  testWidgets('falta de conexión muestra el aviso informativo (RF-13)', (
    WidgetTester tester,
  ) async {
    final ({DispenserBloc bloc, _FakeDispenserRepository repositorio}) escena =
        await _pumpVistaRegistro(tester);
    escena.repositorio.respuestaAlta = Left(
      ConnectivityRequiredFailures('Sin conexión a la red.'),
    );

    await _solicitarVinculacion(tester, escena.bloc);

    _esperarAviso(
      tester,
      titulo: tituloSinConexion,
      mensaje: mensajeSinConexion,
      icono: Icons.wifi_off_rounded,
    );
    _esperarSinSnackBarRojo(tester);
  });

  testWidgets('ningún rechazo muestra datos ajenos en el aviso (RF-16, CL-14)', (
    WidgetTester tester,
  ) async {
    final ({DispenserBloc bloc, _FakeDispenserRepository repositorio}) escena =
        await _pumpVistaRegistro(tester);
    escena.repositorio.respuestaAlta = Left(
      MacAlreadyRegisteredFailures(mensajeDelServidor),
    );

    await _solicitarVinculacion(tester, escena.bloc);

    expect(find.textContaining('RayoSecreto'), findsNothing);
    expect(find.textContaining('dueno.secreto@pdam.test'), findsNothing);
    expect(find.textContaining('7777'), findsNothing);
  });

  testWidgets('el alta correcta conserva su SnackBar de éxito y regresa', (
    WidgetTester tester,
  ) async {
    final ({DispenserBloc bloc, _FakeDispenserRepository repositorio}) escena =
        await _pumpVistaRegistro(tester);
    escena.repositorio.respuestaAlta = Right(
      const Dispenser(
        id: 1,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        pendingDispensing: false,
        isActive: true,
        petId: petIdDePrueba,
      ),
    );

    await _solicitarVinculacion(tester, escena.bloc);

    expect(find.byType(AppNoticeDialog), findsNothing);
    expect(find.text('Dispensador asociado correctamente'), findsOneWidget);
    _esperarSinSnackBarRojo(tester);
    expect(find.text('Detalle de la mascota'), findsOneWidget);
  });
}