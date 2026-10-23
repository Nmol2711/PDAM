import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
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
      autoGenerateSchedulesUc:
          AutoGenerateSchedulesUc(repository: repository),
      updateScheduleUc: UpdateScheduleUc(repository: repository),
    );
  }

  Future<void> pumpPetDetail(WidgetTester tester, Pet pet) async {
    final scheduleBloc = buildScheduleBloc(MockScheduleRepository());
    addTearDown(scheduleBloc.close);
    final dispenserBloc = buildDispenserBloc(MockDispenserRepository());
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
          home: PetDetailView(pet: pet),
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
}
