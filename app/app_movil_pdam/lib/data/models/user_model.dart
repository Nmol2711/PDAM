import 'package:app_movil_pdam/domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  UserModel({required super.id, required super.gmail, required super.isActive});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      gmail: json['gmail'],
      isActive: json['isActive'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['gmail'] = gmail;
    data['isActive'] = isActive;
    return data;
  }
}
