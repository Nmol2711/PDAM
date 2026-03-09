import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

class AppTheme {
  // TEMA OSCURO
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkBackground,
    cardColor: AppColors.darkCard,
    primaryColor: AppColors.primaryPurple,
    textTheme: const TextTheme(bodyLarge: TextStyle(color: Colors.white)),
  );

  // TEMA CLARO
  static ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBackground,
    cardColor: AppColors.lightCard,
    primaryColor: AppColors.primaryPurple,
    textTheme: const TextTheme(bodyLarge: TextStyle(color: Color(0xFF2D2D2D))),
  );
}
