import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/account/presentation/bloc/account_bloc.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/delete_account_dialog.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/profile_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Pantalla de eliminación de cuenta (RF-16 a RF-21).
///
/// Muestra la advertencia de irreversibilidad y el listado literal de datos que
/// se pierden, y abre el diálogo destructivo. No precarga el perfil: la baja no
/// lo necesita y así su indicador no se solapa con `isLoadingProfile` (RNF-03).
/// La vista solo compone widgets y emite eventos; la limpieza local vive en el
/// BLoC y en `AccountLocalCleaner` (principio 3).
class DeleteAccountView extends StatelessWidget {
  const DeleteAccountView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eliminación de cuenta')),
      body: SafeArea(
        child: BlocBuilder<AccountBloc, AccountState>(
          builder: (context, state) => _contenido(context, state),
        ),
      ),
    );
  }

  Widget _contenido(BuildContext context, AccountState state) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mensaje = state.message;
    final avisoOperacion =
        mensaje != null &&
        (mensaje.tipo == AccountMessageType.aviso ||
            mensaje.tipo == AccountMessageType.error);

    return SingleChildScrollView(
      key: const Key('delete_account_scroll'),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (avisoOperacion) ...<Widget>[
                ProfileNotice(
                  message: mensaje.text,
                  icon: mensaje.tipo == AccountMessageType.aviso
                      ? Icons.cloud_off_outlined
                      : Icons.error_outline,
                  actionLabel: 'Reintentar',
                  onAction: () => _abrirDialogo(context),
                ),
                const SizedBox(height: 16),
              ],
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            Icons.warning_amber_rounded,
                            color: colors.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              MensajesCuenta.avisoIrreversible,
                              key: const Key('delete_account_warning'),
                              style: textTheme.titleMedium?.copyWith(
                                color: colors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        MensajesCuenta.datosEnRiesgo,
                        key: const Key('delete_account_data'),
                        style: textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('delete_account_open'),
                onPressed: state.isSubmitting
                    ? null
                    : () => _abrirDialogo(context),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(MensajesCuenta.eliminarMiCuenta),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Abre el diálogo después de descartar cualquier aviso anterior para que no
  /// lo cierre al instante.
  ///
  /// El reintento de RF-21 vuelve a pedir la contraseña a propósito: retenerla
  /// entre una instancia y otra del diálogo la mantendría en memoria fuera del
  /// diálogo, y RNF-06 exige que la contraseña reingresada solo viva mientras
  /// se usa para esa verificación. Se prefiere una escritura más antes que
  /// conservar el secreto.
  Future<void> _abrirDialogo(BuildContext context) async {
    final bloc = context.read<AccountBloc>();
    if (bloc.state.message != null) {
      bloc.add(const AccountMessageConsumed());
      await Future<void>.delayed(Duration.zero);
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => const DeleteAccountDialog(),
    );
  }
}
