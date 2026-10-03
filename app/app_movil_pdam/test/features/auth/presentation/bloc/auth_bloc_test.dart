import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/auth_token.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/auth_token_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/auth_token_uc/delete_token_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';

class MockUserRepositories implements UserRepositories {
  @override
  Future<Either<Failures, User>> currentUser() async {
    return Right(User(id: 1, email: 'current@test.com'));
  }

  @override
  Future<Either<Failures, User>> login(String email, String password) async {
    return Right(User(id: 1, email: email));
  }

  @override
  Future<Either<Failures, User>> register(String email, String password, String confirmPassword) async {
    return Right(User(id: 1, email: email));
  }
}

class MockAuthTokenRepositories implements AuthTokenRepositories {
  @override
  Future<Either<Failures, AuthToken>> cacheToken(String token, {String typeToken = 'Bearer'}) async {
    return Right(AuthToken(token: token, typeToken: typeToken));
  }

  @override
  Future<Either<Failures, void>> deleteToken() async {
    return const Right(null);
  }

  @override
  Future<Either<Failures, AuthToken>> getToken() async {
    return Right(AuthToken(token: 'token', typeToken: 'Bearer'));
  }
}

void main() {
  late AuthBloc authBloc;
  late MockUserRepositories mockUserRepository;
  late MockAuthTokenRepositories mockTokenRepository;

  setUp(() {
    mockUserRepository = MockUserRepositories();
    mockTokenRepository = MockAuthTokenRepositories();

    authBloc = AuthBloc(
      registerUc: RegisterUc(repository: mockUserRepository),
      loginUc: LoginUc(repository: mockUserRepository),
      currentUserUc: CurrentUserUc(repository: mockUserRepository),
      deleteTokenUc: DeleteTokenUc(repository: mockTokenRepository),
    );
  });

  test('estado inicial debe ser AuthInitial', () {
    expect(authBloc.state, isA<AuthInitial>());
  });

  test('emitir AuthLoading y AuthAuthenticated en login exitoso', () async {
    final expectedStates = [
      isA<AuthLoading>(),
      isA<AuthAuthenticated>(),
    ];

    expectLater(authBloc.stream, emitsInOrder(expectedStates));

    authBloc.add(const AuthLoginRequested(email: 'test@pdam.com', password: '123'));
  });
}
