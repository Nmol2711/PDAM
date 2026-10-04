import 'dart:io';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_pet.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:isar/isar.dart';

abstract class LocalPetDatasource {
  Future<List<Pet>> getLocalPets();
  Future<void> cachePets(List<Pet> pets);
  Future<void> saveLocalPet(Pet pet, {bool isSynced = true});
  Future<void> deleteLocalPet(int petId);
}

class LocalPetDatasourceImpl implements LocalPetDatasource {
  final String? testDirectory;

  LocalPetDatasourceImpl({this.testDirectory});

  Future<Isar> _getIsar() async {
    return await IsarService.init(directory: testDirectory);
  }

  @override
  Future<List<Pet>> getLocalPets() async {
    final isar = await _getIsar();
    final localPets = await isar.localPets.where().findAll();
    return localPets.map((lp) => _mapLocalToEntity(lp)).toList();
  }

  @override
  Future<void> cachePets(List<Pet> pets) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      for (final pet in pets) {
        final existing = await isar.localPets.filter().remoteIdEqualTo(pet.id).findFirst();
        final local = existing ?? LocalPet();
        local.remoteId = pet.id;
        local.userId = 'default_user';
        local.name = pet.name;
        local.species = pet.species.name;
        local.birthDate = pet.birthDate.toIso8601String().split('T').first;
        local.weight = pet.weight;
        local.reproductiveStatus = pet.reproductiveStatus;
        local.pathUrl = pet.imgUrl;
        local.updatedAt = DateTime.now();
        local.isSynced = true;
        await isar.localPets.put(local);
      }
    });
  }

  @override
  Future<void> saveLocalPet(Pet pet, {bool isSynced = true}) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      final existing = await isar.localPets.filter().remoteIdEqualTo(pet.id).findFirst();
      final local = existing ?? LocalPet();
      local.remoteId = pet.id > 0 ? pet.id : null;
      local.userId = 'default_user';
      local.name = pet.name;
      local.species = pet.species.name;
      local.birthDate = pet.birthDate.toIso8601String().split('T').first;
      local.weight = pet.weight;
      local.reproductiveStatus = pet.reproductiveStatus;
      local.pathUrl = pet.imgUrl;
      local.updatedAt = DateTime.now();
      local.isSynced = isSynced;
      await isar.localPets.put(local);
    });
  }

  @override
  Future<void> deleteLocalPet(int petId) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      final existing = await isar.localPets.filter().remoteIdEqualTo(petId).findFirst();
      if (existing != null) {
        await isar.localPets.delete(existing.id);
      } else {
        await isar.localPets.delete(petId);
      }
    });
  }

  Pet _mapLocalToEntity(LocalPet lp) {
    TypePest speciesEnum = TypePest.canino;
    try {
      speciesEnum = TypePest.values.byName(lp.species.toLowerCase());
    } catch (_) {}

    return Pet(
      id: lp.remoteId ?? lp.id,
      name: lp.name,
      species: speciesEnum,
      birthDate: DateTime.tryParse(lp.birthDate) ?? DateTime.now(),
      weight: lp.weight,
      reproductiveStatus: lp.reproductiveStatus,
      imgUrl: lp.pathUrl,
    );
  }
}
