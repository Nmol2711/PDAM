import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';

/*
  Los models se encargan de convertir JSON => Entity 
  y tambien de Entity => JSON

  Tambien se puede encargar de  Model => Entity y de Entity => Model
 */

class UserModel extends User {
  UserModel({required super.id, required super.email});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(id: json['id'], email: json['email']);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'email': email};
  }
}
