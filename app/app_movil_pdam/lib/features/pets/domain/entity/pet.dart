import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';

class Pet {
  final int id;
  final String name;
  final TypePest species;
  final int age;
  final double weight;
  final String? imgUrl;

  const Pet({
    required this.id,
    required this.name,
    required this.species,
    required this.age,
    required this.weight,
    this.imgUrl,
  });
}
