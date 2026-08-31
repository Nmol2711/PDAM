import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart';

class GuidedScheduleFormView extends StatefulWidget {
  final Pet pet;

  const GuidedScheduleFormView({super.key, required this.pet});

  @override
  State<GuidedScheduleFormView> createState() => _GuidedScheduleFormViewState();
}

class _GuidedScheduleFormViewState extends State<GuidedScheduleFormView> {
  final _formKey = GlobalKey<FormState>();
  final _kcalController = TextEditingController();

  // Variables de control de estado interno
  int _selectedRaciones = 3; // Por defecto para perros (puede ser 2 o 3)
  List<String> _generatedSchedules = [];
  double _gramosTotalesDiarios = 0.0;
  double _gramosPorRacion = 0.0;
  bool _calculado = false;

  @override
  void initState() {
    super.initState();
    // Si es gato, se fija automáticamente a 6 raciones según su cronobiología
    if (widget.pet.species.name.toLowerCase() == 'felino' ||
        widget.pet.species.name.toLowerCase() == 'gato') {
      _selectedRaciones = 6;
    }
  }

  @override
  void dispose() {
    _kcalController.dispose();
    super.dispose();
  }

  /// 🧮 Motor de cálculo metabólico (Cronobiología y Necesidades Energéticas)
  void _ejecutarCalculos() {
    if (!_formKey.currentState!.validate()) return;

    final double peso = widget.pet.weight;
    final double kcalAlimento = double.parse(_kcalController.text);
    final String especie = widget.pet.species.name.toLowerCase();

    // 1. Calcular RER (Requerimiento de Energía en Reposo)
    // Fórmula: 70 x (peso)^0.75
    final num rer = 70 * pow(peso, 0.75);

    // 2. Calcular REM (Requerimiento Energético de Mantenimiento)
    double rem = 0.0;
    if (especie == 'canino' || especie == 'perro') {
      // Simplificado a adulto entero (Factor 1.8), adaptado de tus indicaciones
      if (widget.pet.age < 1) {
        rem = 2.5 * rer; // Estimación intermedia para cachorros
      } else {
        rem = 1.8 * rer;
      }
    } else {
      // Felinos
      if (widget.pet.age < 1) {
        rem = 2.5 * rer; // Gatitos
      } else {
        rem = 1.4 * rer; // Gatos adultos
      }
    }

    // 3. Calcular gramos diarios totales: (REM / kcal del alimento) * 1000g
    _gramosTotalesDiarios = (rem / kcalAlimento) * 1000;

    // 4. Generar la distribución de horarios automática de 07:00 a 19:00 (12 horas de rango)
    _generarHorariosAutomaticos(especie);

    // 5. Calcular porción individual
    _gramosPorRacion = _gramosTotalesDiarios / _selectedRaciones;

    setState(() {
      _calculado = true;
    });
  }

  /// 🕒 Distribución de horas en el rango establecido (07:00 a 19:00)
  void _generarHorariosAutomaticos(String especie) {
    _generatedSchedules.clear();

    if (especie == 'felino' || especie == 'gato') {
      // 6 raciones automáticas fijas distribuidas equitativamente cada 2.4 horas aprox o fijas uniformes:
      _generatedSchedules = [
        '07:00',
        '09:20',
        '11:40',
        '14:00',
        '16:20',
        '18:40',
      ];
    } else {
      // Perros: Depende de si eligió 2 o 3 raciones
      if (_selectedRaciones == 2) {
        _generatedSchedules = ['07:00', '19:00'];
      } else {
        _generatedSchedules = ['07:00', '13:00', '19:00'];
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String especieClean = widget.pet.species.name.toLowerCase();
    final bool isGato = especieClean == 'felino' || especieClean == 'gato';

    // Cálculos de hidratación basados en el peso de la pet
    final double aguaMin = widget.pet.weight * 44;
    final double aguaMax = widget.pet.weight * 66;

    return Scaffold(
      appBar: AppBar(title: const Text("Plan de Alimentación Guiado")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- BANNER DE MASCOTA ---
                Card(
                  elevation: 0,
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Asistente Cronobiológico para ${widget.pet.name} (${widget.pet.weight} kg • ${widget.pet.age} años)",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // --- PASO 1: CALORÍAS DEL ALIMENTO ---
                Text(
                  "1. Densidad Energética del Alimento",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _kcalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Contenido calórico (kcal/kg)",
                    hintText: "Ej. 3850",
                    prefixIcon: Icon(
                      Icons.local_fire_department,
                      color: Colors.orange,
                    ),
                    border: OutlineInputBorder(),
                    suffixText: "kcal/kg",
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Este campo es requerido";
                    }
                    if (double.tryParse(value) == null) {
                      return "Ingresa un número válido";
                    }
                    return null;
                  },
                  onChanged: (_) {
                    if (_calculado) setState(() => _calculado = false);
                  },
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        "Busca en el reverso de la bolsa el apartado 'Análisis garantizado' o 'Contenido calórico'.",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // --- PASO 2: FRECUENCIA Y CRONOBIOLOGÍA ---
                Text(
                  "2. Distribución Recomendada",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                if (isGato) ...[
                  // UI Informativa fija para Gatos
                  Card(
                    color: Colors.blue.withValues(alpha: 0.08),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "🐱 Recomendación Biológica Felina:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Los gatos están adaptados a comer pequeñas cantidades con alta frecuencia para mantener niveles constantes de glucosa. El sistema ha programado de forma óptima 6 raciones automáticas entre las 07:00 y las 19:00.",
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // UI de selección para Perros
                  const Text(
                    "Los horarios fijos regulan el sistema endocrino de tu canino y evitan la cronodisrupción. Selecciona la opción ideal para tu perro:",
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text(
                            "2 Raciones\n(Mañana/Noche)",
                            textAlign: TextAlign.center,
                          ),
                          selected: _selectedRaciones == 2,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedRaciones = 2;
                                _calculado = false;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text(
                            "3 Raciones\n(Recomendado)",
                            textAlign: TextAlign.center,
                          ),
                          selected: _selectedRaciones == 3,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedRaciones = 3;
                                _calculado = false;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),

                // --- BOTÓN DE CALCULAR ---
                if (!_calculado)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _ejecutarCalculos,
                      icon: const Icon(Icons.calculate),
                      label: const Text("Calcular Horarios y Porciones"),
                    ),
                  ),

                // --- PASO 3: VISTA PREVIA Y CONFIRMACIÓN ---
                if (_calculado) ...[
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    "3. Resultados del Plan Sugerido",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Resumen de cantidades
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _resultStat(
                          "Total Diario",
                          "${_gramosTotalesDiarios.toStringAsFixed(1)} g",
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.green.withValues(alpha: 0.3),
                        ),
                        _resultStat(
                          "Por Ración",
                          "${_gramosPorRacion.toStringAsFixed(1)} g",
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    "Horarios a registrar en el dispensador:",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Lista de los horarios automáticos generados
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _generatedSchedules.length,
                    itemBuilder: (context, index) {
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Icon(
                              Icons.access_time,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            _generatedSchedules[index],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          trailing: Text(
                            "${_gramosPorRacion.toStringAsFixed(1)} gramos",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // --- ADVERTENCIA DE HIDRATACIÓN ---
                  Card(
                    color: Colors.amber.withValues(alpha: 0.1),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Colors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.amber,
                            size: 26,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Advertencia de Hidratación:\nComo el sistema suministra alimento seco (3-11% de agua), asegúrate de que ${widget.pet.name} tenga agua limpia. Debería consumir entre ${aguaMin.toStringAsFixed(0)} ml y ${aguaMax.toStringAsFixed(0)} ml de agua al día.",
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // NOTA DE LATENCIA DEL HARDWARE
                  Center(
                    child: Text(
                      "🕒 Los cambios sincronizarán con el hardware en un máximo de 3 segundos.",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- BOTÓN DE PERSISTENCIA (GUARDAR EN BACKEND) ---
                  BlocConsumer<ScheduleBloc, ScheduleState>(
                    listener: (context, state) {
                      if (state is ScheduleDetailLoaded ||
                          state is ScheduleLoaded) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("¡Horarios automatizados con éxito!"),
                          ),
                        );
                        Navigator.pop(context); // Regresa al detalle
                      }
                      if (state is ScheduleError) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Error: ${state.message}")),
                        );
                      }
                    },
                    builder: (context, state) {
                      return SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: state is ScheduleLoading
                              ? null
                              : () {
                                  // Desplegamos un único evento controlado
                                  context.read<ScheduleBloc>().add(
                                    ScheduleCreateMultipleRequested(
                                      times: _generatedSchedules,
                                      amount: double.parse(
                                        _gramosPorRacion.toStringAsFixed(1),
                                      ),
                                      petId: widget.pet.id,
                                    ),
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: state is ScheduleLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  "Confirmar y Programar Dispensador",
                                  style: TextStyle(fontSize: 16),
                                ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.green,
          ),
        ),
      ],
    );
  }
}
