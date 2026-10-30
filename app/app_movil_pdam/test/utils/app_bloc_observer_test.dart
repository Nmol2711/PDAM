import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:app_movil_pdam/features/account/presentation/bloc/account_bloc.dart';
import 'package:app_movil_pdam/utils/app_bloc_observer.dart';
import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Estado de prueba con un `toString()` que expone un marcador sensible.
///
/// Sirve para discriminar: el observador anterior imprimía el estado completo y
/// esta prueba fallaría al encontrar el marcador en la salida.
class _EstadoSensible {
  final String valor;

  const _EstadoSensible(this.valor);

  @override
  String toString() => 'EstadoSensible($valor)';
}

/// Bloc mínimo cuyo estado expone un dato sensible en `toString()`.
class _BlocEstadoSensible extends Bloc<int, _EstadoSensible> {
  _BlocEstadoSensible() : super(const _EstadoSensible('inicial'));
}

/// Bloc mínimo cuyo estado es un [AccountState] real.
class _BlocCuentaFalso extends Bloc<int, AccountState> {
  _BlocCuentaFalso() : super(const AccountState()) {
    on<int>((evento, emit) {
      emit(
        const AccountState(
          profile: UserProfile(email: 'sensible@x.com', isActive: true),
        ),
      );
    });
  }
}

void main() {
  late List<String> salida;
  late DebugPrintCallback debugPrintOriginal;
  late AppBlocObserver observer;

  setUp(() {
    debugPrintOriginal = debugPrint;
    salida = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) salida.add(message);
    };
    observer = AppBlocObserver();
  });

  tearDown(() {
    debugPrint = debugPrintOriginal;
  });

  group('AppBlocObserver (RNF-06)', () {
    test('no vuelca los datos del AccountState en la consola', () {
      final bloc = _BlocCuentaFalso();

      observer.onChange(
        bloc,
        Change(
          currentState: const AccountState(),
          nextState: const AccountState(
            profile: UserProfile(email: 'sensible@x.com', isActive: true),
          ),
        ),
      );

      final log = salida.join('\n');
      expect(log, isNot(contains('sensible@x.com')));
      expect(log, isNot(contains('access_token')));
      // El diagnóstico se conserva con el nombre del bloc y del estado.
      expect(log, contains('_BlocCuentaFalso'));
      expect(log, contains('AccountState'));
    });

    test('no vuelca el toString de un estado con un dato sensible', () {
      final bloc = _BlocEstadoSensible();

      observer.onChange(
        bloc,
        const Change(
          currentState: _EstadoSensible('inicial'),
          nextState: _EstadoSensible('token-nuevo-secreto'),
        ),
      );

      final log = salida.join('\n');
      expect(log, isNot(contains('token-nuevo-secreto')));
      expect(log, isNot(contains('EstadoSensible(')));
      // La salida es exactamente el bloc y los tipos de estado, sin valores.
      expect(
        log,
        '[BLOC CHANGE] _BlocEstadoSensible: _EstadoSensible -> _EstadoSensible',
      );
    });

    test('no vuelca el mensaje del error en la consola', () {
      final bloc = _BlocCuentaFalso();

      observer.onError(
        bloc,
        Exception('mensaje con token-nuevo-secreto'),
        StackTrace.empty,
      );

      final log = salida.join('\n');
      expect(log, isNot(contains('token-nuevo-secreto')));
      expect(log, contains('_BlocCuentaFalso'));
      expect(log, contains('Exception'));
    });
  });
}
