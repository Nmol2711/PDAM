import '../../domain/entity/ble_permission_result.dart';
import '../../domain/entity/provisioning_stage.dart';

/// Copy en español del catálogo de etapas del aprovisionamiento (RF-19 a
/// RF-21). La vista nunca deriva textos de excepciones (RNF-01).
String provisioningStageMessage(ProvisioningStage stage) {
  switch (stage) {
    case ProvisioningStage.conexion:
      return 'No se pudo conectar con el dispensador. '
          'Acércalo al teléfono y vuelve a intentarlo.';
    case ProvisioningStage.descubrimiento:
      return 'El dispensador no respondió al iniciar la configuración. '
          'Vuelve a intentarlo.';
    case ProvisioningStage.escritura:
      return 'No se pudieron enviar las credenciales al dispensador. '
          'Vuelve a intentarlo.';
    case ProvisioningStage.desconexion:
      return 'La configuración se envió, pero el dispensador no confirmó el '
          'cierre de la conexión. Vuelve a intentarlo.';
    case ProvisioningStage.conexion_perdida:
      return 'Se perdió la conexión con el dispensador. '
          'Acércalo al teléfono y vuelve a intentarlo.';
    case ProvisioningStage.presupuesto_agotado:
      return 'La configuración tardó demasiado y se canceló. '
          'Vuelve a intentarlo.';
  }
}

/// Aviso único de autorización Bluetooth (RF-25, RF-17).
const String bluetoothAuthorizationSettingsMessage =
    'La aplicación no tiene autorización para usar el Bluetooth. '
    'Revisa los permisos en los ajustes.';

/// Aviso de permisos o ubicación al aprovisionar (RF-17, RF-18).
String provisioningPermissionMessage(BlePermissionResult permission) {
  if (permission.requiresLocationSettings) {
    return 'Activa la ubicación del teléfono para configurar el dispensador.';
  }
  if (permission.isPermanentlyDenied) {
    return bluetoothAuthorizationSettingsMessage;
  }
  return 'La aplicación necesita permiso de Bluetooth para configurar el '
      'dispensador. Vuelve a intentarlo.';
}

/// Mensaje del fallo terminal: prioriza el aviso de permisos cuando no se pudo
/// iniciar y, si no, usa el copy de la etapa (RF-17, RF-19 a RF-21).
String provisioningFailureMessage(ProvisioningException failure) {
  final permission = failure.permission;
  if (permission != null) return provisioningPermissionMessage(permission);
  return provisioningStageMessage(failure.stage);
}
