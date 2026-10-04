import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_pet_datasource.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:isar/isar.dart';

void main() {
  late Directory tempDir;
  late LocalPetDatasource datasource;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore();
      final warmupDir = await Directory.systemTemp.createTemp('isar_warmup_');
      await IsarService.init(directory: warmupDir.path);
      await warmupDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_test_');
    datasource = LocalPetDatasourceImpl(testDirectory: tempDir.path);
  });

  tearDown(() async {
    try {
      final isar = await IsarService.init(directory: tempDir.path);
      await isar.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalPetDatasource Tests (RF-01, RF-02, RNF-02)', () {
    test('getLocalPets debe retornar lista vacía inicialmente', () async {
      final stopwatch = Stopwatch()..start();
      final pets = await datasource.getLocalPets();
      stopwatch.stop();

      expect(pets, isEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(100));
    });

    test('saveLocalPet y getLocalPets deben guardar y recuperar mascota en <= 100 ms', () async {
      final pet = Pet(
        id: 1,
        name: 'Firulais',
        species: TypePest.canino,
        birthDate: DateTime(2020, 1, 1),
        weight: 12.5,
        reproductiveStatus: true,
        imgUrl: 'http://example.com/img.jpg',
      );

      final saveWatch = Stopwatch()..start();
      await datasource.saveLocalPet(pet, isSynced: true);
      saveWatch.stop();
      expect(saveWatch.elapsedMilliseconds, lessThanOrEqualTo(100));

      final getWatch = Stopwatch()..start();
      final pets = await datasource.getLocalPets();
      getWatch.stop();
      expect(getWatch.elapsedMilliseconds, lessThanOrEqualTo(100));

      expect(pets.length, 1);
      expect(pets.first.name, 'Firulais');
      expect(pets.first.weight, 12.5);
    });

    test('cachePets debe guardar múltiples mascotas de forma atómica en <= 100 ms', () async {
      final pets = [
        Pet(
          id: 10,
          name: 'Luna',
          species: TypePest.felino,
          birthDate: DateTime(2021, 5, 10),
          weight: 4.2,
          reproductiveStatus: false,
        ),
        Pet(
          id: 11,
          name: 'Max',
          species: TypePest.canino,
          birthDate: DateTime(2019, 3, 15),
          weight: 20.0,
          reproductiveStatus: true,
        ),
      ];

      final stopwatch = Stopwatch()..start();
      await datasource.cachePets(pets);
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(100));

      final cached = await datasource.getLocalPets();
      expect(cached.length, 2);
      expect(cached.any((p) => p.name == 'Luna'), isTrue);
      expect(cached.any((p) => p.name == 'Max'), isTrue);
    });

    test('deleteLocalPet debe eliminar mascota correctamente', () async {
      final pet = Pet(
        id: 5,
        name: 'Rocky',
        species: TypePest.canino,
        birthDate: DateTime(2022, 1, 1),
        weight: 15.0,
        reproductiveStatus: true,
      );

      await datasource.saveLocalPet(pet);
      var pets = await datasource.getLocalPets();
      expect(pets.length, 1);

      await datasource.deleteLocalPet(5);
      pets = await datasource.getLocalPets();
      expect(pets, isEmpty);
    });
  });
}
