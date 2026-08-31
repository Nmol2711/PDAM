part of 'pet_bloc.dart';

sealed class PetEvent {
  const PetEvent();
}

final class PetCreatePressed extends PetEvent {
  final String name;
  final TypePest species;
  final int age;
  final double weight;
  final File? imageFile;

  PetCreatePressed({
    required this.name,
    required this.species,
    required this.age,
    required this.weight,
    this.imageFile,
  });
}

final class PetGetRequested extends PetEvent {
  final int idPet;
  PetGetRequested({required this.idPet});
}

final class PetsLoadedRequested extends PetEvent {}

final class PetUpdatePressed extends PetEvent {
  final int petId;
  final String? name;
  final TypePest? species;
  final int? age;
  final double? weight;
  final File? imageFile;

  PetUpdatePressed({
    required this.petId,
    this.name,
    this.species,
    this.age,
    this.weight,
    this.imageFile,
  });
}

final class PetDeletePressed extends PetEvent {
  final int petId;
  PetDeletePressed({required this.petId});
}
