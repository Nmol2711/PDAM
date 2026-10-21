import 'package:app_movil_pdam/core/constant/api_constants.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/features/dispensers/data/datasources/dispensers_local_datasource.dart';
import 'package:app_movil_pdam/features/dispensers/data/models/dispenser_model.dart';
import 'package:app_movil_pdam/features/dispensers/data/services/ble_provisioning_service.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/dispenser_entity.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/scanned_device.dart';
import 'package:app_movil_pdam/features/dispensers/domain/repositories/dispensers_repository.dart';

class DispensersRepositoryImpl implements DispensersRepository {
  final DispensersLocalDatasource localDatasource;
  final BleProvisioningService bleService;
  final DioClient dioClient;

  DispensersRepositoryImpl({
    required this.localDatasource,
    required this.bleService,
    required this.dioClient,
  });

  @override
  Future<List<DispenserEntity>> getLocalDispensers() async {
    final localList = await localDatasource.getLocalDispensers();
    return localList.map((l) => DispenserModel.fromLocal(l)).toList();
  }

  @override
  Future<void> saveLocalDispenser(DispenserEntity dispenser) async {
    final model = DispenserModel.fromEntity(dispenser);
    await localDatasource.saveLocalDispenser(model.toLocal());
  }

  @override
  Future<void> refillFood(String dispenserId, double grams) async {
    final localList = await localDatasource.getLocalDispensers();
    for (var local in localList) {
      if (local.id.toString() == dispenserId ||
          local.macAddress == dispenserId ||
          local.remoteId?.toString() == dispenserId) {
        local.currentFoodGrams = grams.clamp(0.0, 5000.0);
        local.updatedAt = DateTime.now();
        await localDatasource.saveLocalDispenser(local);
      }
    }
  }

  @override
  Future<void> discountFood(String dispenserId, double grams) async {
    final localList = await localDatasource.getLocalDispensers();
    for (var local in localList) {
      if (local.id.toString() == dispenserId ||
          local.macAddress == dispenserId ||
          local.remoteId?.toString() == dispenserId) {
        local.currentFoodGrams = (local.currentFoodGrams - grams).clamp(0.0, 5000.0);
        local.updatedAt = DateTime.now();
        await localDatasource.saveLocalDispenser(local);
      }
    }
  }

  @override
  Stream<List<ScannedDevice>> scanBleDispensers() {
    return bleService.scanDevices();
  }

  @override
  Future<void> connectAndProvisionBle({
    required String deviceId,
    required String ssid,
    required String password,
  }) async {
    await bleService.connectAndProvision(
      deviceId: deviceId,
      ssid: ssid,
      password: password,
    );
  }

  @override
  Future<void> resetWifiRemote(String dispenserId) async {
    try {
      await dioClient.dio.post('${ApiConstants.dispenser}$dispenserId/reset-wifi');
    } catch (e) {
      throw Exception('Error al solicitar reseteo de WiFi: ${e.toString()}');
    }
  }
}
