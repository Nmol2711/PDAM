#ifndef DISPENSING_SERVICE_H
#define DISPENSING_SERVICE_H

#include "../config/dispensing_utils.h"

namespace dispensing {

// Ejecuta una dispensación por peso (Spec 013, T7).
//
// Valida el factor de calibración y la cantidad antes de tocar el hardware,
// abre la ventana fija de verificación de 2 s, fija la línea base, arranca el
// servo y lo detiene en toda salida (objetivo, tiempo, fallo del sensor o
// aborto). Emite una única línea de registro en español con el resultado.
//
// Requiere que initServo() se haya llamado durante el arranque; la celda HX711
// se inicializa internamente una sola vez, en la primera dispensación válida.
DispenseResult dispenseWeight(float amountGrams);

} // namespace dispensing

#endif // DISPENSING_SERVICE_H
