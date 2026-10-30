import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/account/presentation/bloc/account_bloc.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/profile_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Perfil de la cuenta en modo consulta (RF-06, RF-07, RF-08).
///
/// Muestra el correo normalizado, el estado informativo y el avatar con la
/// inicial. Sin conexión presenta el perfil cacheado real con su aviso; sin
/// caché muestra el mensaje de RF-08 con «Reintentar». No hay campos de
/// edición, contraseña ni token.
class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  @override
  void initState() {
    super.initState();
    // La vista solo emite el evento; la consulta y la caché viven en el BLoC.
    context.read<AccountBloc>().add(const ProfileRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: SafeArea(
        child: BlocBuilder<AccountBloc, AccountState>(
          builder: (context, state) {
            return SingleChildScrollView(
              key: const Key('profile_scroll'),
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _contenido(context, state),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _contenido(BuildContext context, AccountState state) {
    final perfil = state.profile;

    if (perfil != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.isOffline) ...<Widget>[
            const ProfileNotice(
              message: MensajesCuenta.datosGuardados,
              icon: Icons.cloud_off_outlined,
            ),
            const SizedBox(height: 16),
          ],
          _PerfilCard(profile: perfil),
        ],
      );
    }

    if (state.isLoadingProfile) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final mensaje = state.message;
    if (mensaje == null) {
      return const SizedBox.shrink();
    }

    // La sesión inválida la cierra el enrutador y lleva al login: esta pantalla
    // no muestra datos cacheados como si la cuenta siguiera existiendo (RF-07).
    if (mensaje.tipo == AccountMessageType.sesionInvalida) {
      return const SizedBox.shrink();
    }

    return ProfileNotice(
      message: mensaje.text,
      icon: Icons.person_outline,
      actionLabel: 'Reintentar',
      onAction: () =>
          context.read<AccountBloc>().add(const ProfileRetryRequested()),
    );
  }
}

class _PerfilCard extends StatelessWidget {
  final UserProfile profile;

  const _PerfilCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Semantics(
              key: const Key('profile_avatar_semantics'),
              container: true,
              label: 'Avatar con la inicial ${profile.inicial}',
              child: ExcludeSemantics(
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: colors.primaryContainer,
                  child: Text(
                    profile.inicial,
                    style: textTheme.headlineMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Correo electrónico',
              style: textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              profile.email,
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Icon(Icons.verified_user_outlined, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Estado de la cuenta',
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(profile.estado, style: textTheme.titleMedium),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
