import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/activate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/associate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/dasactivate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/delete_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/get_dispenser_by_pet_uc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'dispenser_event.dart';
part 'dispenser_state.dart';

class DispenserBloc extends Bloc<DispenserEvent, DispenserState> {
  final AssociateDispenserUc associateUseCase;
  final GetDispenserByPetUc getDispenserByPetUseCase;
  final ActivateDispenserUc activateUseCase;
  final DesactivateDispenserUc deactivateUseCase;
  final DeleteDispenserUc deleteDispenserUseCase;

  DispenserBloc({
    required this.associateUseCase,
    required this.getDispenserByPetUseCase,
    required this.activateUseCase,
    required this.deactivateUseCase,
    required this.deleteDispenserUseCase,
  }) : super(DispenserInitial()) {
    // Evento para asociar
    on<AssociateDispenserEvent>((event, emit) async {
      emit(DispenserLoading());
      final failureOrDispenser = await associateUseCase(
        event.macAddress,
        event.petId,
        event.secretKeyQr,
      );

      failureOrDispenser.fold(
        (failure) => emit(
          DispenserFailure(failure.message),
        ), // Dependiendo de cómo extraigas el string de tu Failure
        (dispenser) => emit(DispenserSuccess()),
      );
    });

    // Evento para cargar en la vista de detalles
    on<LoadDispenserByPetEvent>((event, emit) async {
      emit(DispenserLoading());
      final failureOrDispenser = await getDispenserByPetUseCase(event.petId);

      failureOrDispenser.fold(
        (failure) => emit(
          DispenserEmpty(),
        ), // Si da error 404 de que no existe, asumimos vacío
        (dispenser) => emit(DispenserLoaded(dispenser)),
      );
    });

    on<DeactivateDispenserEvent>((event, emit) async {
      emit(DispenserLoading());
      final result = await deactivateUseCase(event.dispenserId, event.petId);

      if (result.isLeft()) {
        result.fold(
          (failure) => emit(DispenserFailure(failure.message)),
          (_) => null,
        );
        return;
      }

      final success = result.getOrElse(() => false);
      if (!success) {
        emit(DispenserFailure('No se pudo activar el dispensador'));
        return;
      }

      final refreshed = await getDispenserByPetUseCase(event.petId);
      refreshed.fold(
        (failure) => emit(DispenserFailure(failure.message)),
        (dispenser) => emit(DispenserLoaded(dispenser)),
      );
    });

    on<ActivateDispenserEvent>((event, emit) async {
      emit(DispenserLoading());
      final result = await activateUseCase(event.dispenserId, event.petId);

      if (result.isLeft()) {
        result.fold(
          (failure) => emit(DispenserFailure(failure.message)),
          (_) => null,
        );
        return;
      }

      final success = result.getOrElse(() => false);
      if (!success) {
        emit(DispenserFailure('No se pudo desactivar el dispensador'));
        return;
      }

      final refreshed = await getDispenserByPetUseCase(event.petId);
      refreshed.fold(
        (failure) => emit(DispenserFailure(failure.message)),
        (dispenser) => emit(DispenserLoaded(dispenser)),
      );
    });

    on<DeleteDispenserEvent>((event, emit) async {
      emit(DispenserLoading());
      final result = await deleteDispenserUseCase(event.petId);

      if (result.isLeft()) {
        result.fold(
          (failure) => emit(DispenserFailure(failure.message)),
          (_) => null,
        );
        return;
      }

      final success = result.getOrElse(() => false);
      if (!success) {
        emit(DispenserFailure('No se pudo eliminar el dispensador'));
        return;
      }

      emit(DispenserEmpty());
    });

    on<QrCodeDetectedEvent>((event, emit) {
      emit(
        DispenserQrScanned(
          macAddress: event.macAddress,
          secretKeyQr: event.secretKeyQr,
        ),
      );
    });
  }
}
