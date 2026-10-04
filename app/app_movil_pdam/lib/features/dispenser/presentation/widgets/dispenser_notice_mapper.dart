import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/presentation/widgets/app_notice_dialog.dart';
import 'package:flutter/material.dart';

// Copy de los avisos del módulo de dispensadores (RF-10, RF-11, RF-12, RF-13).
//
// Este archivo solo elige texto: no valida direcciones, no llama al servidor y
// no decide qué hacer. Recibe el `Failures` que ya produjo la capa de datos y
// devuelve los parámetros del aviso reutilizable `AppNoticeDialog`.
//
// Los mensajes son propios y genéricos: nunca reproducen el texto del servidor
// ni mencionan mascota, usuario o dispensador en conflicto (RF-16, CL-14). El
// ejemplo de dirección válido que exige RF-12 es genérico y no revela datos.

/// Traduce un fallo tipado a los parámetros del aviso (presentación pura).
AppNoticeParams appNoticeFor(Failures failure) {
  switch (failure.runtimeType) {
    case MacAlreadyRegisteredFailures:
      return const AppNoticeParams(
        tone: AppNoticeTone.warning,
        icon: Icons.warning_amber_rounded,
        title: 'Este dispensador ya está registrado',
        message:
            'Esa dirección ya está vinculada a otro registro del sistema. '
            'Escanea el código QR del dispensador correcto o revisa con qué '
            'cuenta está vinculado.',
        actionLabel: 'Entendido',
      );

    case MacInUseFailures:
      return const AppNoticeParams(
        tone: AppNoticeTone.warning,
        icon: Icons.warning_amber_rounded,
        title: 'Esa dirección ya está en uso',
        message:
            'La dirección indicada pertenece a otro dispensador. '
            'Verifica la dirección del dispositivo e inténtalo de nuevo.',
        actionLabel: 'Entendido',
      );

    case InvalidMacFormatFailures:
      return const AppNoticeParams(
        tone: AppNoticeTone.warning,
        icon: Icons.warning_amber_rounded,
        title: 'La dirección no es válida',
        message:
            'Revisa la dirección del dispensador: debe tener 12 caracteres '
            'hexadecimales, por ejemplo AA:BB:CC:DD:EE:FF.',
        actionLabel: 'Corregir dirección',
      );

    case ConnectivityRequiredFailures:
      return const AppNoticeParams(
        tone: AppNoticeTone.info,
        icon: Icons.wifi_off_rounded,
        title: 'Necesitas conexión a internet',
        message:
            'El registro del dispensador se valida con el servidor. '
            'Conéctate a internet e inténtalo de nuevo.',
        actionLabel: 'Entendido',
      );

    // Cualquier fallo sin caso propio cae en un aviso informativo por defecto:
    // la presentación nunca deja al usuario sin explicación.
    default:
      return const AppNoticeParams(
        tone: AppNoticeTone.info,
        icon: Icons.help_outline,
        title: 'No se pudo completar la operación',
        message:
            'Vuelve a intentarlo en unos minutos. Si el problema continúa, '
            'revisa los datos e inténtalo otra vez.',
        actionLabel: 'Entendido',
      );
  }
}
