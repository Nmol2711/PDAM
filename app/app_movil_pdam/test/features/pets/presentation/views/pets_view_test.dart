import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/create_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/delete_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/update_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/pets_view.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePetsRepository implements PetsRepositories {
  @override
  Future<Either<Failures, List<Pet>>> getPets() async => const Right(<Pet>[]);

  @override
  Future<Either<Failures, Pet>> createPet(
    String name,
    TypePest species,
    DateTime birthDate,
    double weight,
    bool reproductiveStatus,
    File? imageFile,
  ) async => Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, bool>> deletePet(int petId) async =>
      Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, Pet>> getPet(int petId) async =>
      Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, Pet>> updatePet(
    int petId, {
    String? name,
    TypePest? species,
    DateTime? birthDate,
    double? weight,
    bool? reproductiveStatus,
    File? imageFile,
  }) async => Left(ServerFailures('no usado'));
}

/// RF-01: la cabecera real de Mascotas solo dibuja la entrada al menú por
/// debajo de 600 puntos; desde 600 la única entrada vive en el contenedor.
void main() {
  Future<void> pumpPets(WidgetTester tester) async {
    final repository = _FakePetsRepository();
    final bloc = PetBloc(
      cretePetUc: CreatePetUc(repository: repository),
      getPetUc: GetPetUc(repository: repository),
      getPetsUc: GetPetsUc(repository: repository),
      updatePetUc: UpdatePetUc(repository: repository),
      deletePetUc: DeletePetsUc(repository: repository),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider<PetBloc>.value(
        value: bloc,
        child: MaterialApp(theme: AppTheme.lightTheme, home: const PetsView()),
      ),
    );
    // Sin `pumpAndSettle`: el indicador de carga anima mientras el BLoC
    // resuelve la consulta y podría no terminar nunca en la prueba.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a 600 y 840 la cabecera real no dibuja la entrada', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final ancho in <double>[600, 840]) {
      tester.view.physicalSize = Size(ancho, 800);
      tester.view.devicePixelRatio = 1.0;
      await pumpPets(tester);

      expect(
        find.byTooltip('Abrir configuración'),
        findsNothing,
        reason: 'ancho $ancho',
      );
    }
  });

  testWidgets('a 320 la cabecera real dibuja exactamente una entrada', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPets(tester);

    expect(find.text('Mascotas'), findsOneWidget);
    expect(find.byTooltip('Abrir configuración'), findsOneWidget);
  });
}
