/// Función pura para la resolución de conflictos de sincronización (RF-04).
/// Compara objetos locales y remotos considerando un umbral de desfase de reloj (clock drift)
/// de 5 minutos (300,000 ms) y aplicando prioridad al servidor (remoto) si se supera o hay colisión.
Map<String, dynamic> resolveConflict(
  Map<String, dynamic> localItem,
  Map<String, dynamic> remoteItem, {
  int clockDriftThresholdMs = 300000,
}) {
  final localTime = (localItem['updated_at'] as num?)?.toDouble() ?? 0.0;
  final remoteTime = (remoteItem['updated_at'] as num?)?.toDouble() ?? 0.0;

  final drift = (localTime - remoteTime).abs();

  if (drift <= clockDriftThresholdMs) {
    if (localTime > remoteTime) {
      return localItem;
    } else {
      return remoteItem;
    }
  } else {
    // Supera el umbral de 5 minutos -> Prioridad estricta al servidor (remoto)
    return remoteItem;
  }
}
