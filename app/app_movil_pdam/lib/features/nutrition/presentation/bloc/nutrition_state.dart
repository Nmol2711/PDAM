part of 'nutrition_cubit.dart';

/// Datos del formulario de la calculadora nutricional WSAVA.
///
/// Los campos de texto libre se almacenan como [String] para conservar la
/// entrada del usuario mientras escribe; el cubit los convierte a números al
/// calcular. Los desplegables guardan ya su valor canónico (idéntico al
/// backend) para garantizar la sincronización de resultados (RF-4).
class NutritionFormData {
  final String species;
  final String bodyWeight;
  final String caloricDensity;
  final int bcs;
  final String mcs;
  final String activityLevel;
  final String reproductiveStatus;
  final String lifeStage;
  final int mealsPerDay;
  final String snacksKcal;

  const NutritionFormData({
    this.species = 'canino',
    this.bodyWeight = '',
    this.caloricDensity = '',
    this.bcs = 5,
    this.mcs = 'normal',
    this.activityLevel = 'medium',
    this.reproductiveStatus = 'castrado',
    this.lifeStage = 'adulto',
    this.mealsPerDay = 2,
    this.snacksKcal = '',
  });

  NutritionFormData copyWith({
    String? species,
    String? bodyWeight,
    String? caloricDensity,
    int? bcs,
    String? mcs,
    String? activityLevel,
    String? reproductiveStatus,
    String? lifeStage,
    int? mealsPerDay,
    String? snacksKcal,
  }) {
    return NutritionFormData(
      species: species ?? this.species,
      bodyWeight: bodyWeight ?? this.bodyWeight,
      caloricDensity: caloricDensity ?? this.caloricDensity,
      bcs: bcs ?? this.bcs,
      mcs: mcs ?? this.mcs,
      activityLevel: activityLevel ?? this.activityLevel,
      reproductiveStatus: reproductiveStatus ?? this.reproductiveStatus,
      lifeStage: lifeStage ?? this.lifeStage,
      mealsPerDay: mealsPerDay ?? this.mealsPerDay,
      snacksKcal: snacksKcal ?? this.snacksKcal,
    );
  }
}

/// Estado de la calculadora nutricional.
///
/// Mantiene los datos del formulario y, de forma opcional, el resultado del
/// cálculo o un mensaje de error descriptivo en español. El formulario es la
/// única fuente de verdad de la pantalla, por lo que la vista no necesita
/// `setState` (RNF-2, Constitución §3).
class NutritionState extends Equatable {
  final NutritionFormData form;
  final NutritionResult? result;
  final String? errorMessage;

  const NutritionState({
    required this.form,
    this.result,
    this.errorMessage,
  });

  const NutritionState.initial() : this(form: const NutritionFormData());

  @override
  List<Object?> get props => [form, result, errorMessage];
}
