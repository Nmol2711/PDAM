/// Cálculo del total de páginas del historial (RF-32, RF-33).
library;

/// Páginas que ocupa un total de registros con el tamaño de página indicado.
///
/// Sin registros siempre hay una página, igual que responde el servidor.
int calcularTotalPaginas(int total, int tamanoPagina) {
  if (tamanoPagina <= 0) {
    throw ArgumentError('El tamaño de página debe ser mayor que cero');
  }
  if (total <= 0) return 1;
  return (total + tamanoPagina - 1) ~/ tamanoPagina;
}
