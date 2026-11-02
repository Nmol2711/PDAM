#ifndef HX711_DRIVER_H
#define HX711_DRIVER_H

#include <Arduino.h>

// Inicializa la celda de carga con los pines DT y SCK configurados una única
// vez por arranque (Spec 016). El indicador de inicialización vive en el
// driver, de modo que el muestreo del asentamiento y el ciclo de dispensado
// comparten la misma begin(); las llamadas siguientes no vuelven a configurar
// el HX711. No tara, no calibra y no convierte la lectura a gramos.
void ensureHx711Initialized();

// Espera hasta timeoutMs a que el HX711 tenga un dato disponible y realiza
// una única lectura en bruto. Devuelve false si no hubo dato antes del plazo
// o si rawOut es nullptr. El sondeo previo con is_ready() está acotado por
// timeoutMs. HX711::read() llama internamente a wait_ready() sin cota, por lo
// que ese tramo no está acotado: deuda aceptada de prototipo, documentada.
bool readHx711Raw(long *rawOut, unsigned long timeoutMs);

#endif // HX711_DRIVER_H
