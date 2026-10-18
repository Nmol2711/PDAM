#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <ESP32Servo.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "esp_mac.h"

// UUIDs para el servicio BLE de aprovisionamiento (RF-05, RF-06)
#define SERVICE_UUID               "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID_SSID   "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHARACTERISTIC_UUID_PASS   "1b2f0c83-6f1a-49be-938bb1262744"

// Configuracion de la API
const char* baseUrl = "http://10.22.168.8:8000/dispenserscheck-taks/";

// Variables Globales
Preferences preferences;
String globalMacAddress = "";
String serverUrl = "";

// Configuracion del Hardware (ServoMotor MG966R en Pin 4)
const int servoPin = 4;
Servo myServo;

// Temporizador no bloqueante
unsigned long lastCheckTime = 0;
const unsigned long checkInterval = 20000; // 20 segundos

// Variables de control para aprovisionamiento BLE
bool credentialsReceived = false;
String receivedSsid = "";
String receivedPass = "";

// Maquina de estados del ESP32 (RF-06, RF-07)
enum DeviceState {
  STATE_CHECK_NVS,
  STATE_CONNECT_WIFI,
  STATE_BLE_PROVISIONING,
  STATE_NORMAL
};

DeviceState currentState = STATE_CHECK_NVS;

// Callbacks para recepcion de caracteristicas BLE
class ProvisioningCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    std::string value = pCharacteristic->getValue();
    if (value.length() > 0) {
      String rxValue = String(value.c_str());
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

void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println("\n--- PDAM: INICIALIZANDO DISPENSADOR INTELIGENTE (ESP32) ---");

  // 1. Obtener la MAC por hardware eFuse
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char macStr[18];
  snprintf(macStr, sizeof(macStr), "%02X:%02X:%02X:%02X:%02X:%02X", 
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  
  globalMacAddress = String(macStr);
  serverUrl = String(baseUrl) + globalMacAddress;

  Serial.print("MAC Registrada Globalmente: ");
  Serial.println(globalMacAddress);
  Serial.print("URL de consulta configurada: ");
  Serial.println(serverUrl);

  // 2. Asignar temporizadores para el servo
  ESP32PWM::allocateTimer(0);
  ESP32PWM::allocateTimer(1);
  ESP32PWM::allocateTimer(2);
  ESP32PWM::allocateTimer(3);
  
  myServo.setPeriodHertz(50); 
  myServo.attach(servoPin, 500, 2400);
  myServo.write(90); // Detenido al arrancar
}

void loop() {
  switch (currentState) {
    case STATE_CHECK_NVS: {
      Serial.println("\n[Estado] Verificando NVS para credenciales WiFi...");
      preferences.begin("pdam_wifi", true);
      String storedSsid = preferences.getString("ssid", "");
      String storedPass = preferences.getString("password", "");
      preferences.end();

      if (storedSsid.length() > 0) {
        Serial.println("Credenciales encontradas en NVS. Intentando conexion WiFi (2.4GHz)...");
        currentState = STATE_CONNECT_WIFI;
      } else {
        Serial.println("Advertencia: No hay credenciales en NVS. Abriendo modo aprovisionamiento BLE.");
        currentState = STATE_BLE_PROVISIONING;
      }
      break;
    }

    case STATE_CONNECT_WIFI: {
      preferences.begin("pdam_wifi", true);
      String ssidToConnect = preferences.getString("ssid", "");
      String passToConnect = preferences.getString("password", "");
      preferences.end();

      Serial.print("Conectando a red WiFi 2.4GHz: ");
      Serial.println(ssidToConnect);

      // El ESP32 opera exclusivamente en la banda de 2.4GHz (limitacion fisica de hardware).
      // Se configura explicitamente el modo Station (WIFI_STA).
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
        
        // Primera consulta inmediata
        checkDispenserAction();
        currentState = STATE_NORMAL;
      } else {
        Serial.println("Error: Fallo la conexion WiFi con las credenciales actuales.");
        currentState = STATE_BLE_PROVISIONING;
      }
      break;
    }

    case STATE_BLE_PROVISIONING: {
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

      Serial.println("Credenciales recibidas con exito. Guardando en NVS...");
      preferences.begin("pdam_wifi", false);
      preferences.putString("ssid", receivedSsid);
      preferences.putString("password", receivedPass);
      preferences.end();

      Serial.println("Apagando radio BLE inmediatamente tras guardar credenciales...");
      BLEDevice::deinit(true);

      currentState = STATE_CONNECT_WIFI;
      break;
    }

    case STATE_NORMAL: {
      if (millis() - lastCheckTime >= checkInterval) {
        lastCheckTime = millis();
        
        if (WiFi.status() == WL_CONNECTED) {
          checkDispenserAction();
        } else {
          Serial.println("Advertencia: Conexion WiFi perdida. Intentando reconectar...");
          WiFi.disconnect();
          
          preferences.begin("pdam_wifi", true);
          String ssidToConnect = preferences.getString("ssid", "");
          String passToConnect = preferences.getString("password", "");
          preferences.end();

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

void checkDispenserAction() {
  HTTPClient http;
  
  Serial.println("\nConsultando ordenes pendientes en el servidor...");
  http.begin(serverUrl);
  
  int httpResponseCode = http.GET();
  
  if (httpResponseCode == 200) {
    String payload = http.getString();
    Serial.print("Respuesta recibida: ");
    Serial.println(payload);
    
    StaticJsonDocument<200> doc;
    DeserializationError error = deserializeJson(doc, payload);
    
    if (!error) {
      bool serve = doc["serve"];
      
      if (serve) {
        Serial.println("Orden confirmada: [serve = true]. Iniciando dispensacion.");
        dispensarAlimento();
      } else {
        Serial.println("Estado: [serve = false]. No se requiere dispensar comida aun.");
      }
    } else {
      Serial.print("Error al procesar el JSON: ");
      Serial.println(error.c_str());
    }
  } else {
    Serial.print("Error de comunicacion con la API. Codigo HTTP: ");
    Serial.println(httpResponseCode);
  }
  
  http.end();
}

void dispensarAlimento() {
  Serial.println("Activando motor... El tornillo sin fin esta girando.");
  
  myServo.write(0); 
  delay(10000); // 10 segundos de dispensación
  myServo.write(90); // Detener
  
  Serial.println("Ciclo completado. Motor detenido con exito.");
}
