part of 'pet_bloc.dart';

sealed class PetState {
  const PetState();
}

final class PetInicial extends PetState {}

final class PetLoading extends PetState {}

final class PetLoaded extends PetState {
  final List<Pet> pets;

  PetLoaded({required this.pets});
}

// 4. Estado opcional si entras al detalle de una sola mascota
final class PetDetailLoaded extends PetState {
  final Pet pet;

  PetDetailLoaded({required this.pet});
}

final class PetActionSuccess extends PetState {
  final String message;

  PetActionSuccess({required this.message});
}

final class PetError extends PetState {
  final String message;

  PetError({required this.message});
}
