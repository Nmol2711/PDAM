import 'package:app_movil_pdam/core/constant/token_constant.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';

/// Marca de baja pendiente en el almacenamiento cifrado del dispositivo.
///
/// Se escribe antes de intentar la limpieza local de la baja y solo se borra
/// cuando esa limpieza termina (RNF-10). Sobrevive al reinicio y a la limpieza
/// de Isar, y es lo que impide el acceso sin conexión con las credenciales de
/// una cuenta eliminada. Vive en `flutter_secure_storage` a través de
/// [StorageService] (principio 5).
abstract class PendingDeletionStore {
  /// Escribe la marca. Lanza si el almacenamiento no responde.
  Future<void> markPending();

  /// Indica si la marca existe. Un fallo de lectura se trata como ausencia:
  /// solo un valor escrito de forma explícita bloquea el acceso.
  Future<bool> isPending();

  /// Borra la marca al completar la limpieza. Lanza si no se pudo borrar.
  Future<void> clear();
}

class PendingDeletionStoreImpl implements PendingDeletionStore {
  /// Valor almacenado cuando la marca está activa.
  static const String _valorActivo = 'true';

  final StorageService _storageService;

  PendingDeletionStoreImpl({required StorageService storageService})
    : _storageService = storageService;

  @override
  Future<void> markPending() async {
    final resultado = await _storageService.saveString(
      TokenConstant.keyPendingDeletion,
      _valorActivo,
    );
    resultado.fold(
      (fallo) => throw Exception(
        'No se pudo escribir la marca de baja pendiente: ${fallo.message}',
      ),
      (_) => null,
    );
  }

  @override
  Future<bool> isPending() async {
    final resultado = await _storageService.getString(
      TokenConstant.keyPendingDeletion,
    );
    return resultado.fold((_) => false, (valor) => valor == _valorActivo);
  }

  @override
  Future<void> clear() async {
    final resultado = await _storageService.deleteString(
      TokenConstant.keyPendingDeletion,
    );
    resultado.fold(
      (fallo) => throw Exception(
        'No se pudo borrar la marca de baja pendiente: ${fallo.message}',
      ),
      (_) => null,
    );
  }
}
