import 'package:flutter/material.dart';

/// Radios de la aplicación (spec 017, RF-08).
///
/// Radio base 8: botones, campos, tarjetas, chip, botón flotante y aviso
/// emergente. Diálogos, hojas y menús derivan en 12. Ninguna pantalla debe
/// declarar un radio literal ni formas de píldora.
class AppRadii {
  const AppRadii._();

  static const double base = 8;
  static const double control = base;
  static const double card = base;
  static const double chip = base;
  static const double fab = base;
  static const double banner = base;

  static const double dialog = 12;
  static const double sheet = dialog;
  static const double menu = dialog;

  static const BorderRadius controlRadius = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius dialogRadius = BorderRadius.all(
    Radius.circular(dialog),
  );
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
  static const BorderRadius menuRadius = BorderRadius.all(
    Radius.circular(menu),
  );
}
