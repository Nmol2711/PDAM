#include "wifi_service.h"

// Variables locales para aprovisionamiento BLE
static bool credentialsReceived = false;
static String receivedSsid = "";
static String receivedPass = "";

class ProvisioningCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String rxValue = pCharacteristic->getValue();
    if (rxValue.length() > 0) {
      if (pCharacteristic->getUUID().equals(BLEUUID(CHARACTERISTIC_UUID_SSID))) {
        receivedSsid = rxValue;
        Serial.print("SSID recibido via BLE: ");
        Serial.println(receivedSsid);
      } else if (pCharacteristic->getUUID().equals(BLEUUID(CHARACTERISTIC_UUID_PASS))) {
        receivedPass = rxValue;
        Serial.print("Password recibido via BLE (longitud): ");
        Serial.println(receivedPass.length());
      }
      
      if (receivedSsid.length() > 0 && receivedPass.length() > 0) {
        credentialsReceived = true;
      }
    }
  }
};

String getGlobalMacAddress() {
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char macStr[18];
  snprintf(macStr, sizeof(macStr), "%02X:%02X:%02X:%02X:%02X:%02X", 
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  return String(macStr);
}

bool getStoredCredentials(String &ssid, String &pass) {
  Preferences preferences;
  preferences.begin("pdam_wifi", true);
  ssid = preferences.getString("ssid", "");
  pass = preferences.getString("password", "");
  preferences.end();
  return (ssid.length() > 0);
}

void saveStoredCredentials(const String &ssid, const String &pass) {
  Preferences preferences;
  preferences.begin("pdam_wifi", false);
  preferences.putString("ssid", ssid);
  preferences.putString("password", pass);
  preferences.end();
}

bool connectWiFi(const String &ssid, const String &pass, int maxAttempts) {
  Serial.print("Conectando a red WiFi 2.4GHz: ");
  Serial.println(ssid);

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), pass.c_str());

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < maxAttempts) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("Conectado exitosamente al WiFi (2.4GHz).");
    Serial.print("Direccion IP asignada al ESP32: ");
    Serial.println(WiFi.localIP());
    return true;
  } else {
    Serial.println("Error: Fallo la conexion WiFi con las credenciales actuales.");
    return false;
  }
}

void disconnectWiFi() {
  WiFi.disconnect();
}

bool isWiFiConnected() {
  return (WiFi.status() == WL_CONNECTED);
}

void runBleProvisioning(String &outSsid, String &outPass) {
  Serial.println("\n[Estado] Iniciando servidor GATT BLE para aprovisionamiento...");
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char bleName[30];
  char macClean[13];
  snprintf(macClean, sizeof(macClean), "%02X%02X%02X%02X%02X%02X", 
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  snprintf(bleName, sizeof(bleName), "PDAM-Config-%s", macClean);

  BLEDevice::init(bleName);
  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);

  BLECharacteristic *pSsidCharacteristic = pService->createCharacteristic(
                          CHARACTERISTIC_UUID_SSID,
                          BLECharacteristic::PROPERTY_READ |
                          BLECharacteristic::PROPERTY_WRITE
                        );
  pSsidCharacteristic->setCallbacks(new ProvisioningCallbacks());

  BLECharacteristic *pPassCharacteristic = pService->createCharacteristic(
                          CHARACTERISTIC_UUID_PASS,
                          BLECharacteristic::PROPERTY_READ |
                          BLECharacteristic::PROPERTY_WRITE
                        );
  pPassCharacteristic->setCallbacks(new ProvisioningCallbacks());

  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06); 
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.print("Servidor BLE activo. Anunciando como: ");
  Serial.println(bleName);

  credentialsReceived = false;
  receivedSsid = "";
  receivedPass = "";

  // Esperar recepcion de credenciales desde la App Flutter via BLE
  while (!credentialsReceived) {
    delay(100);
  }

  outSsid = receivedSsid;
  outPass = receivedPass;

  Serial.println("Credenciales recibidas con exito. Guardando en NVS...");
  saveStoredCredentials(outSsid, outPass);

  Serial.println("Apagando radio BLE inmediatamente tras guardar credenciales...");
  BLEDevice::deinit(true);
}
