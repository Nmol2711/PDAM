import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/account/presentation/bloc/account_bloc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/profile_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Formulario de actualización de perfil (RF-09 a RF-15).
///
/// Precarga el correo del servidor o del perfil cacheado real, deja vacías las
/// dos contraseñas y ofrece «Guardar» y «Cancelar». No valida ni decide nada:
/// emite [ProfileUpdateSubmitted] y dibuja el estado del [AccountBloc], que
/// devuelve todos los errores de cliente a la vez y los rechazos del servidor
/// junto a su campo (RNF-03). La contraseña solo vive en los campos y en el
/// almacenamiento cifrado; nunca se muestra en un mensaje.
class UpdateProfileView extends StatefulWidget {
  const UpdateProfileView({super.key});

  @override
  State<UpdateProfileView> createState() => _UpdateProfileViewState();
}

class _UpdateProfileViewState extends State<UpdateProfileView> {
  final TextEditingController _correo = TextEditingController();
  final TextEditingController _passwordNueva = TextEditingController();
  final TextEditingController _confirmacion = TextEditingController();

  /// El correo se rellena una sola vez con el primer perfil real recibido.
  bool _correoPrecargado = false;

  /// Verdadero desde que se pulsa «Guardar»: solo entonces la confirmación del
  /// estado cierra la pantalla, para no reaccionar a mensajes anteriores.
  bool _envioLanzado = false;

  @override
  void initState() {
    super.initState();
    final bloc = context.read<AccountBloc>();
    // Un mensaje de otra pantalla no debe aparecer al abrir el formulario.
    if (bloc.state.message != null) {
      bloc.add(const AccountMessageConsumed());
    }
    // La precarga sale del servidor y, sin conexión, del perfil cacheado real.
    bloc.add(const ProfileRequested());
  }

  @override
  void dispose() {
    _correo.dispose();
    _passwordNueva.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Actualización de perfil')),
      body: SafeArea(
        child: BlocListener<AccountBloc, AccountState>(
          listenWhen: (anterior, actual) =>
              anterior.profile != actual.profile ||
              anterior.message != actual.message ||
              anterior.isSubmitting != actual.isSubmitting ||
              anterior.fieldErrors != actual.fieldErrors,
          listener: _alCambiarEstado,
          child: SingleChildScrollView(
            key: const Key('update_profile_scroll'),
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: BlocBuilder<AccountBloc, AccountState>(
                  builder: (context, state) => _contenido(context, state),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _alCambiarEstado(BuildContext context, AccountState state) {
    final perfil = state.profile;
    if (perfil != null && !_correoPrecargado) {
      _correoPrecargado = true;
      _correo.text = perfil.email;
    }

    final mensaje = state.message;

    // Una validación de cliente bloquea el envío sin respuesta del servidor
    // (RF-11): la bandera vuelve a su sitio para que un envío posterior pueda
    // cerrar la pantalla con su propia confirmación.
    if (state.fieldErrors.isNotEmpty && !state.isSubmitting) {
      _envioLanzado = false;
    }

    if (!_envioLanzado ||
        mensaje == null ||
        mensaje.tipo != AccountMessageType.confirmacion ||
        perfil == null) {
      return;
    }

    _envioLanzado = false;
    // La confirmación queda visible al volver al menú (RF-10).
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje.text)));
    // El saludo del panel se construye con la identidad de la sesión (RF-10).
    context.read<AuthBloc>().add(AuthProfileUpdated(email: perfil.email));
    context.read<AccountBloc>().add(const AccountMessageConsumed());
    context.pop();
  }

  Widget _contenido(BuildContext context, AccountState state) {
    final colors = Theme.of(context).colorScheme;
    final perfil = state.profile;
    final mensaje = state.message;
    final errorFormulario = state.fieldErrors[CampoPerfil.formulario];
    // La precarga también bloquea los campos, pero no se presenta como envío:
    // el spinner de «Guardar» solo aparece cuando hay una actualización en
    // curso (RNF-03).
    final editable = !state.isSubmitting && !state.isLoadingProfile;

    // Sin perfil real no se inventa un correo (RF-07, RF-09): el campo queda
    // vacío y se explica el motivo con la opción de reintentar.
    final avisoSinPerfil =
        perfil == null &&
        mensaje != null &&
        mensaje.tipo != AccountMessageType.sesionInvalida;
    final avisoOperacion =
        perfil != null &&
        mensaje != null &&
        (mensaje.tipo == AccountMessageType.aviso ||
            mensaje.tipo == AccountMessageType.error);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (perfil != null && state.isOffline) ...<Widget>[
          const ProfileNotice(
            message: MensajesCuenta.datosGuardados,
            icon: Icons.cloud_off_outlined,
          ),
          const SizedBox(height: 16),
        ],
        if (avisoSinPerfil) ...<Widget>[
          ProfileNotice(
            message: mensaje.text,
            icon: Icons.person_outline,
            actionLabel: 'Reintentar',
            onAction: () =>
                context.read<AccountBloc>().add(const ProfileRetryRequested()),
          ),
          const SizedBox(height: 16),
        ],
        if (avisoOperacion) ...<Widget>[
          ProfileNotice(
            message: mensaje.text,
            icon: mensaje.tipo == AccountMessageType.aviso
                ? Icons.cloud_off_outlined
                : Icons.error_outline,
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          key: const Key('update_profile_email'),
          controller: _correo,
          enabled: editable,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Correo electrónico',
            border: const OutlineInputBorder(),
            errorText: state.fieldErrors[CampoPerfil.correo],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('update_profile_password'),
          controller: _passwordNueva,
          enabled: editable,
          obscureText: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Contraseña nueva',
            border: const OutlineInputBorder(),
            errorText: state.fieldErrors[CampoPerfil.passwordNueva],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('update_profile_confirmation'),
          controller: _confirmacion,
          enabled: editable,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (editable) _enviar();
          },
          decoration: InputDecoration(
            labelText: 'Confirmar contraseña nueva',
            border: const OutlineInputBorder(),
            errorText: state.fieldErrors[CampoPerfil.confirmacion],
          ),
        ),
        if (errorFormulario != null) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            errorFormulario,
            key: const Key('update_profile_form_error'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.error),
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            OutlinedButton(
              key: const Key('update_profile_cancel'),
              onPressed: editable ? () => context.pop() : null,
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('update_profile_save'),
              onPressed: editable ? _enviar : null,
              child: state.isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar'),
            ),
          ],
        ),
      ],
    );
  }

  void _enviar() {
    _envioLanzado = true;
    context.read<AccountBloc>().add(
      ProfileUpdateSubmitted(
        correo: _correo.text,
        passwordNueva: _passwordNueva.text,
        confirmacion: _confirmacion.text,
      ),
    );
  }
}
