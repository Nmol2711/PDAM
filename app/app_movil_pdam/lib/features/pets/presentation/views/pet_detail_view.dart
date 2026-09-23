import 'dart:math' as Math;
import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:go_router/go_router.dart';

import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/edit_pet_view.dart';

class PetDetailView extends StatefulWidget {
  final Pet pet;

  const PetDetailView({super.key, required this.pet});

  @override
  State<PetDetailView> createState() => _PetDetailViewState();
}

class _PetDetailViewState extends State<PetDetailView> {
  @override
  void initState() {
    super.initState();
    // Carga los horarios
    context.read<ScheduleBloc>().add(
      ScheduleListPetRequested(petId: widget.pet.id),
    );
    // 🔥 Solicitamos al backend saber si esta mascota ya tiene un dispensador asociado
    context.read<DispenserBloc>().add(LoadDispenserByPetEvent(widget.pet.id));
  }

  String _getDefaultAssetPath(TypePest species) {
    switch (species) {
      case TypePest.canino:
        return "assets/imgs/perro.png";
      case TypePest.felino:
      case TypePest.otros:
        return "assets/imgs/gato_1.png";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pet.name),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar mascota',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditPetView(pet: widget.pet),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 1. SECCIÓN DE IMAGEN CON EFECTO BLURRY BACKDROP ---
            SizedBox(
              height: 220,
              width: double.infinity,
              child: widget.pet.imgUrl != null && widget.pet.imgUrl!.isNotEmpty
                  ? Image.network(
                      widget.pet.imgUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Image.asset(
                          _getDefaultAssetPath(widget.pet.species),
                          fit: BoxFit.cover,
                        );
                      },
                    )
                  : Image.asset(
                      _getDefaultAssetPath(widget.pet.species),
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(height: 16),

            // --- 2. INFORMACIÓN CLAVE (Fila de Cards) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  _infoCard(
                    "Edad",
                    "${widget.pet.age} años",
                    Icons.calendar_month,
                  ),
                  _infoCard("Peso", "${widget.pet.weight} kg", Icons.scale),
                  _infoCard(
                    "Especie",
                    widget.pet.species.name,
                    Icons.fingerprint,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // --- 🔥 NUEVA SECCIÓN: ESTADO DEL DISPENSADOR (Reactivo con BLoC) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: BlocConsumer<DispenserBloc, DispenserState>(
                listener: (context, state) {
                  // Si venimos regresando del formulario y el BLoC guardó con éxito,
                  // volvemos a pedir el estado para refrescar los detalles aquí.
                  if (state is DispenserSuccess) {
                    context.read<DispenserBloc>().add(
                      LoadDispenserByPetEvent(widget.pet.id),
                    );
                  }
                },
                builder: (context, state) {
                  if (state is DispenserLoading) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  if (state is DispenserLoaded) {
                    final dispenser = state.dispenser;
                    final isActive = dispenser.isActive;

                    return InkWell(
                      onTap: () =>
                          _showDispenserOptionsDialog(context, dispenser),
                      child: Card(
                        color: isActive
                            ? Colors.green.withOpacity(0.15)
                            : Colors.orange.withOpacity(0.15),
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            color: isActive ? Colors.green : Colors.orange,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isActive
                                ? Colors.green
                                : Colors.orange,
                            child: Icon(
                              isActive ? Icons.check : Icons.pause_circle,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            isActive
                                ? 'Dispensador Vinculado'
                                : 'Dispensador Desactivado',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isActive ? Colors.green : Colors.orange,
                            ),
                          ),
                          subtitle: Text(
                            'MAC: ${dispenser.macAddress}\nEstado: ${isActive ? 'Activo' : 'Desactivado'}',
                            style: TextStyle(
                              color: isActive
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  // ➕ CASO 2: No hay vinculado / Falló la carga -> Mostramos botón para ir a registrar
                  return OutlinedButton.icon(
                    onPressed: () {
                      // Navegamos al formulario pasando la mascota en el extra
                      context.pushNamed(
                        'register_dispenser',
                        extra: widget.pet,
                      );
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text("Vincular Dispensador Inteligente"),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: const BorderSide(color: Colors.blue),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Título de la sección de Horarios
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Horarios de Comida",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle,
                      color: Colors.blue,
                      size: 28,
                    ),
                    onPressed: () {
                      final state = context.read<ScheduleBloc>().state;
                      final schedules = state is ScheduleLoaded ? state.schedules : <Schedule>[];
                      _showAddScheduleOptionsDialog(context, schedules);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // --- 3. LISTA DE HORARIOS ORIGINAL (Conectada al Bloc) ---
            BlocConsumer<ScheduleBloc, ScheduleState>(
              listener: (context, state) {
                if (state is ScheduleLoaded && state.isOffline) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Los horarios se reflejarán cuando haya conexión con el servidor'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              },
              builder: (context, state) {
                if (state is ScheduleLoading) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (state is ScheduleError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        state.message,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }

                if (state is ScheduleLoaded) {
                  if (state.schedules.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text("No hay horarios asignados aún."),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.schedules.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final schedule = state.schedules[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        elevation: 2,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            _showEditScheduleDialog(context, schedule, widget.pet.id);
                          },
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.blueAccent,
                              child: Icon(
                                Icons.access_time,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              schedule.time,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              "Porción: ${schedule.amount} gramos",
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                              tooltip: 'Editar horario',
                              onPressed: () {
                                _showEditScheduleDialog(context, schedule, widget.pet.id);
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }

                return const SizedBox();
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _showDispenserOptionsDialog(
    BuildContext context,
    dynamic dispenser,
  ) async {
    final isActive = dispenser.isActive;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Opciones del dispensador'),
          content: Text(
            isActive
                ? 'El dispensador está activo. Puedes desactivarlo o cerrar esta ventana.'
                : 'El dispensador está desactivado. Puedes activarlo o cerrar esta ventana.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.read<DispenserBloc>().add(
                  isActive
                      ? DeactivateDispenserEvent(
                          dispenserId: dispenser.id,
                          petId: dispenser.petId,
                        )
                      : ActivateDispenserEvent(
                          dispenserId: dispenser.id,
                          petId: dispenser.petId,
                        ),
                );
              },
              child: Text(isActive ? 'Desactivar' : 'Activar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.read<DispenserBloc>().add(
                  DeleteDispenserEvent(petId: dispenser.petId),
                );
              },
              child: const Text(
                'Eliminar',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  double _calculateWsavaDailyGrams(Pet pet, double foodKcalPerKg) {
    final hoy = DateTime.now();
    final edadDias = hoy.difference(pet.birthDate).inDays;
    final edadMeses = edadDias / 30.44;

    final weight = pet.weight;
    final rer = 70 * Math.pow(weight, 0.75);

    final species = pet.species.name.toLowerCase();
    final isNeutered = pet.reproductiveStatus;
    final isGrowth = edadMeses < 12;

    double factorMer = 1.6;
    if (species.contains('canino') || species.contains('dog')) {
      if (isGrowth) {
        factorMer = edadMeses < 4 ? 3.0 : 2.0;
      } else {
        if (isNeutered) {
          factorMer = 1.6;
        } else {
          factorMer = 1.8;
        }
      }
    } else {
      if (isGrowth) {
        factorMer = 2.5;
      } else {
        if (isNeutered) {
          factorMer = 1.2;
        } else {
          factorMer = 1.4;
        }
      }
    }

    final mer = rer * factorMer;
    final dailyKcal = mer;
    final dailyGrams = foodKcalPerKg > 0 ? (dailyKcal / foodKcalPerKg) * 1000 : 0.0;
    return dailyGrams;
  }

  void _showAddScheduleOptionsDialog(BuildContext context, List<Schedule> existingSchedules) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Agregar Horario de Comida",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.add, color: Colors.white),
              ),
              title: const Text("Agregar horario individual"),
              subtitle: const Text("Registra una hora y porción con validación WSAVA"),
              onTap: () {
                Navigator.pop(context);
                _showAddScheduleDialog(context, existingSchedules, widget.pet.id);
              },
            ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.orangeAccent,
                child: Icon(Icons.auto_awesome, color: Colors.white),
              ),
              title: const Text("Plan Nutricional Automático WSAVA"),
              subtitle: const Text("Generar horarios basados en BCS, MCS y densidad calórica"),
              onTap: () {
                Navigator.pop(context);
                context.pushNamed('guided_schedule_form', extra: widget.pet);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddScheduleDialog(BuildContext context, List<Schedule> existingSchedules, int petId) {
    final timeController = TextEditingController();
    final amountController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Nuevo Horario",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: timeController,
                decoration: const InputDecoration(
                  labelText: "Hora (HH:MM)",
                  hintText: "Ej. 08:30",
                  prefixIcon: Icon(Icons.access_time),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return "Requerido";
                  if (!RegExp(r"^([01]\d|2[0-3]):([0-5]\d)$").hasMatch(v)) {
                    return 'Formato HH:MM (ej: 08:30)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Cantidad (gramos)",
                  hintText: "Ej. 150",
                  prefixIcon: Icon(Icons.scale),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  suffixText: 'g',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return "Requerido";
                  if (double.tryParse(v) == null || double.parse(v) <= 0) {
                    return 'Cantidad inválida';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    final newAmount = double.parse(amountController.text.trim());
                    final existingTotal = existingSchedules.fold(0.0, (sum, s) => sum + s.amount);
                    final totalPlanned = existingTotal + newAmount;
                    
                    final wsavaLimitGrams = _calculateWsavaDailyGrams(widget.pet, 3850.0);
                    final excess = totalPlanned - wsavaLimitGrams;

                    if (excess > 50.0) {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("⚠️ Límite WSAVA Excedido"),
                          content: Text(
                            "No se puede crear este horario porque excede significativamente el límite diario recomendado por WSAVA para ${widget.pet.name}.\n\n"
                            "• Límite recomendado: ${wsavaLimitGrams.toStringAsFixed(0)}g\n"
                            "• Total con este horario: ${totalPlanned.toStringAsFixed(0)}g\n\n"
                            "Superar este límite puede causar sobrepeso y riesgos metabólicos.",
                          ),
                          actions: [
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("Entendido"),
                            ),
                          ],
                        ),
                      );
                      return;
                    }

                    if (excess > 0.0) {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("⚠️ Advertencia Nutricional WSAVA"),
                          content: Text(
                            "Esta porción supera ligeramente la recomendación diaria recomendada por WSAVA.\n\n"
                            "• Límite recomendado: ${wsavaLimitGrams.toStringAsFixed(0)}g\n"
                            "• Total planeado: ${totalPlanned.toStringAsFixed(0)}g\n\n"
                            "¿Deseas continuar y registrar el horario de todas formas?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("Cancelar"),
                            ),
                            FilledButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                context.read<ScheduleBloc>().add(
                                      ScheduleCreatePressed(
                                        petId: petId,
                                        time: timeController.text.trim(),
                                        amount: newAmount,
                                      ),
                                    );
                              },
                              child: const Text("Continuar"),
                            ),
                          ],
                        ),
                      );
                      return;
                    }

                    Navigator.pop(context);
                    context.read<ScheduleBloc>().add(
                          ScheduleCreatePressed(
                            petId: petId,
                            time: timeController.text.trim(),
                            amount: newAmount,
                          ),
                        );
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Guardar Horario", style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
  void _showEditScheduleDialog(BuildContext context, Schedule schedule, int petId) {
    final timeController = TextEditingController(text: schedule.time);
    final amountController = TextEditingController(text: schedule.amount.toString());
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Editar Horario",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: timeController,
                decoration: const InputDecoration(
                  labelText: "Hora (HH:MM)",
                  prefixIcon: Icon(Icons.access_time),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return "Requerido";
                  if (!RegExp(r"^([01]\d|2[0-3]):([0-5]\d)$").hasMatch(v)) {
                    return 'Formato HH:MM (ej: 08:30)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Cantidad (gramos)",
                  prefixIcon: Icon(Icons.scale),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  suffixText: 'g',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return "Requerido";
                  if (double.tryParse(v) == null || double.parse(v) <= 0) {
                    return 'Cantidad inválida';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    BlocProvider.of<ScheduleBloc>(context).add(
                      ScheduleUpdatePressed(
                        scheduleId: schedule.id,
                        petId: petId,
                        time: timeController.text.trim(),
                        amount: double.parse(amountController.text.trim()),
                      ),
                    );
                    Navigator.pop(context);
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Guardar Cambios", style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard(String title, String value, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, color: Colors.blueGrey, size: 20),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
