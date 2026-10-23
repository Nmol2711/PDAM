import 'package:isar/isar.dart';

part 'local_dispenser.g.dart';

@collection
class LocalDispenser {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  int? remoteId;

  int? petRemoteId;

  late String macAddress;
  String secretKeyQr = '';
  late bool isActive;
  late bool pendingDispensing;

  double currentFoodGrams = 5000.0;
  bool isOfflineCached = false;

  /// Gramos reabastecidos sin conexión que aún no se enviaron al servidor.
  /// Persistir el delta permite sobrevivir al cierre de la app (RNF-7).
  double pendingRefillGrams = 0.0;

  late DateTime updatedAt;
  late bool isSynced;
}
