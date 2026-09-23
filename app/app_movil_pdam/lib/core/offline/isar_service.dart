import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app_movil_pdam/core/offline/models/local_pet.dart';
import 'package:app_movil_pdam/core/offline/models/local_schedule.dart';
import 'package:app_movil_pdam/core/offline/models/local_log.dart';

class IsarService {
  static Isar? _isarInstance;

  static Future<Isar> init() async {
    if (_isarInstance != null && _isarInstance!.isOpen) {
      return _isarInstance!;
    }
    final dir = await getApplicationDocumentsDirectory();
    _isarInstance = await Isar.open(
      [LocalPetSchema, LocalScheduleSchema, LocalLogSchema],
      directory: dir.path,
      inspector: true,
    );
    return _isarInstance!;
  }

  static Isar get db {
    if (_isarInstance == null || !_isarInstance!.isOpen) {
      throw Exception('Isar no ha sido inicializado. Llama a IsarService.init() primero.');
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
