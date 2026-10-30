/// Validaciones de cliente de la cuenta (RF-06, RF-11, RF-12).
///
/// Módulo puro: sin Flutter, sin red y sin almacenamiento (RNF-04). Es el
/// espejo en Dart de `api/app/domain/cuenta.py`, de modo que la aplicación
/// rechaza antes de enviar exactamente lo que el servidor rechazaría.
library;

import 'dart:convert';

/// Textos visibles del catálogo de la spec 015.
///
/// Se copian literalmente y no admiten variantes (RNF-01). Los que repiten el
/// catálogo de errores de la API sirven de respaldo cuando una respuesta no
/// trae `message`.
abstract final class MensajesCuenta {
  static const String correoObligatorio = 'El correo es obligatorio';
  static const String correoInvalido =
      'Introduce un correo electrónico válido.';
  static const String passwordNuevaObligatoria = 'Escribe la contraseña nueva.';
  static const String confirmacionObligatoria = 'Confirma la contraseña nueva.';
  static const String passwordsNoCoinciden = 'Las contraseñas no coinciden';
  static const String passwordCorta =
      'La contraseña debe tener al menos 8 caracteres.';
  static const String passwordLarga = 'La contraseña es demasiado larga.';
  static const String sinCambios =
      'No has modificado ningún dato. Escribe un correo nuevo o una '
      'contraseña nueva.';

  static const String estadoActiva = 'Activa';
  static const String estadoInactiva = 'Inactiva';

  static const String sesionInvalida =
      'La sesión no es válida. Vuelve a iniciar sesión.';
  static const String errorServidor =
      'No se pudo completar la operación. Inténtalo de nuevo.';
  static const String sinConexion =
      'Se requiere conexión con el servidor para completar esta operación.';
  static const String sinPerfilCacheado =
      'No hay datos de tu cuenta guardados en este dispositivo. '
      'Conéctate para consultarlos.';

  /// Aviso del perfil mostrado desde la caché local (RF-07).
  static const String datosGuardados =
      'Estás viendo datos guardados en este dispositivo.';

  /// Confirmación de la actualización de perfil (RF-10).
  static const String datosActualizados =
      'Tus datos se actualizaron correctamente.';

  /// Rechazo del inicio de sesión (RF-19). Sin punto final.
  static const String credencialesInvalidas = 'Correo o contraseña incorrectos';

  /// Confirmación de la baja de cuenta (RF-18).
  static const String cuentaEliminada =
      'Tu cuenta y todos sus datos se eliminaron de forma definitiva.';

  /// Fallo de la limpieza local de la baja (RNF-10).
  static const String limpiezaLocalFallida =
      'Tu cuenta se eliminó, pero no se pudieron borrar todos los datos de '
      'este dispositivo. Se cerró la sesión para proteger tu información.';

  /// Advertencia de la pantalla y del diálogo de baja (RF-16).
  static const String avisoIrreversible =
      'Esta acción es irreversible y no se puede deshacer.';

  /// Listado literal de los datos que se pierden con la baja (RF-16).
  static const String datosEnRiesgo =
      'Se eliminarán tu cuenta, tus mascotas, tus dispensadores, tus horarios, '
      'las comidas en espera, tus órdenes, tus reabastecimientos y todo tu '
      'historial.';

  /// Acción que abre el diálogo de confirmación destructiva (RF-16).
  static const String eliminarMiCuenta = 'Eliminar mi cuenta';

  /// Indicación del diálogo de baja (RF-16).
  static const String indicacionPasswordActual =
      'Escribe tu contraseña actual para confirmar la eliminación.';

  /// Etiqueta del campo de contraseña actual (RF-16).
  static const String passwordActual = 'Contraseña actual';

  /// Acción de confirmación del diálogo de baja (RF-16).
  static const String eliminarCuenta = 'Eliminar cuenta';

  /// Contraseña actual incorrecta (RF-17).
  static const String passwordIncorrecta = 'La contraseña no es correcta.';

  /// Contraseña vacía en el registro (texto reutilizado del catálogo).
  static const String passwordRegistroObligatoria =
      'La contraseña es obligatoria';

  /// Mensaje del catálogo de errores de la API por código.
  static const Map<String, String> porCodigo = {
    'invalid_email': correoInvalido,
    'weak_password': passwordCorta,
    'password_too_long': passwordLarga,
    'empty_update': sinCambios,
    'email_already_registered': 'El correo electrónico ya está registrado.',
    'invalid_password': passwordIncorrecta,
    'invalid_credentials': credencialesInvalidas,
    'unauthorized': sesionInvalida,
    'conflict': errorServidor,
    'server_error': errorServidor,
  };
}

/// Códigos estables del catálogo de errores de la API que usa la cuenta.
abstract final class CodigosCuenta {
  static const String invalidEmail = 'invalid_email';
  static const String weakPassword = 'weak_password';
  static const String passwordTooLong = 'password_too_long';
  static const String emptyUpdate = 'empty_update';
  static const String emailAlreadyRegistered = 'email_already_registered';
  static const String invalidPassword = 'invalid_password';
  static const String invalidCredentials = 'invalid_credentials';
  static const String unauthorized = 'unauthorized';
  static const String conflict = 'conflict';
  static const String serverError = 'server_error';
}

/// Campo del formulario al que pertenece cada error de cliente (RF-11).
///
/// [formulario] agrupa los avisos que no son de un campo concreto, como el
/// envío sin cambios.
enum CampoPerfil {
  correo,
  passwordNueva,
  confirmacion,
  passwordActual,
  formulario,
}

/// Límites de la contraseña nueva: mínimo en caracteres y máximo en bytes UTF-8.
const int minimoCaracteresPassword = 8;
const int maximoBytesPassword = 72;

/// Correo en forma canónica: sin espacios exteriores y en minúsculas.
///
/// Los espacios interiores se conservan a propósito, porque invalidan el
/// correo y la normalización no debe ocultarlo (RF-11, RF-12, RF-19).
String normalizarCorreo(String texto) => texto.trim().toLowerCase();

/// Indica si el correo tiene formato válido (RF-11).
///
/// Mismas reglas que el servidor: exactamente una `@`, parte local no vacía,
/// dominio con al menos dos etiquetas no vacías y ningún espacio interior.
bool esCorreoValido(String correo) {
  final valor = normalizarCorreo(correo);
  if (valor.isEmpty || valor.contains(RegExp(r'\s'))) return false;

  final partes = valor.split('@');
  if (partes.length != 2) return false;

  final local = partes[0];
  final dominio = partes[1];
  if (local.isEmpty || dominio.isEmpty) return false;

  final etiquetas = dominio.split('.');
  return etiquetas.length >= 2 &&
      etiquetas.every((etiqueta) => etiqueta.isNotEmpty);
}

/// Bytes UTF-8 del texto, que es el límite real de la contraseña (RF-11).
int bytesUtf8(String texto) => utf8.encode(texto).length;

/// Etiqueta visible del estado de la cuenta a partir de `is_active` (RF-06).
String etiquetaEstado(bool isActive) =>
    isActive ? MensajesCuenta.estadoActiva : MensajesCuenta.estadoInactiva;

/// Inicial del avatar: primera letra del correo normalizado, en mayúsculas.
///
/// Sin correo devuelve cadena vacía: el avatar queda vacío antes que mostrar
/// un dato de relleno, que la spec prohíbe (RF-07).
String inicialDeCorreo(String correo) {
  final valor = normalizarCorreo(correo);
  if (valor.isEmpty) return '';
  return valor[0].toUpperCase();
}

/// Valida la contraseña del registro con la misma regla de la cuenta (RF-11).
///
/// Devuelve `null` cuando la contraseña es válida. La vista de registro la usa
/// en lugar de duplicar la longitud mínima y el límite de bytes.
String? validarPasswordRegistro(String? password) {
  if (password == null || password.isEmpty) {
    return MensajesCuenta.passwordRegistroObligatoria;
  }
  if (password.runes.length < minimoCaracteresPassword) {
    return MensajesCuenta.passwordCorta;
  }
  if (bytesUtf8(password) > maximoBytesPassword) {
    return MensajesCuenta.passwordLarga;
  }
  return null;
}

/// Valida el formulario de actualización de perfil (RF-11).
///
/// Devuelve **todos** los errores de cliente aplicables a la vez, cada uno
/// asociado a su campo y en el orden de precedencia de la spec: obligatoriedad
/// del correo, formato, envío sin cambios, confirmación, contraseña nueva,
/// coincidencia, longitud mínima y límite de bytes. Un mapa vacío significa
/// que la actualización es válida. La unicidad del correo no se comprueba
/// aquí: es exclusiva del servidor (RF-12).
Map<CampoPerfil, String> validarFormularioPerfil({
  required String correoActual,
  required String correo,
  required String passwordNueva,
  required String confirmacion,
}) {
  final errores = <CampoPerfil, String>{};
  final correoNuevo = normalizarCorreo(correo);
  final correoVigente = normalizarCorreo(correoActual);

  if (correoNuevo.isEmpty) {
    errores[CampoPerfil.correo] = MensajesCuenta.correoObligatorio;
  } else if (!esCorreoValido(correoNuevo)) {
    errores[CampoPerfil.correo] = MensajesCuenta.correoInvalido;
  }

  final correoValido = !errores.containsKey(CampoPerfil.correo);
  final sinPassword = passwordNueva.isEmpty && confirmacion.isEmpty;

  // El envío sin cambios solo se puede decidir con un correo válido: sin él,
  // el aviso que corresponde es el de obligatoriedad o formato.
  if (correoValido && correoNuevo == correoVigente && sinPassword) {
    errores[CampoPerfil.formulario] = MensajesCuenta.sinCambios;
    return errores;
  }

  if (passwordNueva.isNotEmpty && confirmacion.isEmpty) {
    errores[CampoPerfil.confirmacion] = MensajesCuenta.confirmacionObligatoria;
  } else if (passwordNueva.isEmpty && confirmacion.isNotEmpty) {
    errores[CampoPerfil.passwordNueva] =
        MensajesCuenta.passwordNuevaObligatoria;
  } else if (passwordNueva.isNotEmpty && confirmacion.isNotEmpty) {
    if (passwordNueva != confirmacion) {
      errores[CampoPerfil.confirmacion] = MensajesCuenta.passwordsNoCoinciden;
    } else if (passwordNueva.runes.length < minimoCaracteresPassword) {
      errores[CampoPerfil.passwordNueva] = MensajesCuenta.passwordCorta;
    } else if (bytesUtf8(passwordNueva) > maximoBytesPassword) {
      errores[CampoPerfil.passwordNueva] = MensajesCuenta.passwordLarga;
    }
  }

  return errores;
}
