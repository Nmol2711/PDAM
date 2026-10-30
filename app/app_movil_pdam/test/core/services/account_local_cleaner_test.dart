import 'dart:io';

import 'package:app_movil_pdam/core/constant/token_constant.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_dispenser.dart';
import 'package:app_movil_pdam/core/offline/models/local_log.dart';
import 'package:app_movil_pdam/core/offline/models/local_pet.dart';
import 'package:app_movil_pdam/core/offline/models/local_profile.dart';
import 'package:app_movil_pdam/core/offline/models/local_schedule.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/features/account/data/datasource/local/local_profile_datasource.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/local/auth_local_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/remote/auth_remote_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/models/auth_token_model.dart';
import 'package:app_movil_pdam/features/auth/data/models/user_model.dart';
import 'package:app_movil_pdam/features/auth/data/repositories_impl/user_repositories_impl.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

/// Almacenamiento cifrado simulado que registra el orden de las operaciones y
/// permite inyectar fallos por clave.
class _FakeStorage implements StorageService {
  _FakeStorage({Map<String, String>? valores}) : valores = {...?valores};

  final Map<String, String> valores;
  final List<String> operaciones = <String>[];
  String? fallarAlGuardarClave;
  String? fallarAlBorrarClave;

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async {
    if (fallarAlGuardarClave == key) {
      return Left(LocalStorageFailures('fallo de almacenamiento'));
    }
    valores[key] = value;
    operaciones.add('guardar:$key');
    return const Right(null);
  }

  @override
  Future<Either<Failures, String?>> getString(String key) async =>
      Right(valores[key]);

  @override
  Future<Either<Failures, void>> deleteString(String key) async {
    if (fallarAlBorrarClave == key) {
      return Left(LocalStorageFailures('fallo de almacenamiento'));
    }
    valores.remove(key);
    operaciones.add('borrar:$key');
    return const Right(null);
  }
}

/// Servidor inalcanzable: toda petición falla como red, de modo que el inicio
/// de sesión solo puede resolverse con las credenciales guardadas en el
/// dispositivo. Reproduce el caso de RF-19 sin conexión.
class _SinRedAuthRemoteDatasource implements AuthRemoteDatasource {
  @override
  Future<UserModel> register(String email, String password) async =>
      throw NetworkFailures(MensajesCuenta.sinConexion);

  @override
  Future<AuthTokenModel> login(String email, String password) async =>
      throw NetworkFailures(MensajesCuenta.sinConexion);

  @override
  Future<UserModel> currentUser() async =>
      throw NetworkFailures(MensajesCuenta.sinConexion);
}

/// RNF-10 y RF-18/RF-23: la limpieza local borra token, tipo, credenciales,
/// perfil y colecciones de la cuenta; escribe la marca antes y la borra solo al
/// terminar; y nunca toca `user_theme_mode`.
void main() {
  late Directory tempDir;
  late _FakeStorage storage;
  late PendingDeletionStore pending;
  late AuthLocalDatasource authLocal;
  late LocalProfileDatasource profileDatasource;
  late AccountLocalCleaner cleaner;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(download: true);
      final warmupDir = await Directory.systemTemp.createTemp('isar_warmup_');
      await IsarService.init(directory: warmupDir.path);
      await warmupDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_cleaner_test_');
    storage = _FakeStorage(
      valores: <String, String>{
        TokenConstant.keyToken: 'token-secreto',
        TokenConstant.keyTypeToken: 'Bearer',
        TokenConstant.keyCachedEmail: 'user@x.com',
        TokenConstant.keyCachedPassword: 'clave-secreta',
        'user_theme_mode': 'dark',
      },
    );
    pending = PendingDeletionStoreImpl(storageService: storage);
    authLocal = AuthLocalDatasourceImpl(storageService: storage);
    profileDatasource = LocalProfileDatasourceImpl(testDirectory: tempDir.path);
    cleaner = AccountLocalCleanerImpl(
      pendingDeletionStore: pending,
      authLocalDatasource: authLocal,
      localProfileDatasource: profileDatasource,
      abrirIsar: () => IsarService.init(directory: tempDir.path),
    );
  });

  tearDown(() async {
    try {
      await IsarService.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> sembrarDatosLocales() async {
    final isar = await IsarService.init(directory: tempDir.path);
    await isar.writeTxn(() async {
      await isar.localProfiles.put(
        LocalProfile()
          ..accountKey = 'user@x.com'
          ..email = 'user@x.com'
          ..isActive = true
          ..updatedAt = DateTime.now(),
      );
      await isar.localPets.put(
        LocalPet()
          ..userId = 'default_user'
          ..name = 'Firulais'
          ..species = 'Perro'
          ..birthDate = '2020-01-01'
          ..weight = 10
          ..reproductiveStatus = false
          ..updatedAt = DateTime.now()
          ..isSynced = true,
      );
      await isar.localSchedules.put(
        LocalSchedule()
          ..userId = 'default_user'
          ..petRemoteId = 1
          ..time = '08:00'
          ..amount = 100
          ..updatedAt = DateTime.now()
          ..isSynced = true,
      );
      await isar.localLogs.put(
        LocalLog()
          ..userId = 'default_user'
          ..timestamp = DateTime.now()
          ..description = 'registro'
          ..isSynced = true,
      );
      await isar.localDispensers.put(
        LocalDispenser()
          ..macAddress = 'AA:BB:CC:DD:EE:FF'
          ..isActive = true
          ..pendingDispensing = false
          ..updatedAt = DateTime.now()
          ..isSynced = true,
      );
    });
  }

  Future<void> esperarColeccionesVacias() async {
    final isar = await IsarService.init(directory: tempDir.path);
    expect(await isar.localPets.count(), 0);
    expect(await isar.localSchedules.count(), 0);
    expect(await isar.localLogs.count(), 0);
    expect(await isar.localDispensers.count(), 0);
    expect(await isar.localProfiles.count(), 0);
  }

  group('AccountLocalCleaner (RNF-10)', () {
    test(
      'escribe la marca antes, limpia todo y la borra al terminar',
      () async {
        await sembrarDatosLocales();

        final resultado = await cleaner.limpiarTrasBaja(correo: 'user@x.com');

        expect(resultado.exitoso, isTrue);
        expect(resultado.pasoFallido, isNull);
        expect(
          resultado.pasosCompletados,
          containsAll(<AccountCleanupStep>[
            AccountCleanupStep.marca,
            AccountCleanupStep.token,
            AccountCleanupStep.credenciales,
            AccountCleanupStep.perfil,
            AccountCleanupStep.mascotas,
            AccountCleanupStep.dispensadores,
            AccountCleanupStep.horarios,
            AccountCleanupStep.historial,
            AccountCleanupStep.borrarMarca,
          ]),
        );

        // Orden verificable: la marca se escribe primero y se borra al final.
        expect(
          storage.operaciones.first,
          'guardar:${TokenConstant.keyPendingDeletion}',
        );
        expect(
          storage.operaciones.last,
          'borrar:${TokenConstant.keyPendingDeletion}',
        );
        expect(
          storage.operaciones,
          contains('borrar:${TokenConstant.keyToken}'),
        );
        expect(
          storage.operaciones,
          contains('borrar:${TokenConstant.keyTypeToken}'),
        );
        expect(
          storage.operaciones,
          contains('borrar:${TokenConstant.keyCachedEmail}'),
        );
        expect(
          storage.operaciones,
          contains('borrar:${TokenConstant.keyCachedPassword}'),
        );

        // RF-23: la preferencia de apariencia pertenece al dispositivo.
        expect(storage.valores['user_theme_mode'], 'dark');
        expect(
          storage.valores.containsKey(TokenConstant.keyPendingDeletion),
          isFalse,
        );
        await esperarColeccionesVacias();
      },
    );

    test('si falla el borrado del token, la marca sobrevive y no borra el '
        'resto', () async {
      await sembrarDatosLocales();
      storage.fallarAlBorrarClave = TokenConstant.keyToken;

      final resultado = await cleaner.limpiarTrasBaja(correo: 'user@x.com');

      expect(resultado.exitoso, isFalse);
      expect(resultado.pasoFallido, AccountCleanupStep.token);
      expect(resultado.pasosCompletados, <AccountCleanupStep>[
        AccountCleanupStep.marca,
      ]);
      expect(storage.valores[TokenConstant.keyPendingDeletion], 'true');
      expect(storage.valores['user_theme_mode'], 'dark');
      expect(storage.valores[TokenConstant.keyCachedEmail], 'user@x.com');
      expect(
        await (await IsarService.init(
          directory: tempDir.path,
        )).localPets.count(),
        1,
      );
    });

    test('si falla el borrado del correo cacheado, el paso credenciales falla '
        'y la marca sobrevive', () async {
      // RNF-10 y RF-19: sin borrar las credenciales cifradas el acceso sin
      // conexión seguiría operativo con la cuenta eliminada.
      await sembrarDatosLocales();
      storage.fallarAlBorrarClave = TokenConstant.keyCachedEmail;

      final resultado = await cleaner.limpiarTrasBaja(correo: 'user@x.com');

      expect(resultado.exitoso, isFalse);
      expect(resultado.pasoFallido, AccountCleanupStep.credenciales);
      expect(resultado.pasosCompletados, <AccountCleanupStep>[
        AccountCleanupStep.marca,
        AccountCleanupStep.token,
      ]);
      expect(storage.valores[TokenConstant.keyPendingDeletion], 'true');
      expect(storage.valores[TokenConstant.keyCachedEmail], 'user@x.com');
      expect(storage.valores[TokenConstant.keyCachedPassword], 'clave-secreta');

      // No borra nada más de lo ya hecho: perfil y colecciones siguen.
      final isar = await IsarService.init(directory: tempDir.path);
      expect(await isar.localProfiles.count(), 1);
      expect(await isar.localPets.count(), 1);
    });

    test('si falla el borrado de la contraseña cacheada, el paso credenciales '
        'falla y la marca sobrevive', () async {
      await sembrarDatosLocales();
      storage.fallarAlBorrarClave = TokenConstant.keyCachedPassword;

      final resultado = await cleaner.limpiarTrasBaja(correo: 'user@x.com');

      expect(resultado.exitoso, isFalse);
      expect(resultado.pasoFallido, AccountCleanupStep.credenciales);
      expect(resultado.pasosCompletados, <AccountCleanupStep>[
        AccountCleanupStep.marca,
        AccountCleanupStep.token,
      ]);
      expect(storage.valores[TokenConstant.keyPendingDeletion], 'true');
      expect(storage.valores[TokenConstant.keyCachedPassword], 'clave-secreta');

      final isar = await IsarService.init(directory: tempDir.path);
      expect(await isar.localProfiles.count(), 1);
      expect(await isar.localPets.count(), 1);
    });

    test('si falla el borrado de la marca final, los datos ya están limpios y '
        'la marca permanece', () async {
      await sembrarDatosLocales();
      storage.fallarAlBorrarClave = TokenConstant.keyPendingDeletion;

      final resultado = await cleaner.limpiarTrasBaja(correo: 'user@x.com');

      expect(resultado.exitoso, isFalse);
      expect(resultado.pasoFallido, AccountCleanupStep.borrarMarca);
      expect(storage.valores[TokenConstant.keyPendingDeletion], 'true');
      expect(storage.valores['user_theme_mode'], 'dark');
      await esperarColeccionesVacias();
    });

    test('si no se puede escribir la marca, no borra nada', () async {
      await sembrarDatosLocales();
      storage.fallarAlGuardarClave = TokenConstant.keyPendingDeletion;

      final resultado = await cleaner.limpiarTrasBaja(correo: 'user@x.com');

      expect(resultado.exitoso, isFalse);
      expect(resultado.pasoFallido, AccountCleanupStep.marca);
      expect(storage.valores[TokenConstant.keyToken], 'token-secreto');
      expect(storage.valores[TokenConstant.keyCachedPassword], 'clave-secreta');
      expect(
        await (await IsarService.init(
          directory: tempDir.path,
        )).localPets.count(),
        1,
      );
    });

    test('limpiarSiPendiente no hace nada sin marca', () async {
      await sembrarDatosLocales();

      final resultado = await cleaner.limpiarSiPendiente();

      expect(resultado, isNull);
      expect(storage.operaciones, isEmpty);
      expect(
        await (await IsarService.init(
          directory: tempDir.path,
        )).localPets.count(),
        1,
      );
    });

    test(
      'limpiarSiPendiente reintenta y completa la limpieza al reiniciar',
      () async {
        await sembrarDatosLocales();
        await pending.markPending();

        final resultado = await cleaner.limpiarSiPendiente();

        expect(resultado?.exitoso, isTrue);
        expect(
          storage.valores.containsKey(TokenConstant.keyPendingDeletion),
          isFalse,
        );
        expect(storage.valores['user_theme_mode'], 'dark');
        await esperarColeccionesVacias();
      },
    );

    test('tras un fallo, limpiarSiPendiente reintenta y completa la '
        'limpieza', () async {
      await sembrarDatosLocales();
      storage.fallarAlBorrarClave = TokenConstant.keyToken;

      final fallo = await cleaner.limpiarTrasBaja(correo: 'user@x.com');
      expect(fallo.exitoso, isFalse);
      expect(storage.valores[TokenConstant.keyPendingDeletion], 'true');

      // El siguiente arranque ve la marca y reintenta hasta completar.
      storage.fallarAlBorrarClave = null;
      final reintento = await cleaner.limpiarSiPendiente();

      expect(reintento?.exitoso, isTrue);
      expect(
        storage.valores.containsKey(TokenConstant.keyPendingDeletion),
        isFalse,
      );
      await esperarColeccionesVacias();
    });

    test(
      'el borrado se acota a la cuenta y no barre filas de otra cuenta',
      () async {
        await sembrarDatosLocales();
        final isar = await IsarService.init(directory: tempDir.path);
        await isar.writeTxn(() async {
          await isar.localPets.put(
            LocalPet()
              ..remoteId = 77
              ..userId = 'otra@cuenta.com'
              ..name = 'Michi'
              ..species = 'Gato'
              ..birthDate = '2021-01-01'
              ..weight = 4
              ..reproductiveStatus = false
              ..updatedAt = DateTime.now()
              ..isSynced = true,
          );
          await isar.localDispensers.put(
            LocalDispenser()
              ..remoteId = 77
              ..petRemoteId = 77
              ..macAddress = '11:22:33:44:55:66'
              ..isActive = true
              ..pendingDispensing = false
              ..updatedAt = DateTime.now()
              ..isSynced = true,
          );
        });

        final resultado = await cleaner.limpiarTrasBaja(correo: 'user@x.com');

        expect(resultado.exitoso, isTrue);
        // La cuenta eliminada desaparece por completo...
        expect(
          await isar.localPets.filter().userIdEqualTo('default_user').count(),
          0,
        );
        expect(await isar.localSchedules.count(), 0);
        expect(await isar.localLogs.count(), 0);
        // ...y lo que pertenece a otra cuenta se conserva.
        expect(
          await isar.localPets
              .filter()
              .userIdEqualTo('otra@cuenta.com')
              .count(),
          1,
        );
        expect(
          await isar.localDispensers.filter().petRemoteIdEqualTo(77).count(),
          1,
        );
      },
    );

    test('el reintento sin perfil cacheado limpia la cuenta y no barre filas '
        'de otra cuenta', () async {
      // Al reintentar en el arranque el perfil ya se borró: no hay clave de
      // cuenta y aun así deben desaparecer las filas reales del dispositivo.
      await sembrarDatosLocales();
      await pending.markPending();
      final isar = await IsarService.init(directory: tempDir.path);
      await isar.writeTxn(() async {
        await isar.localPets.put(
          LocalPet()
            ..remoteId = 77
            ..userId = 'otra@cuenta.com'
            ..name = 'Michi'
            ..species = 'Gato'
            ..birthDate = '2021-01-01'
            ..weight = 4
            ..reproductiveStatus = false
            ..updatedAt = DateTime.now()
            ..isSynced = true,
        );
      });
      await profileDatasource.deleteProfile('user@x.com');

      final resultado = await cleaner.limpiarSiPendiente();

      expect(resultado?.exitoso, isTrue);
      expect(
        await isar.localPets.filter().userIdEqualTo('default_user').count(),
        0,
      );
      expect(await isar.localSchedules.count(), 0);
      expect(await isar.localLogs.count(), 0);
      expect(await isar.localDispensers.count(), 0);
      expect(await isar.localProfiles.count(), 0);
      expect(
        await isar.localPets.filter().userIdEqualTo('otra@cuenta.com').count(),
        1,
      );
    });
  });

  test(
    'RF-19: tras la baja, el login sin conexión con las credenciales antiguas se rechaza',
    () async {
      final repositorio = UserRepositoriesImpl(
        authLocalDatasource: authLocal,
        authRemoteDatasource: _SinRedAuthRemoteDatasource(),
        localProfileDatasource: profileDatasource,
      );
      final login = LoginUc(repository: repositorio);

      // Antes de la baja, el dispositivo acepta esas credenciales sin conexión.
      final antes = await login('user@x.com', 'clave-secreta');
      expect(antes.isRight(), isTrue);

      await cleaner.limpiarTrasBaja(correo: 'user@x.com');

      // Después de la baja, la misma pareja ya no tiene credenciales guardadas.
      final despues = await login('user@x.com', 'clave-secreta');
      expect(despues.isLeft(), isTrue);
      final fallo = despues.fold<Failures?>((fallo) => fallo, (_) => null);
      expect(fallo, isA<AccountFailure>());
      expect((fallo! as AccountFailure).code, CodigosCuenta.invalidCredentials);
    },
  );

  test('RF-19: la limpieza de un 401 borra token, credenciales y perfil y '
      'conserva las colecciones y el tema', () async {
    await sembrarDatosLocales();

    await cleaner.limpiarPorSesionExpirada();

    expect(storage.valores.containsKey(TokenConstant.keyToken), isFalse);
    expect(storage.valores.containsKey(TokenConstant.keyTypeToken), isFalse);
    expect(storage.valores.containsKey(TokenConstant.keyCachedEmail), isFalse);
    expect(storage.valores.containsKey(TokenConstant.keyCachedPassword), isFalse);
    // La marca de baja pendiente es solo de la baja (RNF-10).
    expect(
      storage.valores.containsKey(TokenConstant.keyPendingDeletion),
      isFalse,
    );
    // RF-23: la preferencia de apariencia pertenece al dispositivo.
    expect(storage.valores['user_theme_mode'], 'dark');

    final isar = await IsarService.init(directory: tempDir.path);
    expect(await isar.localProfiles.count(), 0);
    // Las colecciones son datos de la aplicación y se resincronizan (RF-19).
    expect(await isar.localPets.count(), 1);
    expect(await isar.localSchedules.count(), 1);
    expect(await isar.localLogs.count(), 1);
    expect(await isar.localDispensers.count(), 1);
  });

  test('RF-19: tras un 401 el login sin conexión con las credenciales '
      'antiguas se rechaza y las colecciones sobreviven', () async {
    await sembrarDatosLocales();
    final repositorio = UserRepositoriesImpl(
      authLocalDatasource: authLocal,
      authRemoteDatasource: _SinRedAuthRemoteDatasource(),
      localProfileDatasource: profileDatasource,
    );
    final login = LoginUc(repository: repositorio);
    final eventos = SessionEvents();
    final authBloc = AuthBloc(
      registerUc: RegisterUc(repository: repositorio),
      loginUc: login,
      currentUserUc: CurrentUserUc(repository: repositorio),
      pendingDeletionStore: pending,
      sessionEvents: eventos,
      accountLocalCleaner: cleaner,
      hayConexion: () async => false,
    );
    addTearDown(() async {
      await authBloc.close();
      await eventos.dispose();
    });

    // Antes del 401, el dispositivo acepta esas credenciales sin conexión.
    final antes = await login('user@x.com', 'clave-secreta');
    expect(antes.isRight(), isTrue);

    // El interceptor avisa del 401 y AuthBloc limpia antes de emitir.
    final expirada = authBloc.stream.firstWhere(
      (estado) => estado is AuthSessionExpired,
    );
    eventos.notify(const SessionEvent.sesionExpirada());
    await expirada;

    final despues = await login('user@x.com', 'clave-secreta');
    expect(despues.isLeft(), isTrue);
    final fallo = despues.fold<Failures?>((fallo) => fallo, (_) => null);
    expect(fallo, isA<AccountFailure>());
    expect((fallo! as AccountFailure).code, CodigosCuenta.invalidCredentials);

    // Mascotas, horarios, historial y tema no se borran en el 401.
    final isar = await IsarService.init(directory: tempDir.path);
    expect(await isar.localPets.count(), 1);
    expect(await isar.localSchedules.count(), 1);
    expect(await isar.localLogs.count(), 1);
    expect(storage.valores['user_theme_mode'], 'dark');
  });
}
