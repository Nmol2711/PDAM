import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
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
  final StorageService storageService;

  DispensersRepositoryImpl({
    required this.localDatasource,
    required this.bleService,
    required this.dioClient,
    required this.storageService,
  });

  @override
  Future<List<DispenserEntity>> getLocalDispensers() async {
    final localList = await localDatasource.getLocalDispensers();
    final list = <DispenserModel>[];
    for (var l in localList) {
      final deviceId = l.remoteId?.toString() ?? l.id.toString();
      final mac = l.macAddress;
      String? ssid;

      final resultSsid = await storageService.getString('wifi_ssid_$mac');
      resultSsid.fold(
        (_) => ssid = null,
        (val) => ssid = val,
      );
      if (ssid == null || ssid!.isEmpty) {
        final resultSsidId = await storageService.getString('wifi_ssid_$deviceId');
        resultSsidId.fold(
          (_) => ssid = null,
          (val) => ssid = val,
        );
      }

      list.add(DispenserModel(
        id: deviceId,
        macAddress: mac,
        name: 'Dispensador $mac',
        isConnected: l.isActive,
        wifiSsid: ssid,
        currentFoodGrams: l.currentFoodGrams,
        isOfflineCached: l.isOfflineCached,
        petId: l.petRemoteId,
      ));
    }
    return list;
  }

  @override
  Future<void> saveLocalDispenser(DispenserEntity dispenser) async {
    final model = DispenserModel.fromEntity(dispenser);
    await localDatasource.saveLocalDispenser(model.toLocal());
    if (dispenser.wifiSsid != null && dispenser.wifiSsid!.isNotEmpty) {
      await storageService.saveString('wifi_ssid_${dispenser.macAddress}', dispenser.wifiSsid!);
      await storageService.saveString('wifi_ssid_${dispenser.id}', dispenser.wifiSsid!);
    }
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
    // RF-01 & RNF-02: Save WiFi credentials securely via flutter_secure_storage
    final resSsid = await storageService.saveString('wifi_ssid_$deviceId', ssid);
    resSsid.fold(
      (f) => throw Exception('Error al guardar SSID de forma segura: ${f.message}'),
      (_) {},
    );
    final resPass = await storageService.saveString('wifi_pass_$deviceId', password);
    resPass.fold(
      (f) => throw Exception('Error al guardar contraseña de forma segura: ${f.message}'),
      (_) {},
    );
  }

  @override
  Future<void> resetWifiRemote(String dispenserId) async {
    try {
      await dioClient.dio.post('${ApiConstants.dispenser}$dispenserId/reset-wifi');
    } catch (e) {
      throw Exception('Error al solicitar reseteo de WiFi: ${e.toString()}');
    }
    await storageService.deleteString('wifi_ssid_$dispenserId');
    await storageService.deleteString('wifi_pass_$dispenserId');
  }
}
