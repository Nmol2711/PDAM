import 'package:app_movil_pdam/core/theme/theme_cubit.dart';
import 'package:app_movil_pdam/features/account/domain/entity/appearance_mode.dart';
import 'package:app_movil_pdam/features/account/presentation/utils/appearance_mode_theme.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/appearance_mode_dialog.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/settings_menu_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Menú de configuración global (RF-02, RF-03, RF-24).
///
/// Título «Configuración» y exactamente cuatro filas en el orden fijado. No
/// incluye el cierre de sesión ni las tres opciones de apariencia como filas:
/// la cuarta es una sola y muestra el modo activo como texto secundario. La
/// vista solo compone widgets y emite eventos (RNF-03).
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              key: const Key('settings_scroll'),
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: <Widget>[
                      SettingsMenuTile(
                        icon: Icons.person_outline,
                        title: 'Perfil',
                        onTap: () => context.push('/settings/profile'),
                      ),
                      const Divider(height: 1, indent: 72),
                      SettingsMenuTile(
                        icon: Icons.edit_outlined,
                        title: 'Actualización de perfil',
                        onTap: () => context.push('/settings/update'),
                      ),
                      const Divider(height: 1, indent: 72),
                      SettingsMenuTile(
                        icon: Icons.delete_outline,
                        title: 'Eliminación de cuenta',
                        onTap: () => context.push('/settings/delete'),
                      ),
                      const Divider(height: 1, indent: 72),
                      BlocBuilder<ThemeCubit, ThemeMode>(
                        builder: (context, themeMode) {
                          final modo = AppearanceMode.desdeCodigo(
                            codigoDeModo(themeMode),
                          );
                          return SettingsMenuTile(
                            icon: Icons.brightness_6_outlined,
                            title: 'Modo claro y oscuro',
                            subtitle: modo.etiqueta,
                            trailingIcon: Icons.tune,
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (context) =>
                                  const AppearanceModeDialog(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
