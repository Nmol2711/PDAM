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
    int age,
    double weight,
    File? imageFile,
  );
  Future<Pet> getPet(int petId);
  Future<List<Pet>> getPets();
  Future<Pet> updatePet(
    int petId, {
    String? name,
    TypePest? species,
    int? age,
    double? weight,
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
    int age,
    double weight,
    File? imageFile,
  ) async {
    try {
      final Map<String, dynamic> formDataMap = {
        'name': name,
        'species': species.name,
        'age': age
            .toString(), // FastAPI lee los campos Form como strings o números nativos
        'weight': weight.toString(),
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
      final response = await _dioClient.dio.get('${ApiConstants.pet}/$id');
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
    int? age,
    double? weight,
    File? imageFile,
  }) async {
    try {
      final response = await _dioClient.dio.put(
        '${ApiConstants.pet}/$petId',
        data: {
          'name': name,
          'species': species,
          'age': age,
          'weight': weight,
          "file": imageFile,
        },
      );
      return PetModel.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(
        e.message ?? "Error con el servidor al interar actualizar la mascota",
      );
    }
  }

  @override
  Future<bool> deletePet(int petId) async {
    try {
      final response = await _dioClient.dio.delete(
        '${ApiConstants.pet}/$petId',
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
