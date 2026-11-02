import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/utils/quick_dispense_limits.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/quick_dispense_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Hoja de dispensación rápida: solo pide la cantidad.
///
/// La validación local vive en `quick_dispense_limits.dart`; el servidor sigue
/// siendo la autoridad. Al aceptar, la hoja se cierra con `true` y la ficha
/// muestra el aviso de orden enviada.
class QuickDispenseSheet extends StatefulWidget {
  final Dispenser dispenser;

  const QuickDispenseSheet({super.key, required this.dispenser});

  @override
  State<QuickDispenseSheet> createState() => _QuickDispenseSheetState();
}

class _QuickDispenseSheetState extends State<QuickDispenseSheet> {
  final TextEditingController _cantidad = TextEditingController();
  String? _errorLocal;

  @override
  void dispose() {
    _cantidad.dispose();
    super.dispose();
  }

  String _mensajeDe(QuickDispenseValidationError error) {
    switch (error) {
      case QuickDispenseValidationError.empty:
        return 'Ingresa una cantidad en gramos.';
      case QuickDispenseValidationError.notNumeric:
        return 'La cantidad debe ser un número.';
      case QuickDispenseValidationError.notPositive:
        return 'La cantidad debe ser mayor que 0.';
      case QuickDispenseValidationError.exceedsLimit:
        return 'La cantidad rápida debe ser mayor que 0 y no superar 200 g.';
      case QuickDispenseValidationError.exceedsStock:
        return 'La cantidad solicitada supera el stock disponible del dispensador.';
    }
  }

  void _enviar() {
    final validacion = validateQuickDispense(
      _cantidad.text,
      widget.dispenser.currentFoodGrams,
    );
    if (!validacion.isValid) {
      setState(() => _errorLocal = _mensajeDe(validacion.error!));
      return;
    }

    setState(() => _errorLocal = null);
    context.read<QuickDispenseCubit>().solicitar(
      widget.dispenser.id,
      validacion.grams!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final stock = widget.dispenser.currentFoodGrams;

    return BlocConsumer<QuickDispenseCubit, QuickDispenseState>(
      listener: (context, state) {
        if (state is QuickDispenseAccepted) {
          Navigator.of(context).pop(true);
        }
      },
      builder: (context, state) {
        final enviando = state is QuickDispenseSending;
        final errorServidor = state is QuickDispenseError
            ? state.message
            : null;

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dispensar ahora',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Indica la cantidad de alimento que quieres suministrar.',
                  style: TextStyle(color: esquema.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  key: const Key('quick-dispense-amount'),
                  controller: _cantidad,
                  enabled: !enviando,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _enviar(),
                  decoration: InputDecoration(
                    labelText: 'Cantidad',
                    suffixText: 'g',
                    helperText:
                        'Máximo 200 g · Stock disponible: ${stock.toStringAsFixed(0)} g',
                    errorText: _errorLocal ?? errorServidor,
                    border: OutlineInputBorder(
                      borderRadius: AppRadii.controlRadius,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: enviando
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton(
                        onPressed: enviando ? null : _enviar,
                        child: enviando
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: esquema.onPrimary,
                                ),
                              )
                            : const Text('Dispensar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
