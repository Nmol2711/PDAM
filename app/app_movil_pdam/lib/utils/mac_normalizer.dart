/// Normalización y validación de la dirección MAC de un dispensador.
///
/// Espejo exacto de `api/app/services/mac_service.py`: mismas lista de
/// separadores y mismo patrón de la forma canónica. La forma canónica es la de
/// 12 dígitos hexadecimales en mayúsculas y sin separadores (`AABBCCDDEEFF`), de
/// modo que todos los formatos equivalentes (`AA:BB:CC:DD:EE:FF`,
/// `aa-bb-cc-dd-ee-ff`, `aa bb cc dd ee ff`, `aa.bb.cc.dd.ee.ff`) colapsen en un
/// único valor comparable (RF-02, RNF-08).
///
/// Funciones puras: no acceden a la red ni al almacenamiento local.
library;

/// Separadores admitidos en la dirección que introduce, escanea o envía el
/// hardware. Deben coincidir con `SEPARADORES` de `mac_service.py`.
const Set<String> macSeparadores = <String>{':', '-', '.', ' '};

/// Patrón de la forma canónica: exactamente 12 dígitos hexadecimales en
/// mayúsculas. Equivale a `PATRON_MAC_NORMALIZADA` de `mac_service.py`.
final RegExp patronMacNormalizada = RegExp(r'^[0-9A-F]{12}$');

/// Devuelve la forma canónica de [raw] sin separadores y en mayúsculas.
///
/// Tolera la cadena vacía: en ese caso devuelve una cadena vacía, que
/// `isValidNormalizedMac` rechaza.
String normalizeMac(String raw) {
  if (raw.isEmpty) {
    return '';
  }

  final String limpia = raw.split('').where((String caracter) => !macSeparadores.contains(caracter)).join();

  return limpia.toUpperCase();
}

/// Indica si [valor] ya está en la forma canónica.
///
/// No normaliza: exige 12 hexadecimales en mayúsculas sin separadores, por eso
/// hay que pasar antes por [normalizeMac].
bool isValidNormalizedMac(String valor) => patronMacNormalizada.hasMatch(valor);