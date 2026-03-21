import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPassword;
  final TextEditingController? controller;
  final Function(String)? onChanged;
  

  const CustomTextField({
    super.key,
    required this.label,
    required this.icon,
    this.isPassword = false,
    this.controller, this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return TextField(
      controller: controller,
      obscureText: isPassword,
      onChanged: onChanged,
      // Texto que escribe el usuario
      style: TextStyle(
        color: theme.textTheme.bodyLarge?.color,
      ),

      decoration: InputDecoration(
        labelText: label,

        // Color del label según el tema
        labelStyle: TextStyle(
          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
        ),

        // Icono
        prefixIcon: Icon(
          icon,
          color: colors.primary,
        ),

        // Fondo del campo
        filled: true,
        fillColor: theme.cardColor,

        // Bordes
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(
            color: colors.outline.withValues(alpha: 0.5),
          ),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(
            color: colors.primary,
            width: 2,
          ),
        ),
      ),
    );
  }
}