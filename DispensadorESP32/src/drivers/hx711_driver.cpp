#include "hx711_driver.h"

#include <HX711.h>

#include "../config/config.h"

// Instancia única de la celda de carga para todo el firmware.
static HX711 hx711;

void initHx711() {
  hx711.begin(hx711DtPin, hx711SckPin);

  // Si el módulo HX711 se desconecta del ESP32, el pin DT queda flotando; el
  // pull-up lo mantiene en HIGH (sin dato), de modo determinista, para que
  // is_ready() no dé una lectura falsa y se cumpla RF-4 (sensor no disponible
  // -> no dispensar). Con el HX711 conectado, su salida push-pull domina el
  // pull-up y no cambia el funcionamiento normal. Si solo se desconecta la
  // celda con el módulo alimentado, las lecturas pueden parecer válidas; el
  // firmware no puede garantizar RF-9 en ese modo.
  pinMode(hx711DtPin, INPUT_PULLUP);

  Serial.printf("HX711 inicializado: DT=%d, SCK=%d, factor=%.1f, signo=%+.1f.\n",
                hx711DtPin, hx711SckPin, hx711CalibrationFactor,
                hx711RawSign);
}

bool readHx711Raw(long *rawOut, unsigned long timeoutMs) {
  if (rawOut == nullptr) {
    return false;
  }

  const unsigned long start = millis();

  // is_ready() solo consulta DOUT; el sondeo no bloquea más allá del plazo.
  while (!hx711.is_ready()) {
    if (millis() - start >= timeoutMs) {
      return false;
    }
    delay(1);
  }

  // read() llama internamente a wait_ready() sin cota. El timeout anterior
  // cubre solo el sondeo previo, no esa llamada: deuda aceptada de prototipo.
  *rawOut = hx711.read();
  return true;
}
