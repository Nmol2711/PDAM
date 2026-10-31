import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
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
import 'package:app_movil_pdam/features/pets/presentation/widget/pet_item.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePetsRepository implements PetsRepositories {
  _FakePetsRepository({this.pets = const <Pet>[]});

  final List<Pet> pets;

  @override
  Future<Either<Failures, List<Pet>>> getPets() async => Right(pets);

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
  Future<PetBloc> petBloc() async {
    final repository = _FakePetsRepository();
    final bloc = PetBloc(
      cretePetUc: CreatePetUc(repository: repository),
      getPetUc: GetPetUc(repository: repository),
      getPetsUc: GetPetsUc(repository: repository),
      updatePetUc: UpdatePetUc(repository: repository),
      deletePetUc: DeletePetsUc(repository: repository),
    );
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> pumpPets(WidgetTester tester) async {
    final bloc = await petBloc();
    await tester.pumpWidget(
      BlocProvider<PetBloc>.value(
        value: bloc,
        child: MaterialApp(theme: AppTheme.lightTheme, home: const PetsView()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('RF-09: la lista de mascotas usa gutter 16 y 24', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final caso in <({double ancho, double gutter})>[
      (ancho: 400, gutter: AppSpacing.page),
      (ancho: 800, gutter: AppSpacing.pageWide),
    ]) {
      tester.view.physicalSize = Size(caso.ancho, 900);
      tester.view.devicePixelRatio = 1.0;

      final repository = _FakePetsRepository(pets: <Pet>[_mascota]);
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
            home: const PetsView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final tarjeta = tester.widget<Card>(find.byType(Card).first);
      expect(
        tarjeta.margin,
        EdgeInsets.symmetric(horizontal: caso.gutter, vertical: AppSpacing.sm),
        reason: 'ancho ${caso.ancho}',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });

  testWidgets('RF-08: el botón flotante de mascotas usa el radio 8', (
    tester,
  ) async {
    await pumpPets(tester);

    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.shape, isNull, reason: 'el FAB no debe llevar forma local');

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(FloatingActionButton),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      material.shape,
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  });

  testWidgets('RF-07 y RF-08: la tarjeta de mascota usa el tema', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: PetItem(pet: _mascota)),
      ),
    );
    final esquema = AppTheme.lightTheme.colorScheme;

    final card = tester.widget<Card>(find.byType(Card));
    expect(card.elevation, isNull);

    final material = tester.widget<Material>(
      find
          .descendant(of: find.byType(Card), matching: find.byType(Material))
          .first,
    );
    expect(material.color, esquema.surface);
    expect(material.elevation, 0);
    final forma = material.shape! as RoundedRectangleBorder;
    expect(forma.borderRadius, BorderRadius.circular(8));
    expect(forma.side.color, esquema.outline);

    final apoyo = tester.widget<Text>(find.text('Peso: 4.5 kg'));
    expect(apoyo.style?.color, esquema.onSurfaceVariant);
  });

  test('RF-03: la presentación de mascotas no conserva literales de color ni '
      'radios', () {
    final archivos = <File>[
      ...Directory('lib/features/pets/presentation')
          .listSync(recursive: true)
          .whereType<File>()
          .where((archivo) => archivo.path.endsWith('.dart')),
    ];
    expect(archivos, isNotEmpty);

    for (final archivo in archivos) {
      final codigo = archivo.readAsStringSync();
      expect(
        RegExp(r'\bColors\.(?!transparent)').hasMatch(codigo),
        isFalse,
        reason: '${archivo.path} usa Colors.*',
      );
      expect(
        RegExp(r'Color\(0x').hasMatch(codigo),
        isFalse,
        reason: '${archivo.path} declara un HEX literal',
      );
      expect(
        RegExp(r'BorderRadius\.circular\(\s*\d').hasMatch(codigo),
        isFalse,
        reason: '${archivo.path} declara un radio literal',
      );
      expect(
        RegExp(r'Radius\.circular\(\s*\d').hasMatch(codigo),
        isFalse,
        reason: '${archivo.path} declara un radio literal',
      );
    }
  });
}
