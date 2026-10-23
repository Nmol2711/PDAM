import 'package:app_movil_pdam/core/di/injection_container.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/auth_token.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/auth_token_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/auth_token_uc/delete_token_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:app_movil_pdam/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/bloc/dashboard_cubit.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/views/dashboard_view.dart';
import 'package:app_movil_pdam/features/nutrition/domain/usecases/calculate_nutrition_usecase.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/bloc/nutrition_cubit.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/views/nutrition_calculator_view.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// RF-6: el dashboard expone un punto de entrada visible que navega a la
/// calculadora nutricional sin que el usuario conozca la ruta interna.
void main() {
  setUp(() async {
    await sl.reset();
    sl.registerFactory<DashboardCubit>(
      () => DashboardCubit(repository: _FakeDashboardRepository()),
    );
  });

  tearDown(() async {
    await sl.reset();
  });

  Future<AuthBloc> buildAuthenticatedBloc() async {
    final bloc = AuthBloc(
      registerUc: RegisterUc(repository: _FakeUserRepository()),
      loginUc: LoginUc(repository: _FakeUserRepository()),
      currentUserUc: CurrentUserUc(repository: _FakeUserRepository()),
      deleteTokenUc: DeleteTokenUc(repository: _FakeTokenRepository()),
    );
    bloc.add(AuthCheckStatusRequested());
    await bloc.stream.firstWhere((state) => state is AuthAuthenticated);
    return bloc;
  }

  testWidgets('el acceso visible navega a NutritionCalculatorView', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authBloc = await buildAuthenticatedBloc();
    addTearDown(authBloc.close);
    final nutritionCubit = NutritionCubit(
      calculateNutritionUsecase: const CalculateNutritionUsecase(),
    );
    addTearDown(nutritionCubit.close);

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (context, state) => const DashboardView()),
        GoRoute(
          path: '/nutrition-calculator',
          name: 'nutrition_calculator',
          builder: (context, state) => const NutritionCalculatorView(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<NutritionCubit>.value(value: nutritionCubit),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final acceso = find.text('Calculadora Nutricional');
    expect(acceso, findsOneWidget);

    await tester.ensureVisible(acceso);
    await tester.tap(acceso);
    await tester.pumpAndSettle();

    expect(find.byType(NutritionCalculatorView), findsOneWidget);
  });
}

class _FakeDashboardRepository implements DashboardRepository {
  @override
  Future<Either<Failures, DashboardSummary>> getDashboardSummary() async {
    return const Right(
      DashboardSummary(
        totalPets: 0,
        sterilizedPets: 0,
        foodDispensedToday: 0,
        foodTargetToday: 0,
        pendingFeedings: 0,
        completedFeedings: 0,
        weeklyDispensed: [0, 0, 0, 0, 0, 0, 0],
      ),
    );
  }
}

class _FakeUserRepository implements UserRepositories {
  @override
  Future<Either<Failures, User>> currentUser() async {
    return Right(User(id: 1, email: 'usuario@test.com'));
  }

  @override
  Future<Either<Failures, User>> login(String email, String password) async {
    return Right(User(id: 1, email: email));
  }

  @override
  Future<Either<Failures, User>> register(
    String email,
    String password,
    String confirmPassword,
  ) async {
    return Right(User(id: 1, email: email));
  }
}

class _FakeTokenRepository implements AuthTokenRepositories {
  @override
  Future<Either<Failures, AuthToken>> cacheToken(
    String token, {
    String typeToken = 'Bearer',
  }) async {
    return Right(AuthToken(token: token, typeToken: typeToken));
  }

  @override
  Future<Either<Failures, void>> deleteToken() async {
    return const Right(null);
  }

  @override
  Future<Either<Failures, AuthToken>> getToken() async {
    return Right(AuthToken(token: 'token'));
  }
}
