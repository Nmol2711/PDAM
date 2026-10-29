#include "dispenser_task.h"
#include "../config/dispensing_utils.h"
#include "../services/wifi_service.h"
#include "../services/api_service.h"
#include "../services/report_service.h"
#include <WiFi.h>
#include <Preferences.h>

static DeviceState currentState = STATE_CHECK_NVS;
static unsigned long lastCheckTime = 0;

// Reporte pendiente reenviado una sola vez por arranque (RF-37). Si vuelve a
// fallar queda en NVS para el siguiente reinicio; no se reintenta en cada ciclo.
static bool pendingReportRetried = false;

extern String serverUrl;

void runDispenserTask() {
  switch (currentState) {
    case STATE_CHECK_NVS: {
      Serial.println("\n[Estado] Verificando NVS para credenciales WiFi...");
      String ssid = "", pass = "";
      if (getStoredCredentials(ssid, pass) && ssid.length() > 0) {
        Serial.println("Credenciales encontradas en NVS. Intentando conexion WiFi (2.4GHz)...");
        currentState = STATE_CONNECT_WIFI;
      } else {
        Serial.println("Advertencia: No hay credenciales en NVS. Abriendo modo aprovisionamiento BLE.");
        currentState = STATE_BLE_PROVISIONING;
      }
      break;
    }

    case STATE_CONNECT_WIFI: {
      String ssidToConnect = "", passToConnect = "";
      getStoredCredentials(ssidToConnect, passToConnect);

      Serial.print("Conectando a red WiFi 2.4GHz: ");
      Serial.println(ssidToConnect);

      WiFi.mode(WIFI_STA);
      WiFi.begin(ssidToConnect.c_str(), passToConnect.c_str());

      int attempts = 0;
      while (WiFi.status() != WL_CONNECTED && attempts < 30) {
        delay(500);
        Serial.print(".");
        attempts++;
      }
      Serial.println();

      if (WiFi.status() == WL_CONNECTED) {
        Serial.println("Conectado exitosamente al WiFi (2.4GHz).");
        Serial.print("Direccion IP asignada al ESP32: ");
        Serial.println(WiFi.localIP());

        // RF-37: el reporte pendiente de un arranque anterior se reenvía justo
        // después de conectar el WiFi, antes de validar el servidor y de la
        // primera consulta. Así el servidor recibe el reporte antes de que su
        // barrido cierre la orden como `sin_reporte`. Se intenta una sola vez
        // por arranque y aunque el servidor no responda: si falla, se aplican
        // los reintentos y el pendiente queda en NVS para el próximo reinicio.
        if (reporting::tocaReenviarPendiente(pendingReportRetried)) {
          pendingReportRetried = true;
          reporting::reenviarReportePendiente(REPORTS_URL);
        }

        if (validateServerConnectivity(serverUrl)) {
          Serial.println("Validación HTTP exitosa (Status 200). Entrando en estado normal.");
          checkDispenserAction(serverUrl);
          // La primera consulta ya se hizo: la siguiente sera 20 s despues de
          // terminar este ciclo (RF-13).
          lastCheckTime = millis();
          currentState = STATE_NORMAL;
        } else {
          Serial.println("Error: El servidor no respondió con Status 200 tras conectar al WiFi. Rollback a aprovisionamiento BLE.");
          WiFi.disconnect();
          currentState = STATE_BLE_PROVISIONING;
        }
      } else {
        Serial.println("Error: Fallo la conexion WiFi con las credenciales actuales.");
        currentState = STATE_BLE_PROVISIONING;
      }
      break;
    }

    case STATE_BLE_PROVISIONING: {
      String outSsid = "", outPass = "";
      runBleProvisioning(outSsid, outPass);
      currentState = STATE_CONNECT_WIFI;
      break;
    }

    case STATE_NORMAL: {
      if (dispensing::isCheckDue(lastCheckTime, millis(), CHECK_INTERVAL)) {
        if (WiFi.status() == WL_CONNECTED) {
          checkDispenserAction(serverUrl);
        } else {
          Serial.println("Advertencia: Conexion WiFi perdida. Intentando reconectar...");
          WiFi.disconnect();
          
          String ssidToConnect = "", passToConnect = "";
          getStoredCredentials(ssidToConnect, passToConnect);

          WiFi.begin(ssidToConnect.c_str(), passToConnect.c_str());
          
          int reconnAttempts = 0;
          while (WiFi.status() != WL_CONNECTED && reconnAttempts < 20) {
            delay(500);
            reconnAttempts++;
          }

          if (WiFi.status() == WL_CONNECTED) {
            Serial.println("Reconexion WiFi exitosa.");
            if (validateServerConnectivity(serverUrl)) {
              Serial.println("Validación HTTP de reconexión exitosa.");
            } else {
              Serial.println("Error: Servidor no disponible tras reconexión WiFi. Rollback a aprovisionamiento BLE...");
              WiFi.disconnect();
              currentState = STATE_BLE_PROVISIONING;
            }
          } else {
            Serial.println("Reconexion WiFi fallida. Reabriendo modo de aprovisionamiento BLE...");
            currentState = STATE_BLE_PROVISIONING;
          }
        }
        // El temporizador se reinicia DESPUES de la consulta o del intento de
        // reconexion: la siguiente consulta sera 20 s despues del fin (RF-13).
        lastCheckTime = millis();
      }
      break;
    }
  }
}
