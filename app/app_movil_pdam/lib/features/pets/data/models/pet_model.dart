import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';

class PetModel extends Pet {
  const PetModel({
    required super.id,
    required super.name,
    required super.species,
    required super.birthDate,
    required super.weight,
    required super.reproductiveStatus,
    super.imgUrl,
  });

  factory PetModel.fromJson(Map<String, dynamic> json) {
    final TypePest species = TypePest.values.firstWhere(
      (e) => e.name == json['species'],
      orElse: () => TypePest.otros,
    );

    final String? imgUrl = (json['path_url'] != null)
        ? "${ApiConstants.baseUrl}${json['path_url']}"
        : null;

    return PetModel(
      id: json['id'],
      name: json['name'],
      species: species,
      birthDate: DateTime.parse(json['birth_date']),
      weight: json['weight'],
      reproductiveStatus: json['reproductive_status'] ?? false,
      imgUrl: imgUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'species': species.name,
      'birth_date': birthDate.toIso8601String().split('T').first,
      'weight': weight,
      'reproductive_status': reproductiveStatus,
    };
  }
}
