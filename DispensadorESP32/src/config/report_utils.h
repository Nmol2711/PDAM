#ifndef REPORT_UTILS_H
#define REPORT_UTILS_H

#include <cstdarg>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>

#include "dispensing_utils.h"

// Reporte de fin de ciclo al servidor (Spec 014: RF-36, RF-37, RF-39).
// Cabecera pura: no incluye <Arduino.h> para poder probarse en el entorno
// nativo y no añade dependencias (RNF-4).

namespace reporting {

// Plazo de respuesta de cada intento del reporte (RF-37).
constexpr unsigned long kReportTimeoutMs = 10000;

// Esperas antes del primer y del segundo reintento (RF-37).
constexpr unsigned long kReportRetryDelaysMs[2] = {5000, 15000};

// Un intento inicial y dos reintentos, como máximo (RF-37).
constexpr unsigned kReportMaxAttempts = 3;

// Queda un reintento mientras los intentos hechos no lleguen al máximo.
inline bool hayReintentoDisponible(unsigned intentosHechos) {
  return intentosHechos < kReportMaxAttempts;
}

// Motivo del reporte por cada fin de ciclo (RF-36).
//
// Los dos cierres que rechazan la orden antes de tocar el hardware no tienen una
// causa propia en el catálogo de la spec y se reportan como `orden_invalida`:
// el ciclo no llegó a dispensar y no hay nada que reconciliar con el servidor.
inline const char *motivoPara(dispensing::DispenseReason reason) {
  switch (reason) {
  case dispensing::DispenseReason::COMPLETED:
    return "objetivo_alcanzado";
  case dispensing::DispenseReason::NOT_REACHED:
    return "objetivo_no_alcanzado";
  case dispensing::DispenseReason::SENSOR_UNAVAILABLE:
    return "sensor_no_disponible";
  case dispensing::DispenseReason::SENSOR_FAILURE:
    return "fallo_sensor_dispensacion";
  case dispensing::DispenseReason::STALL_UNRESOLVED:
    return "atasco_no_resuelto";
  case dispensing::DispenseReason::INVALID_CONFIG:
  case dispensing::DispenseReason::INVALID_AMOUNT:
    return "orden_invalida";
  }
  return "orden_invalida";
}

// Datos del reporte. Cada campo opcional tiene su bandera: el servidor admite la
// ausencia declarada de gramos (RF-14) y el dispositivo no debe inventar un
// valor que no midió.
struct ReporteCiclo {
  bool orderIdAvailable;
  long orderId;
  dispensing::DispenseReason motivo;
  bool solicitadosAvailable;
  float solicitados;
  bool medidosAvailable;
  float medidos;
  unsigned reintentos;
};

// Reporte sin orden ni gramos conocidos, para los cierres que no dispensan.
inline ReporteCiclo reporteVacio(dispensing::DispenseReason motivo) {
  ReporteCiclo reporte{};
  reporte.orderIdAvailable = false;
  reporte.orderId = 0;
  reporte.motivo = motivo;
  reporte.solicitadosAvailable = false;
  reporte.solicitados = 0.0f;
  reporte.medidosAvailable = false;
  reporte.medidos = 0.0f;
  reporte.reintentos = 0;
  return reporte;
}

// Traduce el resultado del ciclo al reporte (RF-36).
//
// Los gramos medidos son el incremento del ciclo: sin línea base no hay
// incremento atribuible y el campo se declara ausente.
inline ReporteCiclo reporteDesdeResultado(const dispensing::DispenseResult &result,
                                          bool orderIdAvailable, long orderId) {
  ReporteCiclo reporte{};
  reporte.orderIdAvailable = orderIdAvailable;
  reporte.orderId = orderIdAvailable ? orderId : 0;
  reporte.motivo = result.reason;
  reporte.solicitadosAvailable = result.requestedGrams > 0.0f;
  reporte.solicitados = reporte.solicitadosAvailable ? result.requestedGrams : 0.0f;
  reporte.medidosAvailable = result.incrementAvailable;
  reporte.medidos = result.incrementAvailable ? result.incrementGrams : 0.0f;
  reporte.reintentos = result.retryCount;
  return reporte;
}

namespace detail {

// Añade texto al buffer sin desbordarlo. Marca `ok` como falso en cuanto un
// campo no cabe, de modo que nunca se envía un JSON truncado.
inline void append(char *buffer, std::size_t size, std::size_t *used, bool *ok,
                   const char *format, ...) {
  if (!*ok) {
    return;
  }
  va_list args;
  va_start(args, format);
  const int written = std::vsnprintf(buffer + *used, size - *used, format, args);
  va_end(args);
  if (written < 0 || static_cast<std::size_t>(written) >= size - *used) {
    *ok = false;
    return;
  }
  *used += static_cast<std::size_t>(written);
}

} // namespace detail

// Construye el cuerpo del reporte para `POST /dispensers/reports` (RF-36).
//
// Omite los campos no disponibles y usa `snprintf` (sin ArduinoJson). Devuelve
// false si el buffer no es usable o si el JSON no cabe completo.
inline bool construirReporteJson(const char *mac, const ReporteCiclo &reporte,
                                 char *buffer, std::size_t size) {
  if (buffer == nullptr || size == 0 || mac == nullptr || mac[0] == '\0') {
    return false;
  }

  std::size_t used = 0;
  bool ok = true;
  buffer[0] = '\0';

  detail::append(buffer, size, &used, &ok, "{\"mac\":\"%s\"", mac);
  if (reporte.orderIdAvailable) {
    detail::append(buffer, size, &used, &ok, ",\"order_id\":%ld",
                   reporte.orderId);
  }
  detail::append(buffer, size, &used, &ok, ",\"motivo\":\"%s\"",
                 motivoPara(reporte.motivo));
  if (reporte.solicitadosAvailable) {
    detail::append(buffer, size, &used, &ok, ",\"gramos_solicitados\":%.2f",
                   static_cast<double>(reporte.solicitados));
  }
  if (reporte.medidosAvailable) {
    detail::append(buffer, size, &used, &ok, ",\"gramos_medidos\":%.2f",
                   static_cast<double>(reporte.medidos));
  }
  detail::append(buffer, size, &used, &ok, ",\"reintentos\":%u}",
                 reporte.reintentos);

  if (!ok) {
    buffer[0] = '\0';
  }
  return ok;
}

// Códigos del catálogo que el servidor responde con 400 y son definitivos: la
// orden, el motivo o la MAC no admiten reintento (RF-39).
inline bool esCodigoDescartable(const char *codigo) {
  if (codigo == nullptr) {
    return false;
  }
  return std::strcmp(codigo, "orden_desconocida") == 0 ||
         std::strcmp(codigo, "motivo_invalido") == 0 ||
         std::strcmp(codigo, "mac_no_registrada") == 0;
}

// Acción para una respuesta del servidor (RF-39).
enum class ReporteAccion {
  DESCARTAR,  // definitiva: se limpia el pendiente de la NVS
  REINTENTAR  // red, timeout o 5xx: se conserva y se reintenta
};

// Clasifica la respuesta del reporte (RF-39).
//
// Un 2xx cierra la orden o devuelve su resultado con `ya_cerrada`: el reporte ya
// no hace falta. En un 400 se consulta el código: los tres enumerados por RF-39
// son rechazos definitivos. Cualquier otro 4xx se descarta también de forma
// **deliberada** (plan §8.19): un rechazo del cliente no se arregla reintentando
// y el reporte quedaría en un bucle; la alternativa se descartó en el plan. La
// red (código negativo), el timeout y los 5xx conservan el reporte para los
// reintentos de RF-37.
inline ReporteAccion clasificarRespuestaReporte(int status,
                                                const char *codigo) {
  if (status >= 200 && status < 300) {
    return ReporteAccion::DESCARTAR;
  }
  if (status == 400 && esCodigoDescartable(codigo)) {
    // Código enumerado por RF-39: rechazo definitivo conocido.
    return ReporteAccion::DESCARTAR;
  }
  if (status >= 400 && status < 500) {
    // Cualquier otro 4xx (incluido un 400 con código no enumerado) se descarta
    // también a propósito y queda documentado; nunca se reintenta.
    return ReporteAccion::DESCARTAR;
  }
  return ReporteAccion::REINTENTAR;
}

} // namespace reporting

#endif // REPORT_UTILS_H
