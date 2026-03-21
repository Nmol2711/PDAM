import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/presentation/auth/views/login/login_screen.dart';
import 'package:flutter/material.dart';
import 'core/di/injection_container.dart' as di;

void main()async {
  // Asegurar la inicializacion de Flutter
  WidgetsFlutterBinding.ensureInitialized();

  //Ejecutar la inyeccion de dependencias
  await di.init();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Registrar temas
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,

      // Usa el tema del sistema
      themeMode: ThemeMode.system,
      
      debugShowCheckedModeBanner: false,
      title: "PDAM",
      home:  const LoginScreen(),
    );
  }
}
