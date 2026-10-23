#ifndef API_SERVICE_H
#define API_SERVICE_H

#include <Arduino.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include "../config/config.h"

// Consulta el endpoint de la API para verificar si se debe dispensar alimento
void checkDispenserAction(const String &serverUrl);

#endif // API_SERVICE_H
