class ActivityLogEntity {
  final int id;
  final String event;
  final DateTime timestamp;
  final int? petId;

  const ActivityLogEntity({
    required this.id,
    required this.event,
    required this.timestamp,
    this.petId,
  });
}

class LogFetchResult {
  final List<ActivityLogEntity> logs;
  final bool isOffline;

  const LogFetchResult({
    required this.logs,
    required this.isOffline,
  });
}
