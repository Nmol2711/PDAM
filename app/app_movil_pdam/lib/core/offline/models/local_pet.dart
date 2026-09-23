import 'package:isar/isar.dart';

part 'local_pet.g.dart';

@collection
class LocalPet {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  int? remoteId;

  late String userId;

  late String name;
  late String species;
  late String birthDate;
  late double weight;
  late bool reproductiveStatus;
  String? pathUrl;

  late DateTime updatedAt;
  late bool isSynced;
}
