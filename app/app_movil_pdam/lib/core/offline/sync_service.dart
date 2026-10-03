import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/offline/sync_conflict_resolver.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

class SyncService {
  final DioClient _dioClient;

  SyncService({required DioClient dioClient}) : _dioClient = dioClient;

  /// Verifica si hay conexión a internet disponible.
  Future<bool> hasConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return !results.contains(ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  /// Ejecuta la sincronización bidireccional en segundo plano (RF-04, RF-05, RNF-03).
  Future<bool> synchronizeBatch({
    required double lastSyncTimestamp,
    required List<Map<String, dynamic>> localItems,
  }) async {
    if (!await hasConnection()) {
      return false;
    }

    try {
      final response = await _dioClient.dio.post(
        ApiConstants.sync,
        data: {
          'last_sync_timestamp': lastSyncTimestamp,
          'items': localItems,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final syncedItems = data['synced_items'] as List<dynamic>? ?? [];

        // Procesar y fusionar elementos sincronizados usando la función pura resolveConflict
        for (var remoteItem in syncedItems) {
          final remoteMap = Map<String, dynamic>.from(remoteItem);
          final matchingLocal = localItems.firstWhere(
            (local) => local['id'] == remoteMap['id'],
            orElse: () => {},
          );

          if (matchingLocal.isNotEmpty) {
            // Resolver posible conflicto (RF-04)
            resolveConflict(matchingLocal, remoteMap);
          }
        }
        return true;
      }
      return false;
    } on DioException catch (_) {
      // RF-05: Si falla la sincronización en servidor, se reintentará en reconexión
      return false;
    } catch (_) {
      return false;
    }
  }
}
