import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';

void main() {
  group('IsarService Exception Detection and Recovery Tests (RNF-02, RNF-03)', () {
    test('debe detectar correctamente excepciones de espacio de almacenamiento agotado', () {
      final ex1 = Exception('Disk full: no space left on device');
      final ex2 = Exception('Error: storage is full (ENOSPC)');
      final ex3 = Exception('Normal network error');

      expect(IsarService.isIsarStorageFullException(ex1), isTrue);
      expect(IsarService.isIsarStorageFullException(ex2), isTrue);
      expect(IsarService.isIsarStorageFullException(ex3), isFalse);
    });

    test('debe detectar correctamente excepciones de corrupción o fallo de migración de Isar', () {
      final ex1 = Exception('IsarError: Database corrupted or invalid magic number');
      final ex2 = Exception('Migration failed: schema version mismatch');
      final ex3 = Exception('Some other runtime error');

      expect(IsarService.isIsarCorruptionException(ex1), isTrue);
      expect(IsarService.isIsarCorruptionException(ex2), isTrue);
      expect(IsarService.isIsarCorruptionException(ex3), isFalse);
    });
  });
}
