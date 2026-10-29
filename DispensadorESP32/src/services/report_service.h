#ifndef REPORT_SERVICE_H
#define REPORT_SERVICE_H

#include <Arduino.h>

#include "../config/report_utils.h"

// Envío del reporte de fin de ciclo con persistencia en NVS (Spec 014, RF-37,
// RF-39).
//
// El reporte se guarda en memoria no volátil ANTES de enviarlo y solo se borra
// con una respuesta definitiva del servidor, de modo que un corte de energía o
// un reinicio no lo pierde.

namespace reporting {

// Namespace propio de la NVS: borrar las credenciales WiFi (`pdam_wifi`) no debe
// borrar el reporte pendiente (RF-37).
constexpr const char *kReportNvsNamespace = "pdam_report";
constexpr const char *kPendingReportKey = "pending";

// Persiste el reporte y lo envía con timeout de 10 s y reintentos a 5 s y 15 s.
//
// Devuelve true si el servidor dio una respuesta definitiva (el pendiente se
// limpió) y false si el reporte se conserva para reenviarlo tras un reinicio.
bool enviarReporte(const char *mac, const ReporteCiclo &reporte,
                   const char *url);

// Reenvía el reporte pendiente, si existe (RF-37). Devuelve true si al terminar
// no queda nada pendiente.
bool reenviarReportePendiente(const char *url);

// Elimina el reporte pendiente de la NVS.
void limpiarReportePendiente();

} // namespace reporting

#endif // REPORT_SERVICE_H
