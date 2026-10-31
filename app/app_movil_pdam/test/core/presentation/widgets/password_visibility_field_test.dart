import 'package:app_movil_pdam/core/presentation/widgets/password_visibility_field.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Texto que Flutter pinta dentro del campo, sea `TextField` o `TextFormField`.
bool _oculto(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).obscureText;

Future<void> _montar(WidgetTester tester, Widget campo) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: Center(child: campo)),
    ),
  );
}

Future<TextEditingController> _campoSimple(
  WidgetTester tester, {
  String? errorText,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
}) async {
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  await _montar(
    tester,
    PasswordVisibilityField(
      controller: controller,
      label: 'Contraseña',
      errorText: errorText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    ),
  );
  return controller;
}

Future<void> _enfocar(WidgetTester tester) async {
  await tester.tap(find.byType(TextField));
  await tester.pump();
}

void main() {
  group('RF-10: widget compartido del ojo', () {
    testWidgets('empieza oculto y sin ojo con el campo vacío y sin foco', (
      tester,
    ) async {
      await _campoSimple(tester);

      expect(_oculto(tester), isTrue);
      expect(find.byTooltip('Mostrar contraseña'), findsNothing);
      expect(find.byTooltip('Ocultar contraseña'), findsNothing);
    });

    testWidgets('el ojo aparece al recibir el foco', (tester) async {
      await _campoSimple(tester);

      await _enfocar(tester);

      expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
      expect(_oculto(tester), isTrue);
    });

    testWidgets('el ojo aparece con contenido y no desaparece al dejar de '
        'escribir', (tester) async {
      await _campoSimple(tester);

      await tester.enterText(find.byType(TextField), 'secreto');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
      expect(find.byTooltip('Ocultar contraseña'), findsNothing);
    });

    testWidgets('alterna mostrar y ocultar sin alterar texto ni cursor', (
      tester,
    ) async {
      final controller = await _campoSimple(tester);
      await tester.enterText(find.byType(TextField), 'secreto');
      controller.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      await tester.tap(find.byTooltip('Mostrar contraseña'));
      await tester.pump();

      expect(_oculto(tester), isFalse);
      expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
      expect(controller.text, 'secreto');
      expect(controller.selection, const TextSelection.collapsed(offset: 3));

      await tester.tap(find.byTooltip('Ocultar contraseña'));
      await tester.pump();

      expect(_oculto(tester), isTrue);
      expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
      expect(controller.text, 'secreto');
      expect(controller.selection, const TextSelection.collapsed(offset: 3));
    });

    testWidgets('mantiene el error externo al alternar la visibilidad', (
      tester,
    ) async {
      await _campoSimple(tester, errorText: 'La contraseña es obligatoria');
      await _enfocar(tester);

      expect(find.text('La contraseña es obligatoria'), findsOneWidget);

      await tester.tap(find.byTooltip('Mostrar contraseña'));
      await tester.pump();

      expect(find.text('La contraseña es obligatoria'), findsOneWidget);
      expect(_oculto(tester), isFalse);
    });

    testWidgets(
      'con error externo el ojo sigue visible sin foco ni contenido',
      (tester) async {
        await _campoSimple(tester, errorText: 'La contraseña es obligatoria');

        expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
        expect(_oculto(tester), isTrue);
      },
    );

    testWidgets('con error de validación el ojo sigue visible con el campo '
        'vacío', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _montar(
        tester,
        Form(
          key: formKey,
          child: PasswordVisibilityField(
            controller: controller,
            label: 'Contraseña',
            validator: (valor) =>
                (valor == null || valor.isEmpty) ? 'Obligatoria' : null,
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      await tester.pump();

      expect(find.text('Obligatoria'), findsOneWidget);
      expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
      expect(_oculto(tester), isTrue);
    });

    testWidgets('valida igual antes y después de alternar', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _montar(
        tester,
        Form(
          key: formKey,
          child: PasswordVisibilityField(
            controller: controller,
            label: 'Contraseña',
            validator: (valor) {
              if (valor == null || valor.isEmpty) {
                return 'La contraseña es obligatoria';
              }
              return null;
            },
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('La contraseña es obligatoria'), findsOneWidget);

      await _enfocar(tester);
      await tester.tap(find.byTooltip('Mostrar contraseña'));
      await tester.pump();

      expect(_oculto(tester), isFalse);
      expect(find.text('La contraseña es obligatoria'), findsOneWidget);
      expect(formKey.currentState!.validate(), isFalse);

      await tester.enterText(find.byType(TextField), 'claveLarga');
      await tester.pump();
      expect(formKey.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('La contraseña es obligatoria'), findsNothing);
    });

    testWidgets('reenvía onChanged y onSubmitted sin cambiar el texto', (
      tester,
    ) async {
      String? cambiado;
      String? enviado;
      final controller = await _campoSimple(
        tester,
        onChanged: (valor) => cambiado = valor,
        onSubmitted: (valor) => enviado = valor,
      );

      await tester.enterText(find.byType(TextField), 'claveLarga');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(cambiado, 'claveLarga');
      expect(enviado, 'claveLarga');
      expect(controller.text, 'claveLarga');
    });

    testWidgets('respeta el estado deshabilitado', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _montar(
        tester,
        PasswordVisibilityField(
          controller: controller,
          label: 'Contraseña',
          enabled: false,
        ),
      );

      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });
  });
}
