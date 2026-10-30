// core/utils/app_bloc_observer.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Observador de BLoC que no vuelca estados ni errores completos.
///
/// Los estados pueden contener tokens nuevos y los errores detalles internos.
/// Solo se registra el tipo del bloc y de los estados, suficiente para
/// diagnosticar sin exponer datos sensibles (RNF-06).
class AppBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    debugPrint(
      '[BLOC CHANGE] ${bloc.runtimeType}: '
      '${change.currentState.runtimeType} -> ${change.nextState.runtimeType}',
    );
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    debugPrint('[BLOC ERROR] ${bloc.runtimeType}: ${error.runtimeType}');
    super.onError(bloc, error, stackTrace);
  }
}
