import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class StorageService {
  Future<Either<Failures, void>> saveString(String key, String value);
  Future<Either<Failures, String?>> getString(String key);
  Future<Either<Failures, void>> deleteString(String key);
}

class StorageServiceImpl implements StorageService {
  final FlutterSecureStorage _dataLocalService;

  StorageServiceImpl({required FlutterSecureStorage dataLocalService})
    : _dataLocalService = dataLocalService;

  @override
  Future<Either<Failures, void>> deleteString(String key) async {
    try {
      await _dataLocalService.delete(key: key);
      return const Right(null);
    } catch (e) {
      return Left(LocalStorageFailures(e.toString()));
    }
  }

  @override
  Future<Either<Failures, String?>> getString(String key) async {
    try {
      final String? value = await _dataLocalService.read(key: key);
      return Right(value);
    } catch (e) {
      return Left(LocalStorageFailures(e.toString()));
    }
  }

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async {
    try {
      await _dataLocalService.write(key: key, value: value);
      return const Right(null);
    } catch (e) {
      return Left(LocalStorageFailures(e.toString()));
    }
  }
}
