/// Reglas puras del refresco del historial (RF-3, RF-5).
///
/// La ventana y el ajuste de página se deciden aquí, fuera de la vista y del
/// BLoC, con el reloj como parámetro para que las pruebas sean deterministas.
library;

/// Indica si ya se puede lanzar un refresco automático.
///
/// [ultimoFin] es el instante en que terminó el último refresco automático (o
/// la carga inicial); `null` significa que todavía no hay ninguno. La ventana
/// se mide desde el fin, no desde el inicio (RF-3), y un reloj que retrocede
/// nunca la da por cumplida.
bool puedeRefrescarAutomatico(
  DateTime? ultimoFin,
  DateTime ahora,
  Duration ventana,
) {
  if (ultimoFin == null) return true;
  return ahora.difference(ultimoFin) >= ventana;
}

/// Ajusta la página conservada a una página disponible.
///
/// Sin registros (o con un total de páginas no positivo) la disponible es la
/// primera; una página mayor que el total cae en la última disponible (RF-5).
int ajustarPagina(int pagina, int totalPaginas) {
  if (totalPaginas <= 0) return 1;
  if (pagina < 1) return 1;
  if (pagina > totalPaginas) return totalPaginas;
  return pagina;
}
