/// Validadores puros del motor nutricional WSAVA (Spec 011).
///
/// Replica exactamente la lógica de validación del backend
/// (`api/app/schemas/nutrition_schemas.py`) para garantizar que la aplicación
/// móvil acepta y normaliza los mismos valores que el servidor (RF-4).
///
/// Los valores de texto se normalizan a una forma canónica (minúsculas, sin
/// espacios) idéntica a la del backend, lo que asegura el determinismo (RNF-1).
library;

/// Excepción de dominio lanzada ante entradas inválidas, con un mensaje
/// descriptivo en español (RF-1, RF-2 y Constitución §6).
class NutritionValidationException implements Exception {
  final String message;

  const NutritionValidationException(this.message);

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Whitelists y valores canónicos (idénticos al backend)
// ---------------------------------------------------------------------------

const Map<String, String> speciesCanonical = {
  'canino': 'canino',
  'perro': 'canino',
  'dog': 'canino',
  'felino': 'felino',
  'gato': 'felino',
  'cat': 'felino',
};

const Map<String, String> mcsCanonical = {
  'normal': 'normal',
  'leve': 'mild',
  'mild': 'mild',
  'moderada': 'moderate',
  'moderate': 'moderate',
  'marcada': 'marked',
  'marked': 'marked',
};

const Map<String, String> activityCanonical = {
  'bajo': 'low',
  'low': 'low',
  'medio': 'medium',
  'medium': 'medium',
  'alto': 'high',
  'high': 'high',
};

const Set<String> reproductiveStatusValues = {'entero', 'castrado', 'esterilizado'};

const Set<String> lifeStageValues = {'crecimiento', 'adulto'};

// ---------------------------------------------------------------------------
// Funciones puras de validación de límites (Boundary Validation)
// ---------------------------------------------------------------------------

/// `True` si el peso corporal es estrictamente mayor a 0.
bool validateBodyWeight(double bw) => bw > 0;

/// `True` si la densidad calórica es estrictamente mayor a 0.
bool validateCaloricDensity(double density) => density > 0;

/// `True` si `1 <= meals_per_day <= 6`.
bool validateMealsPerDay(int meals) => meals >= 1 && meals <= 6;

/// `True` si `1 <= bcs <= 9`.
bool validateBcs(int bcs) => bcs >= 1 && bcs <= 9;

/// `True` si el valor (sin distinguir mayúsculas) es un MCS permitido.
bool validateMcs(String mcs) => mcsCanonical.containsKey(mcs.trim().toLowerCase());

/// `True` si el nivel de actividad es uno de los permitidos.
bool validateActivityLevel(String activity) =>
    activityCanonical.containsKey(activity.trim().toLowerCase());

/// `True` si el estatus reproductivo es uno de los permitidos.
bool validateReproductiveStatus(String status) =>
    reproductiveStatusValues.contains(status.trim().toLowerCase());

/// `True` si la etapa de vida es una de las permitidas.
bool validateLifeStage(String stage) =>
    lifeStageValues.contains(stage.trim().toLowerCase());

/// `True` si las calorías de snacks no son negativas.
bool validateSnacksKcal(double snacksKcal) => snacksKcal >= 0;

// ---------------------------------------------------------------------------
// Normalización de texto a forma canónica
// ---------------------------------------------------------------------------

String _normalizeText(
  String value,
  Map<String, String> mapping,
  String errorMessage,
) {
  final key = value.trim().toLowerCase();
  final canonical = mapping[key];
  if (canonical == null) {
    throw NutritionValidationException(errorMessage);
  }
  return canonical;
}

/// Normaliza la especie a su forma canónica (`canino`/`felino`).
String normalizeSpecies(String value) => _normalizeText(
      value,
      speciesCanonical,
      'Especie inválida. Valores permitidos: canino/perro o felino/gato.',
    );

/// Normaliza el MCS a su forma canónica (`normal`/`mild`/`moderate`/`marked`).
String normalizeMcs(String value) => _normalizeText(
      value,
      mcsCanonical,
      'MCS inválido. Valores permitidos: normal, leve, moderada, marcada.',
    );

/// Normaliza el nivel de actividad a su forma canónica (`low`/`medium`/`high`).
String normalizeActivityLevel(String value) => _normalizeText(
      value,
      activityCanonical,
      'Nivel de actividad inválido. Valores permitidos: bajo, medio, alto.',
    );

/// Normaliza el estatus reproductivo a minúsculas, sin sinónimos.
String normalizeReproductiveStatus(String value) {
  final key = value.trim().toLowerCase();
  if (!reproductiveStatusValues.contains(key)) {
    throw const NutritionValidationException(
      'Estatus reproductivo inválido. Valores permitidos: entero, castrado, '
      'esterilizado.',
    );
  }
  return key;
}

/// Normaliza la etapa de vida a minúsculas, sin sinónimos.
String normalizeLifeStage(String value) {
  final key = value.trim().toLowerCase();
  if (!lifeStageValues.contains(key)) {
    throw const NutritionValidationException(
      'Etapa de vida inválida. Valores permitidos: crecimiento, adulto.',
    );
  }
  return key;
}
