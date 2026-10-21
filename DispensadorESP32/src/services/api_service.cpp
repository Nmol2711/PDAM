#include "api_service.h"
#include <Preferences.h>

void checkDispenserAction(const String &serverUrl) {
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
      bool serve = doc["serve"] | false;
      bool resetWifi = doc["reset_wifi"] | false;
      
      if (resetWifi) {
        Serial.println("Orden recibida: [reset_wifi = true]. Borrando credenciales NVS y reiniciando en modo BLE.");
        Preferences preferences;
        preferences.begin("pdam_wifi", false);
        preferences.clear();
        preferences.end();
        delay(500);
        ESP.restart();
      } else if (serve) {
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
