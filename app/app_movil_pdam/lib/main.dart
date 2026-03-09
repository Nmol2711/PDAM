import 'package:app_movil_pdam/presentation/auth/views/login/login_screen.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "PDAM",
      home: Scaffold(body: Center(child: LoginScreen())),
    );
  }
}
