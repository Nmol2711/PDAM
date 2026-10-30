import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:flutter_test/flutter_test.dart';

/// Utilidades de validación de cliente del perfil (RF-11).
///
/// Cada texto se compara contra el literal del catálogo de la spec 015: si una
/// variante se cuela, la prueba falla. La matriz cubre las catorce filas de
/// RF-11, los límites 7/8/9 caracteres y 72/73 bytes, y los casos en los que
/// hay varios errores a la vez.
void main() {
  String repetir(String texto, int veces) => List.filled(veces, texto).join();

  Map<CampoPerfil, String> validar({
    String correoActual = 'actual@x.com',
    String correo = 'actual@x.com',
    String passwordNueva = '',
    String confirmacion = '',
  }) {
    return validarFormularioPerfil(
      correoActual: correoActual,
      correo: correo,
      passwordNueva: passwordNueva,
      confirmacion: confirmacion,
    );
  }

  group('normalizarCorreo (RF-11, RF-12, RF-19)', () {
    test('recorta los espacios exteriores y pasa a minúsculas', () {
      expect(normalizarCorreo('  User@X.com  '), 'user@x.com');
    });

    test('conserva los espacios interiores, que invalidan el correo', () {
      expect(normalizarCorreo('user name@x.com'), 'user name@x.com');
      expect(esCorreoValido('user name@x.com'), isFalse);
    });

    test('una cadena vacía se normaliza a cadena vacía', () {
      expect(normalizarCorreo('   '), '');
    });
  });

  group('esCorreoValido (RF-11)', () {
    test('acepta correos con una sola arroba y dominio con punto', () {
      for (final correo in [
        'user@x.com',
        'nombre.apellido@sub.dominio.org',
        'USER@X.COM',
        '  user@x.com  ',
      ]) {
        expect(esCorreoValido(correo), isTrue, reason: correo);
      }
    });

    test('rechaza correos sin arroba, con dos arrobas o sin dominio', () {
      for (final correo in [
        '',
        'userx.com',
        'user@@x.com',
        'user@x',
        '@x.com',
        'user@',
        'user@.com',
        'user@x..com',
        'user @x.com',
      ]) {
        expect(esCorreoValido(correo), isFalse, reason: correo);
      }
    });
  });

  group('bytesUtf8 (RF-11)', () {
    test('cuenta bytes UTF-8 y no caracteres', () {
      expect(bytesUtf8('abc'), 3);
      expect(bytesUtf8('ñ'), 2);
      expect(bytesUtf8('😀'), 4);
    });
  });

  group('validarFormularioPerfil: matriz de RF-11', () {
    test('fila 1: correo vacío muestra la obligatoriedad', () {
      final errores = validar(correo: '');
      expect(errores, {CampoPerfil.correo: 'El correo es obligatorio'});
    });

    test('fila 2: correo con formato inválido', () {
      final errores = validar(correo: 'no-es-un-correo');
      expect(errores, {
        CampoPerfil.correo: 'Introduce un correo electrónico válido.',
      });
    });

    test('fila 3: correo igual y las dos contraseñas vacías', () {
      final errores = validar();
      expect(errores, {
        CampoPerfil.formulario:
            'No has modificado ningún dato. Escribe un correo nuevo o una '
            'contraseña nueva.',
      });
    });

    test('fila 4: correo igual, contraseña rellena y confirmación vacía', () {
      final errores = validar(passwordNueva: 'unaClaveLarga');
      expect(errores, {
        CampoPerfil.confirmacion: 'Confirma la contraseña nueva.',
      });
    });

    test('fila 5: correo igual, contraseña vacía y confirmación rellena', () {
      final errores = validar(confirmacion: 'unaClaveLarga');
      expect(errores, {
        CampoPerfil.passwordNueva: 'Escribe la contraseña nueva.',
      });
    });

    test('fila 6: contraseña y confirmación rellenas pero distintas', () {
      final errores = validar(
        passwordNueva: 'unaClaveLarga',
        confirmacion: 'otraClaveLarga',
      );
      expect(errores, {
        CampoPerfil.confirmacion: 'Las contraseñas no coinciden',
      });
    });

    test('fila 7: coinciden y tienen menos de 8 caracteres', () {
      final errores = validar(
        passwordNueva: 'corta12',
        confirmacion: 'corta12',
      );
      expect(errores, {
        CampoPerfil.passwordNueva:
            'La contraseña debe tener al menos 8 caracteres.',
      });
    });

    test('fila 8: coinciden y superan 72 bytes UTF-8', () {
      final larga = repetir('a', 73);
      final errores = validar(passwordNueva: larga, confirmacion: larga);
      expect(errores, {
        CampoPerfil.passwordNueva: 'La contraseña es demasiado larga.',
      });
    });

    test('fila 9: correo igual y contraseña válida', () {
      final errores = validar(
        passwordNueva: 'unaClaveLarga',
        confirmacion: 'unaClaveLarga',
      );
      expect(errores, isEmpty);
    });

    test('fila 10: correo distinto y válido sin contraseña', () {
      final errores = validar(correo: 'nuevo@x.com');
      expect(errores, isEmpty);
    });

    test(
      'fila 11: correo distinto, contraseña rellena y confirmación vacía',
      () {
        final errores = validar(
          correo: 'nuevo@x.com',
          passwordNueva: 'unaClaveLarga',
        );
        expect(errores, {
          CampoPerfil.confirmacion: 'Confirma la contraseña nueva.',
        });
        expect(errores.containsKey(CampoPerfil.correo), isFalse);
      },
    );

    test(
      'fila 12: correo distinto, contraseña vacía y confirmación rellena',
      () {
        final errores = validar(
          correo: 'nuevo@x.com',
          confirmacion: 'unaClaveLarga',
        );
        expect(errores, {
          CampoPerfil.passwordNueva: 'Escribe la contraseña nueva.',
        });
        expect(errores.containsKey(CampoPerfil.correo), isFalse);
      },
    );

    test('fila 13: correo distinto y contraseña válida', () {
      final errores = validar(
        correo: 'nuevo@x.com',
        passwordNueva: 'unaClaveLarga',
        confirmacion: 'unaClaveLarga',
      );
      expect(errores, isEmpty);
    });

    test('fila 14: un correo válido distinto no se comprueba en el cliente; lo '
        'decide el servidor', () {
      final errores = validar(correo: 'ya.registrado@x.com');
      expect(errores, isEmpty);
    });
  });

  group('validarFormularioPerfil: errores simultáneos (RF-11)', () {
    test('correo vacío y falta la confirmación se muestran a la vez', () {
      final errores = validar(correo: '', passwordNueva: 'unaClaveLarga');
      expect(errores, {
        CampoPerfil.correo: 'El correo es obligatorio',
        CampoPerfil.confirmacion: 'Confirma la contraseña nueva.',
      });
    });

    test('correo inválido y contraseña corta se muestran a la vez', () {
      final errores = validar(
        correo: 'no-es-un-correo',
        passwordNueva: 'corta12',
        confirmacion: 'corta12',
      );
      expect(errores, {
        CampoPerfil.correo: 'Introduce un correo electrónico válido.',
        CampoPerfil.passwordNueva:
            'La contraseña debe tener al menos 8 caracteres.',
      });
    });

    test('el orden de precedencia es correo, envío sin cambios, confirmación, '
        'contraseña, coincidencia, mínimo y máximo', () {
      final errores = validar(correo: '', confirmacion: 'unaClaveLarga');
      expect(errores.keys.toList(), [
        CampoPerfil.correo,
        CampoPerfil.passwordNueva,
      ]);
    });

    test('un correo vacío no produce el aviso de envío sin cambios', () {
      final errores = validar(correo: '');
      expect(errores.containsKey(CampoPerfil.formulario), isFalse);
    });

    test('un correo solo con mayúsculas o espacios exteriores cuenta como '
        'igual al actual', () {
      final errores = validar(correo: '  ACTUAL@X.COM  ');
      expect(errores, {
        CampoPerfil.formulario:
            'No has modificado ningún dato. Escribe un correo nuevo o una '
            'contraseña nueva.',
      });
    });
  });

  group('validarFormularioPerfil: límites de la contraseña (RF-11)', () {
    test('7 caracteres se rechazan y 8 se aceptan', () {
      expect(
        validar(passwordNueva: repetir('a', 7), confirmacion: repetir('a', 7)),
        {
          CampoPerfil.passwordNueva:
              'La contraseña debe tener al menos 8 caracteres.',
        },
      );
      expect(
        validar(passwordNueva: repetir('a', 8), confirmacion: repetir('a', 8)),
        isEmpty,
      );
      expect(
        validar(passwordNueva: repetir('a', 9), confirmacion: repetir('a', 9)),
        isEmpty,
      );
    });

    test('exactamente 72 bytes se acepta y 73 se rechaza', () {
      final setentaYDos = repetir('a', 72);
      expect(
        validar(passwordNueva: setentaYDos, confirmacion: setentaYDos),
        isEmpty,
      );

      final setentaYTres = repetir('a', 73);
      expect(validar(passwordNueva: setentaYTres, confirmacion: setentaYTres), {
        CampoPerfil.passwordNueva: 'La contraseña es demasiado larga.',
      });
    });

    test(
      'el límite se mide en bytes: 36 caracteres ñ son 72 bytes válidos',
      () {
        final valida = repetir('ñ', 36);
        expect(bytesUtf8(valida), 72);
        expect(validar(passwordNueva: valida, confirmacion: valida), isEmpty);
      },
    );

    test('37 caracteres ñ superan el límite de bytes', () {
      final larga = repetir('ñ', 37);
      expect(bytesUtf8(larga), 74);
      expect(validar(passwordNueva: larga, confirmacion: larga), {
        CampoPerfil.passwordNueva: 'La contraseña es demasiado larga.',
      });
    });

    test('el mínimo se cuenta en caracteres y no en bytes', () {
      final sieteMultibyte = repetir('ñ', 7);
      expect(
        validar(passwordNueva: sieteMultibyte, confirmacion: sieteMultibyte),
        {
          CampoPerfil.passwordNueva:
              'La contraseña debe tener al menos 8 caracteres.',
        },
      );
    });

    test('el mínimo se comprueba antes que el máximo', () {
      final corta = repetir('😀', 2);
      expect(validar(passwordNueva: corta, confirmacion: corta), {
        CampoPerfil.passwordNueva:
            'La contraseña debe tener al menos 8 caracteres.',
      });
    });
  });

  group('validarPasswordRegistro (RF-11)', () {
    test('la contraseña vacía usa el texto reutilizado del registro', () {
      expect(validarPasswordRegistro(null), 'La contraseña es obligatoria');
      expect(validarPasswordRegistro(''), 'La contraseña es obligatoria');
    });

    test('7 caracteres se rechazan y 8 se aceptan', () {
      expect(
        validarPasswordRegistro('1234567'),
        'La contraseña debe tener al menos 8 caracteres.',
      );
      expect(validarPasswordRegistro('12345678'), isNull);
      expect(validarPasswordRegistro('123456789'), isNull);
    });

    test('el máximo se mide en bytes UTF-8: 72 válidos y 73 rechazados', () {
      expect(validarPasswordRegistro(repetir('a', 72)), isNull);
      expect(
        validarPasswordRegistro(repetir('a', 73)),
        'La contraseña es demasiado larga.',
      );
      expect(validarPasswordRegistro(repetir('ñ', 36)), isNull);
      expect(
        validarPasswordRegistro(repetir('ñ', 37)),
        'La contraseña es demasiado larga.',
      );
    });

    test('el mínimo se cuenta en caracteres y no en bytes', () {
      expect(
        validarPasswordRegistro(repetir('ñ', 7)),
        'La contraseña debe tener al menos 8 caracteres.',
      );
      expect(validarPasswordRegistro(repetir('ñ', 8)), isNull);
    });
  });

  group('etiquetaEstado e inicialDeCorreo (RF-06)', () {
    test(
      'el estado activo se muestra como Activa y el inactivo como Inactiva',
      () {
        expect(etiquetaEstado(true), 'Activa');
        expect(etiquetaEstado(false), 'Inactiva');
      },
    );

    test('la inicial sale del correo normalizado en mayúsculas', () {
      expect(inicialDeCorreo('  usuario@x.com '), 'U');
      expect(inicialDeCorreo('ñandu@x.com'), 'Ñ');
    });

    test('sin correo no hay inicial y no se inventa ningún dato', () {
      expect(inicialDeCorreo(''), '');
      expect(inicialDeCorreo('   '), '');
    });
  });
}
