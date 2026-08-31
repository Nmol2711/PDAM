import 'package:app_movil_pdam/core/router/app_router.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart';
import 'package:app_movil_pdam/utils/app_bloc_observer.dart';
import 'package:flutter/material.dart';

import 'package:app_movil_pdam/core/di/injection_container.dart' as di;
import 'package:flutter_bloc/flutter_bloc.dart';

void main() async {
  // Asegurar la inicializacion de Flutter
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = AppBlocObserver();
  await di.setup();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      // 1. Mantenemos la creación e inicialización del Bloc
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) =>
              di.sl<AuthBloc>()..add(AuthCheckStatusRequested()),
        ),
        BlocProvider<PetBloc>(create: (context) => di.sl<PetBloc>()),
        BlocProvider<ScheduleBloc>(create: (context) => di.sl<ScheduleBloc>()),
        BlocProvider<DispenserBloc>(
          create: (context) => di.sl<DispenserBloc>(),
        ),
      ],

      child: Builder(
        // ◄ 2. AGREGAMOS ESTE BUILDER OBLIGATORIO
        builder: (context) {
          // 3. Al estar dentro del Builder, garantizamos que el router
          // lea el contexto actualizado del BlocProvider.
          final appRouter = di.sl<AppRouter>().router;

          return MaterialApp.router(
            routerConfig: appRouter,
            // Registrar temas
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.system,
            debugShowCheckedModeBanner: false,
            title: "PDAM",
          );
        },
      ),
    );
  }
}
