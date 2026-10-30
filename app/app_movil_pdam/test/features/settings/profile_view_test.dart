import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/account/domain/entity/account_update.dart';
import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:app_movil_pdam/features/account/domain/repository/account_repository.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/delete_account_uc.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/get_profile_uc.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/update_profile_uc.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/account/presentation/bloc/account_bloc.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/auth_token.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/auth_token_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/auth_token_uc/register_token_uc.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/profile_view.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAccountRepository implements AccountRepository {
  Either<Failures, ProfileSnapshot>? perfil;
  int llamadasPerfil = 0;

  @override
  Future<Either<Failures, ProfileSnapshot>> getProfile() async {
    llamadasPerfil++;
    return perfil ??
        Left(NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado));
  }

  @override
  Future<Either<Failures, AccountUpdateResult>> updateProfile(
    AccountUpdate update,
  ) async => Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, bool>> deleteAccount(String password) async =>
      Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, UserProfile?>> cachedProfile() async =>
      const Right(null);
}

class _FakeAuthTokenRepositories implements AuthTokenRepositories {
  @override
  Future<Either<Failures, AuthToken>> cacheToken(
    String token, {
    String typeToken = 'Bearer',
  }) async => Right(AuthToken(token: token, typeToken: typeToken));

  @override
  Future<Either<Failures, void>> deleteToken() async => const Right(null);

  @override
  Future<Either<Failures, AuthToken>> getToken() async =>
      Left(ServerFailures('sin token'));
}

class _FakeCleaner implements AccountLocalCleaner {
  @override
  Future<AccountCleanupResult> limpiarTrasBaja({String? correo}) async =>
      AccountCleanupResult.exito(pasosCompletados: AccountCleanupStep.values);

  @override
  Future<AccountCleanupResult?> limpiarSiPendiente() async => null;

  @override
  Future<void> limpiarPorSesionExpirada() async {}
}

/// RF-06, RF-07 y RF-08: Perfil muestra datos reales, el aviso de caché y el
/// mensaje de «Reintentar» cuando no hay datos locales, sin credenciales ni
/// controles de edición.
void main() {
  late _FakeAccountRepository repo;

  setUp(() {
    repo = _FakeAccountRepository();
  });

  Future<void> pumpProfile(
    WidgetTester tester, {
    double width = 800,
    double height = 800,
    double textScaler = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // El BLoC se crea dentro del cuerpo del test para que sus microtareas
    // corran en la zona de tiempo simulado de `testWidgets`.
    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final bloc = AccountBloc(
      getProfileUc: GetProfileUc(repository: repo),
      updateProfileUc: UpdateProfileUc(repository: repo),
      deleteAccountUc: DeleteAccountUc(repository: repo),
      registerTokenUc: RegisterTokenUc(
        repository: _FakeAuthTokenRepositories(),
      ),
      accountLocalCleaner: _FakeCleaner(),
      sessionEvents: eventos,
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider<AccountBloc>.value(
        value: bloc,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScaler)),
            child: child!,
          ),
          home: const ProfileView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('muestra correo normalizado, estado y avatar con la inicial', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    repo.perfil = const Right(
      ProfileSnapshot(
        profile: UserProfile(email: 'user@x.com', isActive: true),
      ),
    );

    await pumpProfile(tester);

    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('user@x.com'), findsOneWidget);
    expect(find.text('Estado de la cuenta'), findsOneWidget);
    expect(find.text('Activa'), findsOneWidget);
    expect(find.text('U'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('profile_avatar_semantics')))
          .label,
      'Avatar con la inicial U',
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Contraseña'), findsNothing);
    expect(find.textContaining('token'), findsNothing);
    handle.dispose();
  });

  testWidgets('una cuenta inactiva muestra la etiqueta «Inactiva»', (
    tester,
  ) async {
    repo.perfil = const Right(
      ProfileSnapshot(
        profile: UserProfile(email: 'user@x.com', isActive: false),
      ),
    );

    await pumpProfile(tester);

    expect(find.text('Inactiva'), findsOneWidget);
    expect(find.text('Activa'), findsNothing);
  });

  testWidgets('sin conexión muestra el perfil cacheado real con su aviso', (
    tester,
  ) async {
    repo.perfil = const Right(
      ProfileSnapshot(
        profile: UserProfile(email: 'user@x.com', isActive: true),
        desdeCache: true,
      ),
    );

    await pumpProfile(tester);

    expect(
      find.text('Estás viendo datos guardados en este dispositivo.'),
      findsOneWidget,
    );
    expect(find.text('user@x.com'), findsOneWidget);
    expect(find.text('Activa'), findsOneWidget);
  });

  testWidgets('sin perfil cacheado muestra el mensaje de RF-08 y Reintentar', (
    tester,
  ) async {
    repo.perfil = Left(
      NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado),
    );

    await pumpProfile(tester);

    expect(find.text(MensajesCuenta.sinPerfilCacheado), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);

    repo.perfil = const Right(
      ProfileSnapshot(
        profile: UserProfile(email: 'user@x.com', isActive: true),
      ),
    );
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(repo.llamadasPerfil, 2);
    expect(find.text('user@x.com'), findsOneWidget);
  });

  testWidgets('un 401 unauthorized no muestra el perfil cacheado', (
    tester,
  ) async {
    repo.perfil = Left(UnauthorizedFailure(MensajesCuenta.sesionInvalida));

    await pumpProfile(tester);

    expect(find.text('user@x.com'), findsNothing);
    expect(
      find.text('Estás viendo datos guardados en este dispositivo.'),
      findsNothing,
    );
  });

  testWidgets('a 320 puntos con texto al 130 % no hay desbordamientos', (
    tester,
  ) async {
    repo.perfil = const Right(
      ProfileSnapshot(
        profile: UserProfile(
          email: 'usuario.con.correo.largo@ejemplo.com',
          isActive: false,
        ),
      ),
    );

    await pumpProfile(tester, width: 320, height: 640, textScaler: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('usuario.con.correo.largo@ejemplo.com'), findsOneWidget);
  });
}
