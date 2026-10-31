import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';

class PetNutritionalSummaryCard extends StatelessWidget {
  final Pet pet;

  const PetNutritionalSummaryCard({super.key, required this.pet});

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: esquema.primary,
              child: Icon(Icons.pets, color: esquema.onPrimary),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    "${pet.weight} kg • ${pet.age} años • ${pet.reproductiveStatus ? 'Castrado' : 'Entero'}",
                    style: TextStyle(
                      color: esquema.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
