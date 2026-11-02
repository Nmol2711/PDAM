import 'dart:io';
import 'dart:math' as math;

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/di/injection_container.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/core/theme/theme_cubit.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/auth/presentation/views/login_view.dart';
import 'package:app_movil_pdam/features/auth/presentation/views/register_view.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:app_movil_pdam/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/bloc/dashboard_cubit.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/views/dashboard_view.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/ble_scan_page.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/dispensers_page.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/register_dispenser_view.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/wifi_provisioning_page.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/scanner_notice_band.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:app_movil_pdam/features/logs/domain/repository/log_repositories.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_log_catalog_uc.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_logs_uc.dart';
import 'package:app_movil_pdam/features/logs/presentation/bloc/log_bloc.dart';
import 'package:app_movil_pdam/features/logs/presentation/views/logs_view.dart';
import 'package:app_movil_pdam/features/nutrition/domain/usecases/calculate_nutrition_usecase.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/bloc/nutrition_cubit.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/views/nutrition_calculator_view.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/create_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/delete_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/update_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/auto_generate_schedules_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/create_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_by_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/update_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/create_pet_view.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/edit_pet_view.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/guided_schedule_form_view.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/pet_detail_view.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/pets_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/settings_view.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/dispenser/presentation/bloc/dispenser_bloc_test.dart';
import '../../features/pets/presentation/bloc/schedule_bloc_test.dart';

class _FakeStorage implements StorageService {
  final Map<String, String> valores = <String, String>{};

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async {
    valores[key] = value;
    return const Right(null);
  }

  @override
  Future<Either<Failures, String?>> getString(String key) async =>
      Right(valores[key]);

  @override
  Future<Either<Failures, void>> deleteString(String key) async {
    valores.remove(key);
    return const Right(null);
  }
}

class _FakeUserRepository implements UserRepositories {
  @override
  Future<Either<Failures, User>> currentUser() async =>
      Right(User(id: 1, email: 'user@x.com'));

  @override
  Future<Either<Failures, User>> login(String email, String password) async =>
      Right(User(id: 1, email: email));

  @override
  Future<Either<Failures, User>> register(
    String email,
    String password,
    String confirmPassword,
  ) async => Right(User(id: 1, email: email));
}

class _FakeCleaner implements AccountLocalCleaner {
  @override
  Future<AccountCleanupResult> limpiarTrasBaja({String? correo}) async =>
      AccountCleanupResult.exito(pasosCompletados: AccountCleanupStep.values);

  @override
  Future<AccountCleanupResult?> limpiarSiPendiente() async => null;

  @override
  Future<void> limpiarPorSesionExpirada() async {}
}

class _FakePendingDeletionStore implements PendingDeletionStore {
  @override
  Future<void> markPending() async {}

  @override
  Future<bool> isPending() async => false;

  @override
  Future<void> clear() async {}
}

class _FakePetsRepository implements PetsRepositories {
  _FakePetsRepository(this.pet);

  final Pet pet;

  @override
  Future<Either<Failures, List<Pet>>> getPets() async => Right(<Pet>[pet]);

  @override
  Future<Either<Failures, Pet>> createPet(
    String name,
    TypePest species,
    DateTime birthDate,
    double weight,
    bool reproductiveStatus,
    File? imageFile,
  ) async => Right(pet);

  @override
  Future<Either<Failures, bool>> deletePet(int petId) async =>
      const Right(true);

  @override
  Future<Either<Failures, Pet>> getPet(int petId) async => Right(pet);

  @override
  Future<Either<Failures, Pet>> updatePet(
    int petId, {
    String? name,
    TypePest? species,
    DateTime? birthDate,
    double? weight,
    bool? reproductiveStatus,
    File? imageFile,
  }) async => Right(pet);
}

class _FakeLogRepository implements LogRepositories {
  @override
  Future<Either<Failures, LogFetchResult>> getLogs({
    required LogFilters filters,
    required int page,
    int pageSize = 50,
  }) async => Right(
    LogFetchResult(
      page: LogPage(
        items: <ActivityLog>[
          ActivityLog(
            id: 1,
            createdAt: DateTime(2026, 10, 1, 7, 30),
            eventType: 'feeding_dispensed',
            eventLabel: 'Comida dispensada',
            outcome: 'failure',
            outcomeLabel: 'Fallo',
            cause: 'sensor',
            causeLabel: 'Fallo del sensor durante la dispensación',
            description: 'Comida dispensada',
            petId: 1,
            petName: 'Milo',
            dispenserMacMasked: '**:AB:1F',
            orderId: 25,
            requestedGrams: 250,
            measuredGrams: 249.4,
            discountedGrams: 249.4,
            resultingStock: 1000,
            retryCount: 2,
            context: const <String, dynamic>{},
          ),
        ],
        total: 120,
        page: 1,
        pageSize: 50,
      ),
      isOffline: false,
    ),
  );

  @override
  Future<Either<Failures, LogCatalog>> getCatalog() async => const Right(
    LogCatalog(
      eventTypes: <LogCatalogEntry>[
        LogCatalogEntry(code: 'feeding_dispensed', label: 'Comida dispensada'),
      ],
      outcomes: <LogCatalogEntry>[
        LogCatalogEntry(code: 'success', label: 'Éxito'),
        LogCatalogEntry(code: 'failure', label: 'Fallo'),
      ],
    ),
  );
}

class _FakeDashboardRepository implements DashboardRepository {
  @override
  Future<Either<Failures, DashboardSummary>> getDashboardSummary() async =>
      const Right(
        DashboardSummary(
          totalPets: 3,
          sterilizedPets: 1,
          foodDispensedToday: 150,
          foodTargetToday: 300,
          pendingFeedings: 5,
          completedFeedings: 2,
          weeklyDispensed: <double>[10, 20, 30, 40, 50, 60, 70],
          todayIndex: 0,
        ),
      );
}

double _contraste(Color fondo, Color texto) {
  double canal(double valor) => valor <= 0.03928
      ? valor / 12.92
      : math.pow((valor + 0.055) / 1.055, 2.4).toDouble();
  double luminancia(Color color) =>
      0.2126 * canal(color.r) +
      0.7152 * canal(color.g) +
      0.0722 * canal(color.b);

  final l1 = luminancia(fondo);
  final l2 = luminancia(texto);
  final alto = l1 > l2 ? l1 : l2;
  final bajo = l1 > l2 ? l2 : l1;
  return (alto + 0.05) / (bajo + 0.05);
}

void main() {
  testWidgets('320, 600 y 840 vertical y horizontal con texto 1.3', (
    tester,
  ) async {
    const tamanos = <Size>[
      Size(320, 640),
      Size(640, 320),
      Size(600, 800),
      Size(800, 600),
      Size(840, 900),
      Size(900, 840),
    ];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(sl.reset);
    await sl.reset();

    final pet = Pet(
      id: 1,
      name: 'Milo',
      species: TypePest.canino,
      birthDate: DateTime(2020, 1, 1),
      weight: 12.5,
      reproductiveStatus: true,
    );
    const device = ScannedDevice(
      name: 'PDAM-Config-[123456]',
      remoteId: 'AA:BB:CC:DD:EE:FF',
      rssi: -45,
    );

    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final authBloc = AuthBloc(
      registerUc: RegisterUc(repository: _FakeUserRepository()),
      loginUc: LoginUc(repository: _FakeUserRepository()),
      currentUserUc: CurrentUserUc(repository: _FakeUserRepository()),
      pendingDeletionStore: _FakePendingDeletionStore(),
      sessionEvents: eventos,
      accountLocalCleaner: _FakeCleaner(),
    );
    addTearDown(authBloc.close);
    final themeCubit = ThemeCubit(storageService: _FakeStorage());
    addTearDown(themeCubit.close);
    final nutritionCubit = NutritionCubit(
      calculateNutritionUsecase: const CalculateNutritionUsecase(),
    );
    addTearDown(nutritionCubit.close);

    final petsRepository = _FakePetsRepository(pet);
    final petBloc = PetBloc(
      cretePetUc: CreatePetUc(repository: petsRepository),
      getPetUc: GetPetUc(repository: petsRepository),
      getPetsUc: GetPetsUc(repository: petsRepository),
      updatePetUc: UpdatePetUc(repository: petsRepository),
      deletePetUc: DeletePetsUc(repository: petsRepository),
    );
    addTearDown(petBloc.close);

    final scheduleRepository = MockScheduleRepository()
      ..schedules = <Schedule>[
        const Schedule(id: 1, time: '08:00', amount: 100, petId: 1),
      ];
    final scheduleBloc = ScheduleBloc(
      createScheduleUc: CreateScheduleUc(repository: scheduleRepository),
      getScheduleUc: GetScheduleUc(repository: scheduleRepository),
      getSchedulesUc: GetSchedulesUc(repository: scheduleRepository),
      getSchedulesByPetUc: GetSchedulesByPetUc(repository: scheduleRepository),
      autoGenerateSchedulesUc: AutoGenerateSchedulesUc(
        repository: scheduleRepository,
      ),
      updateScheduleUc: UpdateScheduleUc(repository: scheduleRepository),
    );
    addTearDown(scheduleBloc.close);

    final dispenserBloc = buildDispenserBloc(
      MockDispenserRepository(
        mockDispensers: const <Dispenser>[
          Dispenser(
            id: 1,
            macAddress: 'AA:BB:CC:DD:EE:FF',
            name: 'Dispensador Sala',
            isActive: true,
            currentFoodGrams: 2500,
          ),
        ],
      ),
    );

    final logRepository = _FakeLogRepository();
    final logBloc = LogBloc(
      getLogsUc: GetLogsUc(repository: logRepository),
      getLogCatalogUc: GetLogCatalogUc(repository: logRepository),
    );
    addTearDown(logBloc.close);

    sl.registerFactory<DashboardCubit>(
      () => DashboardCubit(repository: _FakeDashboardRepository()),
    );

    final providers = <BlocProvider<dynamic>>[
      BlocProvider<AuthBloc>.value(value: authBloc),
      BlocProvider<ThemeCubit>.value(value: themeCubit),
      BlocProvider<NutritionCubit>.value(value: nutritionCubit),
      BlocProvider<PetBloc>.value(value: petBloc),
      BlocProvider<ScheduleBloc>.value(value: scheduleBloc),
      BlocProvider<DispenserBloc>.value(value: dispenserBloc),
      BlocProvider<LogBloc>.value(value: logBloc),
    ];

    Future<void> montar(Widget home, {bool settle = true}) async {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: providers,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: home,
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      }
    }

    final pantallas = <({String nombre, Widget Function() crear})>[
      (nombre: 'Menú', crear: () => const SettingsView()),
      (nombre: 'Inicio de sesión', crear: () => const LoginView()),
      (nombre: 'Registro', crear: () => const RegisterView()),
      (nombre: 'Panel', crear: () => const DashboardView()),
      (nombre: 'Mascotas', crear: () => const PetsView()),
      (nombre: 'Detalle de mascota', crear: () => PetDetailView(pet: pet)),
      (nombre: 'Crear mascota', crear: () => const CreatePetView()),
      (nombre: 'Editar mascota', crear: () => EditPetView(pet: pet)),
      (nombre: 'Plan guiado', crear: () => GuidedScheduleFormView(pet: pet)),
      (nombre: 'Historial', crear: () => const LogsView()),
      (
        nombre: 'Dispositivos',
        crear: () => const DispensersPage(refreshInterval: null),
      ),
      (nombre: 'WiFi', crear: () => const WifiProvisioningPage(device: device)),
      (
        nombre: 'Registro de dispensador',
        crear: () => const RegisterDispenserView(petId: 1),
      ),
      (
        nombre: 'Calculadora nutricional',
        crear: () => const NutritionCalculatorView(),
      ),
      // El plugin de cámara no se monta en test; se verifica su capa de
      // presentación (velo y banda) en los mismos tamaños.
      (
        nombre: 'QR: banda presentacional',
        crear: () => const Scaffold(
          body: ScannerNoticeBand(
            message: 'No se pudo iniciar la cámara:\nCAMERA_ERROR',
            withScrim: true,
          ),
        ),
      ),
    ];

    for (final tamano in tamanos) {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;

      for (final pantalla in pantallas) {
        if (pantalla.nombre == 'Dispositivos') {
          dispenserBloc.add(LoadDispensersEvent());
        }
        await montar(pantalla.crear());
        expect(
          tester.takeException(),
          isNull,
          reason:
              '${pantalla.nombre} a ${tamano.width}x${tamano.height} '
              'con texto 1.3',
        );
      }

      // BLE se monta al final porque inicia un escaneo con temporizadores.
      await montar(const BleScanPage(), settle: false);
      try {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'BLE a ${tamano.width}x${tamano.height} con texto 1.3',
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump();
      }
    }
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });

  test('los rellenos de estado mantienen 4.5:1 en claro y oscuro', () {
    for (final tema in <ThemeData>[AppTheme.lightTheme, AppTheme.darkTheme]) {
      final esquema = tema.colorScheme;
      final semantica = tema.extension<AppSemanticColors>()!;
      final pares = <String, List<Color>>{
        'éxito': <Color>[semantica.success, semantica.onSuccess],
        'alerta': <Color>[semantica.alert, semantica.onAlert],
        'error': <Color>[esquema.error, esquema.onError],
        'contenedor de error': <Color>[
          esquema.errorContainer,
          esquema.onErrorContainer,
        ],
        'contenedor principal': <Color>[
          esquema.primaryContainer,
          esquema.onPrimaryContainer,
        ],
        'contenedor de acento': <Color>[
          esquema.tertiaryContainer,
          esquema.onTertiaryContainer,
        ],
        'superficie inversa': <Color>[
          esquema.inverseSurface,
          esquema.onInverseSurface,
        ],
      };

      for (final par in pares.entries) {
        expect(
          _contraste(par.value[0], par.value[1]),
          greaterThanOrEqualTo(4.5),
          reason: '${tema.brightness.name}: ${par.key} no alcanza 4.5:1',
        );
      }
    }
  });
}
