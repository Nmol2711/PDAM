import 'dart:io';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app_movil_pdam/core/offline/models/local_pet.dart';
import 'package:app_movil_pdam/core/offline/models/local_schedule.dart';
import 'package:app_movil_pdam/core/offline/models/local_log.dart';
import 'package:app_movil_pdam/core/offline/models/local_dispenser.dart';
import 'package:app_movil_pdam/core/offline/models/local_profile.dart';

class IsarService {
  static Isar? _isarInstance;
  static String? _currentDirectory;

  static bool isIsarStorageFullException(Object exception) {
    final message = exception.toString().toLowerCase();
    return message.contains('full') ||
        message.contains('space') ||
        message.contains('enospc') ||
        message.contains('disk');
  }

  static bool isIsarCorruptionException(Object exception) {
    final message = exception.toString().toLowerCase();
    return message.contains('corrupt') ||
        message.contains('isarerror') ||
        message.contains('migration') ||
        message.contains('schema') ||
        message.contains('invalid') ||
        message.contains('version') ||
        message.contains('bad state');
  }

  static Future<void> close() async {
    _currentDirectory = null;
    if (_isarInstance != null) {
      try {
        if (_isarInstance!.isOpen) {
          await _isarInstance!.close();
        }
      } catch (_) {}
      _isarInstance = null;
    }
  }

  static Future<Isar> init({String? directory}) async {
    final dir = directory != null
        ? Directory(directory)
        : await getApplicationDocumentsDirectory();
    if (_isarInstance != null && _isarInstance!.isOpen) {
      if (_currentDirectory != dir.path) {
        await close();
      } else {
        return _isarInstance!;
      }
    }

    try {
      _currentDirectory = dir.path;
      _isarInstance = await Isar.open(
        [
          LocalPetSchema,
          LocalScheduleSchema,
          LocalLogSchema,
          LocalDispenserSchema,
          LocalProfileSchema,
        ],
        directory: dir.path,
        inspector: true,
      );
      return _isarInstance!;
    } catch (e) {
      if (isIsarCorruptionException(e)) {
        try {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
            await dir.create(recursive: true);
          }
          _currentDirectory = dir.path;
          _isarInstance = await Isar.open(
            [
              LocalPetSchema,
              LocalScheduleSchema,
              LocalLogSchema,
              LocalDispenserSchema,
              LocalProfileSchema,
            ],
            directory: dir.path,
            inspector: true,
          );
          return _isarInstance!;
        } catch (recoveryError) {
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  static Isar get db {
    if (_isarInstance == null || !_isarInstance!.isOpen) {
      throw Exception(
        'Isar no ha sido inicializado. Llama a IsarService.init() primero.',
      );
    }
    return _isarInstance!;
  }

  static Future<void> clearAllData() async {
    final isar = await init();
    await isar.writeTxn(() async {
      await isar.clear();
    });
  }
}
