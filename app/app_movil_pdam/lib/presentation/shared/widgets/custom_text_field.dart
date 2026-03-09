import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPassword;
  final TextEditingController? controller;

  const CustomTextField({
    super.key,
    required this.label,
    required this.icon,
    this.isPassword = false,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: isPassword,

      style: const TextStyle(
        color: Colors.white,
      ), // Texto que escribe el usuario
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(
          icon,
          color: const Color(0xFF917CFF),
        ), // El morado de tu paleta
        // Fondo del campo de texto
        filled: true,
        fillColor: const Color(0x8D1E1E2C),

        // Bordes redondeados y personalizados
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF917CFF), width: 2),
        ),
      ),
    );
  }
}
