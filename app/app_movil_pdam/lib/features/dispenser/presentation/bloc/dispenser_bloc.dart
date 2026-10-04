import 'package:app_movil_pdam/core/error/failures.dart';
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

  Dispenser? _lastLoadedDispenser;

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

      // El fallo viaja tipado hasta la presentación, que decide el copy
      // (RF-10 a RF-13). Aquí no hay textos (RNF-01).
      failureOrDispenser.fold(
        (failure) => emit(DispenserFailure(failure)),
        (dispenser) => emit(DispenserSuccess()),
      );
    });

    // Evento para cargar en la vista de detalles
    on<LoadDispenserByPetEvent>((event, emit) async {
      emit(DispenserLoading());
      final failureOrDispenser = await getDispenserByPetUseCase(event.petId);

      failureOrDispenser.fold(
        (failure) {
          _lastLoadedDispenser = null;
          emit(DispenserEmpty());
        }, // Si da error 404 de que no existe, asumimos vacío
        (dispenser) {
          _lastLoadedDispenser = dispenser;
          emit(DispenserLoaded(dispenser));
        },
      );
    });

    on<DeactivateDispenserEvent>((event, emit) async {
      emit(DispenserLoading());
      final result = await deactivateUseCase(event.dispenserId, event.petId);

      if (result.isLeft()) {
        result.fold(
          (failure) => emit(DispenserFailure(failure, dispenser: _lastLoadedDispenser)),
          (_) => null,
        );
        return;
      }

      final success = result.getOrElse(() => false);
      if (!success) {
        emit(DispenserFailure(_falloOperacionNoCompletada().failure, dispenser: _lastLoadedDispenser));
        return;
      }

      final refreshed = await getDispenserByPetUseCase(event.petId);
      refreshed.fold(
        (failure) => emit(DispenserFailure(failure, dispenser: _lastLoadedDispenser)),
        (dispenser) {
          _lastLoadedDispenser = dispenser;
          emit(DispenserLoaded(dispenser));
        },
      );
    });

    on<ActivateDispenserEvent>((event, emit) async {
      emit(DispenserLoading());
      final result = await activateUseCase(event.dispenserId, event.petId);

      if (result.isLeft()) {
        result.fold(
          (failure) => emit(DispenserFailure(failure, dispenser: _lastLoadedDispenser)),
          (_) => null,
        );
        return;
      }

      final success = result.getOrElse(() => false);
      if (!success) {
        emit(DispenserFailure(_falloOperacionNoCompletada().failure, dispenser: _lastLoadedDispenser));
        return;
      }

      final refreshed = await getDispenserByPetUseCase(event.petId);
      refreshed.fold(
        (failure) => emit(DispenserFailure(failure, dispenser: _lastLoadedDispenser)),
        (dispenser) {
          _lastLoadedDispenser = dispenser;
          emit(DispenserLoaded(dispenser));
        },
      );
    });

    on<DeleteDispenserEvent>((event, emit) async {
      emit(DispenserLoading());
      final result = await deleteDispenserUseCase(event.petId);

      if (result.isLeft()) {
        result.fold(
          (failure) => emit(DispenserFailure(failure, dispenser: _lastLoadedDispenser)),
          (_) => null,
        );
        return;
      }

      final success = result.getOrElse(() => false);
      if (!success) {
        emit(DispenserFailure(_falloOperacionNoCompletada().failure, dispenser: _lastLoadedDispenser));
        return;
      }

      _lastLoadedDispenser = null;
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

/// Fallo para el caso en que la operación responde sin resultado, que solo
/// debería ocurrir ante una inconsistencia interna del caso de uso. Viaja sin
/// mensaje porque el copy del aviso lo decide la presentación
/// (`dispenser_notice_mapper`) y el BLoC no contiene textos (RNF-01).
DispenserFailure _falloOperacionNoCompletada() =>
    DispenserFailure(ServerFailures(''));
