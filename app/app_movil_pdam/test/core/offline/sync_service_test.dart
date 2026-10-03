import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/offline/sync_service.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  test('SyncService puede instanciarse correctamente', () {
    final storageService = StorageServiceImpl(
      dataLocalService: const FlutterSecureStorage(),
    );
    final dioClient = DioClient(storageService);
    final syncService = SyncService(dioClient: dioClient);

    expect(syncService, isNotNull);
  });
}
