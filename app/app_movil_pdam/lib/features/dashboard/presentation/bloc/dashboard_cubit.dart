import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:app_movil_pdam/features/dashboard/domain/repositories/dashboard_repository.dart';

abstract class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

class DashboardInitial extends DashboardState {}

class DashboardLoading extends DashboardState {}

class DashboardLoaded extends DashboardState {
  final DashboardSummary summary;

  /// Aviso de que el último refresco falló mientras se conserva [summary].
  /// Es nulo cuando los datos visibles están actualizados.
  final String? errorMessage;

  const DashboardLoaded({required this.summary, this.errorMessage});

  /// Copia el estado conservando el resumen visible.
  ///
  /// `errorMessage` nulo mantiene el aviso actual, de modo que un mensaje solo
  /// se descarta con [limpiarError], como al recibir datos nuevos.
  DashboardLoaded copyWith({
    DashboardSummary? summary,
    String? errorMessage,
    bool limpiarError = false,
  }) {
    return DashboardLoaded(
      summary: summary ?? this.summary,
      errorMessage: limpiarError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [summary, errorMessage];
}

class DashboardError extends DashboardState {
  final String message;

  const DashboardError({required this.message});

  @override
  List<Object?> get props => [message];
}

class DashboardCubit extends Cubit<DashboardState> {
  final DashboardRepository _repository;

  /// Identificador de la última carga solicitada. Las respuestas de cargas
  /// anteriores se descartan para que la más reciente gane.
  int _solicitud = 0;

  DashboardCubit({required DashboardRepository repository})
      : _repository = repository,
        super(DashboardInitial());

  /// Copy fijo en español para cualquier fallo del resumen (RNF-01 del
  /// proyecto): el texto del fallo o de la excepción nunca llega a la vista.
  static const String mensajeError = 'No se pudo cargar el panel.';

  /// Carga el resumen del panel.
  ///
  /// Si no hay resumen visible muestra la carga; si ya hay uno, el refresco no
  /// borra la pantalla. Un fallo del servidor se expone como aviso sobre el
  /// resumen visible, y un respaldo (caché o datos locales) nunca lo
  /// sustituye: solo reemplaza lo mostrado un resumen fresco del servidor.
  Future<void> loadSummary() async {
    final solicitud = ++_solicitud;
    if (state is! DashboardLoaded) {
      emit(DashboardLoading());
    }

    final result = await _repository.getDashboardSummary();
    if (solicitud != _solicitud) return;

    result.fold(
      (_) => _emitirFallo(),
      (summary) => _emitirResumen(summary),
    );
  }

  /// Repite la carga del panel tras un error o un aviso sin conexión.
  Future<void> reintentar() => loadSummary();

  /// Conserva lo visible ante un fallo del servidor o emite el error fijo si
  /// todavía no hay resumen que mostrar.
  void _emitirFallo() {
    final visible = state;
    if (visible is DashboardLoaded) {
      emit(visible.copyWith(errorMessage: mensajeError));
    } else {
      emit(DashboardError(message: mensajeError));
    }
  }

  /// Emite el resumen recibido.
  ///
  /// Un respaldo (caché o datos locales sin fecha del servidor) solo se muestra
  /// cuando no hay resumen visible. Con datos visibles se conservan y el
  /// respaldo se señala con el aviso fijo, porque puede ser más viejo. Un
  /// resumen fresco reemplaza siempre lo mostrado y limpia el aviso.
  void _emitirResumen(DashboardSummary summary) {
    final visible = state;
    final esRespaldo = summary.isFromCache || summary.calculatedAt == null;

    if (visible is DashboardLoaded && esRespaldo) {
      emit(
        DashboardLoaded(summary: visible.summary, errorMessage: mensajeError),
      );
      return;
    }

    emit(DashboardLoaded(summary: summary));
  }
}
