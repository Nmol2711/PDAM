import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/data/models/activity_log_model.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/remote/log_remote_datasource.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/local/local_log_datasource.dart';
import 'package:app_movil_pdam/features/logs/data/repository_impl/log_repository_impl.dart';

class MockLogRemoteDatasource implements LogRemoteDatasource {
  bool shouldThrow = false;
  List<ActivityLogModel> mockModels = [];

  @override
  Future<List<ActivityLogModel>> getLogs({int? petId, String? date}) async {
    if (shouldThrow) throw Exception('Server offline');
    return mockModels;
  }
}

class MockLocalLogDatasource implements LocalLogDatasource {
  List<ActivityLogEntity> localLogs = [];

  @override
  Future<void> cacheLogs(List<ActivityLogEntity> logs) async {
    localLogs = List.from(logs);
  }

  @override
  Future<void> deleteLocalLog(int logId) async {
    localLogs.removeWhere((l) => l.id == logId);
  }

  @override
  Future<List<ActivityLogEntity>> getLocalLogs({int? petId, String? date}) async {
    return localLogs;
  }

  @override
  Future<void> saveLocalLog(ActivityLogEntity log, {bool isSynced = true}) async {
    localLogs.add(log);
  }
}

void main() {
  late LogRepositoryImpl repository;
  late MockLogRemoteDatasource remoteDatasource;
  late MockLocalLogDatasource localDatasource;

  setUp(() {
    remoteDatasource = MockLogRemoteDatasource();
    localDatasource = MockLocalLogDatasource();
    repository = LogRepositoryImpl(
      remoteDatasource: remoteDatasource,
      localLogDatasource: localDatasource,
    );
  });

  test('getLogs retorna logs remotos y los cachea cuando hay red', () async {
    remoteDatasource.mockModels = [
      ActivityLogModel(id: 1, event: 'Dispensed 50g', timestamp: DateTime.now(), petId: 1)
    ];

    final result = await repository.getLogs(petId: 1);

    expect(result.isRight(), true);
    result.fold(
      (l) => fail('No debería fallar'),
      (fetchResult) {
        expect(fetchResult.isOffline, false);
        expect(fetchResult.logs.length, 1);
      },
    );
  });

  test('getLogs hace fallback local cuando falla la red', () async {
    localDatasource.localLogs = [
      ActivityLogEntity(id: 2, event: 'Offline log', timestamp: DateTime.now(), petId: 1)
    ];
    remoteDatasource.shouldThrow = true;

    final result = await repository.getLogs(petId: 1);

    expect(result.isRight(), true);
    result.fold(
      (l) => fail('No debería fallar'),
      (fetchResult) {
        expect(fetchResult.isOffline, true);
        expect(fetchResult.logs.length, 1);
        expect(fetchResult.logs.first.event, 'Offline log');
      },
    );
  });
}
