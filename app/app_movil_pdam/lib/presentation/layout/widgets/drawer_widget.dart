import 'package:flutter/material.dart';

class DrawerWidget extends StatelessWidget {
  const DrawerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const DrawerHeader(
          child: Center(
            child: CircleAvatar(
              radius: 200,
              child: Text(
                "PDAM",
                style: TextStyle(color: Colors.black, fontSize: 24),
              ),
            ),
          ),
        ),
        _drawerItem(
          context,
          icon: Icons.dashboard,
          label: 'Dashboard',
          index: 0,
        ),
        _drawerItem(context, icon: Icons.schedule, label: 'Horarios', index: 1),
        _drawerItem(context, icon: Icons.history, label: 'Logs', index: 2),
      ],
    );
  }
}

Widget _drawerItem(
  BuildContext context, {
  required IconData icon,
  required String label,
  required int index,
}) {
  return ListTile(
    leading: Icon(icon, color: Colors.black),
    title: Text(label, style: const TextStyle(color: Colors.black)),
    onTap: () {
      // context.read<NavigationCubit>().setPage(index);
      // if (ResponsiveWidget.isMobile(context)) Navigator.pop(context); // Cierra el drawer en móvil
    },
  );
}
