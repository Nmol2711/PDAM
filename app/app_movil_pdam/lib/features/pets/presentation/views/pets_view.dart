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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mascotas")),
      body: Center(
        child: BlocBuilder<PetBloc, PetState>(
          builder: (context, state) {
            if (state is PetLoaded) {
              return PetsList(pets: state.pets);
            } else if (state is PetLoading || state is PetInicial) {
              return CircularProgressIndicator();
            } else if (state is PetError) {
              return Text(state.message);
            } else {
              return Text("A pasado algo inesperado");
            }
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push("/create_pet"),
        child: Icon(Icons.add),
      ),
    );
  }
}
