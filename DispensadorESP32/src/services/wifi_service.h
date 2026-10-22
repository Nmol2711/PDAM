#ifndef WIFI_SERVICE_H
#define WIFI_SERVICE_H

#include <Arduino.h>
#include <WiFi.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "esp_mac.h"
#include "../config/config.h"
#include <HTTPClient.h>

// Obtiene la dirección MAC del ESP32 como String formateado ("XX:XX:XX:XX:XX:XX")
String getGlobalMacAddress();

// Gestión de almacenamiento NVS
bool getStoredCredentials(String &ssid, String &pass);
void saveStoredCredentials(const String &ssid, const String &pass);
void checkAndWipeNVSOnFirstBoot();

// Conexión WiFi 2.4GHz
bool connectWiFi(const String &ssid, const String &pass, int maxAttempts = 30);
void disconnectWiFi();
bool isWiFiConnected();

// Validación de conectividad HTTP al servidor raíz (RF-02)
bool validateServerConnectivity(const String &serverHostOrUrl);

// Ejecuta el servidor BLE de aprovisionamiento (bloqueante hasta recibir credenciales)
void runBleProvisioning(String &outSsid, String &outPass);

#endif // WIFI_SERVICE_H
