import 'package:app_movil_pdam/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

class CustomOutlinedButton extends StatelessWidget {
  final String text;
  final double fontSize;
  final VoidCallback? onPressed;

  const CustomOutlinedButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.fontSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        // "Semi cuadrado": un radio de 8 o 10 es ideal
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: Colors.white24), // Borde sutil
        padding: const EdgeInsets.symmetric(vertical: 15), // Altura cómoda
      ),
      child: Center(
        // Asegura que el texto esté centrado
        child: Padding(
          padding: const EdgeInsetsGeometry.symmetric(
            horizontal: 20,
            vertical: 5,
          ),
          child: AppTypography.textBody(text, fontSize: fontSize),
        ),
      ),
    );
  }
}
