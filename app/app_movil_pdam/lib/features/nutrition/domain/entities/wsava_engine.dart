/// Motor de cálculo nutricional WSAVA (funciones puras).
///
/// Replica exactamente la lógica matemática de
/// `api/app/services/nutrition_service.py` (RF-3) para garantizar la
/// sincronización exacta de resultados con el servidor (RF-4, RNF-1).
///
/// Todas las funciones son puras y deterministas: ante idénticas entradas
/// producen siempre el mismo resultado y no dependen de estado externo. La
/// validación estricta de entradas (RF-1/RF-2) se aplica en
/// `nutrition_validators.dart`; aquí se asume que los valores de texto llegan
/// en su forma canónica y se revalidan defensivamente lanzando
/// `NutritionValidationException` ante valores desconocidos.
///
/// Fórmulas (WSAVA / documento técnico):
///
///     RER = 70 * BW^0.75
///     MER = RER * Factor_Corrector
///     Snack_Limit = MER * 0.10
///     Final_Ration_Kcal = max(0.0, MER - Snacks_Kcal)
///     Ración_Base (g/día) = Final_Ration_Kcal / (Densidad_Calórica (kcal/g))
library;

import 'dart:math' as math;

import 'nutrition_result.dart';
import 'nutrition_validators.dart';

// ---------------------------------------------------------------------------
// Tablas de factores correctores WSAVA (idénticas al backend)
// ---------------------------------------------------------------------------

/// Factor base del MER por (especie, etapa de vida, estatus reproductivo).
const Map<String, Map<String, Map<String, double>>> baseMerFactors = {
  'canino': {
    'adulto': {'entero': 1.8, 'castrado': 1.6, 'esterilizado': 1.6},
    'crecimiento': {'entero': 2.0, 'castrado': 2.0, 'esterilizado': 2.0},
  },
  'felino': {
    'adulto': {'entero': 1.4, 'castrado': 1.2, 'esterilizado': 1.2},
    'crecimiento': {'entero': 2.5, 'castrado': 2.5, 'esterilizado': 2.5},
  },
};

/// Ajuste multiplicativo por nivel de actividad.
const Map<String, double> activityFactors = {
  'low': 0.9,
  'medium': 1.0,
  'high': 1.2,
};

/// Ajuste multiplicativo por masa muscular (MCS).
const Map<String, double> mcsFactors = {
  'normal': 1.0,
  'mild': 1.0,
  'moderate': 0.95,
  'marked': 0.9,
};

/// Ajuste multiplicativo por condición corporal (BCS) extremo.
const double bcsLowFactor = 1.2; // bcs <= 3 (bajo peso -> mayor requerimiento)
const double bcsHighFactor = 0.8; // bcs >= 7 (sobrepeso -> menor requerimiento)

/// Límite máximo de snacks como fracción del MER.
const double snackLimitFraction = 0.10;

/// Variabilidad fisiológica esperada por especie.
const Map<String, (double, double)> variabilityFactors = {
  'canino': (0.7, 1.3), // ±30%
  'felino': (0.5, 1.5), // ±50%
};

// ---------------------------------------------------------------------------
// Funciones puras del motor WSAVA
// ---------------------------------------------------------------------------

/// Calcula el Requerimiento de Energía en Reposo (RER) en kcal/día.
///
/// Fórmula alométrica estándar: ``RER = 70 * BW^0.75``.
double calculateRer(double bodyWeight) {
  if (bodyWeight <= 0) {
    throw const NutritionValidationException(
      'El peso corporal debe ser mayor a 0 (kg).',
    );
  }
  return 70.0 * math.pow(bodyWeight, 0.75).toDouble();
}

double _bcsFactor(int bcs) {
  if (bcs <= 3) return bcsLowFactor;
  if (bcs >= 7) return bcsHighFactor;
  return 1.0;
}

String _normalize(String value) => value.trim().toLowerCase();

/// Calcula el Requerimiento de Energía de Mantenimiento (MER) en kcal/día.
///
/// Aplica de forma multiplicativa el factor base (especie x estatus
/// reproductivo x etapa de vida) y los ajustes por actividad, condición
/// corporal y masa muscular. Lanza `NutritionValidationException` ante valores
/// fuera de los whitelists.
double calculateMer(
  double rer,
  String species,
  String reproductiveStatus,
  String lifeStage,
  String activityLevel,
  int bcs,
  String mcs,
) {
  final speciesKey = _normalize(species);
  final reproductiveKey = _normalize(reproductiveStatus);
  final lifeStageKey = _normalize(lifeStage);
  final activityKey = _normalize(activityLevel);
  final mcsKey = _normalize(mcs);

  final baseFactor = baseMerFactors[speciesKey]?[lifeStageKey]?[reproductiveKey];
  if (baseFactor == null) {
    throw const NutritionValidationException(
      'Combinación inválida de especie, estatus reproductivo o etapa de vida.',
    );
  }

  final activityFactor = activityFactors[activityKey];
  if (activityFactor == null) {
    throw const NutritionValidationException('Nivel de actividad inválido.');
  }

  final mcsFactor = mcsFactors[mcsKey];
  if (mcsFactor == null) {
    throw const NutritionValidationException('MCS inválido.');
  }

  final totalFactor = baseFactor * activityFactor * _bcsFactor(bcs) * mcsFactor;
  return rer * totalFactor;
}

/// Devuelve el rango de variabilidad fisiológica esperada ``(mín, máx)``.
///
/// Perros: ±30% (``mer * 0.7``, ``mer * 1.3``); gatos: ±50% (``mer * 0.5``,
/// ``mer * 1.5``).
(double, double) getVariabilityRange(String species, double mer) {
  final speciesKey = _normalize(species);
  final factors = variabilityFactors[speciesKey];
  if (factors == null) {
    throw const NutritionValidationException(
      'Especie inválida. Valores permitidos: canino, felino.',
    );
  }
  return (mer * factors.$1, mer * factors.$2);
}

/// Resultado de la evaluación del aporte calórico de snacks.
class SnackEvaluation {
  final double snackLimitKcal;
  final double snacksKcal;
  final bool exceedsLimit;
  final double finalRationKcal;

  const SnackEvaluation({
    required this.snackLimitKcal,
    required this.snacksKcal,
    required this.exceedsLimit,
    required this.finalRationKcal,
  });
}

/// Evalúa el aporte calórico de snacks frente al límite del 10% del MER.
SnackEvaluation evaluateSnacks(double mer, double snacksKcal) {
  final snackLimit = mer * snackLimitFraction;
  final exceedsLimit = snacksKcal > snackLimit;
  final finalRationKcal = math.max(0.0, mer - snacksKcal);
  return SnackEvaluation(
    snackLimitKcal: snackLimit,
    snacksKcal: snacksKcal,
    exceedsLimit: exceedsLimit,
    finalRationKcal: finalRationKcal,
  );
}

/// Convierte la ración final en kcal a gramos de alimento por día.
///
/// Usa la densidad calórica en kcal/kg y aplica división segura: si la densidad
/// es menor o igual a 0, devuelve ``0.0`` para evitar divisiones inválidas.
double calculateDailyRationGrams(
  double finalRationKcal,
  double caloricDensityKcalPerKg,
) {
  if (caloricDensityKcalPerKg <= 0) return 0.0;
  final densityKcalPerGram = caloricDensityKcalPerKg / 1000.0;
  return finalRationKcal / densityKcalPerGram;
}

/// Orquesta el flujo completo de dosificación WSAVA (RF-3, RF-4).
///
/// Recibe los parámetros ya validados y normalizados a su forma canónica y
/// devuelve el resultado sincronizado completo. Es pura y determinista (RNF-1).
NutritionResult calculateNutrition({
  required String species,
  required double bodyWeight,
  required double caloricDensityKcalPerKg,
  required int bcs,
  required String mcs,
  required String activityLevel,
  required String reproductiveStatus,
  required String lifeStage,
  required int mealsPerDay,
  double snacksKcal = 0.0,
}) {
  final rer = calculateRer(bodyWeight);
  final mer = calculateMer(
    rer,
    species,
    reproductiveStatus,
    lifeStage,
    activityLevel,
    bcs,
    mcs,
  );
  final variability = getVariabilityRange(species, mer);
  final snacks = evaluateSnacks(mer, snacksKcal);
  final dailyRationGrams =
      calculateDailyRationGrams(snacks.finalRationKcal, caloricDensityKcalPerKg);

  return NutritionResult(
    species: species,
    bodyWeight: bodyWeight,
    mealsPerDay: mealsPerDay,
    rerKcal: rer,
    merKcal: mer,
    variabilityMinKcal: variability.$1,
    variabilityMaxKcal: variability.$2,
    snackLimitKcal: snacks.snackLimitKcal,
    snacksKcal: snacks.snacksKcal,
    exceedsSnackLimit: snacks.exceedsLimit,
    finalRationKcal: snacks.finalRationKcal,
    dailyRationGrams: dailyRationGrams,
    rationPerMealGrams: dailyRationGrams / mealsPerDay,
  );
}
