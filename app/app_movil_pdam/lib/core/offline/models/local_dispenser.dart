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

  late DateTime updatedAt;
  late bool isSynced;
}
