import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';

class LogItemWidget extends StatelessWidget {
  final ActivityLogEntity log;

  const LogItemWidget({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final formattedDate = "${log.timestamp.toLocal()}".split('.')[0];
    
    String? petName;
    if (log.petId != null) {
      final petState = context.watch<PetBloc>().state;
      if (petState is PetLoaded) {
        final pet = petState.pets.where((p) => p.id == log.petId).firstOrNull;
        petName = pet?.name;
      }
    }

    final displayLabel = petName ?? (log.petId != null ? 'Mascota #${log.petId}' : '');

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.history, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(
          log.event,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            formattedDate,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ),
        trailing: log.petId != null
            ? Chip(
                label: Text(displayLabel, style: const TextStyle(fontSize: 11)),
                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              )
            : null,
      ),
    );
  }
}
