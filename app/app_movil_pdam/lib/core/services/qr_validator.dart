class QrValidator {
  // Expresión regular limpia para 6 bloques de dos caracteres hexadecimales
  static final RegExp _macRegex = RegExp(
    r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$',
  );

  static Map<String, String?> processQrCode(String qrRawValue) {
    // 1. Limpiamos espacios o saltos de línea iniciales/finales del QR crudo
    final cleanRawValue = qrRawValue.trim();

    // 2. Dividimos el contenido por el carácter '|'
    final parts = cleanRawValue.split('|');

    if (parts.length != 2) {
      return {'mac_address': null, 'secret_key_qr': null};
    }

    // 3. Limpiamos los espacios individuales de cada parte
    final macCandidate = parts[0].trim();
    final secretKeyCandidate = parts[1].trim();

    // 4. Validamos el formato de la MAC localmente
    if (!_macRegex.hasMatch(macCandidate)) {
      return {'mac_address': null, 'secret_key_qr': null};
    }

    // Si todo coincide, pasamos la MAC limpia y la llave secreta
    return {'mac_address': macCandidate, 'secret_key_qr': secretKeyCandidate};
  }
}
