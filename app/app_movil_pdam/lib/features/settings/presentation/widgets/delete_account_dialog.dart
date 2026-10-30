import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/account/presentation/bloc/account_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Diálogo destructivo de confirmación de la baja (RF-16, RF-17).
///
/// Reúne los tres elementos de la confirmación destructiva: el aviso de
/// irreversibilidad, el listado de datos que se pierden y el reingreso de la
/// contraseña actual. Mantiene la acción deshabilitada mientras el campo esté
/// vacío. La contraseña vive solo en el controlador del diálogo: no se
/// persiste, no se registra y no aparece en ningún texto (RNF-06). Se limpia al
/// cerrar el diálogo.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    // La contraseña reingresada no sobrevive al diálogo (RNF-06).
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return BlocListener<AccountBloc, AccountState>(
      listenWhen: (anterior, actual) =>
          anterior.message != actual.message ||
          anterior.fieldErrors != actual.fieldErrors,
      listener: (context, state) {
        // `invalid_password` llega como error de campo y no cierra el diálogo
        // (RF-17). El resto de avisos los muestra la pantalla o el enrutador.
        if (state.message == null) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: BlocBuilder<AccountBloc, AccountState>(
        builder: (context, state) {
          final errorCampo = state.fieldErrors[CampoPerfil.passwordActual];
          final vacio = _password.text.trim().isEmpty;
          // El botón se deshabilita por contraseña vacía o por un envío en
          // curso, nunca por la precarga del perfil (RNF-03).
          final puedeConfirmar = !vacio && !state.isSubmitting;

          return AlertDialog(
            key: const Key('delete_account_dialog'),
            title: const Text(MensajesCuenta.eliminarCuenta),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    MensajesCuenta.avisoIrreversible,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  // RF-16: el diálogo enumera los datos que se pierden, además
                  // del aviso que ya muestra la pantalla.
                  Text(
                    MensajesCuenta.datosEnRiesgo,
                    key: const Key('delete_account_dialog_data'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    MensajesCuenta.indicacionPasswordActual,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('delete_account_password'),
                    controller: _password,
                    enabled: !state.isSubmitting,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      setState(() {});
                      if (state.fieldErrors.containsKey(
                        CampoPerfil.passwordActual,
                      )) {
                        context.read<AccountBloc>().add(
                          const AccountMessageConsumed(),
                        );
                      }
                    },
                    onSubmitted: (_) {
                      if (puedeConfirmar) _confirmar();
                    },
                    decoration: InputDecoration(
                      labelText: MensajesCuenta.passwordActual,
                      border: const OutlineInputBorder(),
                      errorText: errorCampo,
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                key: const Key('delete_account_cancel'),
                onPressed: state.isSubmitting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const Key('delete_account_confirm'),
                onPressed: puedeConfirmar ? _confirmar : null,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                ),
                child: state.isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(MensajesCuenta.eliminarCuenta),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmar() {
    if (_password.text.trim().isEmpty) return;
    context.read<AccountBloc>().add(
      AccountDeletionRequested(password: _password.text),
    );
  }
}
