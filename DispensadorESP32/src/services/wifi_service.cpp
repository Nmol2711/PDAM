#include "wifi_service.h"
#include "../config/provisioning_utils.h"

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
      
      if (areCredentialsComplete(receivedSsid.c_str(), receivedPass.c_str())) {
        credentialsReceived = true;
      }
    }
  }
};

String getGlobalMacAddress() {
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char macStr[18];
  formatMacAddress(mac, macStr, sizeof(macStr));
  return String(macStr);
}

void checkAndWipeNVSOnFirstBoot() {
  Preferences systemPrefs;
  systemPrefs.begin("pdam_system", false);
  
  String storedBuild = systemPrefs.getString("build_stamp", "");
  String currentBuild = String(__DATE__) + " " + String(__TIME__);
  
  Serial.print("Build guardado en NVS: ");
  Serial.println(storedBuild);
  Serial.print("Build actual de compilacion: ");
  Serial.println(currentBuild);

  if (storedBuild != currentBuild) {
    Serial.println("Detectado nuevo flasheo o primer arranque. Limpiando NVS de credenciales WiFi...");
    Preferences wifiPrefs;
    wifiPrefs.begin("pdam_wifi", false);
    wifiPrefs.clear();
    wifiPrefs.end();
    
    systemPrefs.putString("build_stamp", currentBuild);
    Serial.println("NVS limpiado y build_stamp actualizado correctamente.");
  } else {
    Serial.println("Misma version de firmware detectada. Preservando credenciales NVS.");
  }
  
  systemPrefs.end();
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

bool validateServerConnectivity(const String &serverHostOrUrl) {
  HTTPClient http;
  String endpoint;
  
  if (serverHostOrUrl.startsWith("http://") || serverHostOrUrl.startsWith("https://")) {
    int thirdSlash = serverHostOrUrl.indexOf('/', 8);
    if (thirdSlash != -1) {
      endpoint = serverHostOrUrl.substring(0, thirdSlash + 1);
    } else {
      endpoint = serverHostOrUrl;
      if (!endpoint.endsWith("/")) {
        endpoint += "/";
      }
    }
  } else {
    endpoint = String("http://") + serverHostOrUrl;
    if (!endpoint.endsWith("/")) {
      endpoint += "/";
    }
  }

  Serial.print("Validando conectividad HTTP con servidor en: ");
  Serial.println(endpoint);

  http.begin(endpoint);
  http.setTimeout(4000);
  int httpCode = http.GET();
  http.end();

  Serial.print("Codigo de respuesta HTTP para root (/): ");
  Serial.println(httpCode);

  if (httpCode == 200) {
    Serial.println("Validación HTTP exitosa (Status 200). Conectividad aprobada.");
    return true;
  } else {
    Serial.println("Error: El servidor no respondió con Status 200.");
    return false;
  }
}

void runBleProvisioning(String &outSsid, String &outPass) {
  Serial.println("\n[Estado] Iniciando servidor GATT BLE para aprovisionamiento...");
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char bleName[30];
  buildBleDeviceName(mac, bleName, sizeof(bleName));

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

  Serial.println("Esperando 2 segundos para completar respuesta GATT BLE...");
  delay(2000);

  Serial.println("Apagando radio BLE tras guardar credenciales...");
  BLEDevice::deinit(true);
}
