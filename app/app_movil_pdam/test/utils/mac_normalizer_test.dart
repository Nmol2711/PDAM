import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/utils/mac_normalizer.dart';

// Pruebas unitarias de `lib/utils/mac_normalizer.dart`, espejo Dart de
// `api/app/services/mac_service.py`.
//
// Cubre RF-02 (comparación por forma normalizada), RF-06 (rechazo del formato
// inválido distinguible del conflicto) y RNF-08 (equivalencia demostrada entre
// formatos). La tabla de formatos es la MISMA que `FORMATOS_EQUIVALENTES` de
// `api/tests/test_dispenser_mac.py` (T1): la paridad Python/Dart es el requisito,
// por eso se replican también los valores inválidos y los formatos con separadores.

// Forma canónica de la dirección: 12 dígitos hexadecimales en mayúsculas y sin separadores.
const String macCanonica = 'AABBCCDDEEFF';

// Formatos equivalentes de una misma dirección (CL-1, CL-2, CL-3).
const List<String> formatosEquivalentes = <String>[
  'AA:BB:CC:DD:EE:FF', // dos puntos, mayúsculas
  'aa:bb:cc:dd:ee:ff', // dos puntos, minúsculas
  'AABBCCDDEEFF', // sin separadores, mayúsculas
  'aabbccddeeff', // sin separadores, minúsculas
  'aa-bb-cc-dd-ee-ff', // guiones
  'aa bb cc dd ee ff', // espacios
  'aa.bb.cc.dd.ee.ff', // puntos
  'Aa:bB-cC dD.eE:fF', // mezcla de separadores y de mayúsculas con minúsculas
];

// Formatos con separadores: no son la forma normalizada, aunque representen una MAC
// válida. El validador exige la forma canónica, así que hay que normalizar antes.
const List<String> formatosConSeparadores = <String>[
  'AA:BB:CC:DD:EE:FF',
  'aa:bb:cc:dd:ee:ff',
  'aa-bb-cc-dd-ee-ff',
  'aa bb cc dd ee ff',
  'aa.bb.cc.dd.ee.ff',
];

// Valores que no son una dirección MAC válida una vez normalizados (CL-7).
// El equivalente Dart de `None` de Python no aparece porque el tipo es no nulable:
// la dirección ausente la rechaza el compilador, y su caso equivalente es la cadena
// vacía, que sí se prueba abajo.
const List<String> valoresInvalidos = <String>[
  'AABBCCDDEE', // 11 dígitos hexadecimales
  'AA:BB:CC:DD:EE', // 11 dígitos hexadecimales con separadores
  'AABBCCDDEEFFA', // 13 dígitos hexadecimales
  'AA:BB:CC:DD:EE:FF:00', // 14 dígitos hexadecimales con separadores
  'GG:BB:CC:DD:EE:FF', // carácter no hexadecimal en la primera posición
  'aa:bb:cc:gg:ee:ff', // carácter no hexadecimal en la mitad
  'aa:bb:cc:dd:ee:fg', // carácter no hexadecimal al final
  '', // cadena vacía
  '  :  -  .  ', // solo separadores: al normalizar queda vacía
];

void main() {
  group('normalizeMac', () {
    test('normaliza a la forma canónica cada formato equivalente (RF-02, CL-1, CL-2, CL-3)', () {
      for (final String formato in formatosEquivalentes) {
        expect(
          normalizeMac(formato),
          macCanonica,
          reason: 'El formato "$formato" debe normalizar a $macCanonica.',
        );
      }
    });

    test('todos los formatos equivalentes colapsan en una sola forma normalizada (RNF-08)', () {
      // Sin falsos positivos entre formatos distintos ni falsos negativos entre
      // formatos que representan la misma dirección.
      final Set<String> formas = formatosEquivalentes.map((String formato) => normalizeMac(formato)).toSet();

      expect(formas, <String>{macCanonica});
    });

    test('aserciones de equivalencia cruzada: dos formatos cualesquiera coinciden', () {
      for (final String formatoA in formatosEquivalentes) {
        for (final String formatoB in formatosEquivalentes) {
          expect(
            normalizeMac(formatoA),
            normalizeMac(formatoB),
            reason: '"$formatoA" y "$formatoB" son la misma dirección y deben normalizar igual.',
          );
        }
      }
    });

    test('la normalización es idempotente', () {
      for (final String formato in formatosEquivalentes) {
        final String normalizada = normalizeMac(formato);

        expect(
          normalizeMac(normalizada),
          normalizada,
          reason: 'Normalizar dos veces "$formato" no puede cambiar el resultado.',
        );
      }
    });

    test('los formatos no equivalentes no colapsan a la misma forma', () {
      // Guarda contra una regresión que normalice de más (por ejemplo, quitar
      // cualquier carácter en lugar de solo los separadores admitidos).
      expect(normalizeMac('AABBCCDDEEFF'), isNot(normalizeMac('AABBCCDDEEFFA')));
      expect(normalizeMac('AABBCCDDEEFF'), isNot(normalizeMac('112233445566')));
    });
  });

  group('isValidNormalizedMac', () {
    test('acepta la forma normalizada de cada formato equivalente (RF-02)', () {
      for (final String formato in formatosEquivalentes) {
        expect(
          isValidNormalizedMac(normalizeMac(formato)),
          isTrue,
          reason: 'La forma normalizada de "$formato" debe ser válida.',
        );
      }
    });

    test('rechaza la MAC incompleta de once dígitos hexadecimales (CL-7)', () {
      expect(isValidNormalizedMac('AABBCCDDEE'), isFalse);
      expect(isValidNormalizedMac(normalizeMac('AA:BB:CC:DD:EE')), isFalse);
    });

    test('rechaza la MAC extendida de trece dígitos hexadecimales (CL-7)', () {
      expect(isValidNormalizedMac('AABBCCDDEEFFA'), isFalse);
      expect(isValidNormalizedMac(normalizeMac('AA:BB:CC:DD:EE:FF:0A')), isFalse);
    });

    test('rechaza un carácter no hexadecimal en cualquier posición (CL-7)', () {
      for (int posicion = 0; posicion < macCanonica.length; posicion++) {
        for (final String caracter in <String>['G', 'g']) {
          final String candidato =
              macCanonica.substring(0, posicion) + caracter + macCanonica.substring(posicion + 1);

          expect(
            isValidNormalizedMac(candidato),
            isFalse,
            reason: '"$candidato" lleva "$caracter" en la posición $posicion y no es válida.',
          );
        }
      }
    });

    test('rechaza la cadena vacía y la dirección ausente ya normalizada (CL-7)', () {
      expect(isValidNormalizedMac(''), isFalse);
      expect(isValidNormalizedMac(normalizeMac('')), isFalse);
    });

    test('rechaza un valor compuesto solo por separadores porque queda vacío (CL-7)', () {
      expect(normalizeMac('  :  -  .  '), '');
      expect(isValidNormalizedMac(normalizeMac('  :  -  .  ')), isFalse);
    });

    test('rechaza todos los valores inválidos de la tabla', () {
      for (final String valor in valoresInvalidos) {
        expect(
          isValidNormalizedMac(normalizeMac(valor)),
          isFalse,
          reason: 'La dirección "$valor" no debe considerarse válida.',
        );
      }
    });

    test('rechaza las formas no normalizadas porque exige la forma canónica', () {
      // El validador no normaliza: exige 12 hexadecimales en mayúsculas y sin
      // separadores, por eso hay que pasar antes por `normalizeMac`.
      for (final String formato in formatosConSeparadores) {
        expect(
          isValidNormalizedMac(formato),
          isFalse,
          reason: '"$formato" es una MAC válida escrita con separadores, pero no es la forma canónica.',
        );
      }
    });

    test('rechaza la forma canónica en minúsculas, igual que el patrón [0-9A-F]{12} de Python', () {
      // Paridad con `is_valid_normalized_mac` de Python: el patrón exige mayúsculas.
      expect(isValidNormalizedMac(macCanonica.toLowerCase()), isFalse);
    });
  });

  group('Paridad Python/Dart (RNF-08)', () {
    test('las dos implementaciones comparten la misma lista de separadores', () {
      // Los separadores de la tabla que colapsan a la forma canónica son `:`, `-`,
      // `.` y el espacio. Si alguno dejara de quitarse, dejarían de ser equivalentes.
      const List<String> bytes = <String>['aa', 'bb', 'cc', 'dd', 'ee', 'ff'];

      for (final String separador in <String>[':', '-', '.', ' ']) {
        expect(
          normalizeMac(bytes.join(separador)),
          macCanonica,
          reason: 'El separador "$separador" debe eliminarse al normalizar.',
        );
      }
    });

    test('un separador no admitido no se elimina y por eso invalida la dirección', () {
      // `/` y `#` no están en la lista de separadores: quitarlos sería inventar
      // formatos que el backend no acepta (y el backend tampoco los quita).
      expect(normalizeMac('aa/bb/cc/dd/ee/ff'), isNot(macCanonica));
      expect(isValidNormalizedMac(normalizeMac('aa/bb/cc/dd/ee/ff')), isFalse);
    });
  });
}