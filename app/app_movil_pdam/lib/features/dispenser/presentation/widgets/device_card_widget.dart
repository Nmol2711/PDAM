import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/core/theme/app_colors.dart';
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
        builder: (context, setState) => AlertDialog(
          title: const Text('Reabastecer Alimento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dispositivo: ${dispenser.name}'),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Cantidad a agregar',
                    hintText: selectedUnit == 'g' ? 'Ej. 1000' : 'Ej. 1.5',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
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
                const SizedBox(height: 12),
                const Text(
                  'Capacidad del depósito: 5 kg (5000 g). '
                  'La cantidad se suma al stock y no puede superar el máximo.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                if (limitMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    limitMessage!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                    ),
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
                final val = double.tryParse(amountController.text.trim()) ?? 0.0;
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
        ),
      ),
    );
  }

  void _showDetailsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => FutureBuilder<Map<String, dynamic>>(
        future: _loadPetAndSchedules(),
        builder: (context, snapshot) {
          final petName = snapshot.data?['petName'] as String? ?? 'Sin mascota vinculada';
          final schedules = snapshot.data?['schedules'] as List<Schedule>? ?? [];
          final remainingRations = calculateRemainingRations(dispenser.currentFoodGrams, schedules);
          final rationsText = schedules.isEmpty && dispenser.currentFoodGrams > 0
              ? '${(dispenser.currentFoodGrams / 50).floor()} raciones (estimadas)'
              : '$remainingRations raciones';

          return Padding(
            padding: const EdgeInsets.all(24.0),
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
                const SizedBox(height: 8),
                Text('Dispositivo: ${dispenser.name}'),
                Text('MAC: ${dispenser.macAddress}'),
                Text('Mascota vinculada: $petName', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                DispenserFoodProgressBar(currentFoodGrams: dispenser.currentFoodGrams),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.restaurant_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Estimación de Suministro',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'La cantidad actual durará aproximadamente para $rationsText.',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
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
      final pet = pets.where((p) => dispenser.petId != null && p.id == dispenser.petId).firstOrNull;
      
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
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(isWide ? 20.0 : 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dispenser.isOfflineCached) ...[
                    const InAppNotificationBanner(
                      title: 'Sincronización Local',
                      message: 'Mostrando datos de la última caché local (Offline-First).',
                      type: InAppNotificationType.info,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.router_rounded,
                                color: AppColors.primaryGreen,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dispenser.name,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? Colors.white
                                              : AppColors.textPrimary,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'MAC: ${dispenser.macAddress}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
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
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  DispenserFoodProgressBar(currentFoodGrams: dispenser.currentFoodGrams),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showRefillDialog(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryGreen,
                          side: const BorderSide(color: AppColors.primaryGreen),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                        label: const Text(
                          'Reabastecer',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _showDetailsModal(context),
                        child: const Text(
                          'Más detalles',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (onResetWifi != null) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: onResetWifi,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.warning,
                          side: const BorderSide(color: AppColors.warning),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
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
