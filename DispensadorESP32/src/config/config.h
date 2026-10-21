#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

// UUIDs para el servicio BLE de aprovisionamiento (RF-05, RF-06)
#define SERVICE_UUID               "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID_SSID   "beb5483e-36e1-4688-b7f5-ea07361b26a6"
#define CHARACTERISTIC_UUID_PASS   "1eb67500-8e45-4df9-bffd-a3e973e87c0e"

// Configuración de la API
const char* const BASE_URL = "http://10.22.168.8:8000/dispenserscheck-taks/";

// Configuración del Hardware (ServoMotor MG966R en Pin 4)
const int servoPin = 4;

// Temporizador no bloqueante
const unsigned long CHECK_INTERVAL = 20000; // 20 segundos

// Máquina de estados del ESP32 (RF-06, RF-07)
enum DeviceState {
  STATE_CHECK_NVS,
  STATE_CONNECT_WIFI,
  STATE_BLE_PROVISIONING,
  STATE_NORMAL
};

#endif // CONFIG_H
