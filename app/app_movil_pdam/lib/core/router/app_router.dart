import 'package:app_movil_pdam/core/presentation/widgets/main_navigation_shell.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/qr_scaner_view.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/register_dispenser_view.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/create_pet_view.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/guided_schedule_form_view.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/pet_detail_view.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/pets_view.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

// Importamos tus pantallas
import 'package:app_movil_pdam/features/auth/presentation/views/login_view.dart';
import 'package:app_movil_pdam/features/auth/presentation/views/register_view.dart';
import 'package:app_movil_pdam/features/home/presentation/views/home_view.dart';

// Importamos el Bloc y el puente que creamos
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/core/router/bloc_refresh_listenable.dart';

class AppRouter {
  final AuthBloc authBloc;

  AppRouter(this.authBloc);

  late final router = GoRouter(
    // 1. Ruta con la que arrancará la app por defecto
    initialLocation: '/home',

    // 2. Le inyectamos el puente para que vigile al AuthBloc
    refreshListenable: BlocRefreshListenable(authBloc),

    // 3. El mapa de caminos de tu aplicación
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginView()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterView(),
      ),
      GoRoute(
        path: '/detail_pet',
        builder: (context, state) {
          final pet = state.extra as Pet;
          return PetDetailView(pet: pet);
        },
        // 🔥 Añadimos las sub-rutas para el feature del dispensador
        routes: [
          GoRoute(
            path: 'register-dispenser',
            name: 'register_dispenser',
            builder: (context, state) {
              // Recuperamos la entidad Pet que venía desde el detalle
              final pet = state.extra as Pet;
              return RegisterDispenserView(
                petId: pet.id,
              ); // Pasamos el petId al formulario
            },
          ),
          GoRoute(
            path: 'qr-scanner',
            name: 'qr_scanner',
            builder: (context, state) => const QrScannerView(),
          ),
        ],
      ),

      GoRoute(
        path: '/guided-schedule-form',
        name: 'guided_schedule_form',
        builder: (context, state) {
          // Extraemos la entidad Pet que pasamos por parámetros
          final pet = state.extra as Pet;

          return GuidedScheduleFormView(pet: pet);
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainNavigationShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeView(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/pets',
                builder: (context, state) => const PetsView(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/create_pet',
                builder: (context, state) => const CreatePetView(),
              ),
            ],
          ),
        ],
      ),
    ],

    // 4. El Guardián de Seguridad (Redirección Dinámica)
    redirect: (context, state) {
      final authState = context
          .read<AuthBloc>()
          .state; // O como manejes tu AuthState

      if (authState is AuthRegister) {
        print("Retornando al login");
        return '/login';
      }

      // 1. Si el usuario NO está autenticado, mándalo al login
      if (authState is AuthUnauthenticated) {
        if (state.matchedLocation != '/login' &&
            state.matchedLocation != '/register') {
          return '/login';
        }
        return null;
      }

      // 2. Si el usuario SÍ está autenticado:
      if (authState is AuthAuthenticated) {
        // Si ya está autenticado y va hacia rutas internas del flujo, déjalo pasar sin interferir.
        if (state.matchedLocation == '/login' || state.matchedLocation == '/') {
          return '/home'; // Solo redirige si intenta entrar al login estando ya logueado
        }

        // Para cualquier otra ruta interna (/detail_pet, /qr-scanner, etc.) RETORNA NULL
        return null;
      }

      return null;
    },
  );
}
