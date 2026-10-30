import 'dart:io';
import 'dart:math' as math;

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/core/theme/theme_cubit.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/settings_view.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Luminancia relativa WCAG 2.1 sobre los canales sRGB en 0..1.
double _luminancia(Color color) {
  double canal(double valor) => valor <= 0.03928
      ? valor / 12.92
      : math.pow((valor + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * canal(color.r) +
      0.7152 * canal(color.g) +
      0.0722 * canal(color.b);
}

/// Cociente de contraste WCAG entre dos colores opacos.
double _contraste(Color fondo, Color texto) {
  final l1 = _luminancia(fondo);
  final l2 = _luminancia(texto);
  final alto = math.max(l1, l2);
  final bajo = math.min(l1, l2);
  return (alto + 0.05) / (bajo + 0.05);
}

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// RF-25: el contraste se mide sobre los colores de `AppTheme` efectivamente
/// aplicados en claro y oscuro. Texto normal ≥ 4.5:1; texto grande y
/// componentes gráficos ≥ 3:1.
void main() {
  Future<ThemeData> pumpTema(WidgetTester tester, ThemeData tema) async {
    final themeCubit = ThemeCubit(storageService: _FakeStorage());
    addTearDown(themeCubit.close);
    await tester.pumpWidget(
      BlocProvider<ThemeCubit>.value(
        value: themeCubit,
        child: MaterialApp(theme: tema, home: const SettingsView()),
      ),
    );
    await tester.pumpAndSettle();
    return Theme.of(tester.element(find.byType(SettingsView)));
  }

  void medir(ThemeData tema, String nombre) {
    final scheme = tema.colorScheme;
    final fondo = tema.scaffoldBackgroundColor;
    // Material 3 pinta `Card` con `colorScheme.surfaceContainerLow`: el
    // `cardColor` del tema no se aplica a las tarjetas, así que medir contra él
    // daría la ratio de un fondo que nunca se ve (RF-25).
    final tarjeta = tema.cardTheme.color ?? scheme.surfaceContainerLow;
    final textoNormal = tema.textTheme.bodyMedium?.color ?? scheme.onSurface;
    final textoGrande = tema.textTheme.titleLarge?.color ?? scheme.onSurface;

    final filas = <List<Object>>[
      <Object>['Texto normal sobre el fondo', textoNormal, fondo, 4.5],
      <Object>['Texto normal sobre la tarjeta', textoNormal, tarjeta, 4.5],
      <Object>[
        'Texto secundario sobre la tarjeta',
        scheme.onSurfaceVariant,
        tarjeta,
        4.5,
      ],
      <Object>[
        'Icono del menú (onPrimaryContainer)',
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
        4.5,
      ],
      <Object>[
        'Aviso del perfil (onSecondaryContainer)',
        scheme.onSecondaryContainer,
        scheme.secondaryContainer,
        4.5,
      ],
      <Object>[
        'Aviso de sesión (onErrorContainer)',
        scheme.onErrorContainer,
        scheme.errorContainer,
        4.5,
      ],
      <Object>[
        'Advertencia destructiva sobre la tarjeta',
        scheme.error,
        tarjeta,
        4.5,
      ],
      <Object>[
        'Acción destructiva (onError)',
        scheme.onError,
        scheme.error,
        4.5,
      ],
      <Object>[
        'Acción principal (onPrimary)',
        scheme.onPrimary,
        scheme.primary,
        4.5,
      ],
      <Object>['Texto grande sobre la tarjeta', textoGrande, tarjeta, 3.0],
      <Object>[
        'Componente primario sobre el fondo',
        scheme.primary,
        fondo,
        3.0,
      ],
      <Object>['Componente de error sobre el fondo', scheme.error, fondo, 3.0],
      <Object>[
        'Componente de error sobre la tarjeta',
        scheme.error,
        tarjeta,
        3.0,
      ],
      <Object>[
        'Componente primario sobre la tarjeta',
        scheme.primary,
        tarjeta,
        3.0,
      ],
      <Object>[
        'Componente de contorno sobre el fondo',
        scheme.outline,
        fondo,
        3.0,
      ],
    ];

    for (final fila in filas) {
      final etiqueta = fila[0] as String;
      final color = fila[1] as Color;
      final contra = fila[2] as Color;
      final minimo = fila[3] as double;
      final ratio = _contraste(contra, color);
      // Se imprime la tabla medida para dejar evidencia en la salida de test.
      // ignore: avoid_print
      print(
        '$nombre | $etiqueta | ${_hex(color)} sobre ${_hex(contra)} '
        '= ${ratio.toStringAsFixed(2)}:1 (mínimo ${minimo.toStringAsFixed(1)}:1)',
      );
      expect(
        ratio,
        greaterThanOrEqualTo(minimo),
        reason: '$nombre: $etiqueta no alcanza el mínimo de $minimo:1',
      );
    }
  }

  testWidgets('RF-25: el tema claro cumple el contraste mínimo', (
    tester,
  ) async {
    final tema = await pumpTema(tester, AppTheme.lightTheme);

    expect(tema.brightness, Brightness.light);
    medir(tema, 'Claro');
  });

  testWidgets('RF-25: el tema oscuro cumple el contraste mínimo', (
    tester,
  ) async {
    final tema = await pumpTema(tester, AppTheme.darkTheme);

    expect(tema.brightness, Brightness.dark);
    medir(tema, 'Oscuro');
  });

  test(
    'RF-25: las pantallas nuevas usan los temas globales sin estilos literales',
    () {
      // RF-25: las pantallas del menú y la presentación de la cuenta no deben
      // declarar colores, tipografías ni tamaños literales; todo sale de
      // `AppTheme` y de `Theme.of(context)`.
      final raices = <Directory>[
        Directory('lib/features/settings'),
        Directory('lib/features/account/presentation'),
      ];
      final prohibidos = <String>[
        'Color(0x',
        'Colors.',
        'TextStyle(',
        'fontFamily',
        'fontSize:',
      ];

      final archivos = <File>[
        for (final raiz in raices)
          if (raiz.existsSync())
            ...raiz
                .listSync(recursive: true)
                .whereType<File>()
                .where((archivo) => archivo.path.endsWith('.dart')),
      ];

      expect(
        archivos,
        isNotEmpty,
        reason: 'no se encontraron las pantallas nuevas',
      );
      for (final archivo in archivos) {
        final codigo = archivo.readAsStringSync();
        for (final prohibido in prohibidos) {
          expect(
            codigo.contains(prohibido),
            isFalse,
            reason: '${archivo.path} contiene el estilo literal «$prohibido»',
          );
        }
      }
    },
  );
}
