import 'package:flutter/material.dart';

class MainScreenDesktop extends StatelessWidget {
  const MainScreenDesktop({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.amber,
      body: Center(child: Text("Desktop")),
    );
  }
}
