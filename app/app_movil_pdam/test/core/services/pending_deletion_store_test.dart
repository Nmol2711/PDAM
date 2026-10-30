import 'package:app_movil_pdam/core/constant/token_constant.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

/// Almacenamiento cifrado simulado que registra escrituras y borrados.
class _FakeStorage implements StorageService {
  final Map<String, String> valores;
  final List<String> borradas = [];
  bool fallarAlGuardar = false;
  bool fallarAlLeer = false;
  bool fallarAlBorrar = false;

  _FakeStorage({Map<String, String>? valores}) : valores = {...?valores};

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async {
    if (fallarAlGuardar) {
      return Left(LocalStorageFailures('fallo de almacenamiento'));
    }
    valores[key] = value;
    return const Right(null);
  }

  @override
  Future<Either<Failures, String?>> getString(String key) async {
    if (fallarAlLeer) {
      return Left(LocalStorageFailures('fallo de almacenamiento'));
    }
    return Right(valores[key]);
  }

  @override
  Future<Either<Failures, void>> deleteString(String key) async {
    if (fallarAlBorrar) {
      return Left(LocalStorageFailures('fallo de almacenamiento'));
    }
    valores.remove(key);
    borradas.add(key);
    return const Right(null);
  }
}

void main() {
  late _FakeStorage storage;
  late PendingDeletionStoreImpl store;

  setUp(() {
    storage = _FakeStorage();
    store = PendingDeletionStoreImpl(storageService: storage);
  });

  group('PendingDeletionStoreImpl (RNF-10)', () {
    test('marca la baja pendiente en la clave reservada', () async {
      await store.markPending();

      expect(storage.valores[TokenConstant.keyPendingDeletion], 'true');
    });

    test('sin marca escrita no hay baja pendiente', () async {
      expect(await store.isPending(), isFalse);
    });

    test('con la marca escrita la baja está pendiente', () async {
      await store.markPending();

      expect(await store.isPending(), isTrue);
    });

    test('un valor distinto del activo no cuenta como marca', () async {
      storage.valores[TokenConstant.keyPendingDeletion] = 'otro';

      expect(await store.isPending(), isFalse);
    });

    test('un fallo de lectura se trata como ausencia de marca', () async {
      storage.fallarAlLeer = true;

      expect(await store.isPending(), isFalse);
    });

    test('borrar la marca la retira del almacenamiento', () async {
      await store.markPending();

      await store.clear();

      expect(storage.borradas, [TokenConstant.keyPendingDeletion]);
      expect(
        storage.valores.containsKey(TokenConstant.keyPendingDeletion),
        isFalse,
      );
      expect(await store.isPending(), isFalse);
    });

    test('si el almacenamiento no puede escribir, la marca lanza', () async {
      storage.fallarAlGuardar = true;

      await expectLater(store.markPending(), throwsException);
    });

    test('si el almacenamiento no puede borrar, clear lanza', () async {
      await store.markPending();
      storage.fallarAlBorrar = true;

      await expectLater(store.clear(), throwsException);
      expect(
        storage.valores.containsKey(TokenConstant.keyPendingDeletion),
        isTrue,
      );
    });
  });
}
