import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/core/theme/theme_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Almacenamiento cifrado simulado: guarda en memoria y anota qué se lee.
class _FakeStorage implements StorageService {
  _FakeStorage({Map<String, String>? valores}) : valores = {...?valores};

  final Map<String, String> valores;
  final List<String> clavesLeidas = <String>[];

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async {
    valores[key] = value;
    return const Right(null);
  }

  @override
  Future<Either<Failures, String?>> getString(String key) async {
    clavesLeidas.add(key);
    return Right(valores[key]);
  }

  @override
  Future<Either<Failures, void>> deleteString(String key) async {
    valores.remove(key);
    return const Right(null);
  }
}

/// RF-23: la preferencia de apariencia se guarda en el dispositivo y sobrevive
/// al reinicio de la aplicación. Es independiente de la cuenta: la clave es
/// siempre `user_theme_mode`, sin correo ni identificador de usuario.
void main() {
  group('persistencia del modo de apariencia (RF-23)', () {
    test('setTheme(dark) escribe el código en user_theme_mode', () async {
      final storage = _FakeStorage();
      final cubit = ThemeCubit(storageService: storage);
      addTearDown(cubit.close);
      await cubit.loadTheme();

      await cubit.setTheme(ThemeMode.dark);

      expect(cubit.state, ThemeMode.dark);
      expect(storage.valores, <String, String>{'user_theme_mode': 'dark'});
    });

    test('setTheme escribe light y system con su código', () async {
      final storage = _FakeStorage();
      final cubit = ThemeCubit(storageService: storage);
      addTearDown(cubit.close);
      await cubit.loadTheme();

      await cubit.setTheme(ThemeMode.light);
      expect(storage.valores['user_theme_mode'], 'light');

      await cubit.setTheme(ThemeMode.system);
      expect(storage.valores['user_theme_mode'], 'system');
    });

    test('un cubit nuevo con user_theme_mode=dark restaura Oscuro tras '
        'reiniciar', () async {
      final storage = _FakeStorage();
      final antes = ThemeCubit(storageService: storage);
      await antes.loadTheme();
      await antes.setTheme(ThemeMode.dark);
      await antes.close();

      // «Reinicio»: la aplicación vuelve a arrancar con el mismo almacén.
      final despues = ThemeCubit(storageService: storage);
      addTearDown(despues.close);
      await despues.loadTheme();

      expect(despues.state, ThemeMode.dark);
    });

    test('un cubit nuevo con user_theme_mode=system restaura Automático', () async {
      final storage = _FakeStorage(
        valores: <String, String>{'user_theme_mode': 'system'},
      );
      final cubit = ThemeCubit(storageService: storage);
      addTearDown(cubit.close);

      await cubit.loadTheme();

      expect(cubit.state, ThemeMode.system);
    });

    test('sin la clave la aplicación arranca en Automático', () async {
      final storage = _FakeStorage();
      final cubit = ThemeCubit(storageService: storage);
      addTearDown(cubit.close);

      await cubit.loadTheme();

      expect(cubit.state, ThemeMode.system);
    });

    test('un valor desconocido cae en Automático', () async {
      final storage = _FakeStorage(
        valores: <String, String>{'user_theme_mode': 'sepia'},
      );
      final cubit = ThemeCubit(storageService: storage);
      addTearDown(cubit.close);

      await cubit.loadTheme();

      expect(cubit.state, ThemeMode.system);
    });

    test('la clave no depende de ningún dato de la cuenta', () async {
      // El almacén ya tiene datos de la cuenta: el modo no debe usar ninguno.
      final storage = _FakeStorage(
        valores: <String, String>{
          'user_email': 'cuenta@x.com',
          'user_id': '7',
        },
      );
      final cubit = ThemeCubit(storageService: storage);
      addTearDown(cubit.close);
      await cubit.loadTheme();

      await cubit.setTheme(ThemeMode.dark);

      expect(storage.clavesLeidas, everyElement('user_theme_mode'));
      expect(storage.valores['user_theme_mode'], 'dark');
      expect(storage.valores['user_email'], 'cuenta@x.com');
      expect(storage.valores['user_id'], '7');
      expect(
        storage.valores.keys.where((clave) => clave.contains('@')),
        isEmpty,
      );

      // Otra cuenta en el mismo dispositivo conserva la preferencia.
      storage.valores['user_email'] = 'otra@x.com';
      final otraCuenta = ThemeCubit(storageService: storage);
      addTearDown(otraCuenta.close);
      await otraCuenta.loadTheme();

      expect(otraCuenta.state, ThemeMode.dark);
    });
  });
}
