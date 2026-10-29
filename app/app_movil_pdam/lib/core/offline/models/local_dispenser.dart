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

  /// Identificador de la operación de reabastecimiento pendiente (RF-11).
  /// Se genera una vez y se repite en cada reenvío para que el servidor
  /// deduplique; sin él, un reenvío volvería a sumar el stock.
  String? pendingRefillId;

  late DateTime updatedAt;
  late bool isSynced;
}
