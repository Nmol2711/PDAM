#include <Arduino.h>
#include "config/config.h"
#include "drivers/servo_driver.h"
#include "services/wifi_service.h"
#include "tasks/dispenser_task.h"
#include "esp_mac.h"

String globalMacAddress = "";
String serverUrl = "";

void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println("\n--- PDAM: INICIALIZANDO DISPENSADOR INTELIGENTE (ESP32 - PlatformIO) ---");

  // 1. Obtener la MAC por hardware eFuse
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char macStr[18];
  snprintf(macStr, sizeof(macStr), "%02X:%02X:%02X:%02X:%02X:%02X", 
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  
  globalMacAddress = String(macStr);
  serverUrl = String(BASE_URL) + globalMacAddress;

  Serial.print("MAC Registrada Globalmente: ");
  Serial.println(globalMacAddress);
  Serial.print("URL de consulta configurada: ");
  Serial.println(serverUrl);

  // 2. Inicializar driver del servomotor
  initServo();
}

void loop() {
  runDispenserTask();
}
