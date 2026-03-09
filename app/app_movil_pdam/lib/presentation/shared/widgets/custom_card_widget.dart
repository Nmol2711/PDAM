import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

class CustomCardWidget extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  const CustomCardWidget({
    super.key,
    required this.child,
    this.padding,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Usamos el color de tu paleta (darkCard)
        color: color ?? AppColors.darkCard,
        borderRadius: BorderRadius.circular(
          20,
        ), // Bordes redondeados profesionales
        boxShadow: [
          BoxShadow(
            color: const Color(0x39000000),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
