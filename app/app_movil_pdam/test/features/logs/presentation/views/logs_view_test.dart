import 'dart:async';
import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:app_movil_pdam/features/logs/domain/repository/log_repositories.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_log_catalog_uc.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_logs_uc.dart';
import 'package:app_movil_pdam/features/logs/presentation/bloc/log_bloc.dart';
import 'package:app_movil_pdam/features/logs/presentation/views/logs_view.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/create_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/delete_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/get_pets_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/update_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/pet_bloc/pet_bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

ActivityLog _log({
  int id = 1,
  String? eventType = 'feeding_dispensed',
  String? eventLabel = 'Comida dispensada',
  String? outcome = 'success',
  String? outcomeLabel = 'Éxito',
  String? cause = 'objetivo_alcanzado',
  String? causeLabel = 'Objetivo alcanzado',
  int? petId = 1,
  String? petName = 'Milo',
  String? mac = '**:AB:1F',
  double? requested = 50,
  double? measured = 50.4,
  double? discounted = 50.4,
}) {
  return ActivityLog(
    id: id,
    createdAt: DateTime(2026, 10, 1, 7, 30),
    eventType: eventType,
    eventLabel: eventLabel,
    outcome: outcome,
    outcomeLabel: outcomeLabel,
    cause: cause,
    causeLabel: causeLabel,
    description: eventLabel ?? 'Registro',
    petId: petId,
    petName: petName,
    dispenserMacMasked: mac,
    orderId: 12,
    requestedGrams: requested,
    measuredGrams: measured,
    discountedGrams: discounted,
    resultingStock: 1000,
    retryCount: 0,
    context: const {},
  );
}

class _FakeLogRepository implements LogRepositories {
  LogPage page = const LogPage(items: [], total: 0, page: 1, pageSize: 50);
  bool offline = false;
  Failures? failure;
  int calls = 0;
  int? lastPage;
  LogFilters? lastFilters;

  /// Si está presente, la consulta no responde hasta completarlo: permite
  /// observar el estado de carga antes de la primera respuesta.
  Completer<void>? blocker;

  @override
  Future<Either<Failures, LogFetchResult>> getLogs({
    required LogFilters filters,
    required int page,
    int pageSize = 50,
  }) async {
    calls++;
    lastPage = page;
    lastFilters = filters;
    final espera = blocker;
    if (espera != null) {
      await espera.future;
      blocker = null;
    }
    if (failure != null) return Left(failure!);
    return Right(LogFetchResult(page: this.page, isOffline: offline));
  }

  @override
  Future<Either<Failures, LogCatalog>> getCatalog() async => const Right(
    LogCatalog(
      eventTypes: [
        LogCatalogEntry(code: 'feeding_dispensed', label: 'Comida dispensada'),
        LogCatalogEntry(code: 'pet_created', label: 'Mascota creada'),
      ],
      outcomes: [
        LogCatalogEntry(code: 'success', label: 'Éxito'),
        LogCatalogEntry(code: 'failure', label: 'Fallo'),
      ],
    ),
  );
}

class _FakePetsRepository implements PetsRepositories {
  @override
  Future<Either<Failures, List<Pet>>> getPets() async => Right([
    Pet(
      id: 1,
      name: 'Milo',
      species: TypePest.canino,
      birthDate: DateTime(2020, 1, 1),
      weight: 5,
      reproductiveStatus: false,
    ),
  ]);

  @override
  Future<Either<Failures, Pet>> createPet(
    String name,
    TypePest species,
    DateTime birthDate,
    double weight,
    bool reproductiveStatus,
    File? imageFile,
  ) async => Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, bool>> deletePet(int petId) async =>
      Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, Pet>> getPet(int petId) async =>
      Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, Pet>> updatePet(
    int petId, {
    String? name,
    TypePest? species,
    DateTime? birthDate,
    double? weight,
    bool? reproductiveStatus,
    File? imageFile,
  }) async => Left(ServerFailures('no usado'));
}

void main() {
  late _FakeLogRepository repository;
  LogBloc? logBloc;
  PetBloc? petBloc;

  setUp(() {
    repository = _FakeLogRepository();
    logBloc = null;
    petBloc = null;
  });

  tearDown(() async {
    await logBloc?.close();
    await petBloc?.close();
  });

  /// Los BLoC se crean dentro del cuerpo del test para que sus microtareas
  /// corran en la zona de tiempo simulado de `testWidgets`.
  void crearBlocs() {
    logBloc = LogBloc(
      getLogsUc: GetLogsUc(repository: repository),
      getLogCatalogUc: GetLogCatalogUc(repository: repository),
    );
    final petsRepository = _FakePetsRepository();
    petBloc = PetBloc(
      cretePetUc: CreatePetUc(repository: petsRepository),
      getPetUc: GetPetUc(repository: petsRepository),
      getPetsUc: GetPetsUc(repository: petsRepository),
      updatePetUc: UpdatePetUc(repository: petsRepository),
      deletePetUc: DeletePetsUc(repository: petsRepository),
    );
  }

  /// Bombea los fotogramas necesarios para que la cadena de futuros del BLoC
  /// (catálogo, página y mascotas) se resuelva por completo.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpView(
    WidgetTester tester, {
    bool settle = true,
    double textScaler = 1.0,
  }) async {
    crearBlocs();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LogBloc>.value(value: logBloc!),
          BlocProvider<PetBloc>.value(value: petBloc!),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          // El escalado de texto se aplica como en el dispositivo: la pantalla
          // debe adaptarse sin desbordarse (RF-33).
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScaler)),
            child: child!,
          ),
          home: const LogsView(),
        ),
      ),
    );
    if (settle) {
      await asentar(tester);
    }
  }

  group('lista del historial (RF-33, RF-41)', () {
    testWidgets('muestra fecha, hora, etiquetas, mascota, MAC y gramos', (
      tester,
    ) async {
      repository.page = LogPage(
        items: [_log()],
        total: 1,
        page: 1,
        pageSize: 50,
      );

      await pumpView(tester);

      expect(find.text('Comida dispensada'), findsWidgets);
      expect(find.text('Éxito'), findsOneWidget);
      expect(find.text('Objetivo alcanzado'), findsOneWidget);
      expect(find.textContaining('Milo'), findsWidgets);
      expect(find.text('**:AB:1F'), findsOneWidget);
      expect(find.text('01/10/2026 07:30'), findsOneWidget);
      expect(find.textContaining('Solicitados: 50 g'), findsOneWidget);
      expect(find.textContaining('Medidos: 50.4 g'), findsOneWidget);
      expect(find.textContaining('Descontados: 50.4 g'), findsOneWidget);
    });

    testWidgets('un registro histórico se muestra como «Sin clasificar»', (
      tester,
    ) async {
      repository.page = LogPage(
        items: [
          _log(
            eventType: null,
            eventLabel: null,
            outcome: null,
            outcomeLabel: null,
            cause: null,
            causeLabel: null,
            petId: null,
            petName: null,
            mac: null,
            requested: null,
            measured: null,
            discounted: null,
          ),
        ],
        total: 1,
        page: 1,
        pageSize: 50,
      );

      await pumpView(tester);

      expect(find.text('Sin clasificar'), findsOneWidget);
      expect(find.text('Éxito'), findsNothing);
    });

    testWidgets('no muestra gramos en eventos que no son dispensados', (
      tester,
    ) async {
      repository.page = LogPage(
        items: [_log(eventType: 'pet_created', eventLabel: 'Mascota creada')],
        total: 1,
        page: 1,
        pageSize: 50,
      );

      await pumpView(tester);

      expect(find.textContaining('Solicitados:'), findsNothing);
    });
  });

  group('filtros (RF-27 a RF-31, RF-33)', () {
    testWidgets('muestra los cuatro filtros y el botón de limpiar', (
      tester,
    ) async {
      await pumpView(tester);

      expect(find.text('Mascota'), findsOneWidget);
      expect(find.text('Tipo de evento'), findsOneWidget);
      expect(find.text('Resultado'), findsOneWidget);
      expect(find.text('Rango de fechas'), findsOneWidget);
      expect(find.text('Limpiar filtros'), findsOneWidget);
    });

    testWidgets(
      'el filtro por mascota emite el cambio y vuelve a la página 1',
      (tester) async {
        await pumpView(tester);

        await tester.tap(find.text('Todas las mascotas'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Milo').last);
        await asentar(tester);

        expect(repository.lastFilters?.petId, 1);
      },
    );

    testWidgets('el filtro por tipo de evento emite el cambio', (tester) async {
      await pumpView(tester);

      await tester.tap(find.text('Todos los tipos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mascota creada').last);
      await asentar(tester);

      expect(repository.lastFilters?.eventType, 'pet_created');
    });

    testWidgets('el filtro por resultado emite el cambio', (tester) async {
      await pumpView(tester);

      await tester.tap(find.text('Todos los resultados'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fallo').last);
      await asentar(tester);

      expect(repository.lastFilters?.outcome, 'failure');
    });

    testWidgets('el botón de rango de fechas abre el selector', (tester) async {
      await pumpView(tester);

      await tester.tap(find.text('Rango de fechas'));
      await tester.pumpAndSettle();

      expect(find.byType(DateRangePickerDialog), findsOneWidget);
    });

    testWidgets('limpiar filtros restablece la primera página sin filtros', (
      tester,
    ) async {
      repository.page = LogPage(
        items: [_log()],
        total: 1,
        page: 1,
        pageSize: 50,
      );
      await pumpView(tester);
      logBloc!.add(const LogsRequested(filters: LogFilters(petId: 1), page: 3));
      await asentar(tester);

      await tester.tap(find.text('Limpiar filtros'));
      await asentar(tester);

      expect(repository.lastFilters, LogFilters.empty);
      expect(logBloc!.state.page, 1);
    });
  });

  group('paginación (RF-32, RF-33)', () {
    testWidgets('muestra la página, el total de páginas y los registros', (
      tester,
    ) async {
      repository.page = LogPage(
        items: [_log()],
        total: 120,
        page: 1,
        pageSize: 50,
      );

      await pumpView(tester);

      expect(find.text('Página 1 de 3'), findsOneWidget);
      expect(find.text('120 registros'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_left),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('la página siguiente pide la página 2', (tester) async {
      repository.page = LogPage(
        items: [_log()],
        total: 120,
        page: 1,
        pageSize: 50,
      );
      await pumpView(tester);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
      await asentar(tester);

      expect(repository.lastPage, 2);
    });
  });

  group('avisos (RF-33, RF-34)', () {
    testWidgets('vacío muestra el texto exacto', (tester) async {
      await pumpView(tester);

      expect(
        find.text('No hay registros para los filtros seleccionados'),
        findsOneWidget,
      );
    });

    testWidgets('no muestra el vacío antes de la primera consulta', (
      tester,
    ) async {
      final blocker = Completer<void>();
      repository.blocker = blocker;
      // Evita que un fallo en las aserciones deje la consulta pendiente.
      addTearDown(() {
        if (!blocker.isCompleted) blocker.complete();
      });

      // Primer fotograma: la consulta aún no ha respondido.
      await pumpView(tester, settle: false);

      expect(
        find.text('No hay registros para los filtros seleccionados'),
        findsNothing,
      );

      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        find.text('No hay registros para los filtros seleccionados'),
        findsNothing,
      );

      blocker.complete();
      await asentar(tester);

      expect(
        find.text('No hay registros para los filtros seleccionados'),
        findsOneWidget,
      );
    });

    testWidgets('offline muestra los datos locales y su aviso', (tester) async {
      repository.offline = true;
      repository.page = LogPage(
        items: [_log()],
        total: 1,
        page: 1,
        pageSize: 50,
      );

      await pumpView(tester);

      expect(find.text('Datos sin conexión'), findsOneWidget);
      expect(find.text('Comida dispensada'), findsWidgets);
    });

    testWidgets('offline sin caché informa que no hay datos locales', (
      tester,
    ) async {
      repository.offline = true;

      await pumpView(tester);

      expect(find.text('Datos sin conexión'), findsOneWidget);
      expect(find.text('No hay datos locales guardados'), findsOneWidget);
    });

    testWidgets(
      'un error muestra el mensaje y el reintento vuelve a consultar',
      (tester) async {
        repository.failure = ServerFailures('Servidor no disponible');

        await pumpView(tester);

        expect(find.text('Servidor no disponible'), findsOneWidget);
        final llamadas = repository.calls;

        repository.failure = null;
        repository.page = LogPage(
          items: [_log()],
          total: 1,
          page: 1,
          pageSize: 50,
        );
        await tester.tap(find.text('Reintentar'));
        await asentar(tester);

        expect(repository.calls, llamadas + 1);
        expect(find.text('Comida dispensada'), findsWidgets);
      },
    );
  });

  group('adaptación al ancho del móvil (RF-33)', () {
    testWidgets('se pinta sin desbordamientos en 360 dp con texto al 130 %', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      repository.page = LogPage(
        items: [
          _log(
            outcome: 'failure',
            outcomeLabel: 'Fallo',
            causeLabel: 'Fallo del sensor durante la dispensación',
          ),
          _log(id: 2),
        ],
        total: 120,
        page: 1,
        pageSize: 50,
      );

      await pumpView(tester, textScaler: 1.3);

      expect(tester.takeException(), isNull);
      expect(find.text('Limpiar filtros'), findsOneWidget);
      expect(find.text('Página 1 de 3'), findsOneWidget);
      expect(find.text('Comida dispensada'), findsWidgets);
      expect(find.text('Fallo del sensor durante la dispensación'), findsOneWidget);
    });

    testWidgets(
      'los avisos de error y sin conexión también se adaptan en 360 dp con texto al 130 %',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        repository.failure = ServerFailures(
          'El servidor no respondió a la consulta del historial de eventos',
        );

        await pumpView(tester, textScaler: 1.3);

        expect(tester.takeException(), isNull);
        expect(find.text('Reintentar'), findsOneWidget);
      },
    );

    testWidgets('se pinta sin desbordamientos en 320 dp', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      repository.page = LogPage(
        items: [
          _log(
            outcome: 'failure',
            outcomeLabel: 'Fallo',
            causeLabel: 'Fallo del sensor durante la dispensación',
          ),
        ],
        total: 120,
        page: 1,
        pageSize: 50,
      );

      await pumpView(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Limpiar filtros'), findsOneWidget);
      expect(find.text('Página 1 de 3'), findsOneWidget);
      expect(find.text('Comida dispensada'), findsWidgets);
    });

    testWidgets('el aviso de error también se adapta al ancho estrecho', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      repository.failure = ServerFailures('Servidor no disponible');

      await pumpView(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });
}
