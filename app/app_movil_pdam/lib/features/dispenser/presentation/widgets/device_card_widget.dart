import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/core/di/injection_container.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser_food_status.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/dispenser_food_progress_bar.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/core/presentation/widgets/in_app_notification_banner.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_pet_datasource.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_schedule_datasource.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';

class DeviceCardWidget extends StatelessWidget {
  final Dispenser dispenser;
  final VoidCallback? onResetWifi;
  final VoidCallback? onTap;

  const DeviceCardWidget({
    super.key,
    required this.dispenser,
    this.onResetWifi,
    this.onTap,
  });

  void _showRefillDialog(BuildContext context) {
    final amountController = TextEditingController();
    final bloc = context.read<DispenserBloc>();
    String selectedUnit = 'g';
    String? limitMessage;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final esquema = Theme.of(context).colorScheme;
          return AlertDialog(
            title: const Text('Reabastecer Alimento'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dispositivo: ${dispenser.name}'),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Cantidad a agregar',
                      hintText: selectedUnit == 'g' ? 'Ej. 1000' : 'Ej. 1.5',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Unidad: '),
                      ChoiceChip(
                        label: const Text('Gramos (g)'),
                        selected: selectedUnit == 'g',
                        onSelected: (selected) {
                          if (selected) setState(() => selectedUnit = 'g');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Kilogramos (kg)'),
                        selected: selectedUnit == 'kg',
                        onSelected: (selected) {
                          if (selected) setState(() => selectedUnit = 'kg');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Capacidad del depósito: 5 kg (5000 g). '
                    'La cantidad se suma al stock y no puede superar el máximo.',
                    style: TextStyle(
                      fontSize: 12,
                      color: esquema.onSurfaceVariant,
                    ),
                  ),
                  if (limitMessage != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      limitMessage!,
                      style: TextStyle(fontSize: 12, color: esquema.error),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  final val =
                      double.tryParse(amountController.text.trim()) ?? 0.0;
                  try {
                    final grams = convertAndValidateRefill(val, selectedUnit);
                    applyRefill(dispenser.currentFoodGrams, grams);
                  } on RefillLimitException catch (e) {
                    setState(() => limitMessage = e.toString());
                    return;
                  }
                  setState(() => limitMessage = null);
                  Navigator.of(dialogContext).pop();
                  bloc.add(
                    RefillFoodEvent(
                      dispenserId: dispenser.deviceId,
                      amount: val,
                      unit: selectedUnit,
                    ),
                  );
                },
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDetailsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetRadius),
      builder: (context) => FutureBuilder<Map<String, dynamic>>(
        future: _loadPetAndSchedules(),
        builder: (context, snapshot) {
          final esquema = Theme.of(context).colorScheme;
          final petName =
              snapshot.data?['petName'] as String? ?? 'Sin mascota vinculada';
          final schedules =
              snapshot.data?['schedules'] as List<Schedule>? ?? [];
          final remainingRations = calculateRemainingRations(
            dispenser.currentFoodGrams,
            schedules,
          );
          final rationsText =
              schedules.isEmpty && dispenser.currentFoodGrams > 0
              ? '${(dispenser.currentFoodGrams / 50).floor()} raciones (estimadas)'
              : '$remainingRations raciones';

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Detalles de Alimento',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),
                Text('Dispositivo: ${dispenser.name}'),
                Text('MAC: ${dispenser.macAddress}'),
                Text(
                  'Mascota vinculada: $petName',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.md),
                DispenserFoodProgressBar(
                  currentFoodGrams: dispenser.currentFoodGrams,
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  decoration: BoxDecoration(
                    color: esquema.primary.withValues(alpha: 0.08),
                    borderRadius: AppRadii.cardRadius,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.restaurant_rounded,
                        color: esquema.primary,
                        size: 28,
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Estimación de Suministro',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: esquema.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'La cantidad actual durará aproximadamente para $rationsText.',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: esquema.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showRefillDialog(context);
                    },
                    child: const Text('Reabastecer Depósito'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _loadPetAndSchedules() async {
    try {
      final petDatasource = sl<LocalPetDatasource>();
      final scheduleDatasource = sl<LocalScheduleDatasource>();

      final pets = await petDatasource.getLocalPets();
      final pet = pets
          .where((p) => dispenser.petId != null && p.id == dispenser.petId)
          .firstOrNull;

      final petName = pet?.name ?? 'Sin mascota vinculada';
      final petId = pet?.id;

      List<Schedule> schedules = [];
      if (petId != null) {
        schedules = await scheduleDatasource.getLocalSchedules(petId: petId);
      }
      return {'petName': petName, 'schedules': schedules};
    } catch (_) {
      return {'petName': 'Sin mascota vinculada', 'schedules': <Schedule>[]};
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;
    final gutter = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Card(
          margin: EdgeInsets.symmetric(
            horizontal: gutter,
            vertical: AppSpacing.sm,
          ),
          child: InkWell(
            borderRadius: AppRadii.cardRadius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dispenser.isOfflineCached) ...[
                    const InAppNotificationBanner(
                      title: 'Sincronización Local',
                      message:
                          'Mostrando datos de la última caché local (Offline-First).',
                      type: InAppNotificationType.info,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: esquema.primary.withValues(alpha: 0.12),
                                borderRadius: AppRadii.cardRadius,
                              ),
                              child: Icon(
                                Icons.router_rounded,
                                color: esquema.primary,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dispenser.name,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: esquema.onSurface,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'MAC: ${dispenser.macAddress}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: esquema.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Divider(height: 1),
                  ),
                  DispenserFoodProgressBar(
                    currentFoodGrams: dispenser.currentFoodGrams,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showRefillDialog(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          size: 16,
                        ),
                        label: const Text(
                          'Reabastecer',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _showDetailsModal(context),
                        child: const Text(
                          'Más detalles',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (onResetWifi != null) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Divider(height: 1),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: onResetWifi,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: esquema.error,
                          side: BorderSide(color: esquema.error),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                        icon: const Icon(Icons.wifi_off_rounded, size: 16),
                        label: const Text(
                          'Resetear WiFi',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
