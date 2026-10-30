import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/offline/sync_service.dart';
import 'package:app_movil_pdam/core/router/app_router.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/core/theme/theme_cubit.dart';
import 'package:app_movil_pdam/features/account/data/datasource/local/local_profile_datasource.dart';
import 'package:app_movil_pdam/features/account/data/datasource/remote/account_remote_datasource.dart';
import 'package:app_movil_pdam/features/account/data/repository_impl/account_repository_impl.dart';
import 'package:app_movil_pdam/features/account/domain/repository/account_repository.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/delete_account_uc.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/get_profile_uc.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/update_profile_uc.dart';
import 'package:app_movil_pdam/features/account/presentation/bloc/account_bloc.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/local/auth_local_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/remote/auth_remote_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/repositories_impl/auth_repositories_impl.dart';
import 'package:app_movil_pdam/features/auth/data/repositories_impl/user_repositories_impl.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/auth_token_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/auth_token_uc/delete_token_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/auth_token_uc/register_token_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/dashboard/data/datasources/dashboard_remote_datasource.dart';
import 'package:app_movil_pdam/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:app_movil_pdam/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/bloc/dashboard_cubit.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/local/local_dispenser_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/repositories_impl/dispenser_repository_impl.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/activate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/associate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/check_pending_task_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/dasactivate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/delete_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/get_dispenser_by_pet_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/update_dispenser_mac_uc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_pet_datasource.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_schedule_datasource.dart';
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
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/auto_generate_schedules_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/update_schedule_uc.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/local/local_log_datasource.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/remote/log_remote_datasource.dart';
import 'package:app_movil_pdam/features/logs/data/repository_impl/log_repository_impl.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_log_catalog_uc.dart';
import 'package:app_movil_pdam/features/logs/domain/repository/log_repositories.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_logs_uc.dart';
import 'package:app_movil_pdam/features/logs/presentation/bloc/log_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/data/services/ble_provisioning_service.dart';
import 'package:app_movil_pdam/features/nutrition/domain/usecases/calculate_nutrition_usecase.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/bloc/nutrition_cubit.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

// El localizador Global
final sl = GetIt.instance;

Future<void> setup() async {
  // Fuente de datos local es la primera por que su dependencia no necesita de otra dependencias
  sl.registerLazySingleton<StorageService>(
    () => StorageServiceImpl(dataLocalService: const FlutterSecureStorage()),
  );

  // Canal de avisos de sesión compartido por el interceptor y AuthBloc (RF-05).
  sl.registerLazySingleton<SessionEvents>(() => SessionEvents());

  // Marca de baja pendiente en almacenamiento seguro (RNF-10).
  sl.registerLazySingleton<PendingDeletionStore>(
    () => PendingDeletionStoreImpl(storageService: sl<StorageService>()),
  );

  // Dio Cleinte
  sl.registerLazySingleton(
    () => DioClient(sl<StorageService>(), sessionEvents: sl<SessionEvents>()),
  );

  // Sincronización (consulta de conexión usada por el registro de dispensadores)
  sl.registerLazySingleton<SyncService>(
    () => SyncService(dioClient: sl<DioClient>()),
  );

  // Fuente de Datos
  sl.registerLazySingleton<AuthRemoteDatasource>(
    () => AuthRemoteDatasourceImpl(dioClient: sl<DioClient>()),
  );
  sl.registerLazySingleton<AccountRemoteDatasource>(
    () => AccountRemoteDatasourceImpl(dioClient: sl<DioClient>()),
  );
  sl.registerLazySingleton<LocalProfileDatasource>(
    () => LocalProfileDatasourceImpl(),
  );
  sl.registerLazySingleton<PetRemoteDatasource>(
    () => PetRemoteDatasourceImpl(dioClient: sl<DioClient>()),
  );

  sl.registerLazySingleton<LocalPetDatasource>(() => LocalPetDatasourceImpl());

  sl.registerLazySingleton<LocalLogDatasource>(() => LocalLogDatasourceImpl());

  sl.registerLazySingleton<LocalScheduleDatasource>(
    () => LocalScheduleDatasourceImpl(),
  );

  sl.registerLazySingleton<LocalDispenserDatasource>(
    () => LocalDispenserDatasourceImpl(),
  );

  sl.registerLazySingleton<ScheduleRemoteDatasource>(
    () => ScheduleTemoteDatasourceImp(dioClient: sl<DioClient>()),
  );

  sl.registerLazySingleton<AuthLocalDatasource>(
    () => AuthLocalDatasourceImpl(storageService: sl<StorageService>()),
  );

  // Limpieza local de la baja con marca persistente (RF-18, RNF-10). Borra
  // token, tipo, credenciales, perfil y colecciones Isar; conserva el tema.
  sl.registerLazySingleton<AccountLocalCleaner>(
    () => AccountLocalCleanerImpl(
      pendingDeletionStore: sl<PendingDeletionStore>(),
      authLocalDatasource: sl<AuthLocalDatasource>(),
      localProfileDatasource: sl<LocalProfileDatasource>(),
    ),
  );

  sl.registerLazySingleton<DispenserRemoteDatasource>(
    () => DispenserRemoteDatasourceImpl(dioClient: sl<DioClient>()),
  );

  sl.registerLazySingleton<LogRemoteDatasource>(
    () => LogRemoteDatasourceImpl(dioClient: sl<DioClient>()),
  );

  sl.registerLazySingleton<DashboardRemoteDatasource>(
    () => DashboardRemoteDatasourceImpl(dioClient: sl<DioClient>()),
  );

  // Repositorios
  sl.registerLazySingleton<AuthTokenRepositories>(
    () => AuthRepositoriesImpl(authLocalDatasource: sl<AuthLocalDatasource>()),
  );

  sl.registerLazySingleton<UserRepositories>(
    () => UserRepositoriesImpl(
      authLocalDatasource: sl<AuthLocalDatasource>(),
      authRemoteDatasource: sl<AuthRemoteDatasource>(),
      localProfileDatasource: sl<LocalProfileDatasource>(),
    ),
  );

  sl.registerLazySingleton<AccountRepository>(
    () => AccountRepositoryImpl(
      remoteDatasource: sl<AccountRemoteDatasource>(),
      localProfileDatasource: sl<LocalProfileDatasource>(),
      // RF-14: tras un cambio de correo o contraseña se actualizan las
      // credenciales cifradas del acceso sin conexión en este dispositivo.
      authLocalDatasource: sl<AuthLocalDatasource>(),
    ),
  );

  sl.registerLazySingleton<PetsRepositories>(
    () => PetRepositoriesImpl(
      petRemoteDataosurce: sl<PetRemoteDatasource>(),
      localPetDatasource: sl<LocalPetDatasource>(),
    ),
  );

  sl.registerLazySingleton<ScheduleRepositories>(
    () => ScheduleRepositoryImpl(
      scheduleRemoteDatasource: sl<ScheduleRemoteDatasource>(),
      localScheduleDatasource: sl<LocalScheduleDatasource>(),
    ),
  );

  sl.registerLazySingleton<BleProvisioningService>(
    () => BleProvisioningService(),
  );

  sl.registerLazySingleton<DispenserRepositories>(
    () => DispenserRepositoryImpl(
      dispenserRemoteDatasource: sl<DispenserRemoteDatasource>(),
      localDispenserDatasource: sl<LocalDispenserDatasource>(),
      syncService: sl<SyncService>(),
      bleService: sl<BleProvisioningService>(),
      dioClient: sl<DioClient>(),
      storageService: sl<StorageService>(),
    ),
  );

  sl.registerLazySingleton<LogRepositories>(
    () => LogRepositoryImpl(
      remoteDatasource: sl<LogRemoteDatasource>(),
      localLogDatasource: sl<LocalLogDatasource>(),
    ),
  );

  sl.registerLazySingleton<DashboardRepository>(
    () => DashboardRepositoryImpl(
      remoteDatasource: sl<DashboardRemoteDatasource>(),
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

  sl.registerLazySingleton(
    () => RegisterTokenUc(repository: sl<AuthTokenRepositories>()),
  );

  // Cuenta (spec 015)
  sl.registerLazySingleton(
    () => GetProfileUc(repository: sl<AccountRepository>()),
  );
  sl.registerLazySingleton(
    () => UpdateProfileUc(repository: sl<AccountRepository>()),
  );
  sl.registerLazySingleton(
    () => DeleteAccountUc(repository: sl<AccountRepository>()),
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
  sl.registerLazySingleton(
    () => AutoGenerateSchedulesUc(repository: sl<ScheduleRepositories>()),
  );
  sl.registerLazySingleton(
    () => UpdateScheduleUc(repository: sl<ScheduleRepositories>()),
  );

  sl.registerLazySingleton(() => GetLogsUc(repository: sl<LogRepositories>()));
  sl.registerLazySingleton(
    () => GetLogCatalogUc(repository: sl<LogRepositories>()),
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
    () => UpdateDispenserMacUc(repository: sl<DispenserRepositories>()),
  );

  // Nutrición (motor WSAVA, Spec 011)
  sl.registerLazySingleton(() => const CalculateNutritionUsecase());

  sl.registerLazySingleton(
    () => DispenserBloc(
      repository: sl<DispenserRepositories>(),
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
      pendingDeletionStore: sl<PendingDeletionStore>(),
      sessionEvents: sl<SessionEvents>(),
      // RF-19: un 401 borra token, credenciales y perfil cacheado antes de
      // cerrar la sesión; conserva mascotas, horarios e historial.
      accountLocalCleaner: sl<AccountLocalCleaner>(),
    ),
  );

  sl.registerLazySingleton(
    () => AccountBloc(
      getProfileUc: sl<GetProfileUc>(),
      updateProfileUc: sl<UpdateProfileUc>(),
      deleteAccountUc: sl<DeleteAccountUc>(),
      registerTokenUc: sl<RegisterTokenUc>(),
      accountLocalCleaner: sl<AccountLocalCleaner>(),
      sessionEvents: sl<SessionEvents>(),
      // El cierre de sesión, la expiración y la baja limpian el perfil para no
      // mostrar datos de una cuenta anterior (RF-05, RF-18).
      authStates: sl<AuthBloc>().stream,
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
      autoGenerateSchedulesUc: sl<AutoGenerateSchedulesUc>(),
      updateScheduleUc: sl<UpdateScheduleUc>(),
    ),
  );

  sl.registerLazySingleton(
    () => LogBloc(
      getLogsUc: sl<GetLogsUc>(),
      getLogCatalogUc: sl<GetLogCatalogUc>(),
    ),
  );

  sl.registerFactory(
    () => NutritionCubit(
      calculateNutritionUsecase: sl<CalculateNutritionUsecase>(),
    ),
  );

  sl.registerFactory(
    () => DashboardCubit(repository: sl<DashboardRepository>()),
  );

  sl.registerLazySingleton(
    () => ThemeCubit(storageService: sl<StorageService>()),
  );

  sl.registerLazySingleton(() => AppRouter(sl<AuthBloc>()));
}
