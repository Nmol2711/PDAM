part of 'pet_bloc.dart';

sealed class PetEvent {
  const PetEvent();
}

final class PetCreatePressed extends PetEvent {
  final String name;
  final TypePest species;
  final DateTime birthDate;
  final double weight;
  final bool reproductiveStatus;
  final File? imageFile;

  PetCreatePressed({
    required this.name,
    required this.species,
    required this.birthDate,
    required this.weight,
    required this.reproductiveStatus,
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
  final DateTime? birthDate;
  final double? weight;
  final bool? reproductiveStatus;
  final File? imageFile;

  PetUpdatePressed({
    required this.petId,
    this.name,
    this.species,
    this.birthDate,
    this.weight,
    this.reproductiveStatus,
    this.imageFile,
  });
}

final class PetDeletePressed extends PetEvent {
  final int petId;
  PetDeletePressed({required this.petId});
}
