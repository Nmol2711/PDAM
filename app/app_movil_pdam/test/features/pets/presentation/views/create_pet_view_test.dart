import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/presentation/widgets/app_cta_button.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/create_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/delete_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/update_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/create_pet_view.dart';
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

void main() {
  Future<void> pumpCreate(WidgetTester tester) async {
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
          home: const CreatePetView(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'RF-05: «Guardar Mascota» usa AppCtaButton con el CTA y radio 8',
    (tester) async {
      await pumpCreate(tester);

      final cta = find.byType(AppCtaButton);
      expect(cta, findsOneWidget);
      expect(
        find.descendant(of: cta, matching: find.text('Guardar Mascota')),
        findsOneWidget,
      );

      final semantica = AppTheme.lightTheme.extension<AppSemanticColors>()!;
      final boton = tester.widget<FilledButton>(
        find.descendant(of: cta, matching: find.byType(FilledButton)),
      );
      expect(
        boton.style!.backgroundColor!.resolve(<WidgetState>{}),
        semantica.cta,
      );
      expect(
        boton.style!.foregroundColor!.resolve(<WidgetState>{}),
        semantica.onCta,
      );
      expect(boton.style!.shape, isNull);
      final forma =
          AppTheme.lightTheme.filledButtonTheme.style!.shape!.resolve(
                <WidgetState>{},
              )!
              as RoundedRectangleBorder;
      expect(forma.borderRadius, BorderRadius.circular(8));
    },
  );

  testWidgets('conserva textos y validadores del formulario', (tester) async {
    await pumpCreate(tester);

    expect(find.text('Registrar Mascota'), findsOneWidget);
    expect(find.text('Nombre de la mascota'), findsOneWidget);
    expect(find.text('Especie'), findsOneWidget);
    expect(find.text('Fecha de nacimiento'), findsOneWidget);
    expect(find.text('Peso (kg)'), findsOneWidget);
    expect(find.text('Guardar Mascota'), findsOneWidget);
  });
}
