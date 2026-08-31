import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';

class PetModel extends Pet {
  const PetModel({
    required super.id,
    required super.name,
    required super.species,
    required super.age,
    required super.weight,
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
      age: json['age'],
      weight: json['weight'],
      imgUrl: imgUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'spcies': species};
  }
}
