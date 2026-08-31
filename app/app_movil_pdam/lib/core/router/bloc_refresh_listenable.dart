// core/router/bloc_refresh_listenable.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BlocRefreshListenable<B extends BlocBase<S>, S> extends ChangeNotifier {
  final B bloc;
  late final StreamSubscription<S> _subscription;

  BlocRefreshListenable(this.bloc) {
    // 1. Notificamos inmediatamente al construir para que GoRouter
    // sincronice el estado actual si cambió muy rápido en el arranque.
    notifyListeners();

    // 2. Escuchamos de forma permanente todos los cambios futuros
    _subscription = bloc.stream.listen((state) {
      debugPrint(
        "🔔 [Puente Router] El Bloc emitió un estado. Notificando a GoRouter...",
      );
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
