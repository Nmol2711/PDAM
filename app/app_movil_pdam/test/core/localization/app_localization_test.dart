import 'package:app_movil_pdam/core/localization/app_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la aplicación declara español y los delegados del SDK', () {
    expect(idiomaPorDefecto, const Locale('es'));
    expect(idiomasAdmitidos, contains(const Locale('es')));
    expect(
      delegadosDeLocalizacion,
      containsAll(<LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ]),
    );
  });

  testWidgets('el selector de rango de fechas muestra rótulos en español', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: idiomaPorDefecto,
        supportedLocales: idiomasAdmitidos,
        localizationsDelegates: delegadosDeLocalizacion,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2025),
                  lastDate: DateTime(2026, 12, 31),
                  helpText: 'Rango de fechas',
                ),
                child: const Text('Abrir selector'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir selector'));
    await tester.pumpAndSettle();

    // Rótulos que aporta `MaterialLocalizations`; en inglés serían «SAVE» o
    // «CANCEL». El texto de ayuda es el que pasa el historial.
    expect(find.text('Rango de fechas'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);

    final contexto = tester.element(find.text('Rango de fechas'));
    expect(MaterialLocalizations.of(contexto).saveButtonLabel, 'Guardar');
  });
}
