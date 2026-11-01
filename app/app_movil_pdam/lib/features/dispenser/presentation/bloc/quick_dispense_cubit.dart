import 'package:app_movil_pdam/features/dispenser/domain/use_case/quick_dispense_uc.dart';
import 'package:app_movil_pdam/features/logs/domain/utils/operation_id_utils.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Estado de la solicitud rápida. El texto del error lo decide la presentación
/// a partir del `message` tipado del fallo, no este módulo.
abstract class QuickDispenseState extends Equatable {
  const QuickDispenseState();

  @override
  List<Object?> get props => [];
}

class QuickDispenseInitial extends QuickDispenseState {
  const QuickDispenseInitial();
}

class QuickDispenseSending extends QuickDispenseState {
  const QuickDispenseSending();
}

class QuickDispenseAccepted extends QuickDispenseState {
  final double grams;

  const QuickDispenseAccepted(this.grams);

  @override
  List<Object?> get props => [grams];
}

class QuickDispenseError extends QuickDispenseState {
  final String message;

  const QuickDispenseError(this.message);

  @override
  List<Object?> get props => [message];
}

class QuickDispenseCubit extends Cubit<QuickDispenseState> {
  final QuickDispenseUc quickDispenseUc;
  final String Function() _generarIdentificador;

  /// Identificador de la operación en curso y la cantidad a la que pertenece.
  /// Se reutiliza en el reintento mientras la cantidad no cambie (RF-14); si
  /// cambia, se renueva para no devolver la solicitud anterior.
  String? _operationId;
  double? _cantidadOperacion;

  QuickDispenseCubit({
    required this.quickDispenseUc,
    String Function()? generarIdentificador,
  }) : _generarIdentificador =
           generarIdentificador ?? generarIdentificadorOperacion,
       super(const QuickDispenseInitial());

  Future<void> solicitar(int dispenserId, double grams) async {
    if (state is QuickDispenseSending) return;

    final operationId = _operationIdPara(grams);
    emit(const QuickDispenseSending());
    final result = await quickDispenseUc(dispenserId, grams, operationId);
    if (isClosed) return;

    result.fold(
      (failure) => emit(QuickDispenseError(failure.message)),
      (_) => emit(QuickDispenseAccepted(grams)),
    );
  }

  /// Conserva el identificador si la cantidad no cambia y lo renueva si cambia.
  String _operationIdPara(double grams) {
    final guardado = _operationId;
    if (guardado != null && _cantidadOperacion == grams) return guardado;

    final nuevo = _generarIdentificador();
    _operationId = nuevo;
    _cantidadOperacion = grams;
    return nuevo;
  }
}
