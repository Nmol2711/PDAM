#include <Arduino.h>
#include "config/config.h"
#include "config/provisioning_utils.h"
#include "drivers/servo_driver.h"
#include "services/scale_guard_service.h"
#include "services/wifi_service.h"
#include "tasks/dispenser_task.h"
#include "esp_mac.h"

String globalMacAddress = "";
String serverUrl = "";

void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println("\n--- PDAM: INICIALIZANDO DISPENSADOR INTELIGENTE (ESP32 - PlatformIO) ---");

  // 1. Verificar y limpiar NVS en caso de nuevo flasheo o primer arranque (RF-03)
  checkAndWipeNVSOnFirstBoot();

  // 2. Obtener la MAC por hardware eFuse
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char macStr[18];
  formatMacAddress(mac, macStr, sizeof(macStr));
  
  globalMacAddress = String(macStr);
  serverUrl = String(BASE_URL) + globalMacAddress;

  Serial.print("MAC Registrada Globalmente: ");
  Serial.println(globalMacAddress);
  Serial.print("URL de consulta configurada: ");
  Serial.println(serverUrl);

  // 3. Inicializar driver del servomotor
  initServo();

  // 4. Inicializar la celda y el muestreo continuo del asentamiento (RF-1)
  guard::initScaleGuard();
}

void loop() {
  // Muestreo del asentamiento fuera del ciclo de motor y antes de la consulta
  // periódica, que sigue intacta (RF-1, RNF-1).
  guard::updateSettlement();
  runDispenserTask();
}
