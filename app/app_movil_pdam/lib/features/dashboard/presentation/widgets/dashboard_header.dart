import 'package:flutter/material.dart';

class DashboardHeader extends StatelessWidget {
  final String userName;
  final VoidCallback onThemeToggle;
  final VoidCallback onLogout;

  const DashboardHeader({
    super.key,
    required this.userName,
    required this.onThemeToggle,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              userName,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Panel de Control Nutricional',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.brightness_6_outlined),
              tooltip: 'Cambiar Tema',
              onPressed: onThemeToggle,
            ),
            const SizedBox(width: 4),
            CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: IconButton(
                icon: const Icon(Icons.logout, size: 18),
                tooltip: 'Cerrar sesión',
                onPressed: onLogout,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
