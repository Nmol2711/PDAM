import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_pet.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:isar/isar.dart';

abstract class LocalPetDatasource {
  Future<List<Pet>> getLocalPets();
  Future<void> cachePets(List<Pet> pets);
  Future<void> saveLocalPet(Pet pet, {bool isSynced = true});
}

class LocalPetDatasourceImpl implements LocalPetDatasource {
  @override
  Future<List<Pet>> getLocalPets() async {
    final isar = await IsarService.init();
    final localPets = await isar.localPets.where().findAll();
    return localPets.map((lp) => _mapLocalToEntity(lp)).toList();
  }

  @override
  Future<void> cachePets(List<Pet> pets) async {
    final isar = await IsarService.init();
    await isar.writeTxn(() async {
      for (final pet in pets) {
        final existing = await isar.localPets.filter().remoteIdEqualTo(pet.id).findFirst();
        final local = existing ?? LocalPet();
        local.remoteId = pet.id;
        local.userId = 'default_user'; // O ID del usuario actual
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
    final isar = await IsarService.init();
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
