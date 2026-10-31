import 'package:app_movil_pdam/core/presentation/utils/settings_entry_visibility.dart';
import 'package:app_movil_pdam/core/presentation/widgets/settings_entry_button.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/widget/pets_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class PetsView extends StatefulWidget {
  const PetsView({super.key});

  @override
  State<PetsView> createState() => _PetsViewState();
}

class _PetsViewState extends State<PetsView> {
  @override
  void initState() {
    super.initState();
    context.read<PetBloc>().add(PetsLoadedRequested());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<PetBloc>().add(PetsLoadedRequested());
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final semantica = AppSemanticColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mascotas"),
        actions: const <Widget>[
          SettingsEntryButton(ubicacion: UbicacionEntrada.cabeceraPantalla),
        ],
      ),
      body: Center(
        child: BlocConsumer<PetBloc, PetState>(
          listener: (context, state) {
            if (state is PetActionSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: semantica.success,
                  content: Text(
                    state.message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: semantica.onSuccess,
                    ),
                  ),
                ),
              );
            }
          },
          builder: (context, state) {
            if (state is PetLoaded) {
              if (state.pets.isEmpty) {
                return const Text('No hay mascotas registradas');
              }
              return PetsList(pets: state.pets);
            } else if (state is PetLoading || state is PetInicial) {
              return const CircularProgressIndicator();
            } else if (state is PetError) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.sectionGap),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.pets, size: 64, color: esquema.onSurfaceVariant),
                    const SizedBox(height: AppSpacing.fieldGap),
                    Text(
                      state.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: esquema.error),
                    ),
                    const SizedBox(height: AppSpacing.fieldGap),
                    ElevatedButton(
                      onPressed: () {
                        context.read<PetBloc>().add(PetsLoadedRequested());
                      },
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              );
            } else {
              return const SizedBox.shrink();
            }
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push("/create_pet"),
        child: const Icon(Icons.add),
      ),
    );
  }
}
