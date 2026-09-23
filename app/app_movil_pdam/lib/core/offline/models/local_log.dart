import 'package:isar/isar.dart';

part 'local_log.g.dart';

@collection
class LocalLog {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  int? remoteId;

  late String userId;
  int? petRemoteId;

  late String event;
  late DateTime timestamp;

  late bool isSynced;
}
