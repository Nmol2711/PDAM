#include "dispenser_task.h"
#include "../services/wifi_service.h"
#include "../services/api_service.h"
#include <WiFi.h>
#include <Preferences.h>

static DeviceState currentState = STATE_CHECK_NVS;
static unsigned long lastCheckTime = 0;
static const unsigned long checkInterval = 20000; // 20 segundos

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
        
        checkDispenserAction(serverUrl);
        currentState = STATE_NORMAL;
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
      if (millis() - lastCheckTime >= checkInterval) {
        lastCheckTime = millis();
        
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
          } else {
            Serial.println("Reconexion WiFi fallida. Reabriendo modo de aprovisionamiento BLE...");
            currentState = STATE_BLE_PROVISIONING;
          }
        }
      }
      break;
    }
  }
}
