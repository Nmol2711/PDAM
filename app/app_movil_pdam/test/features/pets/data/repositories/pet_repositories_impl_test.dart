import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/remote/pet_remote_datasource.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_pet_datasource.dart';
import 'package:app_movil_pdam/features/pets/data/repository_impl/pet_repositories_impl.dart';

class MockPetRemoteDatasource implements PetRemoteDatasource {
  bool shouldThrow = false;
  Pet? mockPet;
  List<Pet> mockPets = [];

  @override
  Future<Pet> createPet(String name, TypePest species, DateTime birthDate, double weight, bool reproductiveStatus, File? imageFile) async {
    if (shouldThrow) throw Exception('Server offline');
    return mockPet ?? Pet(id: 1, name: name, species: species, birthDate: birthDate, weight: weight, reproductiveStatus: reproductiveStatus);
  }

  @override
  Future<bool> deletePet(int petId) async {
    if (shouldThrow) throw Exception('Server offline');
    return true;
  }

  @override
  Future<Pet> getPet(int petId) async {
    if (shouldThrow) throw Exception('Server offline');
    return mockPet ?? Pet(id: petId, name: 'Test Pet', species: TypePest.canino, birthDate: DateTime(2020, 1, 1), weight: 10.0, reproductiveStatus: true);
  }

  @override
  Future<List<Pet>> getPets() async {
    if (shouldThrow) throw Exception('Server offline');
    return mockPets;
  }

  @override
  Future<Pet> updatePet(int petId, {String? name, TypePest? species, DateTime? birthDate, double? weight, bool? reproductiveStatus, File? imageFile}) async {
    if (shouldThrow) throw Exception('Server offline');
    return mockPet ?? Pet(id: petId, name: name ?? 'Updated', species: species ?? TypePest.canino, birthDate: birthDate ?? DateTime(2020, 1, 1), weight: weight ?? 10.0, reproductiveStatus: reproductiveStatus ?? true);
  }
}

class MockLocalPetDatasource implements LocalPetDatasource {
  List<Pet> localPets = [];
  bool savedSynced = true;

  @override
  Future<void> cachePets(List<Pet> pets) async {
    localPets = List.from(pets);
  }

  @override
  Future<void> deleteLocalPet(int petId) async {
    localPets.removeWhere((p) => p.id == petId);
  }

  @override
  Future<List<Pet>> getLocalPets() async {
    return localPets;
  }

  @override
  Future<void> saveLocalPet(Pet pet, {bool isSynced = true}) async {
    savedSynced = isSynced;
    final index = localPets.indexWhere((p) => p.id == pet.id);
    if (index >= 0) {
      localPets[index] = pet;
    } else {
      localPets.add(pet);
    }
  }
}

void main() {
  late PetRepositoriesImpl repository;
  late MockPetRemoteDatasource remoteDatasource;
  late MockLocalPetDatasource localDatasource;

  setUp(() {
    remoteDatasource = MockPetRemoteDatasource();
    localDatasource = MockLocalPetDatasource();
    repository = PetRepositoriesImpl(
      petRemoteDataosurce: remoteDatasource,
      localPetDatasource: localDatasource,
    );
  });

  test('getPets debe retornar datos remotos y cachearlos cuando hay red', () async {
    remoteDatasource.mockPets = [
      Pet(id: 1, name: 'Firulais', species: TypePest.canino, birthDate: DateTime(2020, 1, 1), weight: 12.0, reproductiveStatus: true)
    ];

    final result = await repository.getPets();

    expect(result.isRight(), true);
    result.fold(
      (l) => fail('No debería fallar'),
      (pets) => expect(pets.length, 1),
    );
  });

  test('getPets debe hacer fallback local cuando falla la red', () async {
    localDatasource.localPets = [
      Pet(id: 2, name: 'Local Dog', species: TypePest.canino, birthDate: DateTime(2021, 1, 1), weight: 8.0, reproductiveStatus: false)
    ];
    remoteDatasource.shouldThrow = true;

    final result = await repository.getPets();

    expect(result.isRight(), true);
    result.fold(
      (l) => fail('No debería fallar'),
      (pets) {
        expect(pets.length, 1);
        expect(pets.first.name, 'Local Dog');
      },
    );
  });

  test('createPet offline debe guardar localmente con isSynced false', () async {
    remoteDatasource.shouldThrow = true;

    final result = await repository.createPet(
      'Offline Pet',
      TypePest.felino,
      DateTime(2022, 1, 1),
      4.5,
      true,
      null,
    );

    expect(result.isRight(), true);
    expect(localDatasource.savedSynced, false);
    expect(localDatasource.localPets.length, 1);
  });
}
