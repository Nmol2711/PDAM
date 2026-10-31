#ifndef SCALE_GUARD_SERVICE_H
#define SCALE_GUARD_SERVICE_H

// Servicio adaptador del asentamiento de la celda (Spec 016, RF-1, RF-2, RF-8).
//
// Mantiene el único SettlementState del firmware y traduce las lecturas del
// HX711 a la lógica pura de config/scale_guard_utils.h: aquí no se decide nada,
// solo se muestrea y se registran las transiciones en español. Sin tarea
// FreeRTOS, sin memoria compartida y sin memoria dinámica: updateSettlement()
// se llama únicamente desde loop(), nunca desde el ciclo de motor.

namespace guard {

// Inicializa la celda una sola vez (ensureHx711Initialized) y, si el factor de
// calibración no es finito o no es positivo, imprime una única línea que nombra
// esa causa (caso (d) de la Spec 016). No decide nada.
void initScaleGuard();

// Toma como máximo una muestra por kSamplePeriodMs, con el sondeo acotado por
// kReadTimeoutMs, y delega la decisión en recordSettlementSample. Se llama una
// vez por iteración de loop().
void updateSettlement();

// Consulta del estado para la compuerta de entrada (RF-1).
bool settlementGained();

// Retira el asentamiento y registra el motivo si se pasa (RF-5, RF-8).
// Con `motivo` nulo no se imprime nada; el texto es solo diagnostico y la
// decision (que motivo invalida) vive en quien conoce el cierre del ciclo.
void invalidateSettlement(const char *motivo);

} // namespace guard

#endif // SCALE_GUARD_SERVICE_H
