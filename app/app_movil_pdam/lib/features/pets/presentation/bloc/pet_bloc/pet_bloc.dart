import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/create_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/delete_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/update_pet_uc.dart';
import 'package:bloc/bloc.dart';

part 'pet_state.dart';
part 'pet_event.dart';

class PetBloc extends Bloc<PetEvent, PetState> {
  final CreatePetUc _createPetUc;
  final GetPetUc _getPetUc;
  final GetPetsUc _getPetsUc;
  final UpdatePetUc _updatePetUc;
  final DeletePetsUc _deletePetsUc;

  PetBloc({
    required CreatePetUc cretePetUc,
    required GetPetUc getPetUc,
    required GetPetsUc getPetsUc,
    required UpdatePetUc updatePetUc,
    required DeletePetsUc deletePetUc,
  }) : _createPetUc = cretePetUc,
       _getPetUc = getPetUc,
       _getPetsUc = getPetsUc,
       _updatePetUc = updatePetUc,
       _deletePetsUc = deletePetUc,
       super(PetInicial()) {
    on<PetCreatePressed>(_onPetCreatePressed);
    on<PetGetRequested>(_onPetGetRequested);
    on<PetsLoadedRequested>(_onPetsLoadedRequested);
    on<PetUpdatePressed>(_onPetUpdatePressed);
    on<PetDeletePressed>(_onPetDeletePressed);
  }

  Future<void> _onPetCreatePressed(
    PetCreatePressed event,
    Emitter<PetState> emit,
  ) async {
    emit(PetLoading());

    final result = await _createPetUc(
      event.name,
      event.species,
      event.age,
      event.weight,
      event.imageFile,
    );

    result.fold(
      (failure) => emit(PetError(message: failure.message)),
      (pet) => emit(PetDetailLoaded(pet: pet)),
    );
  }

  Future<void> _onPetGetRequested(
    PetGetRequested event,
    Emitter<PetState> emit,
  ) async {
    emit(PetLoading());

    final result = await _getPetUc(event.idPet);
    result.fold(
      (failure) => emit(PetError(message: failure.message)),
      (pet) => emit(PetDetailLoaded(pet: pet)),
    );
  }

  Future<void> _onPetsLoadedRequested(
    PetsLoadedRequested event,
    Emitter<PetState> emit,
  ) async {
    emit(PetLoading());
    final result = await _getPetsUc();
    result.fold(
      (failure) => emit(PetError(message: failure.message)),
      (pets) => emit(PetLoaded(pets: pets)),
    );
  }

  Future<void> _onPetUpdatePressed(
    PetUpdatePressed event,
    Emitter<PetState> emit,
  ) async {
    emit(PetLoading());
    final result = await _updatePetUc(
      event.petId,
      name: event.name,
      species: event.species,
      age: event.age,
      weight: event.weight,
      imageFile: event.imageFile,
    );

    result.fold(
      (failure) => emit(PetError(message: failure.message)),
      (pet) =>
          emit(PetActionSuccess(message: "Se actualizo la mascota con exíto")),
    );
  }

  Future<void> _onPetDeletePressed(
    PetDeletePressed event,
    Emitter<PetState> emit,
  ) async {
    emit(PetLoading());
    final result = await _deletePetsUc(event.petId);

    result.fold((failure) => emit(PetError(message: failure.message)), (
      success,
    ) {
      if (success) {
        emit(PetActionSuccess(message: "Se elimino la mascota con exíto"));
      } else {
        emit(PetError(message: "No se puedo eliminar la mascota"));
      }
    });
  }
}
