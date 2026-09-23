import 'dart:io';

import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';

import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/features/pets/data/models/pet_model.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:dartz/dartz.dart';

import 'package:dio/dio.dart';

abstract class PetRemoteDatasource {
  Future<Pet> createPet(
    String name,
    TypePest species,
    DateTime birthDate,
    double weight,
    bool reproductiveStatus,
    File? imageFile,
  );
  Future<Pet> getPet(int petId);
  Future<List<Pet>> getPets();
  Future<Pet> updatePet(
    int petId, {
    String? name,
    TypePest? species,
    DateTime? birthDate,
    double? weight,
    bool? reproductiveStatus,
    File? imageFile,
  });
  Future<bool> deletePet(int petId);
}

class PetRemoteDatasourceImpl implements PetRemoteDatasource {
  final DioClient _dioClient;

  PetRemoteDatasourceImpl({required DioClient dioClient})
    : _dioClient = dioClient;

  @override
  Future<Pet> createPet(
    String name,
    TypePest species,
    DateTime birthDate,
    double weight,
    bool reproductiveStatus,
    File? imageFile,
  ) async {
    try {
      final Map<String, dynamic> formDataMap = {
        'name': name,
        'species': species.name,
        'birth_date': birthDate.toIso8601String().split('T').first,
        'weight': weight.toString(),
        'reproductive_status': reproductiveStatus.toString(),
      };

      if (imageFile != null) {
        formDataMap['file'] = await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split('/').last,
        );
      }

      final fromData = FormData.fromMap(formDataMap);

      final response = await _dioClient.dio.post(
        ApiConstants.pet,
        data: fromData,
        options: Options(
          contentType: 'multipart/form-data', // Indispensable para archivos
        ),
      );
      return PetModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(
        e.message ?? 'Error con el servidor al registra la mascota',
      );
    }
  }

  @override
  Future<Pet> getPet(int petId) async {
    try {
      final response = await _dioClient.dio.get('${ApiConstants.pet}$petId');
      return PetModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(
        e.message ?? 'Error con el servidor al obtener la mascota',
      );
    }
  }

  @override
  Future<List<Pet>> getPets() async {
    try {
      final response = await _dioClient.dio.get(ApiConstants.pet);

      return (response.data as List)
          .map((e) => PetModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw Exception(
        e.message ?? 'Error con el servidor al obtener las mascota',
      );
    }
  }

  @override
  Future<Pet> updatePet(
    int petId, {
    String? name,
    TypePest? species,
    DateTime? birthDate,
    double? weight,
    bool? reproductiveStatus,
    File? imageFile,
  }) async {
    try {
      final Map<String, dynamic> formDataMap = {};
      if (name != null) formDataMap['name'] = name;
      if (species != null) formDataMap['species'] = species.name;
      if (birthDate != null) {
        formDataMap['birth_date'] = birthDate.toIso8601String().split('T').first;
      }
      if (weight != null) formDataMap['weight'] = weight.toString();
      if (reproductiveStatus != null) {
        formDataMap['reproductive_status'] = reproductiveStatus.toString();
      }

      if (imageFile != null) {
        formDataMap['file'] = await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split('/').last,
        );
      }

      final formData = FormData.fromMap(formDataMap);

      final response = await _dioClient.dio.put(
        '${ApiConstants.pet}$petId',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
        ),
      );
      return PetModel.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(
        e.message ?? "Error con el servidor al intentar actualizar la mascota",
      );
    }
  }

  @override
  Future<bool> deletePet(int petId) async {
    try {
      final response = await _dioClient.dio.delete(
        '${ApiConstants.pet}$petId',
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        return false;
      }
    } on DioException catch (e) {
      throw Exception(
        e.message ?? "Error con el servidor al eliminar la mascota",
      );
    }
  }
}
