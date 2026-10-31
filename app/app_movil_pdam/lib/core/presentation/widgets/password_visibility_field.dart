import 'package:flutter/material.dart';

/// Campo de contraseña con su propio control de visibilidad (spec 017, RF-10).
///
/// El estado del ojo vive aquí y no en las vistas principales: la vista solo
/// compone el campo y recibe sus cambios. Empieza oculto, muestra el ojo con el
/// foco o con contenido y no altera texto, cursor, error ni validación.
///
/// Con [validator] construye un `TextFormField` para integrarse en un `Form`;
/// sin él construye un `TextField` y pinta [errorText] tal como llega de fuera.
class PasswordVisibilityField extends StatefulWidget {
  const PasswordVisibilityField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.errorText,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.keyboardType,
    this.textInputAction,
    this.prefixIcon,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? prefixIcon;

  @override
  State<PasswordVisibilityField> createState() =>
      _PasswordVisibilityFieldState();
}

class _PasswordVisibilityFieldState extends State<PasswordVisibilityField> {
  late final FocusNode _focusNode;
  bool _visible = false;

  /// Último resultado del validador: con error el ojo debe seguir visible
  /// aunque el campo esté vacío y sin foco (RF-10, casos límite).
  bool _errorDeValidacion = false;
  bool _repintadoPendiente = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_alCambiar);
    widget.controller.addListener(_alCambiar);
  }

  @override
  void didUpdateWidget(covariant PasswordVisibilityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_alCambiar);
      widget.controller.addListener(_alCambiar);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_alCambiar);
    _focusNode
      ..removeListener(_alCambiar)
      ..dispose();
    super.dispose();
  }

  /// Repinta el ojo cuando cambia el foco o el contenido del campo.
  void _alCambiar() {
    if (mounted) {
      setState(() {});
    }
  }

  void _alternarVisibilidad() => setState(() => _visible = !_visible);

  /// Envuelve al validador de la pantalla para recordar si hay error y
  /// repintar el ojo después de la validación del formulario.
  String? _validar(String? valor) {
    final error = widget.validator!(valor);
    final conError = error != null;
    if (conError != _errorDeValidacion) {
      _errorDeValidacion = conError;
      _programarRepintado();
    }
    return error;
  }

  void _programarRepintado() {
    if (_repintadoPendiente) {
      return;
    }
    _repintadoPendiente = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repintadoPendiente = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // El ojo puede ocultarse con el campo vacío y sin foco; vuelve con el foco,
    // el contenido o un error, y no desaparece al dejar de escribir.
    final mostrarOjo =
        _focusNode.hasFocus ||
        widget.controller.text.isNotEmpty ||
        widget.errorText != null ||
        _errorDeValidacion;
    final decoracion = InputDecoration(
      labelText: widget.label,
      prefixIcon: widget.prefixIcon,
      errorText: widget.errorText,
      suffixIcon: mostrarOjo
          ? IconButton(
              tooltip: _visible ? 'Ocultar contraseña' : 'Mostrar contraseña',
              icon: Icon(
                _visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: _alternarVisibilidad,
            )
          : null,
    );

    final validator = widget.validator;
    if (validator != null) {
      return TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        obscureText: !_visible,
        autocorrect: widget.autocorrect,
        enableSuggestions: widget.enableSuggestions,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onChanged: widget.onChanged,
        onFieldSubmitted: widget.onSubmitted,
        validator: _validar,
        decoration: decoracion,
      );
    }

    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      obscureText: !_visible,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: decoracion,
    );
  }
}
