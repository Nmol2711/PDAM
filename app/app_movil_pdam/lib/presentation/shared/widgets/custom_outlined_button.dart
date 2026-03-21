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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),

        // Color del borde según el tema
        side: BorderSide(
          color: colors.outline,
        ),

        padding: const EdgeInsets.symmetric(vertical: 15),

        // Color cuando se presiona
        foregroundColor: colors.primary,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 5,
          ),
          child: AppTypography.textBody(
            context,
            text,
            fontSize: fontSize,
            color: theme.textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }
}