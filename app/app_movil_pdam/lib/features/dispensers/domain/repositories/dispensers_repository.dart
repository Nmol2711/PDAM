import 'package:app_movil_pdam/features/dispensers/domain/entities/dispenser_entity.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/scanned_device.dart';

abstract class DispensersRepository {
  Future<List<DispenserEntity>> getLocalDispensers();
  Future<void> saveLocalDispenser(DispenserEntity dispenser);
  Stream<List<ScannedDevice>> scanBleDispensers();
  Future<void> connectAndProvisionBle({
    required String deviceId,
    required String ssid,
    required String password,
  });
  Future<void> resetWifiRemote(String dispenserId);
}
