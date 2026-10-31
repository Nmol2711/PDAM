import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/core/presentation/widgets/app_cta_button.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/widget/pet_nutritional_summary_card.dart';
import 'package:app_movil_pdam/features/pets/presentation/widget/generated_schedules_list_widget.dart';

class GuidedScheduleFormView extends StatefulWidget {
  final Pet pet;

  const GuidedScheduleFormView({super.key, required this.pet});

  @override
  State<GuidedScheduleFormView> createState() => _GuidedScheduleFormViewState();
}

class _GuidedScheduleFormViewState extends State<GuidedScheduleFormView> {
  final _formKey = GlobalKey<FormState>();
  final _kcalController = TextEditingController();

  int _bcs = 5;
  String _mcs = 'normal';
  String _activityLevel = 'medium';
  int _mealsPerDay = 2;

  List<Schedule>? _generatedSchedules;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final String especie = widget.pet.species.name.toLowerCase();
    if (especie == 'felino' || especie == 'gato') {
      _mealsPerDay = 4;
    } else {
      _mealsPerDay = 2;
    }
  }

  @override
  void dispose() {
    _kcalController.dispose();
    super.dispose();
  }

  void _onGeneratePressed() {
    if (!_formKey.currentState!.validate()) return;

    final double kcal = double.parse(_kcalController.text);
    context.read<ScheduleBloc>().add(
      AutoGenerateSchedulesRequested(
        petId: widget.pet.id,
        foodKcalPerKg: kcal,
        bcs: _bcs,
        mcs: _mcs,
        activityLevel: _activityLevel,
        mealsPerDay: _mealsPerDay,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String especieClean = widget.pet.species.name.toLowerCase();
    final bool isGato = especieClean == 'felino' || especieClean == 'gato';
    final esquema = Theme.of(context).colorScheme;
    final semantica = AppSemanticColors.of(context);
    final ancho = MediaQuery.sizeOf(context).width;

    final double aguaMin = widget.pet.weight * 44;
    final double aguaMax = widget.pet.weight * 66;

    return Scaffold(
      appBar: AppBar(title: const Text("Plan Nutricional WSAVA")),
      body: BlocConsumer<ScheduleBloc, ScheduleState>(
        listener: (context, state) {
          if (state is ScheduleLoading) {
            setState(() => _isLoading = true);
          } else if (state is ScheduleLoaded) {
            setState(() {
              _isLoading = false;
              _generatedSchedules = state.schedules;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: semantica.success,
                content: Text(
                  "¡Plan nutricional y horarios generados con éxito!",
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: semantica.onSuccess),
                ),
              ),
            );
          } else if (state is ScheduleError) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: esquema.error,
                content: Text(
                  state.message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: esquema.onError),
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.pageFor(ancho),
              vertical: AppSpacing.page,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PetNutritionalSummaryCard(pet: widget.pet),
                  const SizedBox(height: AppSpacing.sectionGap),

                  _buildSectionHeader("1. Información del Alimento"),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _kcalController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: "Densidad calórica (kcal/kg)",
                      hintText: "Ej. 3850",
                      prefixIcon: Icon(
                        Icons.local_fire_department_outlined,
                        color: esquema.tertiary,
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return "Requerido";
                      if (double.tryParse(v) == null) return "Número válido";
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  _buildSectionHeader("2. Condición Física y Corporal"),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<int>(
                    value: _bcs,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Condición Corporal (BCS 1-9)",
                      prefixIcon: Icon(Icons.monitor_weight_outlined),
                    ),
                    items: List.generate(9, (index) => index + 1)
                        .map(
                          (val) => DropdownMenuItem(
                            value: val,
                            child: Text(
                              "$val - ${val == 5
                                  ? 'Ideal'
                                  : val < 5
                                  ? 'Delgado'
                                  : 'Sobrepeso'}",
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => _bcs = val ?? 5),
                  ),
                  const SizedBox(height: AppSpacing.fieldGap),
                  DropdownButtonFormField<String>(
                    value: _mcs,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Masa Muscular (MCS)",
                      prefixIcon: Icon(Icons.accessibility_new_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'normal',
                        child: Text(
                          'Normal (Sin pérdida)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'mild',
                        child: Text(
                          'Leve pérdida muscular',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'moderate',
                        child: Text(
                          'Moderada pérdida muscular',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'marked',
                        child: Text(
                          'Marcada pérdida (Caquexia)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _mcs = val ?? 'normal'),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  _buildSectionHeader("3. Actividad y Comidas"),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    value: _activityLevel,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Nivel de Actividad",
                      prefixIcon: Icon(Icons.directions_run),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'low',
                        child: Text(
                          'Bajo / Sedentario',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'medium',
                        child: Text(
                          'Moderado / Normal',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'high',
                        child: Text(
                          'Alto / Activo',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (val) =>
                        setState(() => _activityLevel = val ?? 'medium'),
                  ),
                  const SizedBox(height: AppSpacing.fieldGap),
                  DropdownButtonFormField<int>(
                    value: _mealsPerDay,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Comidas Diarias",
                      prefixIcon: Icon(Icons.restaurant_outlined),
                    ),
                    items: isGato
                        ? const [
                            DropdownMenuItem(
                              value: 3,
                              child: Text(
                                '3 al día',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 4,
                              child: Text(
                                '4 al día (Recomendado)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 6,
                              child: Text(
                                '6 al día (Óptimo felino)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ]
                        : const [
                            DropdownMenuItem(
                              value: 1,
                              child: Text(
                                '1 al día',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text(
                                '2 al día (Mañana / Noche)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 3,
                              child: Text(
                                '3 al día (Recomendado)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 4,
                              child: Text(
                                '4 al día',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                    onChanged: (val) =>
                        setState(() => _mealsPerDay = val ?? (isGato ? 4 : 2)),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),

                  AppCtaButton(
                    onPressed: _isLoading ? null : _onGeneratePressed,
                    icon: _isLoading ? null : Icons.auto_awesome,
                    child: _isLoading
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: esquema.onSurfaceVariant,
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              const Text(
                                "Calculando...",
                                style: TextStyle(fontSize: 16),
                              ),
                            ],
                          )
                        : const Text(
                            "Generar Plan Automático",
                            style: TextStyle(fontSize: 16),
                          ),
                  ),

                  if (_generatedSchedules != null &&
                      _generatedSchedules!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxxl),
                    GeneratedSchedulesListWidget(
                      schedules: _generatedSchedules!,
                      waterMin: aguaMin,
                      waterMax: aguaMax,
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Volver al Detalle"),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
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
