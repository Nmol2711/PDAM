class Schedule {
  final int id;
  final String time;
  final double amount;
  final int petId;

  const Schedule({
    required this.id,
    required this.time,
    required this.amount,
    required this.petId,
  });
}

class ScheduleFetchResult {
  final List<Schedule> schedules;
  final bool isOffline;

  const ScheduleFetchResult({
    required this.schedules,
    required this.isOffline,
  });
}
