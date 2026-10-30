import 'dart:io';

import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_profile.dart';
import 'package:app_movil_pdam/features/account/data/datasource/local/local_profile_datasource.dart';
import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

/// Perfil cacheado real en Isar (RF-07, RF-08, RF-10).
///
/// Solo guarda datos recibidos del servidor: la clave de la cuenta es el correo
/// normalizado y el dispositivo mantiene un único perfil vigente.
void main() {
  late Directory tempDir;
  late LocalProfileDatasource datasource;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(download: true);
      final warmupDir = await Directory.systemTemp.createTemp('isar_warmup_');
      await IsarService.init(directory: warmupDir.path);
      await warmupDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_profile_test_');
    datasource = LocalProfileDatasourceImpl(testDirectory: tempDir.path);
  });

  tearDown(() async {
    try {
      await IsarService.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalProfileDatasource (RF-07, RF-08)', () {
    test('sin perfil guardado devuelve null y no inventa datos', () async {
      expect(await datasource.getCachedProfile(), isNull);
    });

    test('guarda el perfil del servidor y lo recupera igual', () async {
      const perfil = UserProfile(email: 'user@x.com', isActive: true);

      await datasource.saveProfile(perfil);

      final guardado = await datasource.getCachedProfile();
      expect(guardado, perfil);
    });

    test('conserva el estado inactivo del servidor', () async {
      await datasource.saveProfile(
        const UserProfile(email: 'user@x.com', isActive: false),
      );

      final guardado = await datasource.getCachedProfile();
      expect(guardado?.isActive, isFalse);
      expect(guardado?.email, 'user@x.com');
    });

    test('la clave de la cuenta es el correo normalizado', () async {
      await datasource.saveProfile(
        const UserProfile(email: '  User@X.com ', isActive: true),
      );

      final isar = await IsarService.init(directory: tempDir.path);
      final filas = await isar.localProfiles.where().findAll();
      expect(filas, hasLength(1));
      expect(filas.single.accountKey, 'user@x.com');
      expect(filas.single.email, 'user@x.com');
    });

    test(
      'guardar el mismo correo con otro estado actualiza la misma fila',
      () async {
        await datasource.saveProfile(
          const UserProfile(email: 'user@x.com', isActive: true),
        );
        await datasource.saveProfile(
          const UserProfile(email: 'user@x.com', isActive: false),
        );

        final isar = await IsarService.init(directory: tempDir.path);
        final filas = await isar.localProfiles.where().findAll();
        expect(filas, hasLength(1));
        expect(filas.single.isActive, isFalse);
      },
    );

    test(
      'un correo nuevo sustituye al perfil anterior (un solo perfil vigente)',
      () async {
        await datasource.saveProfile(
          const UserProfile(email: 'viejo@x.com', isActive: true),
        );
        await datasource.saveProfile(
          const UserProfile(email: 'nuevo@x.com', isActive: true),
        );

        final isar = await IsarService.init(directory: tempDir.path);
        final filas = await isar.localProfiles.where().findAll();
        expect(filas, hasLength(1));
        expect(filas.single.accountKey, 'nuevo@x.com');
        expect((await datasource.getCachedProfile())?.email, 'nuevo@x.com');
      },
    );

    test('deleteProfile borra solo el perfil indicado', () async {
      await datasource.saveProfile(
        const UserProfile(email: 'user@x.com', isActive: true),
      );

      await datasource.deleteProfile('  USER@X.COM ');

      expect(await datasource.getCachedProfile(), isNull);
    });

    test('deleteProfile con otro correo no borra el perfil vigente', () async {
      await datasource.saveProfile(
        const UserProfile(email: 'user@x.com', isActive: true),
      );

      await datasource.deleteProfile('otro@x.com');

      expect((await datasource.getCachedProfile())?.email, 'user@x.com');
    });

    test('el perfil sobrevive al cierre y reapertura de Isar', () async {
      await datasource.saveProfile(
        const UserProfile(email: 'user@x.com', isActive: false),
      );

      await IsarService.close();
      final reabierto = LocalProfileDatasourceImpl(testDirectory: tempDir.path);
      final guardado = await reabierto.getCachedProfile();

      expect(guardado?.email, 'user@x.com');
      expect(guardado?.isActive, isFalse);
    });
  });
}
