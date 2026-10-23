import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/bloc/nutrition_cubit.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/widgets/nutrition_result_card.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/widgets/nutrition_snack_alert.dart';

/// Pantalla de la calculadora nutricional WSAVA (RF-4, RNF-2).
///
/// Es un [StatelessWidget]: no usa `setState` ni contiene lógica de negocio.
/// Toda la interacción con el formulario y el cálculo se delega al
/// [NutritionCubit], que es la única fuente de verdad (Constitución §3).
class NutritionCalculatorView extends StatelessWidget {
  const NutritionCalculatorView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calculadora Nutricional'), elevation: 0),
      body: BlocBuilder<NutritionCubit, NutritionState>(
        builder: (context, state) {
          final form = state.form;
          final cubit = context.read<NutritionCubit>();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('1. Información de la mascota y alimento'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('nutrition_species'),
                  value: form.species,
                  isExpanded: true,
                  decoration: _decoration('Especie', Icons.pets_outlined),
                  items: _speciesItems,
                  onChanged: (v) {
                    if (v != null) cubit.updateSpecies(v);
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('nutrition_body_weight'),
                  initialValue: form.bodyWeight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: cubit.updateBodyWeight,
                  decoration: _decoration(
                    'Peso corporal (kg)',
                    Icons.monitor_weight_outlined,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('nutrition_caloric_density'),
                  initialValue: form.caloricDensity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: cubit.updateCaloricDensity,
                  decoration: _decoration(
                    'Densidad calórica (kcal/kg)',
                    Icons.local_fire_department_outlined,
                  ),
                ),
                const SizedBox(height: 24),
                const _SectionHeader('2. Condición física corporal'),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const ValueKey('nutrition_bcs'),
                  value: form.bcs,
                  isExpanded: true,
                  decoration: _decoration(
                    'Condición corporal (BCS 1-9)',
                    Icons.monitor_weight_outlined,
                  ),
                  items: _bcsItems,
                  onChanged: (v) {
                    if (v != null) cubit.updateBcs(v);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('nutrition_mcs'),
                  value: form.mcs,
                  isExpanded: true,
                  decoration: _decoration(
                    'Masa muscular (MCS)',
                    Icons.accessibility_new_outlined,
                  ),
                  items: _mcsItems,
                  onChanged: (v) {
                    if (v != null) cubit.updateMcs(v);
                  },
                ),
                const SizedBox(height: 24),
                const _SectionHeader('3. Actividad y reproducción'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('nutrition_activity'),
                  value: form.activityLevel,
                  isExpanded: true,
                  decoration: _decoration(
                    'Nivel de actividad',
                    Icons.directions_run,
                  ),
                  items: _activityItems,
                  onChanged: (v) {
                    if (v != null) cubit.updateActivityLevel(v);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('nutrition_reproductive_status'),
                  value: form.reproductiveStatus,
                  isExpanded: true,
                  decoration: _decoration(
                    'Estatus reproductivo',
                    Icons.favorite_outline,
                  ),
                  items: _reproductiveItems,
                  onChanged: (v) {
                    if (v != null) cubit.updateReproductiveStatus(v);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('nutrition_life_stage'),
                  value: form.lifeStage,
                  isExpanded: true,
                  decoration: _decoration('Etapa de vida', Icons.cake_outlined),
                  items: _lifeStageItems,
                  onChanged: (v) {
                    if (v != null) cubit.updateLifeStage(v);
                  },
                ),
                const SizedBox(height: 24),
                const _SectionHeader('4. Comidas y snacks'),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const ValueKey('nutrition_meals_per_day'),
                  value: form.mealsPerDay,
                  isExpanded: true,
                  decoration: _decoration(
                    'Comidas diarias',
                    Icons.restaurant_outlined,
                  ),
                  items: _mealsItems,
                  onChanged: (v) {
                    if (v != null) cubit.updateMealsPerDay(v);
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('nutrition_snacks_kcal'),
                  initialValue: form.snacksKcal,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: cubit.updateSnacksKcal,
                  decoration: _decoration(
                    'Snacks (kcal/día, opcional)',
                    Icons.fastfood_outlined,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: cubit.calculate,
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('Calcular', style: TextStyle(fontSize: 16)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 20),
                  _ErrorBanner(message: state.errorMessage!),
                ],
                if (state.result != null) ...[
                  const SizedBox(height: 24),
                  if (state.result!.exceedsSnackLimit) ...[
                    NutritionSnackAlert(result: state.result!),
                    const SizedBox(height: 12),
                  ],
                  NutritionResultCard(result: state.result!),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

InputDecoration _decoration(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

const List<DropdownMenuItem<String>> _speciesItems = [
  DropdownMenuItem(value: 'canino', child: Text('Perro')),
  DropdownMenuItem(value: 'felino', child: Text('Gato')),
];

const List<DropdownMenuItem<String>> _mcsItems = [
  DropdownMenuItem(value: 'normal', child: Text('Normal (sin pérdida)')),
  DropdownMenuItem(value: 'mild', child: Text('Leve pérdida muscular')),
  DropdownMenuItem(value: 'moderate', child: Text('Moderada pérdida muscular')),
  DropdownMenuItem(value: 'marked', child: Text('Marcada pérdida (caquexia)')),
];

const List<DropdownMenuItem<String>> _activityItems = [
  DropdownMenuItem(value: 'low', child: Text('Bajo / Sedentario')),
  DropdownMenuItem(value: 'medium', child: Text('Moderado / Normal')),
  DropdownMenuItem(value: 'high', child: Text('Alto / Activo')),
];

const List<DropdownMenuItem<String>> _reproductiveItems = [
  DropdownMenuItem(value: 'entero', child: Text('Entero')),
  DropdownMenuItem(value: 'castrado', child: Text('Castrado')),
  DropdownMenuItem(value: 'esterilizado', child: Text('Esterilizado')),
];

const List<DropdownMenuItem<String>> _lifeStageItems = [
  DropdownMenuItem(value: 'crecimiento', child: Text('Crecimiento (< 12 meses)')),
  DropdownMenuItem(value: 'adulto', child: Text('Adulto')),
];

final List<DropdownMenuItem<int>> _bcsItems = List.generate(9, (index) {
  final value = index + 1;
  final label = value == 5
      ? 'Ideal'
      : value < 5
          ? 'Delgado'
          : 'Sobrepeso';
  return DropdownMenuItem(value: value, child: Text('$value - $label'));
});

const List<DropdownMenuItem<int>> _mealsItems = [
  DropdownMenuItem(value: 1, child: Text('1 al día')),
  DropdownMenuItem(value: 2, child: Text('2 al día')),
  DropdownMenuItem(value: 3, child: Text('3 al día')),
  DropdownMenuItem(value: 4, child: Text('4 al día')),
  DropdownMenuItem(value: 5, child: Text('5 al día')),
  DropdownMenuItem(value: 6, child: Text('6 al día')),
];
