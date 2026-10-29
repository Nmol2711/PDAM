#include "report_service.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <Preferences.h>

#include <cstddef>
#include <cstring>

namespace reporting {
namespace {

// Tamaño del cuerpo del reporte: MAC, motivo, tres números y el texto fijo.
constexpr std::size_t kReportBufferSize = 256;

// Tamaño del código de negocio de una respuesta 400 (`detail.code`).
constexpr std::size_t kCodigoBufferSize = 32;

bool guardarPendiente(const char *json) {
  Preferences preferences;
  if (!preferences.begin(kReportNvsNamespace, false)) {
    return false;
  }
  const std::size_t escrito = preferences.putString(kPendingReportKey, json);
  preferences.end();
  return escrito > 0;
}

bool leerPendiente(char *destino, std::size_t tamanio) {
  if (destino == nullptr || tamanio == 0) {
    return false;
  }
  Preferences preferences;
  if (!preferences.begin(kReportNvsNamespace, true)) {
    return false;
  }
  const String guardado = preferences.getString(kPendingReportKey, "");
  preferences.end();

  if (guardado.length() == 0 || guardado.length() + 1 > tamanio) {
    return false;
  }
  std::strncpy(destino, guardado.c_str(), tamanio - 1);
  destino[tamanio - 1] = '\0';
  return true;
}

// Extrae `detail.code` del cuerpo de un rechazo del catálogo (RF-39).
void extraerCodigo(const String &cuerpo, char *codigo, std::size_t tamanio) {
  if (codigo == nullptr || tamanio == 0) {
    return;
  }
  codigo[0] = '\0';

  StaticJsonDocument<192> doc;
  if (deserializeJson(doc, cuerpo) != DeserializationError::Ok) {
    return;
  }
  const char *recibido = doc["detail"]["code"] | "";
  if (recibido[0] == '\0') {
    return;
  }
  std::strncpy(codigo, recibido, tamanio - 1);
  codigo[tamanio - 1] = '\0';
}

// Resumen del reporte para el monitor serie. Nunca imprime la MAC completa ni
// el JSON entero (RNF-1): solo la orden, el motivo y la longitud del cuerpo.
void imprimirResumen(const char *json, std::size_t longitud) {
  StaticJsonDocument<192> doc;
  const bool valido = deserializeJson(doc, json) == DeserializationError::Ok;

  Serial.print("Reporte a enviar: order_id=");
  if (valido && doc["order_id"].is<long>()) {
    Serial.print(doc["order_id"].as<long>());
  } else {
    Serial.print("no disponible");
  }

  const char *motivo = valido ? (doc["motivo"] | "") : "";
  Serial.print(", motivo=");
  Serial.print(motivo[0] != '\0' ? motivo : "no disponible");
  Serial.print(", longitud=");
  Serial.print(static_cast<unsigned long>(longitud));
  Serial.println(" bytes");
}

// Un intento de envío. Devuelve el código HTTP del servidor o un valor negativo
// cuando no hubo respuesta (error de red o timeout de 10 s).
int enviarUnaVez(const char *url, const char *json, char *codigo,
                 std::size_t codigoTamanio) {
  codigo[0] = '\0';

  HTTPClient http;
  http.setTimeout(kReportTimeoutMs);
  http.setConnectTimeout(kReportTimeoutMs);
  if (!http.begin(String(url))) {
    return -1;
  }
  http.addHeader("Content-Type", "application/json");

  const int status = http.POST(String(json));
  String cuerpo;
  if (status >= 400) {
    cuerpo = http.getString();
  }
  http.end();

  if (status >= 400) {
    extraerCodigo(cuerpo, codigo, codigoTamanio);
  }
  return status;
}

// Aplica la política de RF-37 y RF-39 sobre un cuerpo ya construido.
bool enviarConReintentos(const char *url, const char *json) {
  char codigo[kCodigoBufferSize] = {0};
  unsigned intentos = 0;

  while (true) {
    const int status = enviarUnaVez(url, json, codigo, sizeof(codigo));
    ++intentos;

    Serial.print("Reporte de fin de ciclo: intento ");
    Serial.print(intentos);
    Serial.print(", HTTP ");
    Serial.print(status);
    if (codigo[0] != '\0') {
      Serial.print(", codigo ");
      Serial.print(codigo);
    }
    Serial.println();

    if (clasificarRespuestaReporte(status, codigo) ==
        ReporteAccion::DESCARTAR) {
      limpiarReportePendiente();
      Serial.println("Reporte aceptado o rechazado de forma definitiva: se "
                     "descarta y no se reintenta.");
      return true;
    }

    if (!hayReintentoDisponible(intentos)) {
      Serial.println("Reporte sin respuesta valida tras los reintentos: se "
                     "conserva pendiente para reenviarlo tras un reinicio.");
      return false;
    }

    // Esperas de 5 s y 15 s entre intentos (RF-37).
    const unsigned long espera = kReportRetryDelaysMs[intentos - 1];
    Serial.print("Reintentando el reporte en ");
    Serial.print(espera);
    Serial.println(" ms...");
    delay(espera);
  }
}

} // namespace

bool enviarReporte(const char *mac, const ReporteCiclo &reporte,
                   const char *url) {
  char json[kReportBufferSize];
  if (!construirReporteJson(mac, reporte, json, sizeof(json))) {
    Serial.println("Reporte: no se pudo construir el cuerpo; no se envia.");
    return false;
  }

  Serial.print("Reporte de fin de ciclo: orden ");
  Serial.print(reporte.orderIdAvailable ? reporte.orderId : -1);
  Serial.print(", motivo ");
  Serial.println(motivoPara(reporte.motivo));

  // Se persiste ANTES de enviar: un corte durante el envío no pierde el
  // reporte (RF-37). Si la NVS falla, se intenta igual el envío.
  if (!guardarPendiente(json)) {
    Serial.println("Reporte: aviso, no se pudo guardar en NVS.");
  }

  imprimirResumen(json, std::strlen(json));
  return enviarConReintentos(url, json);
}

bool reenviarReportePendiente(const char *url) {
  char json[kReportBufferSize];
  if (!leerPendiente(json, sizeof(json))) {
    return true;
  }

  Serial.println("Reporte pendiente encontrado en NVS");
  imprimirResumen(json, std::strlen(json));
  return enviarConReintentos(url, json);
}

void limpiarReportePendiente() {
  Preferences preferences;
  if (!preferences.begin(kReportNvsNamespace, false)) {
    return;
  }
  preferences.remove(kPendingReportKey);
  preferences.end();
}

} // namespace reporting
