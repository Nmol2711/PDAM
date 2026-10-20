import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/dispenser_entity.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/dispenser_food_status.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/widgets/dispenser_food_progress_bar.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/bloc/dispensers_bloc.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/bloc/dispensers_event.dart';
import 'package:app_movil_pdam/core/presentation/widgets/in_app_notification_banner.dart';

class DeviceCardWidget extends StatelessWidget {
  final DispenserEntity dispenser;
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
    String selectedUnit = 'g';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Reabastecer Alimento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dispositivo: ${dispenser.name}'),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  hintText: selectedUnit == 'g' ? 'Ej. 1000' : 'Ej. 1.5',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Unidad: '),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('Gramos (g)'),
                    selected: selectedUnit == 'g',
                    onSelected: (selected) {
                      if (selected) setState(() => selectedUnit = 'g');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Kilogramos (kg)'),
                    selected: selectedUnit == 'kg',
                    onSelected: (selected) {
                      if (selected) setState(() => selectedUnit = 'kg');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Límite máximo: 5 kg (5000 g)',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
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
                  convertAndValidateRefill(val, selectedUnit);
                  Navigator.of(dialogContext).pop();
                  context.read<DispensersBloc>().add(
                        RefillFoodEvent(
                          dispenserId: dispenser.id,
                          amount: val,
                          unit: selectedUnit,
                        ),
                      );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reabastecimiento registrado con éxito')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                  );
                }
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
      builder: (context) => Padding(
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
            const SizedBox(height: 12),
            DispenserFoodProgressBar(currentFoodGrams: dispenser.currentFoodGrams),
            const SizedBox(height: 16),
            const Text(
              'Información de Estimación:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            const Text(
              '• El stock se calcula restando el gramaje consumido por dispensación o sumando el reabastecimiento manual.\n'
              '• Límite máximo del depósito: 5,000 g (5 kg).\n'
              '• Alerta de umbral crítico activada cuando el stock es inferior al 20% (< 1,000 g).',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
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
      ),
    );
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
                                color: (dispenser.isConnected
                                        ? AppColors.success
                                        : AppColors.textSecondary)
                                    .withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.router_rounded,
                                color: dispenser.isConnected
                                    ? AppColors.success
                                    : AppColors.textSecondary,
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
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: (dispenser.isConnected
                                  ? AppColors.success
                                  : AppColors.warning)
                              .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dispenser.isConnected
                                    ? AppColors.success
                                    : AppColors.warning,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              dispenser.isConnected
                                  ? 'Conectado'
                                  : 'Desconectado',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: dispenser.isConnected
                                    ? AppColors.success
                                    : AppColors.warning,
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
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Estado de WiFi:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (dispenser.wifiSsid == null ||
                                dispenser.wifiSsid!.isEmpty ||
                                dispenser.wifiSsid == 'No configurado')
                              const Text(
                                'Aún no se han proporcionado las credenciales de wifi',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.warning,
                                ),
                              )
                            else
                              Text(
                                'Red: ${dispenser.wifiSsid}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white70
                                      : AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      if (onResetWifi != null) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
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
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
