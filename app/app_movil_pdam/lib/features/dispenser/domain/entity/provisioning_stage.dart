// Las etapas conservan los códigos del catálogo de la spec 018 (RF-19 a RF-21);
// son claves de traducción, no nombres de API pública en camelCase.
// ignore_for_file: constant_identifier_names

import 'package:equatable/equatable.dart';

import 'ble_permission_result.dart';

/// Catálogo cerrado de etapas del aprovisionamiento (RF-19 a RF-21).
///
/// La presentación traduce cada etapa a su mensaje en español; el dominio no
/// transporta textos.
enum ProvisioningStage {
  conexion,
  descubrimiento,
  escritura,
  desconexion,
  conexion_perdida,
  presupuesto_agotado,
}

/// Fallo tipado del aprovisionamiento con la etapa que lo originó.
///
/// [permission] solo se informa cuando el aprovisionamiento no pudo iniciar por
/// permisos o ubicación (RF-17, RF-18); en ese caso [stage] es `conexion` y la
/// vista prioriza el aviso de permisos sobre el mensaje de la etapa.
/// [toString] es técnico y nunca se usa como copy de interfaz (RNF-01).
class ProvisioningException extends Equatable implements Exception {
  final ProvisioningStage stage;
  final BlePermissionResult? permission;

  const ProvisioningException({required this.stage, this.permission});

  @override
  List<Object?> get props => [stage, permission];

  @override
  String toString() {
    final permissionStatus = permission?.status.name;
    if (permissionStatus == null) {
      return 'ProvisioningException(stage: ${stage.name})';
    }
    return 'ProvisioningException(stage: ${stage.name}, '
        'permission: $permissionStatus)';
  }
}
