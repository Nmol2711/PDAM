import 'package:app_movil_pdam/core/theme/theme_cubit.dart';
import 'package:app_movil_pdam/features/account/domain/entity/appearance_mode.dart';
import 'package:app_movil_pdam/features/account/presentation/utils/appearance_mode_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Diálogo «Modo de apariencia» (RF-22, RF-23, RF-24).
///
/// Ofrece exactamente las tres opciones del catálogo —Claro, Oscuro y
/// Automático—, marca la que está activa en ese momento y aplica el cambio en
/// cuanto se elige, sin cerrar sesión ni reiniciar. La preferencia pertenece al
/// dispositivo y la guarda `ThemeCubit`; el diálogo solo la lee y la escribe.
///
/// Cerrar el diálogo sin elegir no llama a `setTheme`, de modo que el modo no
/// cambia (RF-22).
class AppearanceModeDialog extends StatelessWidget {
  const AppearanceModeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeMode>(
      builder: (context, themeMode) {
        final activo = AppearanceMode.desdeCodigo(codigoDeModo(themeMode));
        final colors = Theme.of(context).colorScheme;

        return AlertDialog(
          title: const Text('Modo de apariencia'),
          // Sin `contentPadding` propio: se usa el del tema, de modo que las
          // opciones conservan el mismo margen horizontal que el título.
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final modo in AppearanceMode.values)
                  ListTile(
                    key: Key('appearance_mode_${modo.codigo}'),
                    title: Text(modo.etiqueta),
                    selected: modo == activo,
                    trailing: modo == activo
                        ? Icon(Icons.check, color: colors.primary)
                        : null,
                    onTap: () =>
                        context.read<ThemeCubit>().setTheme(modo.aThemeMode()),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
