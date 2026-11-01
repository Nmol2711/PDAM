import 'dart:async';
import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:app_movil_pdam/features/logs/domain/repository/log_repositories.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_log_catalog_uc.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_logs_uc.dart';
import 'package:app_movil_pdam/features/logs/presentation/bloc/log_bloc.dart';
import 'package:app_movil_pdam/features/logs/presentation/views/logs_view.dart';
import 'package:app_movil_pdam/features/logs/presentation/widgets/log_pagination_bar.dart';
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
  ///
  /// [ahora] permite fijar el reloj de la ventana de refresco (RNF-2).
  void crearBlocs({DateTime Function()? ahora}) {
    logBloc = LogBloc(
      getLogsUc: GetLogsUc(repository: repository),
      getLogCatalogUc: GetLogCatalogUc(repository: repository),
      ahora: ahora,
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

  Future<void> montarVista(
    WidgetTester tester, {
    double textScaler = 1.0,
  }) async {
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
  }

  /// Monta la vista dentro de un `IndexedStack` con `TickerMode`, como hace
  /// `StatefulShellRoute.indexedStack`: la rama oculta sigue montada.
  Future<void> montarShell(
    WidgetTester tester,
    ValueNotifier<bool> visible,
  ) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LogBloc>.value(value: logBloc!),
          BlocProvider<PetBloc>.value(value: petBloc!),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, activa, child) => IndexedStack(
              index: activa ? 1 : 0,
              children: [
                const Scaffold(body: Center(child: Text('Otra pestaña'))),
                TickerMode(enabled: activa, child: const LogsView()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Monta la vista en un `Navigator` de rama anidado en el navegador raíz,
  /// como en `StatefulShellRoute.indexedStack`: los diálogos abiertos con
  /// `useRootNavigator: true` caen en el navegador raíz, no en la rama.
  Future<void> montarRama(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LogBloc>.value(value: logBloc!),
          BlocProvider<PetBloc>.value(value: petBloc!),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const LogsView(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpView(
    WidgetTester tester, {
    bool settle = true,
    double textScaler = 1.0,
    Size? tamano,
  }) async {
    if (tamano != null) {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    crearBlocs();
    await montarVista(tester, textScaler: textScaler);
    if (settle) {
      await asentar(tester);
    }
  }

  /// Abre el panel plegable de filtros antes de interactuar con sus campos.
  Future<void> abrirFiltros(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('logs_filters_toggle')));
    await tester.pumpAndSettle();
  }

  /// Desliza la lista hacia abajo desde su inicio para pedir un refresco
  /// manual. Usa `pump` acotado: el indicador del gesto anima sin parar
  /// (MEMORY).
  Future<void> deslizarRecarga(WidgetTester tester) async {
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Simula la vuelta de la aplicación a primer plano.
  Future<void> reanudarApp(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
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
      await abrirFiltros(tester);

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
        await abrirFiltros(tester);

        await tester.tap(find.text('Todas las mascotas'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Milo').last);
        await asentar(tester);

        expect(repository.lastFilters?.petId, 1);
      },
    );

    testWidgets('el filtro por tipo de evento emite el cambio', (tester) async {
      await pumpView(tester);
      await abrirFiltros(tester);

      await tester.tap(find.text('Todos los tipos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mascota creada').last);
      await asentar(tester);

      expect(repository.lastFilters?.eventType, 'pet_created');
    });

    testWidgets('el filtro por resultado emite el cambio', (tester) async {
      await pumpView(tester);
      await abrirFiltros(tester);

      await tester.tap(find.text('Todos los resultados'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fallo').last);
      await asentar(tester);

      expect(repository.lastFilters?.outcome, 'failure');
    });

    testWidgets('el botón de rango de fechas abre el selector', (tester) async {
      await pumpView(tester);
      await abrirFiltros(tester);

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
      await abrirFiltros(tester);

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
      await abrirFiltros(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Limpiar filtros'), findsOneWidget);
      expect(find.text('Página 1 de 3'), findsOneWidget);
      expect(find.text('Comida dispensada'), findsWidgets);
      expect(
        find.text('Fallo del sensor durante la dispensación'),
        findsOneWidget,
      );
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
      await abrirFiltros(tester);

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

  group('entrada única en la cabecera real (RF-01)', () {
    testWidgets('a 600 y 840 la cabecera no dibuja la entrada', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final ancho in <double>[600, 840]) {
        tester.view.physicalSize = Size(ancho, 800);
        tester.view.devicePixelRatio = 1.0;
        await pumpView(tester);

        expect(
          find.byTooltip('Abrir configuración'),
          findsNothing,
          reason: 'ancho $ancho',
        );
      }
    });

    testWidgets('a 320 la cabecera dibuja exactamente una entrada', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpView(tester);

      expect(find.byTooltip('Abrir configuración'), findsOneWidget);
    });
  });

  group('panel de filtros plegable (RF-11 y RF-12)', () {
    testWidgets('empieza plegado y solo muestra el botón Filtros', (
      tester,
    ) async {
      await pumpView(tester);

      expect(find.byKey(const Key('logs_filters_toggle')), findsOneWidget);
      expect(find.text('Filtros'), findsOneWidget);
      expect(find.text('Mascota'), findsNothing);
      expect(find.text('Tipo de evento'), findsNothing);
      expect(find.text('Resultado'), findsNothing);
      expect(find.text('Rango de fechas'), findsNothing);
      expect(find.text('Limpiar filtros'), findsNothing);
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('desplegar y plegar no recarga ni altera los filtros', (
      tester,
    ) async {
      await pumpView(tester);
      final llamadas = repository.calls;
      final filtros = logBloc!.state.filters;

      await abrirFiltros(tester);
      expect(find.text('Mascota'), findsOneWidget);
      expect(find.text('Limpiar filtros'), findsOneWidget);

      await tester.tap(find.byKey(const Key('logs_filters_toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Mascota'), findsNothing);
      expect(repository.calls, llamadas);
      expect(logBloc!.state.filters, filtros);
    });

    testWidgets('permanece abierto al aplicar un filtro', (tester) async {
      await pumpView(tester);
      await abrirFiltros(tester);

      await tester.tap(find.text('Todas las mascotas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Milo').last);
      await asentar(tester);

      expect(find.text('Mascota'), findsOneWidget);
      expect(find.text('Limpiar filtros'), findsOneWidget);
    });

    testWidgets('permanece abierto al cambiar de página', (tester) async {
      repository.page = LogPage(
        items: [_log()],
        total: 120,
        page: 1,
        pageSize: 50,
      );
      await pumpView(tester);
      await abrirFiltros(tester);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
      await asentar(tester);

      expect(find.text('Mascota'), findsOneWidget);
    });

    testWidgets('permanece abierto al recargar', (tester) async {
      await pumpView(tester);
      await abrirFiltros(tester);

      logBloc!.add(const LogsRequested());
      await asentar(tester);

      expect(find.text('Mascota'), findsOneWidget);
    });

    testWidgets('permanece abierto al reintentar tras un error', (
      tester,
    ) async {
      repository.failure = ServerFailures('Servidor no disponible');
      await pumpView(tester);
      await abrirFiltros(tester);
      expect(find.text('Reintentar'), findsOneWidget);

      repository.failure = null;
      repository.page = LogPage(
        items: [_log()],
        total: 1,
        page: 1,
        pageSize: 50,
      );
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);

      expect(find.text('Mascota'), findsOneWidget);
    });

    testWidgets(
      'se pliega al volver a la pestaña con una consulta automática (017, 019)',
      (tester) async {
        var ahora = DateTime.utc(2026, 10, 31, 12);
        crearBlocs(ahora: () => ahora);
        final visible = ValueNotifier<bool>(true);
        addTearDown(visible.dispose);

        await montarShell(tester, visible);
        await asentar(tester);
        await abrirFiltros(tester);
        expect(find.text('Mascota'), findsOneWidget);

        final llamadas = repository.calls;
        final filtros = repository.lastFilters;

        // La pestaña deja de estar activa: TickerMode pasa a false y la rama
        // sigue montada, como en StatefulShellRoute.indexedStack.
        visible.value = false;
        await tester.pumpAndSettle();
        // Fuera de la ventana de 4 s para que el reingreso refresque (019).
        ahora = ahora.add(const Duration(seconds: 5));
        visible.value = true;
        await tester.pumpAndSettle();

        expect(find.text('Filtros'), findsOneWidget);
        expect(find.text('Mascota'), findsNothing);
        expect(find.text('Limpiar filtros'), findsNothing);
        expect(repository.calls, llamadas + 1);
        expect(repository.lastFilters, filtros);
      },
    );

    testWidgets('los filtros y el botón usan el radio 8 del tema', (
      tester,
    ) async {
      await pumpView(tester);
      await abrirFiltros(tester);

      final decorador = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byType(DropdownButtonFormField<int?>).first,
          matching: find.byType(InputDecorator),
        ),
      );
      final borde = decorador.decoration.border! as OutlineInputBorder;
      expect(borde.borderRadius, BorderRadius.circular(8));

      final rango = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Rango de fechas'),
      );
      expect(rango.style?.shape, isNull);
      final forma =
          AppTheme.lightTheme.outlinedButtonTheme.style!.shape!.resolve(
                <WidgetState>{},
              )!
              as RoundedRectangleBorder;
      expect(forma.borderRadius, BorderRadius.circular(8));

      final boton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Filtros'),
      );
      expect(boton.style, isNull);
    });

    testWidgets('a 320 con texto 1.3 el panel plegado no desborda', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpView(tester, textScaler: 1.3);

      expect(tester.takeException(), isNull);
      expect(find.text('Filtros'), findsOneWidget);
      expect(find.text('Mascota'), findsNothing);
    });
  });

  group('recarga del historial (RF-1, RF-2, RF-4, CP-1 a CP-5 y CP-9)', () {
    testWidgets(
      'CP-1: deslizar recarga conservando filtros y página, solo con el '
      'indicador del gesto',
      (tester) async {
        repository.page = LogPage(
          items: [_log(id: 1)],
          total: 120,
          page: 2,
          pageSize: 50,
        );
        crearBlocs();
        await montarVista(tester);
        await asentar(tester);
        logBloc!.add(
          const LogsRequested(filters: LogFilters(petId: 1), page: 2),
        );
        await asentar(tester);
        expect(logBloc!.state.page, 2);

        final blocker = Completer<void>();
        repository.blocker = blocker;
        addTearDown(() {
          if (!blocker.isCompleted) blocker.complete();
        });

        await deslizarRecarga(tester);

        expect(repository.lastPage, 2);
        expect(repository.lastFilters?.petId, 1);
        expect(logBloc!.state.refresco, LogRefreshOrigin.manual);
        // La lista previa sigue visible: no hay vacío intermedio.
        expect(logBloc!.state.items, isNotEmpty);
        expect(find.text('Comida dispensada'), findsWidgets);
        expect(
          find.text('No hay registros para los filtros seleccionados'),
          findsNothing,
        );
        // Solo el indicador del gesto; la barra lineal queda oculta.
        expect(find.byType(RefreshProgressIndicator), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);

        blocker.complete();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(RefreshProgressIndicator), findsNothing);
        expect(logBloc!.state.refresco, isNull);
        expect(logBloc!.state.isLoading, isFalse);
      },
    );

    testWidgets('CP-2: el gesto funciona con la lista vacía', (tester) async {
      await pumpView(tester);
      final llamadas = repository.calls;

      await deslizarRecarga(tester);

      expect(repository.calls, llamadas + 1);
      expect(logBloc!.state.isLoading, isFalse);
    });

    testWidgets(
      'CP-2: el gesto funciona con menos elementos que el alto de la pantalla',
      (tester) async {
        repository.page = LogPage(
          items: [_log()],
          total: 1,
          page: 1,
          pageSize: 50,
        );
        await pumpView(tester);
        final llamadas = repository.calls;

        await deslizarRecarga(tester);

        expect(repository.calls, llamadas + 1);
        expect(logBloc!.state.isLoading, isFalse);
      },
    );

    testWidgets('CP-3: mostrar la pestaña refresca con la barra lineal, sin el '
        'indicador del gesto y sin mover el scroll', (tester) async {
      var ahora = DateTime.utc(2026, 10, 31, 12);
      crearBlocs(ahora: () => ahora);
      repository.page = LogPage(
        items: List<ActivityLog>.generate(20, (i) => _log(id: i + 1)),
        total: 20,
        page: 1,
        pageSize: 50,
      );
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);

      await montarShell(tester, visible);
      await asentar(tester);
      await abrirFiltros(tester);
      expect(find.text('Mascota'), findsOneWidget);

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      final desplazamiento = scrollable.position.pixels;
      expect(desplazamiento, greaterThan(0));

      // La pestaña deja de estar activa y vuelve pasada la ventana de 4 s.
      visible.value = false;
      await tester.pump();
      ahora = ahora.add(const Duration(seconds: 5));

      final blocker = Completer<void>();
      repository.blocker = blocker;
      addTearDown(() {
        if (!blocker.isCompleted) blocker.complete();
      });
      final llamadas = repository.calls;

      visible.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(repository.calls, llamadas + 1);
      expect(logBloc!.state.refresco, LogRefreshOrigin.automatico);
      // Solo la barra lineal existente, sin el indicador del gesto.
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      // La posición de la lista no se mueve.
      expect(scrollable.position.pixels, desplazamiento);
      // El panel se pliega al reentrar (017) y el refresco no lo despliega.
      expect(find.text('Filtros'), findsOneWidget);
      expect(find.text('Mascota'), findsNothing);
      expect(find.text('Limpiar filtros'), findsNothing);

      blocker.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(logBloc!.state.refresco, isNull);
    });

    testWidgets(
      'CP-4: volver del segundo plano con el historial visible refresca',
      (tester) async {
        var ahora = DateTime.utc(2026, 10, 31, 12);
        crearBlocs(ahora: () => ahora);
        await montarVista(tester);
        await asentar(tester);
        ahora = ahora.add(const Duration(seconds: 5));

        final blocker = Completer<void>();
        repository.blocker = blocker;
        addTearDown(() {
          if (!blocker.isCompleted) blocker.complete();
        });
        final llamadas = repository.calls;

        await reanudarApp(tester);

        expect(repository.calls, llamadas + 1);
        expect(logBloc!.state.refresco, LogRefreshOrigin.automatico);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byType(RefreshProgressIndicator), findsNothing);

        blocker.complete();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      },
    );

    testWidgets(
      'CP-4: volver del segundo plano con otra pestaña activa no refresca',
      (tester) async {
        var ahora = DateTime.utc(2026, 10, 31, 12);
        crearBlocs(ahora: () => ahora);
        final visible = ValueNotifier<bool>(false);
        addTearDown(visible.dispose);

        await montarShell(tester, visible);
        await asentar(tester);
        ahora = ahora.add(const Duration(seconds: 5));
        final llamadas = repository.calls;

        await reanudarApp(tester);

        expect(repository.calls, llamadas);
        expect(logBloc!.state.refresco, isNull);
        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'CP-4: volver del segundo plano con un diálogo encima no refresca',
      (tester) async {
        var ahora = DateTime.utc(2026, 10, 31, 12);
        crearBlocs(ahora: () => ahora);
        await montarVista(tester);
        await asentar(tester);
        await abrirFiltros(tester);
        await tester.tap(find.text('Rango de fechas'));
        await tester.pumpAndSettle();
        expect(find.byType(DateRangePickerDialog), findsOneWidget);

        ahora = ahora.add(const Duration(seconds: 5));
        final llamadas = repository.calls;

        await reanudarApp(tester);

        expect(repository.calls, llamadas);
        expect(logBloc!.state.refresco, isNull);
      },
    );

    testWidgets(
      'CP-4: con navegador de rama, un diálogo del navegador raíz impide el '
      'refresco al reanudar',
      (tester) async {
        var ahora = DateTime.utc(2026, 10, 31, 12);
        crearBlocs(ahora: () => ahora);
        await montarRama(tester);
        await asentar(tester);
        await abrirFiltros(tester);
        // El selector de fechas usa el navegador raíz (como en la app).
        await tester.tap(find.text('Rango de fechas'));
        await tester.pumpAndSettle();
        expect(find.byType(DateRangePickerDialog), findsOneWidget);

        ahora = ahora.add(const Duration(seconds: 5));
        final llamadas = repository.calls;

        await reanudarApp(tester);

        expect(repository.calls, llamadas);
        expect(logBloc!.state.refresco, isNull);
        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'CP-4: con navegador de rama y sin diálogo, reanudar refresca',
      (tester) async {
        var ahora = DateTime.utc(2026, 10, 31, 12);
        crearBlocs(ahora: () => ahora);
        await montarRama(tester);
        await asentar(tester);
        ahora = ahora.add(const Duration(seconds: 5));

        final blocker = Completer<void>();
        repository.blocker = blocker;
        addTearDown(() {
          if (!blocker.isCompleted) blocker.complete();
        });
        final llamadas = repository.calls;

        await reanudarApp(tester);

        expect(repository.calls, llamadas + 1);
        expect(logBloc!.state.refresco, LogRefreshOrigin.automatico);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byType(RefreshProgressIndicator), findsNothing);

        blocker.complete();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      },
    );

    testWidgets('CP-5: cerrar un diálogo o un selector no dispara refresco', (
      tester,
    ) async {
      var ahora = DateTime.utc(2026, 10, 31, 12);
      crearBlocs(ahora: () => ahora);
      await montarVista(tester);
      await asentar(tester);
      await abrirFiltros(tester);
      final llamadas = repository.calls;

      // Diálogo: abrir y cerrar sin elegir rango.
      await tester.tap(find.text('Rango de fechas'));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(DateRangePickerDialog))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsNothing);

      expect(repository.calls, llamadas);
      expect(logBloc!.state.refresco, isNull);

      // Selector: abrir y descartar sin elegir.
      await tester.tap(find.text('Todas las mascotas'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(repository.calls, llamadas);
      expect(logBloc!.state.refresco, isNull);
    });

    testWidgets(
      'CP-9: cambiar el filtro durante un refresco descarta el refresco y '
      'deja un solo indicador',
      (tester) async {
        repository.page = LogPage(
          items: [_log()],
          total: 120,
          page: 1,
          pageSize: 50,
        );
        await pumpView(tester);
        await abrirFiltros(tester);

        final blocker = Completer<void>();
        repository.blocker = blocker;
        addTearDown(() {
          if (!blocker.isCompleted) blocker.complete();
        });

        await deslizarRecarga(tester);
        expect(logBloc!.state.refresco, LogRefreshOrigin.manual);
        expect(find.byType(RefreshProgressIndicator), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);

        // La acción nueva prevalece: el refresco se descarta (RF-4).
        await tester.tap(find.text('Todas las mascotas'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Milo').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(logBloc!.state.filters.petId, 1);
        expect(logBloc!.state.refresco, isNull);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byType(RefreshProgressIndicator), findsNothing);

        blocker.complete();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(logBloc!.state.isLoading, isFalse);
        expect(logBloc!.state.filters.petId, 1);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byType(RefreshProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'RF-4: deslizar durante un refresco automático no añade un segundo '
      'indicador',
      (tester) async {
        repository.page = LogPage(
          items: [_log()],
          total: 1,
          page: 1,
          pageSize: 50,
        );
        var ahora = DateTime.utc(2026, 10, 31, 12);
        crearBlocs(ahora: () => ahora);
        await montarVista(tester);
        await asentar(tester);

        // Refresco automático en curso y bloqueado: solo barra lineal.
        ahora = ahora.add(const Duration(seconds: 5));
        final blocker = Completer<void>();
        repository.blocker = blocker;
        addTearDown(() {
          if (!blocker.isCompleted) blocker.complete();
        });
        final llamadas = repository.calls;
        await reanudarApp(tester);
        expect(repository.calls, llamadas + 1);
        expect(logBloc!.state.refresco, LogRefreshOrigin.automatico);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byType(RefreshProgressIndicator), findsNothing);

        // El gesto no apila otro indicador ni otra consulta (RF-4).
        await deslizarRecarga(tester);
        await tester.pump(const Duration(milliseconds: 600));

        expect(repository.calls, llamadas + 1);
        expect(logBloc!.state.refresco, LogRefreshOrigin.automatico);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byType(RefreshProgressIndicator), findsNothing);

        blocker.complete();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(logBloc!.state.refresco, isNull);
      },
    );

    testWidgets(
      'RF-4: deslizar tras cambiar un filtro durante un refresco no deja el '
      'indicador del gesto pendiente',
      (tester) async {
        repository.page = LogPage(
          items: [_log()],
          total: 120,
          page: 1,
          pageSize: 50,
        );
        var ahora = DateTime.utc(2026, 10, 31, 12);
        crearBlocs(ahora: () => ahora);
        await montarVista(tester);
        await asentar(tester);

        // Refresco automático A en curso y bloqueado.
        ahora = ahora.add(const Duration(seconds: 5));
        final blocker = Completer<void>();
        repository.blocker = blocker;
        addTearDown(() {
          if (!blocker.isCompleted) blocker.complete();
        });
        final llamadas = repository.calls;
        await reanudarApp(tester);
        expect(repository.calls, llamadas + 1);
        expect(logBloc!.state.refresco, LogRefreshOrigin.automatico);

        // Cambio de filtro durante A: nueva generación y `refresco` limpio,
        // pero A sigue en curso hasta que responda.
        logBloc!.add(const LogFiltersChanged(LogFilters(petId: 1)));
        await tester.pump();
        expect(repository.calls, llamadas + 2);
        expect(logBloc!.state.refresco, isNull);
        expect(logBloc!.state.isLoading, isTrue);
        expect(logBloc!.refrescoEnCurso, isTrue);

        // El gesto no debe añadir otra consulta ni dejar su indicador.
        await deslizarRecarga(tester);
        await tester.pump(const Duration(milliseconds: 600));

        expect(repository.calls, llamadas + 2);
        expect(logBloc!.state.isLoading, isTrue);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byType(RefreshProgressIndicator), findsNothing);

        blocker.complete();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(logBloc!.state.isLoading, isFalse);
        expect(logBloc!.state.filters.petId, 1);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byType(RefreshProgressIndicator), findsNothing);
      },
    );
  });

  group('gutter exterior (RF-09)', () {
    Future<void> comprobarGutter(
      WidgetTester tester, {
      required Size tamano,
      required double gutter,
    }) async {
      repository.page = LogPage(
        items: [_log()],
        total: 1,
        page: 1,
        pageSize: 50,
      );
      await pumpView(tester, tamano: tamano);

      final tarjeta = tester.widget<Card>(find.byType(Card).first);
      expect(
        tarjeta.margin,
        EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: gutter),
        reason: 'tarjeta a ${tamano.width}',
      );

      final paginacion = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(LogPaginationBar),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        paginacion.padding,
        EdgeInsets.symmetric(horizontal: gutter, vertical: AppSpacing.xs),
        reason: 'paginación a ${tamano.width}',
      );
    }

    testWidgets('a 400 puntos las tarjetas y la paginación usan 16', (
      tester,
    ) async {
      await comprobarGutter(
        tester,
        tamano: const Size(400, 900),
        gutter: AppSpacing.page,
      );
    });

    testWidgets('a 800 puntos las tarjetas y la paginación usan 24', (
      tester,
    ) async {
      await comprobarGutter(
        tester,
        tamano: const Size(800, 900),
        gutter: AppSpacing.pageWide,
      );
    });
  });
}
