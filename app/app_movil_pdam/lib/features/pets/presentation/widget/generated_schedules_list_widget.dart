import 'package:flutter/material.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';

class GeneratedSchedulesListWidget extends StatelessWidget {
  final List<Schedule> schedules;
  final double waterMin;
  final double waterMax;

  const GeneratedSchedulesListWidget({
    super.key,
    required this.schedules,
    required this.waterMin,
    required this.waterMax,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 16),
        Text(
          "Horarios Programados:",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: schedules.length,
          itemBuilder: (context, index) {
            final s = schedules[index];
            return Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.access_time, color: Colors.blue),
                title: Text(s.time, style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text("${s.amount} g", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15)),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: Colors.cyan.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                const Icon(Icons.water_drop, color: Colors.cyan, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "💧 Agua recomendada: ${waterMin.toStringAsFixed(0)} - ${waterMax.toStringAsFixed(0)} ml/día.",
                    style: const TextStyle(fontSize: 13, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
