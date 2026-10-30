import 'package:app_movil_pdam/core/router/app_router.dart';
import 'package:app_movil_pdam/core/localization/app_localization.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/core/theme/theme_cubit.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/features/account/presentation/bloc/account_bloc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart';
import 'package:app_movil_pdam/features/logs/presentation/bloc/log_bloc.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/bloc/nutrition_cubit.dart';
import 'package:app_movil_pdam/utils/app_bloc_observer.dart';
import 'package:flutter/material.dart';

import 'package:app_movil_pdam/core/di/injection_container.dart' as di;
import 'package:flutter_bloc/flutter_bloc.dart';

void main() async {
  // Asegurar la inicializacion de Flutter
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = AppBlocObserver();
  await IsarService.init();
  await di.setup();

  // RNF-10: si una baja anterior dejó la limpieza local a medias, se reintenta
  // antes de arrancar. La marca solo se borra cuando la limpieza termina; si
  // vuelve a fallar, `AuthBloc` bloquea el acceso sin conexión con esas
  // credenciales. Nunca se impide el arranque de la aplicación.
  try {
    await di.sl<AccountLocalCleaner>().limpiarSiPendiente();
  } catch (_) {
    // La marca permanece y el bloqueo de acceso sin conexión sigue vigente.
  }

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
        // La cuenta vive por encima del enrutador: el menú y el perfil leen el
        // mismo estado y el BLoC se limpia al cerrar o expirar la sesión.
        BlocProvider<AccountBloc>(create: (context) => di.sl<AccountBloc>()),
        BlocProvider<PetBloc>(create: (context) => di.sl<PetBloc>()),
        BlocProvider<ScheduleBloc>(create: (context) => di.sl<ScheduleBloc>()),
        BlocProvider<DispenserBloc>(
          create: (context) =>
              di.sl<DispenserBloc>()..add(LoadDispensersEvent()),
        ),
        BlocProvider<LogBloc>(create: (context) => di.sl<LogBloc>()),
        BlocProvider<NutritionCubit>(
          create: (context) => di.sl<NutritionCubit>(),
        ),
        BlocProvider<ThemeCubit>(create: (context) => di.sl<ThemeCubit>()),
      ],

      child: Builder(
        // ◄ 2. AGREGAMOS ESTE BUILDER OBLIGATORIO
        builder: (context) {
          // 3. Al estar dentro del Builder, garantizamos que el router
          // lea el contexto actualizado del BlocProvider.
          final appRouter = di.sl<AppRouter>().router;

          return BlocBuilder<ThemeCubit, ThemeMode>(
            builder: (context, themeMode) {
              return MaterialApp.router(
                routerConfig: appRouter,
                // Registrar temas
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeMode,
                debugShowCheckedModeBanner: false,
                title: "PDAM",
                // Español también en los textos del SDK: el selector de rango
                // de fechas del historial sale en español (spec 014, T10).
                locale: idiomaPorDefecto,
                supportedLocales: idiomasAdmitidos,
                localizationsDelegates: delegadosDeLocalizacion,
              );
            },
          );
        },
      ),
    );
  }
}
