#include "api_service.h"

#include <Preferences.h>
#include <cmath>

#include "../config/dispensing_utils.h"
#include "dispensing_service.h"
#include "report_service.h"
#include "wifi_service.h"

void checkDispenserAction(const String &serverUrl) {
  HTTPClient http;

  Serial.println("\nConsultando ordenes pendientes en el servidor...");
  http.begin(serverUrl);

  int httpResponseCode = http.GET();

  // El socket se cierra antes de parsear, dispensar o reiniciar: el ciclo de
  // dispensado puede durar hasta 32 s y no debe retener la conexion.
  String payload = "";
  if (httpResponseCode == 200) {
    payload = http.getString();
  }
  http.end();

  if (httpResponseCode != 200) {
    Serial.print("Error de comunicacion con la API. Codigo HTTP: ");
    Serial.println(httpResponseCode);
    return;
  }

  Serial.print("Respuesta recibida: ");
  Serial.println(payload);

  StaticJsonDocument<200> doc;
  DeserializationError error = deserializeJson(doc, payload);

  if (error) {
    Serial.print("Error al procesar el JSON: ");
    Serial.println(error.c_str());
    return;
  }

  const bool serve = doc["serve"] | false;
  const bool resetWifi = doc["reset_wifi"] | false;

  // `amount` solo cuenta como cantidad si viene presente y es numerico; una
  // cadena, un booleano o un nulo se consideran orden invalida.
  const bool amountPresent = doc.containsKey("amount") && !doc["amount"].isNull();
  bool amountNumeric = false;
  float amount = 0.0f;
  if (amountPresent) {
    const JsonVariantConst amountValue = doc["amount"];
    if (amountValue.is<float>() || amountValue.is<int>()) {
      amount = amountValue.as<float>();
      amountNumeric = std::isfinite(amount);
    }
  }

  // Identificador de la orden entregada: es la clave del reporte de fin de
  // ciclo (RF-36). Sin el no se puede cerrar la orden en el servidor.
  bool orderIdAvailable = false;
  long orderId = 0;
  const JsonVariantConst orderValue = doc["order_id"];
  if (orderValue.is<long>() || orderValue.is<int>()) {
    const long candidate = orderValue.as<long>();
    if (candidate > 0) {
      orderId = candidate;
      orderIdAvailable = true;
    }
  }

  switch (dispensing::classifyOrder(resetWifi, serve, amountPresent,
                                    amountNumeric, amount)) {
  case dispensing::OrderAction::RESET_WIFI: {
    Serial.println("Orden recibida: [reset_wifi = true]. Borrando credenciales "
                   "NVS y reiniciando en modo BLE.");
    Preferences preferences;
    preferences.begin("pdam_wifi", false);
    preferences.clear();
    preferences.end();
    delay(500);
    ESP.restart();
    return;
  }
  case dispensing::OrderAction::DISPENSE: {
    const dispensing::DispenseResult result = dispensing::dispenseWeight(amount);
    // Reporte de fin de ciclo (RF-36): el servidor cierra la orden con los
    // gramos medidos y el motivo. El envio no bloquea la siguiente consulta:
    // el temporizador de 20 s se reinicia al terminar esta funcion.
    const reporting::ReporteCiclo reporte =
        reporting::reporteDesdeResultado(result, orderIdAvailable, orderId);
    reporting::enviarReporte(getGlobalMacAddress().c_str(), reporte,
                             REPORTS_URL);
    break;
  }
  case dispensing::OrderAction::INVALID_ORDER: {
    Serial.println("Advertencia: orden de dispensacion invalida. No se mueve el "
                   "servo.");
    // Cierre sin ciclo: se reporta `orden_invalida` y los gramos solicitados
    // solo si la cantidad recibida era numerica (RF-36).
    reporting::ReporteCiclo reporte = reporting::reporteVacio(
        dispensing::DispenseReason::INVALID_AMOUNT);
    reporte.orderIdAvailable = orderIdAvailable;
    reporte.orderId = orderIdAvailable ? orderId : 0;
    if (amountNumeric && amount > 0.0f) {
      reporte.solicitadosAvailable = true;
      reporte.solicitados = amount;
    }
    reporting::enviarReporte(getGlobalMacAddress().c_str(), reporte,
                             REPORTS_URL);
    break;
  }
  case dispensing::OrderAction::REST:
    Serial.println("Estado: sin orden de dispensacion. No se requiere dispensar "
                   "comida aun.");
    break;
  }
}
