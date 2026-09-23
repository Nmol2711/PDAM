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

  const DashboardLoaded({required this.summary});

  @override
  List<Object?> get props => [summary];
}

class DashboardError extends DashboardState {
  final String message;

  const DashboardError({required this.message});

  @override
  List<Object?> get props => [message];
}

class DashboardCubit extends Cubit<DashboardState> {
  final DashboardRepository _repository;

  DashboardCubit({required DashboardRepository repository})
      : _repository = repository,
        super(DashboardInitial());

  Future<void> loadSummary() async {
    emit(DashboardLoading());
    final result = await _repository.getDashboardSummary();
    result.fold(
      (failure) => emit(DashboardError(message: failure.message)),
      (summary) => emit(DashboardLoaded(summary: summary)),
    );
  }
}
