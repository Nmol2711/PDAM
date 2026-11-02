#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

#include "dispensing_utils.h"

// Umbrales de detección y resolución de atascos (Spec 013, RNF-7). Se reexportan
// desde dispensing_utils.h y solo se ajustan allí, en un único lugar; este archivo
// no duplica valores:
//   - gracia tras cada arranque de avance: 2 000 ms (kStallGraceMs)
//   - ventana de estancamiento: 5 000 ms (kStallWindowMs)
//   - progreso mínimo: 2,0 g (kMinProgressGrams)
//   - tamaño de la mediana móvil: 5 lecturas válidas (kMovingMedianSize)
//   - mínimo de lecturas válidas desde el arranque: 5 (kMinAdvanceValidReadings)
//   - retroceso de desatasco: 1 200 ms (kReverseMs)
//   - pausa tras el retroceso: 300 ms (kPauseMs)
//   - máximo de reintentos: 3 (kMaxStallRetries)
//   - presupuesto de motor: 30 000 ms (kMotorBudgetMs)
//   - presupuesto mínimo de reintento: 3 500 ms (kMinRetryBudgetMs)

// Umbrales de la validación de línea base y de la plausibilidad (Spec 016):
// 15 lecturas de asentamiento, paso máximo de 1,0 g, factor 3,0 del tope,
// margen de 10,0 g, suelo de -10,0 g y 3 lecturas consecutivas de
// plausibilidad. Se definen y documentan en dispensing_utils.h; este archivo no
// duplica sus valores (RNF-3).

// UUIDs para el servicio BLE de aprovisionamiento (RF-05, RF-06)
#define SERVICE_UUID               "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID_SSID   "beb5483e-36e1-4688-b7f5-ea07361b26a6"
#define CHARACTERISTIC_UUID_PASS   "1eb67500-8e45-4df9-bffd-a3e973e87c0e"

// Configuración de la API
// Consulta de orden pendiente. La ruta real del servidor se compone con el
// prefijo del router y su ruta sin barra inicial (`/dispensers` +
// `check-taks/{mac}`), de ahí el typo `dispenserscheck-taks` y la falta de barra
// entre `dispensers` y `check`: firmware y datasource de la app usan esa misma
// URL y el contrato del servidor no se cambia.
const char* const BASE_URL = "http://192.168.1.58:8000/dispenserscheck-taks/";

// Reporte de fin de ciclo (`POST /dispensers/reports`, §5.2 del plan 014).
// Mismo host que la consulta, con la ruta del contrato.
const char* const REPORTS_URL = "http://192.168.1.58:8000/dispensers/reports";

// Configuración del Hardware (ServoMotor MG966R en Pin 4)
const int servoPin = 4;

// Celda de carga de 5 kg con amplificador HX711 (D18 y D19)
const int hx711SckPin = 18;
const int hx711DtPin = 19;

// Calibración medida con un peso patrón de ~206.8 g: con la bandeja vacía el
// RAW es 160658 y con el peso es 260500, es decir, unas 482.7 cuentas ADC por
// gramo. El signo es +1.0f porque el RAW aumenta al añadir peso. Si se cambia
// la celda o el montaje, recalcular el factor con un peso conocido.
const float hx711CalibrationFactor = 482.7f;
const float hx711RawSign = 1.0f;

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
