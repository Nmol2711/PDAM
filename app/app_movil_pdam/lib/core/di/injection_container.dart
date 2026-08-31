import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/router/app_router.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/local/auth_local_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/remote/auth_remote_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/repositories_impl/auth_repositories_impl.dart';
import 'package:app_movil_pdam/features/auth/data/repositories_impl/user_repositories_impl.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/auth_token_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/auth_token_uc/delete_token_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/repositories_impl/dispenser_repository_impl.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/activate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/associate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/check_pending_task_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/dasactivate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/delete_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/get_dispenser_by_pet_uc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/remote/pet_remote_datasource.dart';
import 'package:app_movil_pdam/features/pets/data/repository_impl/pet_repositories_impl.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/create_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/delete_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/update_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/remote/schedule_remote_datasource.dart';
import 'package:app_movil_pdam/features/pets/data/repository_impl/schedule_repository_impl.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/schedule_repositories.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/create_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_by_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_uc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

// El localizador Global
final sl = GetIt.instance;

Future<void> setup() async {
  // Fuente de datos local es la primera por que su dependencia no necesita de otra dependencias
  sl.registerLazySingleton<StorageService>(
    () => StorageServiceImpl(dataLocalService: const FlutterSecureStorage()),
  );

  // Dio Cleinte
  sl.registerLazySingleton(() => DioClient(sl<StorageService>()));

  // Fuente de Datos
  sl.registerLazySingleton<AuthRemoteDatasource>(
    () => AuthRemoteDatasourceImpl(dioClient: sl<DioClient>()),
  );
  sl.registerLazySingleton<PetRemoteDatasource>(
    () => PetRemoteDatasourceImpl(dioClient: sl<DioClient>()),
  );

  sl.registerLazySingleton<ScheduleRemoteDatasource>(
    () => ScheduleTemoteDatasourceImp(dioClient: sl<DioClient>()),
  );

  sl.registerLazySingleton<AuthLocalDatasource>(
    () => AuthLocalDatasourceImpl(storageService: sl<StorageService>()),
  );

  sl.registerLazySingleton<DispenserRemoteDatasource>(
    () => DispenserRemoteDatasourceImpl(dioClient: sl<DioClient>()),
  );

  // Repositorios
  sl.registerLazySingleton<AuthTokenRepositories>(
    () => AuthRepositoriesImpl(authLocalDatasource: sl<AuthLocalDatasource>()),
  );

  sl.registerLazySingleton<UserRepositories>(
    () => UserRepositoriesImpl(
      authLocalDatasource: sl<AuthLocalDatasource>(),
      authRemoteDatasource: sl<AuthRemoteDatasource>(),
    ),
  );

  sl.registerLazySingleton<PetsRepositories>(
    () => PetRepositoriesImpl(petRemoteDataosurce: sl<PetRemoteDatasource>()),
  );

  sl.registerLazySingleton<ScheduleRepositories>(
    () => ScheduleRepositoryImpl(
      scheduleRemoteDatasource: sl<ScheduleRemoteDatasource>(),
    ),
  );

  sl.registerLazySingleton<DispenserRepositories>(
    () => DispenserRepositoryImpl(
      dispenserRemoteDatasource: sl<DispenserRemoteDatasource>(),
    ),
  );

  // Use Case
  sl.registerLazySingleton(
    () => CurrentUserUc(repository: sl<UserRepositories>()),
  );
  sl.registerLazySingleton(() => LoginUc(repository: sl<UserRepositories>()));
  sl.registerLazySingleton(
    () => RegisterUc(repository: sl<UserRepositories>()),
  );

  sl.registerLazySingleton(
    () => DeleteTokenUc(repository: sl<AuthTokenRepositories>()),
  );

  // Pets

  sl.registerLazySingleton(
    () => CreatePetUc(repository: sl<PetsRepositories>()),
  );

  sl.registerLazySingleton(() => GetPetUc(repository: sl<PetsRepositories>()));

  sl.registerLazySingleton(() => GetPetsUc(repository: sl<PetsRepositories>()));

  sl.registerLazySingleton(
    () => UpdatePetUc(repository: sl<PetsRepositories>()),
  );

  sl.registerLazySingleton(
    () => DeletePetsUc(repository: sl<PetsRepositories>()),
  );

  // Schedule

  sl.registerLazySingleton(
    () => CreateScheduleUc(repository: sl<ScheduleRepositories>()),
  );
  sl.registerLazySingleton(
    () => GetScheduleUc(repository: sl<ScheduleRepositories>()),
  );
  sl.registerLazySingleton(
    () => GetSchedulesUc(repository: sl<ScheduleRepositories>()),
  );
  sl.registerLazySingleton(
    () => GetSchedulesByPetUc(repository: sl<ScheduleRepositories>()),
  );

  // Dispenser
  sl.registerLazySingleton(
    () => ActivateDispenserUc(repository: sl<DispenserRepositories>()),
  );
  sl.registerLazySingleton(
    () => AssociateDispenserUc(repository: sl<DispenserRepositories>()),
  );
  sl.registerLazySingleton(
    () => CheckPendingTaskUc(repository: sl<DispenserRepositories>()),
  );
  sl.registerLazySingleton(
    () => DesactivateDispenserUc(repository: sl<DispenserRepositories>()),
  );
  sl.registerLazySingleton(
    () => GetDispenserByPetUc(repository: sl<DispenserRepositories>()),
  );

  sl.registerLazySingleton(
    () => DeleteDispenserUc(repository: sl<DispenserRepositories>()),
  );

  sl.registerLazySingleton(
    () => DispenserBloc(
      associateUseCase: sl<AssociateDispenserUc>(),
      getDispenserByPetUseCase: sl<GetDispenserByPetUc>(),
      activateUseCase: sl<ActivateDispenserUc>(),
      deactivateUseCase: sl<DesactivateDispenserUc>(),
      deleteDispenserUseCase: sl<DeleteDispenserUc>(),
    ),
  );

  // Gestor de estado
  sl.registerLazySingleton(
    () => AuthBloc(
      registerUc: sl<RegisterUc>(),
      loginUc: sl<LoginUc>(),
      currentUserUc: sl<CurrentUserUc>(),
      deleteTokenUc: sl<DeleteTokenUc>(),
    ),
  );

  sl.registerLazySingleton(
    () => PetBloc(
      cretePetUc: sl<CreatePetUc>(),
      getPetUc: sl<GetPetUc>(),
      getPetsUc: sl<GetPetsUc>(),
      updatePetUc: sl<UpdatePetUc>(),
      deletePetUc: sl<DeletePetsUc>(),
    ),
  );

  sl.registerLazySingleton(
    () => ScheduleBloc(
      createScheduleUc: sl<CreateScheduleUc>(),
      getScheduleUc: sl<GetScheduleUc>(),
      getSchedulesUc: sl<GetSchedulesUc>(),
      getSchedulesByPetUc: sl<GetSchedulesByPetUc>(),
    ),
  );

  sl.registerLazySingleton(() => AppRouter(sl<AuthBloc>()));
}
