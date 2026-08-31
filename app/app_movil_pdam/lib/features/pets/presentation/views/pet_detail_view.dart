import 'dart:ui'; // 💡 IMPORTANTE: Necesario para usar ImageFilter
import 'package:app_movil_pdam/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:go_router/go_router.dart';

import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';

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

  @override
  Widget build(BuildContext context) {
    // Detectamos si el tema actual es oscuro o claro para ajustar la opacidad de la capa intermedia
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(widget.pet.name), centerTitle: true),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 1. SECCIÓN DE IMAGEN CON EFECTO BLURRY BACKDROP ---
            SizedBox(
              height: 220,
              width: double.infinity,
              child: widget.pet.imgUrl != null && widget.pet.imgUrl!.isNotEmpty
                  ? Stack(
                      children: [
                        // Capa 1: Fondo estirado (Imagen de fondo difusa)
                        Container(
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: NetworkImage(widget.pet.imgUrl!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        // Capa 2: Filtro de desenfoque Gaussiano adaptativo al tema
                        Positioned.fill(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: 15.0,
                              sigmaY: 15.0,
                            ),
                            child: Container(
                              // Se mimetiza con el fondo actual del scaffold
                              color: Theme.of(context).scaffoldBackgroundColor
                                  .withOpacity(isDarkMode ? 0.4 : 0.6),
                            ),
                          ),
                        ),
                        // Capa 3: Imagen nítida, centrada y completa sin recortes
                        Center(
                          child: Image.network(
                            widget.pet.imgUrl!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    )
                  : Container(
                      color: Colors.grey.shade300,
                      child: const Icon(
                        Icons.pets,
                        size: 80,
                        color: Colors.grey,
                      ),
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
                      // 🚀 Navegamos al formulario guiado pasando el objeto pet actual
                      context.pushNamed(
                        'guided_schedule_form',
                        extra: widget.pet,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // --- 3. LISTA DE HORARIOS ORIGINAL (Conectada al Bloc) ---
            BlocBuilder<ScheduleBloc, ScheduleState>(
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
                            print("Horario seleccionado: ${schedule.id}");
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
                            trailing: const Icon(Icons.chevron_right),
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
