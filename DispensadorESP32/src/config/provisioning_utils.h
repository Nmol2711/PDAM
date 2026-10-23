#ifndef PROVISIONING_UTILS_H
#define PROVISIONING_UTILS_H

#include <cstddef>
#include <cstdio>

// Utilidades puras del aprovisionamiento WiFi/BLE.
// No dependen de Arduino para poder probarse en el entorno nativo de PlatformIO.

// Formatea una MAC de 6 bytes como "XX:XX:XX:XX:XX:XX" (17 caracteres + '\0').
inline void formatMacAddress(const unsigned char mac[6], char *output, size_t outputSize) {
  if (output == nullptr || outputSize == 0) {
    return;
  }
  if (mac == nullptr) {
    output[0] = '\0';
    return;
  }
  snprintf(output, outputSize, "%02X:%02X:%02X:%02X:%02X:%02X",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

// Construye el nombre publicitado por BLE: "PDAM-Config-<MAC sin separadores>".
inline void buildBleDeviceName(const unsigned char mac[6], char *output, size_t outputSize) {
  if (output == nullptr || outputSize == 0) {
    return;
  }
  if (mac == nullptr) {
    output[0] = '\0';
    return;
  }
  snprintf(output, outputSize, "PDAM-Config-%02X%02X%02X%02X%02X%02X",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

// Las credenciales solo se consideran completas cuando SSID y password existen.
inline bool areCredentialsComplete(const char *ssid, const char *password) {
  return ssid != nullptr && password != nullptr &&
         ssid[0] != '\0' && password[0] != '\0';
}

#endif // PROVISIONING_UTILS_H
