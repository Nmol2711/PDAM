import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

    final double aguaMin = widget.pet.weight * 44;
    final double aguaMax = widget.pet.weight * 66;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Plan Nutricional WSAVA"),
        elevation: 0,
      ),
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
              const SnackBar(
                content: Text("¡Plan nutricional y horarios generados con éxito!"),
                backgroundColor: Colors.green,
              ),
            );
          } else if (state is ScheduleError) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message), backgroundColor: Colors.red),
            );
          }
        },
        builder: (context, state) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PetNutritionalSummaryCard(pet: widget.pet),
                  const SizedBox(height: 24),

                  _buildSectionHeader("1. Información del Alimento"),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _kcalController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Densidad calórica (kcal/kg)",
                      hintText: "Ej. 3850",
                      prefixIcon: Icon(Icons.local_fire_department_outlined, color: Colors.orange),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return "Requerido";
                      if (double.tryParse(v) == null) return "Número válido";
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  _buildSectionHeader("2. Condición Física y Corporal"),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _bcs,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Condición Corporal (BCS 1-9)",
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      prefixIcon: Icon(Icons.monitor_weight_outlined),
                    ),
                    items: List.generate(9, (index) => index + 1)
                        .map((val) => DropdownMenuItem(
                              value: val,
                              child: Text(
                                "$val - ${val == 5 ? 'Ideal' : val < 5 ? 'Delgado' : 'Sobrepeso'}",
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (val) => setState(() => _bcs = val ?? 5),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _mcs,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Masa Muscular (MCS)",
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      prefixIcon: Icon(Icons.accessibility_new_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'normal', child: Text('Normal (Sin pérdida)', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'mild', child: Text('Leve pérdida muscular', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'moderate', child: Text('Moderada pérdida muscular', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'marked', child: Text('Marcada pérdida (Caquexia)', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) => setState(() => _mcs = val ?? 'normal'),
                  ),
                  const SizedBox(height: 20),

                  _buildSectionHeader("3. Actividad y Comidas"),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _activityLevel,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Nivel de Actividad",
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      prefixIcon: Icon(Icons.directions_run),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Bajo / Sedentario', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'medium', child: Text('Moderado / Normal', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'high', child: Text('Alto / Activo', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) => setState(() => _activityLevel = val ?? 'medium'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: _mealsPerDay,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Comidas Diarias",
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      prefixIcon: Icon(Icons.restaurant_outlined),
                    ),
                    items: isGato
                        ? const [
                            DropdownMenuItem(value: 3, child: Text('3 al día', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 4, child: Text('4 al día (Recomendado)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 6, child: Text('6 al día (Óptimo felino)', overflow: TextOverflow.ellipsis)),
                          ]
                        : const [
                            DropdownMenuItem(value: 1, child: Text('1 al día', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 2, child: Text('2 al día (Mañana / Noche)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 3, child: Text('3 al día (Recomendado)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 4, child: Text('4 al día', overflow: TextOverflow.ellipsis)),
                          ],
                    onChanged: (val) => setState(() => _mealsPerDay = val ?? (isGato ? 4 : 2)),
                  ),
                  const SizedBox(height: 32),

                  FilledButton.icon(
                    onPressed: _isLoading ? null : _onGeneratePressed,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.auto_awesome),
                    label: Text(_isLoading ? "Calculando..." : "Generar Plan Automático", style: const TextStyle(fontSize: 16)),
                  ),

                  if (_generatedSchedules != null && _generatedSchedules!.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    GeneratedSchedulesListWidget(
                      schedules: _generatedSchedules!,
                      waterMin: aguaMin,
                      waterMax: aguaMax,
                    ),
                    const SizedBox(height: 24),
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
