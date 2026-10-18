import 'package:app_movil_pdam/features/dispensers/data/datasources/dispensers_local_datasource.dart';
import 'package:app_movil_pdam/features/dispensers/data/models/dispenser_model.dart';
import 'package:app_movil_pdam/features/dispensers/data/services/ble_provisioning_service.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/dispenser_entity.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/scanned_device.dart';
import 'package:app_movil_pdam/features/dispensers/domain/repositories/dispensers_repository.dart';

class DispensersRepositoryImpl implements DispensersRepository {
  final DispensersLocalDatasource localDatasource;
  final BleProvisioningService bleService;

  DispensersRepositoryImpl({
    required this.localDatasource,
    required this.bleService,
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
    // Implement or call backend API if needed; for offline/local, we can also handle it or leave stub.
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
