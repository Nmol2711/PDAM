import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/presentation/widgets/app_cta_button.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/quick_dispense_uc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/quick_dispense_cubit.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/quick_dispense_sheet.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/pet_wsava_limit.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/auto_generate_schedules_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/create_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_by_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/update_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/pet_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';

import '../../../dispenser/presentation/bloc/dispenser_bloc_test.dart';
import '../bloc/schedule_bloc_test.dart';

/// Regresión de T11 (RNF-4): el detalle de mascota debe obtener el límite
/// WSAVA del helper de dominio y nunca de una fórmula embebida en la vista.
void main() {
  ScheduleBloc buildScheduleBloc(MockScheduleRepository repository) {
    return ScheduleBloc(
      createScheduleUc: CreateScheduleUc(repository: repository),
      getScheduleUc: GetScheduleUc(repository: repository),
      getSchedulesUc: GetSchedulesUc(repository: repository),
      getSchedulesByPetUc: GetSchedulesByPetUc(repository: repository),
      autoGenerateSchedulesUc: AutoGenerateSchedulesUc(repository: repository),
      updateScheduleUc: UpdateScheduleUc(repository: repository),
    );
  }

  Future<void> pumpPetDetail(
    WidgetTester tester,
    Pet pet, {
    MockDispenserRepository? dispenserRepository,
    MockScheduleRepository? scheduleRepository,
    QuickDispenseCubit? quickDispenseCubit,
    double textScaler = 1.0,
  }) async {
    final scheduleBloc = buildScheduleBloc(
      scheduleRepository ?? MockScheduleRepository(),
    );
    addTearDown(scheduleBloc.close);
    final dispenserBloc = buildDispenserBloc(
      dispenserRepository ?? MockDispenserRepository(),
    );
    addTearDown(dispenserBloc.close);

    // Los proveedores deben quedar por encima del Navigator para que el
    // bottom sheet (otra ruta) pueda leer el ScheduleBloc al guardar.
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ScheduleBloc>.value(value: scheduleBloc),
          BlocProvider<DispenserBloc>.value(value: dispenserBloc),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScaler)),
            child: child!,
          ),
          home: PetDetailView(
            pet: pet,
            quickDispenseCubit: quickDispenseCubit,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> agregarHorario(
    WidgetTester tester, {
    required String hora,
    required String gramos,
  }) async {
    await tester.ensureVisible(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar horario individual'));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), hora);
    await tester.enterText(campos.at(1), gramos);
    await tester.tap(find.text('Guardar Horario'));
    await tester.pumpAndSettle();
  }

  Pet mascotaDePrueba(TypePest species) {
    return Pet(
      id: 1,
      name: 'Mascota de prueba',
      species: species,
      birthDate: DateTime(2018, 1, 1),
      weight: 12.5,
      reproductiveStatus: true,
    );
  }

  testWidgets('muestra el límite WSAVA calculado por el helper de dominio', (
    tester,
  ) async {
    final pet = mascotaDePrueba(TypePest.canino);
    final limiteEsperado = petWsavaDailyLimitGrams(pet)!;

    await pumpPetDetail(tester, pet);
    await agregarHorario(tester, hora: '09:00', gramos: '250');

    // 250 g supera en más de 50 g el límite de 193 g: el diálogo debe mostrar
    // exactamente el valor del motor, no una fórmula paralela en la vista.
    expect(find.textContaining('Límite WSAVA Excedido'), findsOneWidget);
    expect(
      find.textContaining(
        'Límite recomendado: ${limiteEsperado.toStringAsFixed(0)}g',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no muestra límite WSAVA cuando la especie no está soportada', (
    tester,
  ) async {
    final pet = mascotaDePrueba(TypePest.otros);

    await pumpPetDetail(tester, pet);
    await agregarHorario(tester, hora: '09:00', gramos: '250');

    // RF-2: "otros" no tiene especie canónica, por lo que no debe calcularse un
    // límite como si fuera felino ni mostrarse ningún aviso WSAVA.
    expect(find.textContaining('Límite WSAVA'), findsNothing);
    expect(find.textContaining('Advertencia Nutricional WSAVA'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Porción: 250.0 gramos'), findsOneWidget);
  });

  testWidgets(
    'RF-04 y RF-14: el dispensador activo usa primaryContainer con su '
    'contenido',
    (tester) async {
      await pumpPetDetail(tester, mascotaDePrueba(TypePest.canino));
      final esquema = AppTheme.lightTheme.colorScheme;

      final titulo = tester.widget<Text>(find.text('Dispensador Vinculado'));
      expect(titulo.style?.color, esquema.onPrimaryContainer);

      final card = tester.widget<Card>(
        find
            .ancestor(
              of: find.text('Dispensador Vinculado'),
              matching: find.byType(Card),
            )
            .first,
      );
      expect(card.color, esquema.primaryContainer);
    },
  );

  testWidgets('RF-04 y RF-14: el dispensador desactivado usa '
      'surfaceContainerHighest con su contenido', (tester) async {
    await pumpPetDetail(
      tester,
      mascotaDePrueba(TypePest.canino),
      dispenserRepository: _InactiveDispenserRepository(),
    );
    final esquema = AppTheme.lightTheme.colorScheme;

    final titulo = tester.widget<Text>(find.text('Dispensador Desactivado'));
    expect(titulo.style?.color, esquema.onSurfaceVariant);

    final card = tester.widget<Card>(
      find
          .ancestor(
            of: find.text('Dispensador Desactivado'),
            matching: find.byType(Card),
          )
          .first,
    );
    expect(card.color, esquema.surfaceContainerHighest);
  });

  testWidgets(
    'RF-05: vincular dispensador sigue siendo una acción secundaria',
    (tester) async {
      await pumpPetDetail(
        tester,
        mascotaDePrueba(TypePest.canino),
        dispenserRepository: MockDispenserRepository(shouldFail: true),
      );

      expect(find.text('Vincular Dispensador Inteligente'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsWidgets);
      expect(find.byType(AppCtaButton), findsNothing);
    },
  );

  testWidgets('RF-07 y RF-08: todas las tarjetas del detalle usan el tema', (
    tester,
  ) async {
    final scheduleRepository = MockScheduleRepository()
      ..schedules = <Schedule>[
        const Schedule(id: 1, time: '08:00', amount: 100, petId: 1),
      ];
    await pumpPetDetail(
      tester,
      mascotaDePrueba(TypePest.canino),
      scheduleRepository: scheduleRepository,
    );
    final esquema = AppTheme.lightTheme.colorScheme;

    final tarjetas = tester.widgetList<Card>(find.byType(Card)).toList();
    expect(tarjetas.length, greaterThanOrEqualTo(5));

    for (final card in tarjetas) {
      expect(card.elevation, isNull, reason: 'elevación local en una tarjeta');
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byWidget(card),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 0);
      if (card.color == null) {
        expect(material.color, esquema.surface);
        final forma = material.shape! as RoundedRectangleBorder;
        expect(forma.borderRadius, BorderRadius.circular(8));
        expect(forma.side.color, esquema.outline);
      }
    }
  });

  testWidgets('RF-09: las tarjetas de información rellenan 16', (tester) async {
    await pumpPetDetail(tester, mascotaDePrueba(TypePest.canino));

    final rellenos = tester
        .widgetList<Padding>(
          find.descendant(
            of: find.byType(Card),
            matching: find.byType(Padding),
          ),
        )
        .where(
          (relleno) =>
              relleno.padding == const EdgeInsets.all(AppSpacing.cardPadding),
        );
    expect(rellenos.length, 3);
  });

  testWidgets('RNF-02: a 320 puntos con texto al 130 % no desborda', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPetDetail(
      tester,
      mascotaDePrueba(TypePest.canino),
      textScaler: 1.3,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('RF-09: el detalle usa gutter 16 y 24', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final caso in <({double ancho, double gutter})>[
      (ancho: 400, gutter: AppSpacing.page),
      (ancho: 800, gutter: AppSpacing.pageWide),
    ]) {
      tester.view.physicalSize = Size(caso.ancho, 1000);
      tester.view.devicePixelRatio = 1.0;

      final scheduleRepository = MockScheduleRepository()
        ..schedules = <Schedule>[
          const Schedule(id: 1, time: '08:00', amount: 100, petId: 1),
        ];
      await pumpPetDetail(
        tester,
        mascotaDePrueba(TypePest.canino),
        scheduleRepository: scheduleRepository,
      );

      final rellenos = tester.widgetList<Padding>(
        find.ancestor(of: find.text('Edad'), matching: find.byType(Padding)),
      );
      expect(
        rellenos.any(
          (relleno) =>
              relleno.padding == EdgeInsets.symmetric(horizontal: caso.gutter),
        ),
        isTrue,
        reason: 'sección sin gutter ${caso.ancho}',
      );

      final lista = tester.widget<ListView>(find.byType(ListView).first);
      expect(
        lista.padding,
        EdgeInsets.symmetric(horizontal: caso.gutter),
        reason: 'horarios sin gutter ${caso.ancho}',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });

  testWidgets('muestra «Dispensar ahora» y abre la hoja con un dispensador activo', (
    tester,
  ) async {
    final repository = MockDispenserRepository();
    final cubit = QuickDispenseCubit(
      quickDispenseUc: QuickDispenseUc(repository: repository),
    );
    addTearDown(cubit.close);

    await pumpPetDetail(
      tester,
      mascotaDePrueba(TypePest.canino),
      quickDispenseCubit: cubit,
    );

    expect(find.text('Dispensar ahora'), findsOneWidget);

    await tester.tap(find.text('Dispensar ahora'));
    await tester.pumpAndSettle();

    expect(find.byType(QuickDispenseSheet), findsOneWidget);
  });

  testWidgets('la dispensación rápida muestra la confirmación al aceptar', (
    tester,
  ) async {
    final repository = MockDispenserRepository();
    final cubit = QuickDispenseCubit(
      quickDispenseUc: QuickDispenseUc(repository: repository),
    );
    addTearDown(cubit.close);

    await pumpPetDetail(
      tester,
      mascotaDePrueba(TypePest.canino),
      quickDispenseCubit: cubit,
    );

    await tester.tap(find.text('Dispensar ahora'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quick-dispense-amount')),
      '50',
    );
    await tester.tap(find.text('Dispensar'));
    await tester.pumpAndSettle();

    expect(find.text('Orden de dispensación enviada'), findsOneWidget);
    expect(repository.quickDispenseCalls, 1);
  });

  testWidgets('con el dispensador desactivado la acción queda deshabilitada', (
    tester,
  ) async {
    final cubit = QuickDispenseCubit(
      quickDispenseUc: QuickDispenseUc(repository: MockDispenserRepository()),
    );
    addTearDown(cubit.close);

    await pumpPetDetail(
      tester,
      mascotaDePrueba(TypePest.canino),
      dispenserRepository: _InactiveDispenserRepository(),
      quickDispenseCubit: cubit,
    );

    final boton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Dispensar ahora'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(boton.onPressed, isNull);
  });

  testWidgets('con stock 0 la acción queda deshabilitada (RF-11)', (
    tester,
  ) async {
    final cubit = QuickDispenseCubit(
      quickDispenseUc: QuickDispenseUc(
        repository: MockDispenserRepository(dispenserStock: 0),
      ),
    );
    addTearDown(cubit.close);

    await pumpPetDetail(
      tester,
      mascotaDePrueba(TypePest.canino),
      dispenserRepository: MockDispenserRepository(dispenserStock: 0),
      quickDispenseCubit: cubit,
    );

    expect(find.text('Dispensar ahora'), findsOneWidget);
    final boton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Dispensar ahora'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(boton.onPressed, isNull);
  });

  testWidgets('sin dispensador no ofrece la acción (RF-6)', (tester) async {
    await pumpPetDetail(
      tester,
      mascotaDePrueba(TypePest.canino),
      dispenserRepository: MockDispenserRepository(shouldFail: true),
    );

    expect(find.text('Dispensar ahora'), findsNothing);
    expect(find.text('Vincular Dispensador Inteligente'), findsOneWidget);
  });
}

class _InactiveDispenserRepository extends MockDispenserRepository {
  @override
  Future<Either<Failures, Dispenser>> getDispenserByPet(int petId) async {
    return Right(
      Dispenser(
        id: 1,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: false,
        petId: petId,
      ),
    );
  }
}
