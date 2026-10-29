import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Configuración de idioma de la aplicación (RNF-6 de la spec 014).
///
/// Toda la interfaz está en español, incluidos los textos que aportan los
/// widgets del SDK, como el selector de rango de fechas del historial. Se
/// declara un único idioma admitido para que `MaterialLocalizations` no elija
/// inglés por el idioma del dispositivo.
const List<Locale> idiomasAdmitidos = <Locale>[Locale('es')];

/// Idioma por defecto de la aplicación.
const Locale idiomaPorDefecto = Locale('es');

/// Delegados de material, widgets y Cupertino en español.
const List<LocalizationsDelegate<dynamic>> delegadosDeLocalizacion =
    <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];
