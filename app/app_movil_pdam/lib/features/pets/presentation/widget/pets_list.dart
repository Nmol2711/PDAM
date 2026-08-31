import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/presentation/widget/pet_item.dart';
import 'package:flutter/material.dart';

class PetsList extends StatelessWidget {
  final List<Pet> pets;
  const PetsList({super.key, required this.pets});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ListView.builder(
        itemCount: pets.length,
        itemBuilder: (BuildContext context, int index) {
          return PetItem(pet: pets[index]);
        },
      ),
    );
  }
}
