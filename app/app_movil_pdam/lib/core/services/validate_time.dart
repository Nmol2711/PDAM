bool validateTime(String texto) {
  // Esta expresión regular valida el formato HH:mm en 24 horas
  final regExp = RegExp(r'^(0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]$');

  return regExp.hasMatch(texto);
}
