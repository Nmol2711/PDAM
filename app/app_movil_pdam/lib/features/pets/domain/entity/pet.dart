import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';

class Pet {
  final int id;
  final String name;
  final TypePest species;
  final DateTime birthDate;
  final double weight;
  final bool reproductiveStatus;
  final String? imgUrl;

  const Pet({
    required this.id,
    required this.name,
    required this.species,
    required this.birthDate,
    required this.weight,
    required this.reproductiveStatus,
    this.imgUrl,
  });

  int get age {
    final now = DateTime.now();
    int ageYears = now.year - birthDate.year;
    if (now.month < birthDate.month || (now.month == birthDate.month && now.day < birthDate.day)) {
      ageYears--;
    }
    return ageYears < 0 ? 0 : ageYears;
  }
}
