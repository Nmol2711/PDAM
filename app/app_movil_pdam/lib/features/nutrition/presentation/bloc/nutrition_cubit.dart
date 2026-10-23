import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_params.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_result.dart';
import 'package:app_movil_pdam/features/nutrition/domain/usecases/calculate_nutrition_usecase.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'nutrition_state.dart';

/// Cubit de la calculadora nutricional WSAVA (RF-4, RNF-2).
///
/// Mantiene el formulario como única fuente de verdad y delega el cálculo en el
/// caso de uso puro [CalculateNutritionUsecase], de modo que la vista queda
/// libre de lógica de negocio (Constitución §3) y no necesita `setState`.
/// Al ser un cálculo síncrono y determinista (RNF-1), no se requiere estado de
/// carga asíncrono.
class NutritionCubit extends Cubit<NutritionState> {
  final CalculateNutritionUsecase _calculateNutritionUsecase;

  NutritionCubit({
    required CalculateNutritionUsecase calculateNutritionUsecase,
  })  : _calculateNutritionUsecase = calculateNutritionUsecase,
        super(const NutritionState.initial());

  void updateSpecies(String value) =>
      _updateForm((f) => f.copyWith(species: value));

  void updateBodyWeight(String value) =>
      _updateForm((f) => f.copyWith(bodyWeight: value));

  void updateCaloricDensity(String value) =>
      _updateForm((f) => f.copyWith(caloricDensity: value));

  void updateBcs(int value) => _updateForm((f) => f.copyWith(bcs: value));

  void updateMcs(String value) => _updateForm((f) => f.copyWith(mcs: value));

  void updateActivityLevel(String value) =>
      _updateForm((f) => f.copyWith(activityLevel: value));

  void updateReproductiveStatus(String value) =>
      _updateForm((f) => f.copyWith(reproductiveStatus: value));

  void updateLifeStage(String value) =>
      _updateForm((f) => f.copyWith(lifeStage: value));

  void updateMealsPerDay(int value) =>
      _updateForm((f) => f.copyWith(mealsPerDay: value));

  void updateSnacksKcal(String value) =>
      _updateForm((f) => f.copyWith(snacksKcal: value));

  /// Calcula la dosificación a partir del formulario actual.
  ///
  /// Convierte los campos de texto a números y, ante entradas no numéricas,
  /// emite un error descriptivo; en caso contrario delega en el caso de uso,
  /// que valida los rangos y normaliza los valores de texto (RF-1, RF-2).
  void calculate() {
    final form = state.form;

    final double? bodyWeight = double.tryParse(form.bodyWeight.trim());
    if (bodyWeight == null) {
      _emitError('Ingresa un peso corporal válido (número mayor a 0 en kg).');
      return;
    }

    final double? caloricDensity = double.tryParse(form.caloricDensity.trim());
    if (caloricDensity == null) {
      _emitError(
        'Ingresa una densidad calórica válida (número mayor a 0 en kcal/kg).',
      );
      return;
    }

    final snacksText = form.snacksKcal.trim();
    double snacksKcal = 0.0;
    if (snacksText.isNotEmpty) {
      final double? parsed = double.tryParse(snacksText);
      if (parsed == null) {
        _emitError(
          'Ingresa un valor numérico válido para las calorías de snacks.',
        );
        return;
      }
      snacksKcal = parsed;
    }

    final params = NutritionParams(
      species: form.species,
      bodyWeight: bodyWeight,
      caloricDensityKcalPerKg: caloricDensity,
      bcs: form.bcs,
      mcs: form.mcs,
      activityLevel: form.activityLevel,
      reproductiveStatus: form.reproductiveStatus,
      lifeStage: form.lifeStage,
      mealsPerDay: form.mealsPerDay,
      snacksKcal: snacksKcal,
    );

    final result = _calculateNutritionUsecase(params);
    result.fold(
      (failure) => _emitError(failure.message),
      (nutrition) => _emitResult(nutrition),
    );
  }

  void _updateForm(NutritionFormData Function(NutritionFormData) transform) {
    emit(NutritionState(form: transform(state.form)));
  }

  void _emitError(String message) {
    emit(NutritionState(form: state.form, errorMessage: message));
  }

  void _emitResult(NutritionResult result) {
    emit(NutritionState(form: state.form, result: result));
  }
}
