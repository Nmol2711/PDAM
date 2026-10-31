import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/presentation/widgets/app_cta_button.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/auto_generate_schedules_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/create_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_by_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/update_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart';
import 'package:app_movil_pdam/features/pets/presentation/views/guided_schedule_form_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bloc/schedule_bloc_test.dart';

final Pet _mascota = Pet(
  id: 1,
  name: 'Luna',
  species: TypePest.felino,
  birthDate: DateTime(2020),
  weight: 4.5,
  reproductiveStatus: true,
);

void main() {
  Future<void> pumpGuided(WidgetTester tester) async {
    final repository = MockScheduleRepository();
    final bloc = ScheduleBloc(
      createScheduleUc: CreateScheduleUc(repository: repository),
      getScheduleUc: GetScheduleUc(repository: repository),
      getSchedulesUc: GetSchedulesUc(repository: repository),
      getSchedulesByPetUc: GetSchedulesByPetUc(repository: repository),
      autoGenerateSchedulesUc: AutoGenerateSchedulesUc(repository: repository),
      updateScheduleUc: UpdateScheduleUc(repository: repository),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: BlocProvider<ScheduleBloc>.value(
          value: bloc,
          child: GuidedScheduleFormView(pet: _mascota),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('RF-05: «Generar Plan Automático» usa AppCtaButton con radio 8', (
    tester,
  ) async {
    await pumpGuided(tester);

    final cta = find.byType(AppCtaButton);
    expect(cta, findsOneWidget);
    expect(
      find.descendant(of: cta, matching: find.text('Generar Plan Automático')),
      findsOneWidget,
    );

    final semantica = AppTheme.lightTheme.extension<AppSemanticColors>()!;
    final boton = tester.widget<FilledButton>(
      find.descendant(of: cta, matching: find.byType(FilledButton)),
    );
    expect(
      boton.style!.backgroundColor!.resolve(<WidgetState>{}),
      semantica.cta,
    );
    expect(
      boton.style!.foregroundColor!.resolve(<WidgetState>{}),
      semantica.onCta,
    );
    expect(boton.style!.shape, isNull);
    final forma =
        AppTheme.lightTheme.filledButtonTheme.style!.shape!.resolve(
              <WidgetState>{},
            )!
            as RoundedRectangleBorder;
    expect(forma.borderRadius, BorderRadius.circular(8));
  });
}
