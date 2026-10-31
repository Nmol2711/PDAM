import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/presentation/widgets/app_cta_button.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/create_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/delete_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/update_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/edit_pet_view.dart';
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

final Pet _mascota = Pet(
  id: 1,
  name: 'Luna',
  species: TypePest.felino,
  birthDate: DateTime(2020),
  weight: 4.5,
  reproductiveStatus: true,
);

void main() {
  Future<void> pumpEdit(WidgetTester tester) async {
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
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: EditPetView(pet: _mascota),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('RF-05: «Actualizar Mascota» sigue en el principal, no en CTA', (
    tester,
  ) async {
    await pumpEdit(tester);
    final esquema = AppTheme.lightTheme.colorScheme;

    expect(find.byType(AppCtaButton), findsNothing);
    final botonFinder = find.widgetWithText(FilledButton, 'Actualizar Mascota');
    expect(botonFinder, findsOneWidget);
    final boton = tester.widget<FilledButton>(botonFinder);
    expect(boton.style, isNull, reason: 'el botón no debe llevar estilo local');

    final material = tester
        .widgetList<Material>(
          find.descendant(of: botonFinder, matching: find.byType(Material)),
        )
        .firstWhere((widget) => widget.color == esquema.primary);
    final forma = material.shape! as RoundedRectangleBorder;
    expect(forma.borderRadius, BorderRadius.circular(8));
  });
}
