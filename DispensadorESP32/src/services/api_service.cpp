#include "api_service.h"

#include <Preferences.h>
#include <cmath>

#include "../config/dispensing_utils.h"
#include "../config/scale_guard_utils.h"
#include "dispensing_service.h"
#include "report_service.h"
#include "scale_guard_service.h"
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

  // Compuerta de asentamiento (Spec 016, RF-1): la decision de entrada se
  // resuelve en la logica pura y aqui solo se cablea el switch, sin repetir
  // condiciones. La compuerta es anterior a cualquier comprobacion del factor de
  // calibracion, asi que un factor invalido se cierra como `sensor_no_disponible`
  // (caso (d)) y nunca como `orden_invalida`. No bloquea `reset_wifi` ni el
  // reposo: solo impide abrir una dispensacion.
  switch (dispensing::decideDispenseEntry(
      dispensing::classifyOrder(resetWifi, serve, amountPresent, amountNumeric,
                                amount),
      guard::settlementGained())) {
  case dispensing::DispenseEntry::RESET_WIFI: {
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
  case dispensing::DispenseEntry::DISPENSE: {
    // Solo se llega aqui con el asentamiento ganado. Se invalida antes de mover
    // el servo porque durante el ciclo no se muestrea y la celda cambia de peso:
    // el estado no puede quedar obsoleto para la siguiente orden (RF-8). La
    // apertura no informa del motivo (nullptr) para no duplicar la linea de
    // invalidacion del cierre: la unica que aporta informacion es la del cierre.
    guard::invalidateSettlement(nullptr);
    const dispensing::DispenseResult result = dispensing::dispenseWeight(amount);
    // Cierre del ciclo (RF-5, RF-8): un cierre sin medicion fiable (tope, suelo
    // o 3 lecturas invalidas consecutivas) o un fallo de sensor exigen una
    // racha nueva antes de aceptar otra orden. El servicio solo ve el motivo del
    // cierre; no distingue la causa fisica, que se decide y se prueba en la
    // logica pura. Un cierre exitoso no invalida nada por si mismo.
    if (result.reason == dispensing::DispenseReason::SENSOR_UNAVAILABLE) {
      guard::invalidateSettlement("cierre sin medicion fiable");
    } else if (result.reason == dispensing::DispenseReason::SENSOR_FAILURE) {
      guard::invalidateSettlement("fallo de sensor");
    }
    // Reporte de fin de ciclo (RF-36): el servidor cierra la orden con los
    // gramos medidos y el motivo. El envio no bloquea la siguiente consulta:
    // el temporizador de 20 s se reinicia al terminar esta funcion.
    const reporting::ReporteCiclo reporte =
        reporting::reporteDesdeResultado(result, orderIdAvailable, orderId);
    reporting::enviarReporte(getGlobalMacAddress().c_str(), reporte,
                             REPORTS_URL);
    break;
  }
  case dispensing::DispenseEntry::REJECT_NO_SETTLEMENT: {
    // Cierre sin ciclo (RF-1, RF-7): no se llama a dispenseWeight, el servo no
    // se toca y el intento queda reportado como `sensor_no_disponible` con el
    // `order_id` y los gramos solicitados recibidos, sin gramos medidos.
    Serial.println("Sin asentamiento de la celda: la orden se cierra como "
                   "sensor_no_disponible sin mover el servo.");
    // No se invalida el asentamiento (decision 18 del plan): el estado ya no
    // estaba ganado y borrar la racha en curso retrasaria la recuperacion.
    reporting::ReporteCiclo reporte = reporting::reporteVacio(
        dispensing::DispenseReason::SENSOR_UNAVAILABLE);
    reporte.orderIdAvailable = orderIdAvailable;
    reporte.orderId = orderIdAvailable ? orderId : 0;
    reporte.solicitadosAvailable = amount > 0.0f;
    reporte.solicitados = amount;
    reporting::enviarReporte(getGlobalMacAddress().c_str(), reporte,
                             REPORTS_URL);
    break;
  }
  case dispensing::DispenseEntry::REJECT_ORDER: {
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
  case dispensing::DispenseEntry::REST:
    Serial.println("Estado: sin orden de dispensacion. No se requiere dispensar "
                   "comida aun.");
    break;
  }
}
