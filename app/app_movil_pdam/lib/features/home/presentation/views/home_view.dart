// features/home/presentation/views/home_view.dart (o donde desees ubicarla)
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    // Al estar autenticado, sabemos que el estado posee la entidad de usuario
    final authState = context.watch<AuthBloc>().state;
    String email = "Usuario";

    if (authState is AuthAuthenticated) {
      email = authState.user.email;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDAM Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AuthBloc>().add(AuthLogoutPressed());
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '¡Panel Principal del Dispensador!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              'Conectado como: $email',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
