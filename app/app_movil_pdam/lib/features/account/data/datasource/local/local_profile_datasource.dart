import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_profile.dart';
import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:isar/isar.dart';

/// Perfil cacheado real en Isar (RF-07, RF-08, RF-10).
///
/// Solo escribe lo que devuelve el servidor. El dispositivo mantiene un único
/// perfil vigente: al guardar un correo nuevo, el anterior se sustituye para
/// que un cambio de correo no deje dos filas y se muestre la obsoleta.
abstract class LocalProfileDatasource {
  Future<UserProfile?> getCachedProfile();

  Future<void> saveProfile(UserProfile profile);

  Future<void> deleteProfile(String correoNormalizado);
}

class LocalProfileDatasourceImpl implements LocalProfileDatasource {
  final String? testDirectory;

  LocalProfileDatasourceImpl({this.testDirectory});

  Future<Isar> _getIsar() async {
    return await IsarService.init(directory: testDirectory);
  }

  @override
  Future<UserProfile?> getCachedProfile() async {
    final isar = await _getIsar();
    final fila = await isar.localProfiles.where().findFirst();
    if (fila == null) return null;
    return UserProfile(email: fila.email, isActive: fila.isActive);
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    final isar = await _getIsar();
    final clave = normalizarCorreo(profile.email);

    await isar.writeTxn(() async {
      // Un solo perfil por dispositivo: si el correo cambió, la fila anterior
      // deja de ser válida.
      await isar.localProfiles.clear();
      final fila = LocalProfile()
        ..accountKey = clave
        ..email = clave
        ..isActive = profile.isActive
        ..updatedAt = DateTime.now();
      await isar.localProfiles.put(fila);
    });
  }

  @override
  Future<void> deleteProfile(String correoNormalizado) async {
    final isar = await _getIsar();
    final clave = normalizarCorreo(correoNormalizado);

    await isar.writeTxn(() async {
      final fila = await isar.localProfiles
          .filter()
          .accountKeyEqualTo(clave)
          .findFirst();
      if (fila != null) {
        await isar.localProfiles.delete(fila.id);
      }
    });
  }
}
