import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/offline/sync_conflict_resolver.dart';

void main() {
  group('resolveConflict pure function tests (RF-04)', () {
    test('debe seleccionar el registro local si es más nuevo y el drift es menor al umbral (<= 5 min)', () {
      final local = {'id': '1', 'updated_at': 1710000120000.0, 'version': 'local'}; // +2 min
      final remote = {'id': '1', 'updated_at': 1710000000000.0, 'version': 'remote'};

      final winner = resolveConflict(local, remote);
      expect(winner['version'], 'local');
    });

    test('debe seleccionar el registro remoto si es más nuevo y el drift es menor al umbral (<= 5 min)', () {
      final local = {'id': '1', 'updated_at': 1710000000000.0, 'version': 'local'};
      final remote = {'id': '1', 'updated_at': 1710000120000.0, 'version': 'remote'}; // +2 min

      final winner = resolveConflict(local, remote);
      expect(winner['version'], 'remote');
    });

    test('debe priorizar el registro remoto si el drift supera el umbral de 5 minutos (> 300000 ms)', () {
      final local = {'id': '1', 'updated_at': 1710006000000.0, 'version': 'local'}; // +10 min
      final remote = {'id': '1', 'updated_at': 1710000000000.0, 'version': 'remote'};

      final winner = resolveConflict(local, remote);
      expect(winner['version'], 'remote');
    });
  });
}
