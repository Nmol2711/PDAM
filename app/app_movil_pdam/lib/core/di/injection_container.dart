import 'package:app_movil_pdam/data/data_sources/local/auth_local_data_source.dart';
import 'package:app_movil_pdam/data/data_sources/remote/auth_remote_data_source.dart';
import 'package:app_movil_pdam/data/data_sources/remote/log_remote_data_source.dart';
import 'package:app_movil_pdam/data/data_sources/remote/schedule_remote_data_source.dart';
import 'package:app_movil_pdam/data/repositories/auth_repository_impl.dart';
import 'package:app_movil_pdam/data/repositories/log_repository_impl.dart';
import 'package:app_movil_pdam/data/repositories/schedule_repository_impl.dart';
import 'package:app_movil_pdam/domain/repositories/auth_repository.dart';
import 'package:app_movil_pdam/domain/repositories/log_repository.dart';
import 'package:app_movil_pdam/domain/repositories/schedule_repository.dart';
import 'package:app_movil_pdam/domain/use_cases/auth/delete_token_use_case.dart';
import 'package:app_movil_pdam/domain/use_cases/auth/get_current_user_use_case.dart';
import 'package:app_movil_pdam/domain/use_cases/auth/get_token_use_case.dart';
import 'package:app_movil_pdam/domain/use_cases/auth/login_use_case.dart';
import 'package:app_movil_pdam/domain/use_cases/auth/save_token_use_case.dart';
import 'package:app_movil_pdam/domain/use_cases/auth/sing_up_use_case.dart';
import 'package:app_movil_pdam/domain/use_cases/log/create_log_use_case.dart';
import 'package:app_movil_pdam/domain/use_cases/log/get_logs_use_cases.dart';
import 'package:app_movil_pdam/domain/use_cases/schedule/create_schedule_use_case.dart' show CreateScheduleUseCase;
import 'package:app_movil_pdam/domain/use_cases/schedule/get_schedules_use_case.dart';
import 'package:app_movil_pdam/domain/use_cases/schedule/get_time_schedules.dart';
import 'package:app_movil_pdam/domain/use_cases/schedule/update_schedule_use_case.dart';
import 'package:app_movil_pdam/presentation/auth/bloc/auth_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // 1) Feature: Bloc (Presentation)
  sl.registerFactory(() => AuthBloc(loginUseCase: sl(), singUpUseCase: sl()));

  // 2) Use Cases (Domain)
  //Autenticación
  sl.registerLazySingleton(() => LoginUseCase(sl()));
  sl.registerLazySingleton(() => SingUpUseCase(sl()));
  sl.registerLazySingleton(() => GetTokenUseCase(sl()));
  sl.registerLazySingleton(() => SaveTokenUseCase(sl()));
  sl.registerLazySingleton(() => DeleteTokenUseCase(sl()));
  sl.registerLazySingleton(() => GetCurrentUserUseCase(sl()));

  //Log
  sl.registerLazySingleton(() => CreateLogUseCase(sl()));
  sl.registerLazySingleton(() => GetLogsUseCases(sl()));

  //Schedule (Horario)
  sl.registerLazySingleton(() => CreateScheduleUseCase(sl()));
  sl.registerLazySingleton(() => GetSchedulesUseCase(sl()));
  sl.registerLazySingleton(() => GetTimeSchedules(sl()));
  sl.registerLazySingleton(() => UpdateScheduleUseCase(sl()));

  // 3) Repositories (Data -> Domain)
  //Autenticación
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      authLocalDataSource: sl(),
      authRemoteDataSource: sl()
      )
    );

  //Log
  sl.registerLazySingleton<LogRepository>(
    () => LogRepositoryImpl(
      logRemoteDataSource: sl(), 
      authLocalDataSource: sl()
      )
    );
  
  //Horario
  sl.registerLazySingleton<ScheduleRepository>(
    () => ScheduleRepositoryImpl(
      scheduleRemoteDataSource: sl(), 
      authLocalDataSource: sl()
      ),
    );

  // 4) Data Sources (Data)
  //a) Remote
  //Auth
  sl.registerLazySingleton<AuthRemoteDataSource>(() => AuthRemoteDataSourceImpl());
  //Log
  sl.registerLazySingleton<LogRemoteDataSource>(() => LogRemoteDataSourceImpl());
  //Schedule
  sl.registerLazySingleton<ScheduleRemoteDataSource>(() => ScheduleRemoteDataSourceImpl());

  //b) Local
  //Auth
  sl.registerLazySingleton<AuthLocalDataSource>(() => AuthLocalDataSourceImpl(storage: sl()));

  //Fluter Secure Storage
  sl.registerLazySingleton(() => const FlutterSecureStorage());
}