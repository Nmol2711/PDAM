#ifndef DISPENSING_SERVICE_H
#define DISPENSING_SERVICE_H

#include "../config/dispensing_utils.h"

namespace dispensing {

// Ejecuta una dispensación por peso (Spec 013).
//
// Valida el factor de calibración y la cantidad antes de tocar el hardware,
// inicializa la celda una sola vez y delega el ciclo en runDispenseCycle:
// ventana fija de verificación de 2 s, avance con objetivo sostenido, retroceso
// y pausa de desatasco dentro del presupuesto de motor, y servo detenido en toda
// salida (objetivo, tiempo, atasco, fallo del sensor o aborto). Emite una única
// línea de registro en español con el resultado y reintentos=N.
//
// Requiere que initServo() se haya llamado durante el arranque.
DispenseResult dispenseWeight(float amountGrams);

} // namespace dispensing

#endif // DISPENSING_SERVICE_H
