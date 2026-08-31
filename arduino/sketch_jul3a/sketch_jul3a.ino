#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <ESP32Servo.h>
#include "esp_mac.h"

// 📶 Configuración de Red (Mantenemos la que te funcionó)
const char* ssid = "nmol2711"; 
const char* password = "12345678";

// 🌐 Configuración de la API (Path Parameter)
//const char* baseUrl = "http://192.168.1.58:8000/dispenserscheck-taks/";

const char* baseUrl = "http://10.22.168.8:8000/dispenserscheck-taks/";

// 🆔 Variables Globales
String globalMacAddress = "";
String serverUrl = "";

// ⚙️ Configuración del Hardware (Ajustado a tu pin de prueba exitoso)
const int servoPin = 4; // Pin 4 (D4) 
Servo myServo;

// ⏱️ Temporizador no bloqueante
unsigned long lastCheckTime = 0;
const unsigned long checkInterval = 20000; // 10 seg

void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println("\n--- PDAM: INICIALIZANDO DISPENSADOR INTELIGENTE ---");

  // 1. Obtener la MAC por hardware eFuse
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char macStr[18];
  snprintf(macStr, sizeof(macStr), "%02X:%02X:%02X:%02X:%02X:%02X", 
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  
  globalMacAddress = String(macStr);
  serverUrl = String(baseUrl) + globalMacAddress;

  Serial.print("🔹 MAC Registrada Globalmente: ");
  Serial.println(globalMacAddress);
  Serial.print("🔹 URL de consulta configurada: ");
  Serial.println(serverUrl);

  // 2. Asignar los timers completos como en tu prueba original
  ESP32PWM::allocateTimer(0);
  ESP32PWM::allocateTimer(1);
  ESP32PWM::allocateTimer(2);
  ESP32PWM::allocateTimer(3);
  
  myServo.setPeriodHertz(50); 
  myServo.attach(servoPin, 500, 2400);
  myServo.write(90); // Empezar detenido

  // 3. Conexión Wi-Fi
  WiFi.begin(ssid, password);
  Serial.print("Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\n¡Conectado exitosamente al WiFi!");
  Serial.print("Dirección IP asignada al ESP32: ");
  Serial.println(WiFi.localIP());
  
  // Primera consulta inmediata
  checkDispenserAction();
}

void loop() {
  if (millis() - lastCheckTime >= checkInterval) {
    lastCheckTime = millis();
    
    if (WiFi.status() == WL_CONNECTED) {
      checkDispenserAction();
    } else {
      Serial.println("⚠️ Error: Conexión WiFi perdida. Intentando reconectar...");
      WiFi.disconnect();
      WiFi.begin(ssid, password);
    }
  }
}

void checkDispenserAction() {
  HTTPClient http;
  
  Serial.println("\nConsultando órdenes pendientes en el servidor...");
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
        Serial.println("🟢 Orden confirmada: [serve = true]. Iniciando dispensación.");
        dispensarAlimento();
      } else {
        Serial.println("⚪ Estado: [serve = false]. No se requiere dispensar comida aún.");
      }
    } else {
      Serial.print("❌ Error al procesar el JSON: ");
      Serial.println(error.c_str());
    }
  } else {
    Serial.print("❌ Error de comunicación con la API. Código HTTP: ");
    Serial.println(httpResponseCode);
  }
  
  http.end();
}

void dispensarAlimento() {
  Serial.println("🔄 Activando motor... El tornillo sin fin está girando.");
  
  // 🔴 Usamos '0' que es el valor con el que giró correctamente en tu prueba inversa
  myServo.write(0); 
  
  // Mantenemos el movimiento por los 15 segundos solicitados
  delay(10000); 
  
  // Detenemos el motor por completo
  myServo.write(90);
  
  Serial.println("🛑 Ciclo completado. Motor detenido con éxito.");
}