import 'package:isar/isar.dart';

part 'local_schedule.g.dart';

@collection
class LocalSchedule {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  int? remoteId;

  late String userId;
  late int petRemoteId;

  late String time;
  late double amount;

  late DateTime updatedAt;
  late bool isSynced;
}
