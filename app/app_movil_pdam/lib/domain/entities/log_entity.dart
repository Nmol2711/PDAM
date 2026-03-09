class LogEntity {
  final int id;
  final String event;
  final DateTime timestamp;
  final int userId;

  LogEntity({
    required this.id,
    required this.event,
    required this.timestamp,
    required this.userId,
  });
}
