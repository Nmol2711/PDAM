import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/presentation/widgets/app_notice_dialog.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/dispenser_notice_mapper.dart';

// Pruebas unitarias de `dispenser_notice_mapper.dart`: el mapeo de un `Failures`
// tipado a los parámetros del aviso reutilizable `AppNoticeDialog`.
//
// Cubre RF-10, RF-11, RF-12 (título y descripción por caso), RF-16 (el aviso es
// genérico y no reproduce datos ajenos) y RNF-05 (cada motivo tiene su propio tono
// e icono, no un `SnackBar` genérico).
//
// Contrato esperado (plan §2.2 y §3.5): `appNoticeFor(Failures)` devuelve un
// `AppNoticeParams` con `tone`, `icon`, `title`, `message` y `actionLabel`. El mapper
// solo elige copy: no decide lógica ni llama al backend.

// Datos del propietario que ningún aviso puede reproducir (CL-14, RF-16). Se
// inyectan en el mensaje del fallo para comprobar que el mapper no lo copia.
const String nombreMascota = 'RayoSecreto';
const String emailDueno = 'dueno.secreto@pdam.test';
const String idDispensador = '7777';
const String mensajeConDatosAjenos =
    'El dispensador $idDispensador de $nombreMascota ($emailDueno) ya está registrado.';

void main() {
  group('appNoticeFor con los rechazos del servidor', () {
    test('conflicto de alta produce aviso de advertencia con copy genérico (RF-10)', () {
      final AppNoticeParams aviso = appNoticeFor(MacAlreadyRegisteredFailures(mensajeConDatosAjenos));

      expect(aviso.tone, AppNoticeTone.warning);
      expect(aviso.title.trim(), isNotEmpty, reason: 'El aviso necesita un título.');
      expect(aviso.message.trim(), isNotEmpty, reason: 'El aviso necesita un mensaje.');
      expect(aviso.actionLabel.trim(), isNotEmpty, reason: 'El aviso necesita la etiqueta de su acción.');
      expect(aviso.icon, isNotNull, reason: 'El aviso necesita un icono: el significado no lo transmite solo el color.');
    });

    test('dirección en uso produce aviso de advertencia con copy genérico (RF-11)', () {
      final AppNoticeParams aviso = appNoticeFor(MacInUseFailures(mensajeConDatosAjenos));

      expect(aviso.tone, AppNoticeTone.warning);
      expect(aviso.title.trim(), isNotEmpty);
      expect(aviso.message.trim(), isNotEmpty);
      expect(aviso.actionLabel.trim(), isNotEmpty);
    });

    test('formato inválido produce aviso de advertencia con copy genérico (RF-12)', () {
      final AppNoticeParams aviso = appNoticeFor(InvalidMacFormatFailures(mensajeConDatosAjenos));

      expect(aviso.tone, AppNoticeTone.warning);
      expect(aviso.title.trim(), isNotEmpty);
      expect(aviso.message.trim(), isNotEmpty);
      expect(aviso.actionLabel.trim(), isNotEmpty);
    });

    test('falta de conexión produce aviso informativo con copy genérico (RF-13)', () {
      final AppNoticeParams aviso = appNoticeFor(ConnectivityRequiredFailures('Sin conexión a la red.'));

      expect(aviso.tone, AppNoticeTone.info);
      expect(aviso.title.trim(), isNotEmpty);
      expect(aviso.message.trim(), isNotEmpty);
      expect(aviso.actionLabel.trim(), isNotEmpty);
    });

    test('cada motivo tiene su propio título, para que el usuario distinga el caso', () {
      final Set<String> titulos = <String>{
        appNoticeFor(MacAlreadyRegisteredFailures('x')).title,
        appNoticeFor(MacInUseFailures('x')).title,
        appNoticeFor(InvalidMacFormatFailures('x')).title,
        appNoticeFor(ConnectivityRequiredFailures('x')).title,
      };

      expect(titulos, hasLength(4), reason: 'Los cuatro motivos necesitan textos distintos: $titulos');
    });
  });

  group('Privacidad del aviso (RF-16, CL-14)', () {
    test('ningún motivo reproduce datos de la mascota, del dueño o del dispensador', () {
      final List<Failures> fallos = <Failures>[
        MacAlreadyRegisteredFailures(mensajeConDatosAjenos),
        MacInUseFailures(mensajeConDatosAjenos),
        InvalidMacFormatFailures(mensajeConDatosAjenos),
        ConnectivityRequiredFailures(mensajeConDatosAjenos),
      ];

      for (final Failures fallo in fallos) {
        final AppNoticeParams aviso = appNoticeFor(fallo);
        final String copy = '${aviso.title} ${aviso.message}';

        for (final String datoProhibido in <String>[nombreMascota, emailDueno, idDispensador]) {
          expect(
            copy.contains(datoProhibido),
            isFalse,
            reason: 'El aviso de ${fallo.runtimeType} no puede filtrar "$datoProhibido".',
          );
        }
      }
    });
  });

  group('Tono e icono del aviso', () {
    test('los tonos info y warning usan iconos distintos (RNF-05)', () {
      final AppNoticeParams informativo = appNoticeFor(ConnectivityRequiredFailures('x'));
      final AppNoticeParams advertencia = appNoticeFor(MacAlreadyRegisteredFailures('x'));

      expect(informativo.tone, AppNoticeTone.info);
      expect(advertencia.tone, AppNoticeTone.warning);
      expect(informativo.icon, isNot(equals(advertencia.icon)));
    });
  });

  group('Fallos sin caso propio', () {
    test('un fallo desconocido cae en un aviso informativo por defecto, nunca en una excepción', () {
      final List<Failures> fallosDesconocidos = <Failures>[
        ServerFailures('Error interno del servidor.'),
        ConfigurationFailure('Falta configurar la aplicación.'),
        UserFailures('Credenciales incorrectas.'),
        NetworkFailures('Error de red.'),
        LocalStorageFailures('No se pudo leer el almacenamiento local.'),
      ];

      for (final Failures fallo in fallosDesconocidos) {
        final AppNoticeParams aviso = appNoticeFor(fallo);

        expect(aviso.tone, AppNoticeTone.info, reason: '${fallo.runtimeType} debe usar el aviso informativo por defecto.');
        expect(aviso.title.trim(), isNotEmpty);
        expect(aviso.message.trim(), isNotEmpty);
        expect(aviso.actionLabel.trim(), isNotEmpty);
      }
    });
  });
}