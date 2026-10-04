import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/sync_conflict_resolver.dart';
import 'package:app_movil_pdam/core/offline/models/local_pet.dart';
import 'package:app_movil_pdam/core/offline/models/local_schedule.dart';
import 'package:app_movil_pdam/core/offline/models/local_log.dart';
import 'package:app_movil_pdam/core/offline/models/local_dispenser.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:isar/isar.dart';

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

  /// Orquesta la sincronización bidireccional de todos los registros pendientes de dominio
  /// (mascotas, horarios y logs con isSynced == false) almacenados en Isar (RF-05).
  Future<bool> synchronizePendingData({String? testDirectory, double lastSyncTimestamp = 0.0}) async {
    if (!await hasConnection()) {
      return false;
    }

    try {
      final isar = await IsarService.init(directory: testDirectory);

      final unsyncedPets = await isar.localPets.filter().isSyncedEqualTo(false).findAll();
      final unsyncedSchedules = await isar.localSchedules.filter().isSyncedEqualTo(false).findAll();
      final unsyncedLogs = await isar.localLogs.filter().isSyncedEqualTo(false).findAll();
      final unsyncedDispensers = await isar.localDispensers.filter().isSyncedEqualTo(false).findAll();

      if (unsyncedPets.isEmpty && unsyncedSchedules.isEmpty && unsyncedLogs.isEmpty && unsyncedDispensers.isEmpty) {
        return true;
      }

      final List<Map<String, dynamic>> items = [];

      for (final pet in unsyncedPets) {
        items.add({
          'id': 'pet_${pet.remoteId ?? pet.id}',
          'updated_at': pet.updatedAt.millisecondsSinceEpoch.toDouble(),
          'data': {
            'type': 'pet',
            'id': pet.remoteId ?? pet.id,
            'name': pet.name,
            'species': pet.species,
            'birth_date': pet.birthDate,
            'weight': pet.weight,
            'reproductive_status': pet.reproductiveStatus,
            'path_url': pet.pathUrl,
            'updated_at': pet.updatedAt.millisecondsSinceEpoch.toDouble(),
          },
        });
      }

      for (final sched in unsyncedSchedules) {
        items.add({
          'id': 'schedule_${sched.remoteId ?? sched.id}',
          'updated_at': sched.updatedAt.millisecondsSinceEpoch.toDouble(),
          'data': {
            'type': 'schedule',
            'id': sched.remoteId ?? sched.id,
            'pet_id': sched.petRemoteId,
            'time': sched.time,
            'amount': sched.amount,
            'updated_at': sched.updatedAt.millisecondsSinceEpoch.toDouble(),
          },
        });
      }

      for (final log in unsyncedLogs) {
        items.add({
          'id': 'log_${log.remoteId ?? log.id}',
          'updated_at': log.timestamp.millisecondsSinceEpoch.toDouble(),
          'data': {
            'type': 'log',
            'id': log.remoteId ?? log.id,
            'pet_id': log.petRemoteId,
            'event': log.event,
            'timestamp': log.timestamp.toIso8601String(),
            'updated_at': log.timestamp.millisecondsSinceEpoch.toDouble(),
          },
        });
      }

      for (final disp in unsyncedDispensers) {
        items.add({
          'id': 'dispenser_${disp.remoteId ?? disp.id}',
          'updated_at': disp.updatedAt.millisecondsSinceEpoch.toDouble(),
          'data': {
            'type': 'dispenser',
            'id': disp.remoteId ?? disp.id,
            'mac_address': disp.macAddress,
            'pet_id': disp.petRemoteId,
            'secret_key_qr': disp.secretKeyQr,
            'is_active': disp.isActive,
            'updated_at': disp.updatedAt.millisecondsSinceEpoch.toDouble(),
          },
        });
      }

      final response = await _dioClient.dio.post(
        ApiConstants.sync,
        data: {
          'last_sync_timestamp': lastSyncTimestamp,
          'items': items,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final syncedItems = data['synced_items'] as List<dynamic>? ?? [];

        await isar.writeTxn(() async {
          for (var remoteItem in syncedItems) {
            final remoteMap = Map<String, dynamic>.from(remoteItem);
            final localItemMatch = items.firstWhere(
              (item) => item['id'] == remoteMap['id'],
              orElse: () => {},
            );

            if (localItemMatch.isNotEmpty) {
              resolveConflict(localItemMatch, remoteMap);
            }
          }

          for (final pet in unsyncedPets) {
            pet.isSynced = true;
            await isar.localPets.put(pet);
          }
          for (final sched in unsyncedSchedules) {
            sched.isSynced = true;
            await isar.localSchedules.put(sched);
          }
          for (final log in unsyncedLogs) {
            log.isSynced = true;
            await isar.localLogs.put(log);
          }
          for (final disp in unsyncedDispensers) {
            disp.isSynced = true;
            await isar.localDispensers.put(disp);
          }
        });

        return true;
      }
      return false;
    } on DioException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
}
