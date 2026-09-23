import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_logs_uc.dart';
import 'package:bloc/bloc.dart';

part 'log_event.dart';
part 'log_state.dart';

class LogBloc extends Bloc<LogEvent, LogState> {
  final GetLogsUc _getLogsUc;

  LogBloc({required GetLogsUc getLogsUc})
      : _getLogsUc = getLogsUc,
        super(LogInitial()) {
    on<LogsRequested>(_onLogsRequested);
  }

  Future<void> _onLogsRequested(
    LogsRequested event,
    Emitter<LogState> emit,
  ) async {
    emit(LogLoading());
    final result = await _getLogsUc(petId: event.petId, date: event.date);
    result.fold(
      (failure) => emit(LogError(message: failure.message)),
      (fetchResult) => emit(LogLoaded(logs: fetchResult.logs, isOffline: fetchResult.isOffline)),
    );
  }
}
