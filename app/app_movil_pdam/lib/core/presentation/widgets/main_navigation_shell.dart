// core/presentation/widgets/main_navigation_shell.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainNavigationShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainNavigationShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 600;

        if (isWideScreen) {
          const titles = ['Inicio', 'Mascotas', 'Historial'];
          final currentTitle = titles[navigationShell.currentIndex];

          return Scaffold(
            appBar: AppBar(
              title: Text(currentTitle),
            ),
            drawer: NavigationDrawer(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (int index) {
                navigationShell.goBranch(
                  index,
                  initialLocation: index == navigationShell.currentIndex,
                );
                Navigator.of(context).pop(); // Cierra el drawer al seleccionar
              },
              children: const [
                Padding(
                  padding: EdgeInsets.fromLTRB(28, 24, 16, 12),
                  child: Text(
                    'PDAM - Menú',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Divider(),
                NavigationDrawerDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('Inicio'),
                ),
                NavigationDrawerDestination(
                  icon: Icon(Icons.pets_outlined),
                  selectedIcon: Icon(Icons.pets),
                  label: Text('Mascotas'),
                ),
                NavigationDrawerDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history),
                  label: Text('Historial'),
                ),
              ],
            ),
            body: navigationShell,
          );
        }

        // Vista móvil normal: mantiene la barra de navegación inferior clásica
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: navigationShell.currentIndex,
            type: BottomNavigationBarType.fixed,
            onTap: (int index) {
              navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              );
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined),
                activeIcon: Icon(Icons.dashboard),
                label: 'Inicio',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.pets_outlined),
                activeIcon: Icon(Icons.pets),
                label: 'Mascotas',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history_outlined),
                activeIcon: Icon(Icons.history),
                label: 'Historial',
              ),
            ],
          ),
        );
      },
    );
  }
}
