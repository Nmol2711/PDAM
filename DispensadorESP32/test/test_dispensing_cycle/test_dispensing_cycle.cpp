#include <unity.h>

#include <cmath>
#include <cstring>

#include "config/dispensing_cycle.h"
#include "config/report_utils.h"

using namespace dispensing;

void setUp(void) {}

void tearDown(void) {}

namespace {

// --- Servo y celda simulados (RF-17, RNF-6) ---
// El ciclo se ejecuta con un reloj virtual: waitUntil adelanta el instante hasta
// el vencimiento pedido, de modo que 32 s de firmware se recorren en milisegundos
// de CPU.

// Factor y signo de prueba: 1 000 cuentas por gramo con polaridad directa, así
// que el raw de un peso en gramos es grams * 1000.
constexpr float kTestFactor = 1000.0f;
constexpr float kTestSign = 1.0f;

struct FakeReading {
  bool responded;
  long raw;
};

FakeReading validGrams(float grams) {
  FakeReading reading;
  reading.responded = true;
  reading.raw = static_cast<long>(grams * kTestFactor);
  return reading;
}

FakeReading noAnswer() {
  FakeReading reading;
  reading.responded = false;
  reading.raw = 0;
  return reading;
}

// Perfil de la celda simulado: valor en función del instante virtual.
using CellProfile = FakeReading (*)(unsigned long nowMs);

enum class ServoAction { ADVANCE, REVERSE, STOP };

constexpr unsigned kMaxServoEvents = 64;
constexpr unsigned kMaxReads = 320;

struct ServoEvent {
  ServoAction action;
  unsigned long atMs;
};

struct CycleHarness {
  CellProfile profile;
  unsigned long clockMs;
  ServoEvent servo[kMaxServoEvents];
  unsigned servoCount;
  unsigned advanceCount;
  unsigned reverseCount;
  unsigned stopCount;
  unsigned long readTimesMs[kMaxReads];
  unsigned readCount;
};

void harnessStartAdvance(void *context) {
  CycleHarness *harness = static_cast<CycleHarness *>(context);
  ++harness->advanceCount;
  if (harness->servoCount < kMaxServoEvents) {
    harness->servo[harness->servoCount].action = ServoAction::ADVANCE;
    harness->servo[harness->servoCount].atMs = harness->clockMs;
    ++harness->servoCount;
  }
}

void harnessStartReverse(void *context) {
  // Equivale a reverseServo() del servo_driver; el servicio lo conecta en T13.
  CycleHarness *harness = static_cast<CycleHarness *>(context);
  ++harness->reverseCount;
  if (harness->servoCount < kMaxServoEvents) {
    harness->servo[harness->servoCount].action = ServoAction::REVERSE;
    harness->servo[harness->servoCount].atMs = harness->clockMs;
    ++harness->servoCount;
  }
}

void harnessStop(void *context) {
  CycleHarness *harness = static_cast<CycleHarness *>(context);
  ++harness->stopCount;
  if (harness->servoCount < kMaxServoEvents) {
    harness->servo[harness->servoCount].action = ServoAction::STOP;
    harness->servo[harness->servoCount].atMs = harness->clockMs;
    ++harness->servoCount;
  }
}

bool harnessReadRaw(void *context, long *rawOut, unsigned long timeoutMs) {
  // La celda simulada responde de inmediato: no consume el plazo de 100 ms.
  (void)timeoutMs;
  CycleHarness *harness = static_cast<CycleHarness *>(context);
  if (harness->readCount < kMaxReads) {
    harness->readTimesMs[harness->readCount] = harness->clockMs;
    ++harness->readCount;
  }
  const FakeReading reading = harness->profile(harness->clockMs);
  if (rawOut != nullptr) {
    *rawOut = reading.raw;
  }
  return reading.responded;
}

unsigned long harnessNowMs(void *context) {
  return static_cast<CycleHarness *>(context)->clockMs;
}

void harnessWaitUntil(void *context, unsigned long deadlineMs) {
  CycleHarness *harness = static_cast<CycleHarness *>(context);
  // El reloj virtual de las pruebas no desborda: se adelanta al vencimiento.
  if (deadlineMs > harness->clockMs) {
    harness->clockMs = deadlineMs;
  }
}

// Ejecuta el ciclo con el servo y la celda simulados.
DispenseResult runHarness(CycleHarness *harness, float amountGrams,
                          CycleDiagnostics *diagnostics = nullptr,
                          float factor = kTestFactor,
                          const CycleLimits &limits = CycleLimits{}) {
  CyclePorts ports;
  ports.context = harness;
  ports.startAdvance = harnessStartAdvance;
  ports.startReverse = harnessStartReverse;
  ports.stop = harnessStop;
  ports.readRaw = harnessReadRaw;
  ports.nowMs = harnessNowMs;
  ports.waitUntil = harnessWaitUntil;
  return runDispenseCycle(ports, amountGrams, factor, kTestSign, diagnostics,
                          limits);
}

// Instante del primer retroceso registrado.
bool firstReverseMs(const CycleHarness &harness, unsigned long *reverseMs) {
  for (unsigned i = 0; i < harness.servoCount; ++i) {
    if (harness.servo[i].action == ServoAction::REVERSE) {
      *reverseMs = harness.servo[i].atMs;
      return true;
    }
  }
  return false;
}

// Secuencia temporal del primer reintento: retroceso, parada de la pausa y
// reanudación del avance (RF-15).
struct RetryTimeline {
  unsigned long reverseMs;
  unsigned long stopMs;
  unsigned long resumeMs;
};

// Instante del primer retroceso, de la parada que abre la pausa y del arranque
// de avance que la reanuda.
bool firstRetryTimeline(const CycleHarness &harness, RetryTimeline *timeline) {
  for (unsigned i = 0; i < harness.servoCount; ++i) {
    if (harness.servo[i].action != ServoAction::REVERSE) {
      continue;
    }
    timeline->reverseMs = harness.servo[i].atMs;
    for (unsigned j = i + 1; j < harness.servoCount; ++j) {
      if (harness.servo[j].action != ServoAction::STOP) {
        continue;
      }
      timeline->stopMs = harness.servo[j].atMs;
      for (unsigned k = j + 1; k < harness.servoCount; ++k) {
        if (harness.servo[k].action == ServoAction::ADVANCE) {
          timeline->resumeMs = harness.servo[k].atMs;
          return true;
        }
      }
      return false;
    }
    return false;
  }
  return false;
}

// Instante del n-ésimo retroceso registrado (1-based).
bool nthReverseMs(const CycleHarness &harness, unsigned nth,
                  unsigned long *reverseMs) {
  unsigned seen = 0;
  for (unsigned i = 0; i < harness.servoCount; ++i) {
    if (harness.servo[i].action != ServoAction::REVERSE) {
      continue;
    }
    ++seen;
    if (seen == nth) {
      *reverseMs = harness.servo[i].atMs;
      return true;
    }
  }
  return false;
}

// Instante de la última acción registrada por el servo.
unsigned long lastActionMs(const CycleHarness &harness) {
  return harness.servoCount == 0 ? 0
                                 : harness.servo[harness.servoCount - 1].atMs;
}

bool lastActionIsStop(const CycleHarness &harness) {
  if (harness.servoCount == 0) {
    return false;
  }
  return harness.servo[harness.servoCount - 1].action == ServoAction::STOP;
}

// Duración del ciclo de motor: del primer avance a la última acción registrada.
unsigned long motorDurationMs(const CycleHarness &harness) {
  unsigned long firstAdvanceMs = 0;
  bool found = false;
  for (unsigned i = 0; i < harness.servoCount; ++i) {
    if (harness.servo[i].action == ServoAction::ADVANCE) {
      firstAdvanceMs = harness.servo[i].atMs;
      found = true;
      break;
    }
  }
  if (!found || harness.servoCount == 0) {
    return 0;
  }
  const unsigned long lastMs = harness.servo[harness.servoCount - 1].atMs;
  return lastMs - firstAdvanceMs;
}

// Lecturas registradas dentro de [fromMs, toMs).
unsigned readsBetween(const CycleHarness &harness, unsigned long fromMs,
                      unsigned long toMs) {
  unsigned count = 0;
  for (unsigned i = 0; i < harness.readCount; ++i) {
    const unsigned long atMs = harness.readTimesMs[i];
    if (atMs >= fromMs && atMs < toMs) {
      ++count;
    }
  }
  return count;
}

// --- Perfiles de la celda ---

// El peso no progresa nunca: atasco o depósito vacío.
FakeReading profileStalled(unsigned long nowMs) {
  (void)nowMs;
  return validGrams(0.0f);
}

// La celda responde durante la verificación y hasta los 4 s; después deja de
// responder de forma sostenida.
FakeReading profileSensorFailure(unsigned long nowMs) {
  if (nowMs < 4000) {
    return validGrams(0.0f);
  }
  return noAnswer();
}

// Una lectura de cada dos no responde (nunca hay 3 inválidas consecutivas) y el
// peso sube 1 g por lectura válida.
FakeReading profileAlternatingInvalid(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(0.0f);
  }
  const unsigned long index =
      (nowMs - kVerificationWindowMs) / kSamplePeriodMs;
  if (index % 2 == 1) {
    return noAnswer();
  }
  return validGrams(static_cast<float>(index / 2));
}

// Flujo constante de 0,5 g/s, por encima del umbral de 0,4 g/s.
FakeReading profileFlow(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(0.0f);
  }
  const float seconds =
      static_cast<float>(nowMs - kVerificationWindowMs) / 1000.0f;
  return validGrams(0.5f * seconds);
}

// Atasco resuelto: el peso no progresa hasta la reanudación del primer reintento
// y desde ahí sube 2 g/s.
constexpr unsigned long kFirstResumeMs = kVerificationWindowMs + kStallGraceMs +
                                         kStallWindowMs + kReverseMs + kPauseMs;

FakeReading profileResolvedStall(unsigned long nowMs) {
  if (nowMs < kFirstResumeMs) {
    return validGrams(0.0f);
  }
  const float seconds =
      static_cast<float>(nowMs - kFirstResumeMs) / 1000.0f;
  return validGrams(2.0f * seconds);
}

// La mediana se queda 1 g por debajo del objetivo justo cuando vence la ventana
// de estancamiento: la misma muestra cumple el objetivo y declararía atasco.
constexpr unsigned long kStallExpiryMs =
    kVerificationWindowMs + kStallGraceMs + kStallWindowMs;

FakeReading profileTargetAndStall(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(0.0f);
  }
  if (nowMs < kStallExpiryMs - 2 * kSamplePeriodMs) {
    return validGrams(9.5f);
  }
  return validGrams(10.0f);
}

// El peso salta por encima del objetivo en pleno retroceso con un incremento
// plausible: 25 g con una orden de 10 g (tope 30 g). Antes saltaba a 50 g, que
// con la plausibilidad de la Spec 016 cerraría por tope; el perfil conserva así
// su propósito de la 013 (objetivo en retroceso) con resultado COMPLETED.
FakeReading profileTargetInReverse(unsigned long nowMs) {
  if (nowMs < kStallExpiryMs + kSamplePeriodMs) {
    return validGrams(0.0f);
  }
  return validGrams(25.0f);
}

// El peso salta por encima del objetivo ya en la pausa del reintento, también
// con un incremento plausible (25 g con orden de 10 g).
FakeReading profileTargetInPause(unsigned long nowMs) {
  if (nowMs < kStallExpiryMs + 5 * kSamplePeriodMs) {
    return validGrams(0.0f);
  }
  return validGrams(25.0f);
}

// La celda no responde nunca: la verificación no se supera.
FakeReading profileNoSensor(unsigned long nowMs) {
  (void)nowMs;
  return noAnswer();
}

// --- Perfiles de línea base (Spec 016, RF-2, RF-3, RF-4, RF-8) ---

// La última lectura de la ventana se separa 1,01 g de la anterior: la base se
// rechaza por inestable.
FakeReading profileUnstableBaseline(unsigned long nowMs) {
  if (nowMs == kVerificationWindowMs - kSamplePeriodMs) {
    return validGrams(1.01f);
  }
  return validGrams(0.0f);
}

// Paso de exactamente 1,0 g en la última lectura de la ventana: el límite se
// incluye y la base se acepta; después fluye 0,5 g/s desde 1 g.
FakeReading profileBaselineStepOneGram(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    const bool lastSample = nowMs == kVerificationWindowMs - kSamplePeriodMs;
    return validGrams(lastSample ? 1.0f : 0.0f);
  }
  const float seconds =
      static_cast<float>(nowMs - kVerificationWindowMs) / 1000.0f;
  return validGrams(1.0f + 0.5f * seconds);
}

// Cuatro lecturas válidas y seis inválidas sin llegar nunca a tres consecutivas:
// la ventana expira por tiempo con menos de cinco válidas.
FakeReading profileFourValidBaseline(unsigned long nowMs) {
  const unsigned index = nowMs / kSamplePeriodMs;
  if (index == 2 || index == 5 || index >= 8) {
    return validGrams(0.0f);
  }
  return noAnswer();
}

// Lecturas negativas que la 013 clasifica como inválidas: no entran en la
// mediana y dejan la ventana con cuatro válidas, también sin tres inválidas
// consecutivas.
FakeReading profileNegativeReadings(unsigned long nowMs) {
  const unsigned index = nowMs / kSamplePeriodMs;
  if (index == 2 || index == 5 || index >= 8) {
    return validGrams(0.0f);
  }
  return validGrams(-5.0f);
}

// Cinco válidas estables y después tres inválidas consecutivas: la ventana se
// aborta con cinco válidas ya guardadas (RF-4 de la 013, RF-8).
FakeReading profileAbortedBaseline(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs - 1000) {
    return validGrams(0.0f);
  }
  return noAnswer();
}

// Ocho válidas con paso de 1,0 g y dos inválidas al final: la mediana de todas
// las válidas es el promedio de las centrales, 3,5 g.
FakeReading profileEvenMedianBaseline(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    const unsigned index = nowMs / kSamplePeriodMs;
    if (index >= 8) {
      return noAnswer();
    }
    return validGrams(static_cast<float>(index));
  }
  const float seconds =
      static_cast<float>(nowMs - kVerificationWindowMs) / 1000.0f;
  return validGrams(7.0f + 0.5f * seconds);
}

// Nueve válidas: cuatro a 0,0 g, un pico de 4 g y una bajada de 1 g por lectura
// hasta 0,0 g, más una inválida al final. Las últimas cinco se separan 1,0 g
// exacto y la mediana de todas las válidas es 0,0 g (la de las últimas cinco
// sería 2,0 g).
FakeReading profileOddMedianBaseline(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    const unsigned index = nowMs / kSamplePeriodMs;
    if (index == 9) {
      return noAnswer();
    }
    if (index < 4) {
      return validGrams(0.0f);
    }
    return validGrams(8.0f - static_cast<float>(index));
  }
  const float seconds =
      static_cast<float>(nowMs - kVerificationWindowMs) / 1000.0f;
  return validGrams(0.5f * seconds);
}

// Flujo realista por encima de 0,4 g/s: 1 g/s con ruido alterno de 0,4 g.
// El umbral de 2 g cada 5 s no debe declarar ningún atasco.
FakeReading profileRealisticFlow(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(0.0f);
  }
  const unsigned long elapsedMs = nowMs - kVerificationWindowMs;
  const float seconds = static_cast<float>(elapsedMs) / 1000.0f;
  const unsigned long index = elapsedMs / kSamplePeriodMs;
  const float noise = (index % 2 == 0) ? 0.4f : -0.4f;
  return validGrams(seconds + noise);
}

// Carga transitoria durante el retroceso: sube 7,5 g/s hasta 9 g al final del
// giro inverso, la pausa la mantiene y desaparece al reanudar el avance, donde
// queda un flujo de 0,5 g/s desde 4 g.
FakeReading profileTransientInReverse(unsigned long nowMs) {
  if (nowMs < kStallExpiryMs) {
    return validGrams(0.0f);
  }
  if (nowMs < kStallExpiryMs + kReverseMs) {
    const float seconds =
        static_cast<float>(nowMs - kStallExpiryMs) / 1000.0f;
    return validGrams(7.5f * seconds);
  }
  if (nowMs < kFirstResumeMs) {
    return validGrams(9.0f);
  }
  const float seconds = static_cast<float>(nowMs - kFirstResumeMs) / 1000.0f;
  return validGrams(4.0f + 0.5f * seconds);
}

// La celda deja de responder a mitad del retroceso: la tercera inválida
// consecutiva se detecta todavía dentro del giro inverso (RF-9).
FakeReading profileSensorFailureInReverse(unsigned long nowMs) {
  if (nowMs < kStallExpiryMs + 100) {
    return validGrams(0.0f);
  }
  return noAnswer();
}

// La celda deja de responder justo antes de la pausa: la tercera inválida
// consecutiva se detecta ya en la pausa, antes de reanudar el avance (RF-9).
FakeReading profileSensorFailureInPause(unsigned long nowMs) {
  if (nowMs < kStallExpiryMs + 700) {
    return validGrams(0.0f);
  }
  return noAnswer();
}

// La celda deja de responder con la primera lectura de la pausa: solo caben dos
// inválidas dentro de los 0,3 s de pausa, así que el avance se reanuda y la
// tercera inválida consecutiva llega ya en el avance reanudado (RF-9).
FakeReading profileSensorFailureResumesAfterPause(unsigned long nowMs) {
  if (nowMs < kStallExpiryMs + kReverseMs) {
    return validGrams(0.0f);
  }
  return noAnswer();
}

// El peso sube despacio (0,5 g/s) durante el retroceso y la pausa del reintento,
// por debajo del umbral de progreso de 2 g, y desde la reanudación avanza 2 g/s
// hasta el objetivo.
constexpr unsigned long kRiseInRetryResumeMs =
    kStallExpiryMs + kReverseMs + kPauseMs;

FakeReading profileRiseDuringRetry(unsigned long nowMs) {
  if (nowMs < kStallExpiryMs) {
    return validGrams(0.0f);
  }
  if (nowMs < kRiseInRetryResumeMs) {
    const float seconds =
        static_cast<float>(nowMs - kStallExpiryMs) / 1000.0f;
    return validGrams(0.5f * seconds);
  }
  const float seconds =
      static_cast<float>(nowMs - kRiseInRetryResumeMs) / 1000.0f;
  return validGrams(0.75f + 2.0f * seconds);
}

// --- Perfiles de plausibilidad del incremento (Spec 016, RF-5, RF-6) ---
// La comprobación se hace en las tres fases. Con una orden de 20 g el tope es
// max(3 x 20, 20 + 10) = 60 g y el suelo -10 g respecto de la línea base.

// Tres lecturas consecutivas de 80 g con una orden de 20 g: el incremento
// imposible cierra el ciclo en el tercer muestreo del avance.
FakeReading profileAboveTopInAdvance(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(0.0f);
  }
  return validGrams(80.0f);
}

// Línea base de 12 g: el peso sube a 20 g (incremento plausible de 8 g) y cae a
// 0 g, doce gramos por debajo de la base y por tanto bajo el suelo de -10 g.
FakeReading profileBelowFloorInAdvance(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(12.0f);
  }
  const unsigned long index =
      (nowMs - kVerificationWindowMs) / kSamplePeriodMs;
  if (index < 3) {
    return validGrams(20.0f);
  }
  return validGrams(0.0f);
}

// Dos lecturas por encima del tope y una dentro del intervalo: el contador se
// reinicia y el ciclo completa la orden con un flujo de 2 g/s.
constexpr unsigned long kTwoOutsideResetMs =
    kVerificationWindowMs + 3 * kSamplePeriodMs;

FakeReading profileTwoAboveTopOneInside(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(0.0f);
  }
  const unsigned long index =
      (nowMs - kVerificationWindowMs) / kSamplePeriodMs;
  if (index < 2) {
    return validGrams(80.0f);
  }
  if (index == 2) {
    return validGrams(0.0f);
  }
  const float seconds =
      static_cast<float>(nowMs - kTwoOutsideResetMs) / 1000.0f;
  return validGrams(2.0f * seconds);
}

// Dos fuera, una inválida (que reinicia el contador porque RF-5 exige lecturas
// válidas consecutivas) y una más fuera: tampoco cierra. El flujo posterior es
// rápido (6 g/s) para llegar al objetivo antes del vencimiento de la ventana de
// estancamiento, que la mediana móvil abrió con el pico de 80 g.
constexpr unsigned long kTwoOutsideInvalidFlowMs =
    kVerificationWindowMs + 4 * kSamplePeriodMs;

FakeReading profileTwoAboveTopOneInvalid(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(0.0f);
  }
  const unsigned long index =
      (nowMs - kVerificationWindowMs) / kSamplePeriodMs;
  if (index < 2) {
    return validGrams(80.0f);
  }
  if (index == 2) {
    return noAnswer();
  }
  if (index == 3) {
    return validGrams(80.0f);
  }
  const float seconds =
      static_cast<float>(nowMs - kTwoOutsideInvalidFlowMs) / 1000.0f;
  return validGrams(6.0f * seconds);
}

// Una lectura que alcanza el objetivo y supera el tope a la vez: con orden de
// 10 g el tope es 30 g y el objetivo 10 g, así que 31 g cumple ambos. Prevalece
// el tope y no se declara objetivo alcanzado.
FakeReading profileTargetAndTop(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(0.0f);
  }
  return validGrams(31.0f);
}

// Con la línea base en 12 g el peso no progresa: el atasco se declara a los 7 s
// de motor (gracia más ventana), ya con la base aceptada.
constexpr unsigned long kBaselineStallExpiryMs =
    kVerificationWindowMs + kStallGraceMs + kStallWindowMs;

// La tercera lectura bajo el suelo coincide con el vencimiento de la ventana de
// estancamiento: la 013 declararía ahí el atasco y retrocedería; RF-6 exige que
// el cierre por suelo gane y que no haya retroceso.
constexpr unsigned long kFloorAtStallExpiryMs =
    kBaselineStallExpiryMs - 2 * kSamplePeriodMs;

FakeReading profileFloorAtStallExpiry(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(12.0f);
  }
  if (nowMs < kFloorAtStallExpiryMs) {
    return validGrams(12.0f);
  }
  return validGrams(0.0f);
}

// El salto imposible llega en pleno retroceso: 50 g con una orden de 10 g
// (tope 30 g), tres lecturas antes de que termine el giro inverso.
FakeReading profileAboveTopInReverse(unsigned long nowMs) {
  if (nowMs < kStallExpiryMs + kSamplePeriodMs) {
    return validGrams(0.0f);
  }
  return validGrams(50.0f);
}

// El salto imposible llega ya en la pausa del reintento: cierra por tope antes
// de reanudar el avance.
FakeReading profileAboveTopInPause(unsigned long nowMs) {
  if (nowMs < kStallExpiryMs + 5 * kSamplePeriodMs) {
    return validGrams(0.0f);
  }
  return validGrams(50.0f);
}

// La pérdida de masa llega durante el retroceso abierto por el atasco.
constexpr unsigned long kFloorReverseDropMs =
    kBaselineStallExpiryMs + 2 * kSamplePeriodMs;

FakeReading profileBelowFloorInReverse(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(12.0f);
  }
  if (nowMs < kFloorReverseDropMs) {
    return validGrams(12.0f);
  }
  return validGrams(0.0f);
}

// La pérdida de masa llega con la pausa del reintento: la tercera lectura cae
// dentro de los 0,3 s de pausa, antes de la reanudación prevista.
constexpr unsigned long kFloorPauseDropMs = kBaselineStallExpiryMs + 1000;

FakeReading profileBelowFloorInPause(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(12.0f);
  }
  if (nowMs < kFloorPauseDropMs) {
    return validGrams(12.0f);
  }
  return validGrams(0.0f);
}

// Flujo constante de 0,5 g/s desde una línea base de 12 g: el incremento se mide
// respecto de la base, es plausible y el ciclo termina en objetivo alcanzado.
FakeReading profileFlowFromBaseline(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(12.0f);
  }
  const float seconds =
      static_cast<float>(nowMs - kVerificationWindowMs) / 1000.0f;
  return validGrams(12.0f + 0.5f * seconds);
}

// Bajada pequeña dentro del suelo: con línea base de 12 g el peso queda en 9 g,
// un incremento de -3 g que no es implausible y debe comportarse como la 013.
FakeReading profileSmallDropStalled(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(12.0f);
  }
  return validGrams(9.0f);
}

// Línea base de 12 g y lecturas de 0 g desde el primer muestreo del motor: todos
// los incrementos del ciclo son negativos (-12 g), así que el mayor observado es
// el primero de ellos y no el cero de partida (RF-5, RF-6).
FakeReading profileAllIncrementsNegative(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(12.0f);
  }
  return validGrams(0.0f);
}

// --- Caso feliz completo (Spec 016) ---

// Línea base estable de 0 g y flujo de 1 g/s desde el arranque del motor: una
// orden de 20 g se alcanza a los 20 s, dentro del presupuesto de 30 s, con un
// incremento máximo de 20,4 g muy por debajo del tope de 60 g. El plan citaba
// 50 g con 1 g/s, que exigirían 50 s de motor y superarían el presupuesto de la
// 013; se usa la cantidad mayor que cabe con ese flujo.
FakeReading profileHappyPath(unsigned long nowMs) {
  if (nowMs < kVerificationWindowMs) {
    return validGrams(0.0f);
  }
  const float seconds =
      static_cast<float>(nowMs - kVerificationWindowMs) / 1000.0f;
  return validGrams(1.0f * seconds);
}

} // namespace

// --- Perfil de estancamiento: retroceso, pausa y reanudación (RF-14, RF-15) ---

void test_stall_profile_reverses_with_fixed_sequence(void) {
  CycleHarness harness{};
  harness.profile = profileStalled;

  const DispenseResult result = runHarness(&harness, 50.0f);

  TEST_ASSERT_GREATER_THAN_UINT(0, harness.reverseCount);

  RetryTimeline timeline{};
  TEST_ASSERT_TRUE(firstRetryTimeline(harness, &timeline));
  // El retroceso dura exactamente 1,2 s: la parada que abre la pausa llega ahí.
  TEST_ASSERT_EQUAL_UINT32(static_cast<unsigned long>(kReverseMs),
                           timeline.stopMs - timeline.reverseMs);
  // La pausa dura exactamente 0,3 s antes de reanudar el avance.
  TEST_ASSERT_EQUAL_UINT32(static_cast<unsigned long>(kPauseMs),
                           timeline.resumeMs - timeline.stopMs);
  // La secuencia completa retroceso más pausa suma 1,5 s.
  TEST_ASSERT_EQUAL_UINT32(static_cast<unsigned long>(kReverseMs + kPauseMs),
                           timeline.resumeMs - timeline.reverseMs);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::STALL_UNRESOLVED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(kMaxStallRetries),
                         result.retryCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

// --- Límites inyectados: las ramas de «no retroceder» (RF-16) ---
// Con los umbrales aprobados solo se llega a GIVE_UP tras 30 s de ciclo; el
// punto de inyección de CycleLimits permite ejercitar la rama con presupuesto y
// reintentos reducidos sin cambiar el comportamiento de producción.

// CycleLimits es el punto de inyección exclusivo de las pruebas: sus valores por
// defecto deben ser exactamente las constantes aprobadas, de modo que el valor
// de producción no pueda separarse de ellas (RNF-7). El servicio llama al ciclo
// sin este parámetro, así que estos dos valores son los que usa el firmware.
void test_cycle_limits_default_to_approved_constants(void) {
  const CycleLimits limits{};

  TEST_ASSERT_EQUAL_UINT32(static_cast<unsigned long>(kMotorBudgetMs),
                           limits.motorBudgetMs);
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(kMaxStallRetries),
                         limits.maxRetries);
}

void test_stall_without_retries_gives_up_without_reverse(void) {
  CycleHarness harness{};
  harness.profile = profileStalled;

  CycleLimits limits;
  limits.maxRetries = 0;

  const DispenseResult result =
      runHarness(&harness, 50.0f, nullptr, kTestFactor, limits);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::STALL_UNRESOLVED),
                        static_cast<int>(result.reason));
  // Se declara el primer atasco (gracia más ventana) y ahí termina el ciclo: sin
  // reintentos disponibles no hay retroceso ni reanudación.
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_EQUAL_UINT32(static_cast<unsigned long>(kStallExpiryMs),
                           lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

void test_stall_with_insufficient_retry_budget_gives_up_without_reverse(void) {
  CycleHarness harness{};
  harness.profile = profileStalled;

  // El atasco se declara 7 000 ms después del arranque del motor (gracia más
  // ventana); con 10 000 ms de presupuesto quedan 3 000 ms, menos que el mínimo
  // exigido para iniciar un reintento.
  CycleLimits limits;
  limits.motorBudgetMs = 10000;
  const unsigned long remainingAtStallMs =
      limits.motorBudgetMs - (kStallExpiryMs - kVerificationWindowMs);
  TEST_ASSERT_LESS_THAN_UINT32(static_cast<unsigned long>(kMinRetryBudgetMs),
                               remainingAtStallMs);

  const DispenseResult result =
      runHarness(&harness, 50.0f, nullptr, kTestFactor, limits);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::STALL_UNRESOLVED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_EQUAL_UINT32(static_cast<unsigned long>(kStallExpiryMs),
                           lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

// Presupuesto inyectado sin atasco: el ciclo termina por agotamiento del
// presupuesto del ciclo y no por la constante de producción (RF-8). El perfil
// alterna una lectura válida de cada dos con un objetivo inalcanzable, así que
// nunca declara atasco y el único desenlace posible es «objetivo no alcanzado».
void test_injected_budget_exhausts_cycle_without_stall(void) {
  CycleHarness harness{};
  harness.profile = profileAlternatingInvalid;

  CycleLimits limits;
  limits.motorBudgetMs = 10000;

  const DispenseResult result =
      runHarness(&harness, 200.0f, nullptr, kTestFactor, limits);

  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::NOT_REACHED),
                        static_cast<int>(result.reason));
  // El motor se detiene exactamente al agotarse el presupuesto inyectado.
  TEST_ASSERT_EQUAL_UINT32(static_cast<unsigned long>(limits.motorBudgetMs),
                           motorDurationMs(harness));
  // Y la parada final llega después de los 2 s de verificación.
  TEST_ASSERT_EQUAL_UINT32(
      static_cast<unsigned long>(kVerificationWindowMs + limits.motorBudgetMs),
      lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

// --- El máximo observado incluye retroceso y pausa (RF-14) ---

void test_reverse_and_pause_readings_raise_observed_max(void) {
  CycleHarness harness{};
  harness.profile = profileTransientInReverse;

  const DispenseResult result = runHarness(&harness, 50.0f);

  // La definición de «máximo observado» incluye la mediana del retroceso y de
  // la pausa: la carga transitoria de 9 g eleva la referencia del avance
  // reanudado a 7,5 g, de modo que el peso ya pesado no se vuelve a contar como
  // progreso nuevo. Sin esas lecturas la referencia sería la del propio avance
  // reanudado, el progreso llegaría a 2 g antes de vencer la ventana y no habría
  // segundo atasco.
  TEST_ASSERT_EQUAL_UINT(2, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(2, result.retryCount);

  // El segundo atasco se declara al vencer la ventana abierta tras la gracia.
  unsigned long secondReverseMs = 0;
  TEST_ASSERT_TRUE(nthReverseMs(harness, 2, &secondReverseMs));
  TEST_ASSERT_EQUAL_UINT32(
      static_cast<unsigned long>(kFirstResumeMs + kStallGraceMs + kStallWindowMs),
      secondReverseMs);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

// --- Las lecturas de retroceso y pausa no declaran atasco (RF-14) ---

void test_readings_during_reverse_and_pause_never_declare_stall(void) {
  CycleHarness harness{};
  harness.profile = profileRiseDuringRetry;

  const DispenseResult result = runHarness(&harness, 10.0f);

  // El peso sube despacio en el retroceso y la pausa (por debajo del umbral de
  // 2 g): si el atasco se evaluara ahí, la ventana vencida del primer atasco
  // volvería a declararlo. Solo el avance lo evalúa, así que hay un único
  // retroceso y el objetivo se alcanza tras el reintento.
  unsigned long reverseMs = 0;
  TEST_ASSERT_TRUE(firstReverseMs(harness, &reverseMs));
  TEST_ASSERT_GREATER_THAN_UINT(
      0, readsBetween(harness, reverseMs, reverseMs + kReverseMs));
  TEST_ASSERT_GREATER_THAN_UINT(
      0, readsBetween(harness, reverseMs + kReverseMs,
                      reverseMs + kReverseMs + kPauseMs));

  TEST_ASSERT_EQUAL_UINT(1, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(1, result.retryCount);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

// --- Fallo del sensor: sin retroceso ni reanudación (RF-9, RF-17) ---

void test_three_consecutive_invalid_readings_fail_without_reverse(void) {
  CycleHarness harness{};
  harness.profile = profileSensorFailure;

  const DispenseResult result = runHarness(&harness, 50.0f);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_FAILURE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

// --- Orden inválida: ni avance ni retroceso (RF-2, RF-11, RF-17) ---

void test_invalid_order_does_not_touch_ports(void) {
  const float invalidAmounts[] = {0.0f, -5.0f, NAN};
  for (unsigned i = 0; i < 3; ++i) {
    CycleHarness harness{};
    harness.profile = profileFlow;

    const DispenseResult result = runHarness(&harness, invalidAmounts[i]);

    TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::INVALID_AMOUNT),
                          static_cast<int>(result.reason));
    TEST_ASSERT_EQUAL_UINT(0, harness.advanceCount);
    TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
    TEST_ASSERT_EQUAL_UINT(0, harness.stopCount);
    TEST_ASSERT_EQUAL_UINT(0, harness.readCount);
  }

  // Factor no positivo: error de configuración sin tocar los puertos.
  CycleHarness harness{};
  harness.profile = profileFlow;
  const DispenseResult result = runHarness(&harness, 50.0f, nullptr, 0.0f);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::INVALID_CONFIG),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(0, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.readCount);
}

// --- Lecturas inválidas alternas: nunca se interpretan como atasco (RF-17) ---

void test_alternating_invalid_readings_never_reverse(void) {
  CycleHarness harness{};
  harness.profile = profileAlternatingInvalid;

  const DispenseResult result = runHarness(&harness, 200.0f);

  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::NOT_REACHED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

// --- Flujo por encima de 0,4 g/s: objetivo alcanzado sin reintentos (RF-7) ---

void test_flow_profile_reaches_target_without_retries(void) {
  CycleHarness harness{};
  harness.profile = profileFlow;

  const DispenseResult result = runHarness(&harness, 5.0f);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_TRUE(result.incrementAvailable);
  TEST_ASSERT_TRUE(result.incrementGrams >= 5.0f);
}

// --- Flujo realista con ruido: ningún falso atasco (RF-7, RF-14) ---

void test_realistic_flow_with_noise_reaches_target_without_retries(void) {
  CycleHarness harness{};
  harness.profile = profileRealisticFlow;

  const DispenseResult result = runHarness(&harness, 20.0f);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_TRUE(result.incrementAvailable);
  TEST_ASSERT_TRUE(result.incrementGrams >= 20.0f);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

// --- Atasco resuelto: el reintento no impide alcanzar el objetivo (RF-15) ---

void test_resolved_stall_reaches_target_with_one_retry(void) {
  CycleHarness harness{};
  harness.profile = profileResolvedStall;

  const DispenseResult result = runHarness(&harness, 5.0f);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(1, result.retryCount);
  TEST_ASSERT_EQUAL_UINT(1, harness.reverseCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

// --- El objetivo tiene prioridad sobre el atasco en la misma muestra (RF-7) ---

void test_target_has_priority_over_stall_on_same_sample(void) {
  // Con objetivo de 10 g la tercera lectura consecutiva llega justo al vencer la
  // ventana de estancamiento: prevalece el objetivo y no hay retroceso.
  CycleHarness targetHarness{};
  targetHarness.profile = profileTargetAndStall;
  const DispenseResult targetResult = runHarness(&targetHarness, 10.0f);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(targetResult.reason));
  TEST_ASSERT_EQUAL_UINT(0, targetHarness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(0, targetResult.retryCount);

  // El mismo perfil con un objetivo inalcanzable declara atasco en esa misma
  // muestra, lo que demuestra que el objetivo se comprobó antes.
  CycleHarness stallHarness{};
  stallHarness.profile = profileTargetAndStall;
  const DispenseResult stallResult = runHarness(&stallHarness, 10.5f);

  TEST_ASSERT_GREATER_THAN_UINT(0, stallHarness.reverseCount);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::STALL_UNRESOLVED),
                        static_cast<int>(stallResult.reason));
}

// --- El objetivo se comprueba también en retroceso y pausa (RF-7) ---

void test_target_reached_during_reverse_stops_the_cycle(void) {
  CycleHarness harness{};
  harness.profile = profileTargetInReverse;

  const DispenseResult result = runHarness(&harness, 10.0f);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(1, harness.reverseCount);
  // El retroceso no llegó a completarse: no cuenta como reintento (RF-12).
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);

  unsigned long reverseMs = 0;
  TEST_ASSERT_TRUE(firstReverseMs(harness, &reverseMs));
  // La parada ocurre dentro del retroceso, antes de la pausa.
  TEST_ASSERT_TRUE(harness.servo[harness.servoCount - 1].atMs <
                   reverseMs + kReverseMs);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

void test_target_reached_during_pause_stops_the_cycle(void) {
  CycleHarness harness{};
  harness.profile = profileTargetInPause;

  const DispenseResult result = runHarness(&harness, 10.0f);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(1, harness.reverseCount);
  // El avance no se reanudó: el reintento no se cuenta (RF-12).
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

// --- Fallo del sensor durante el retroceso o la pausa (RF-9, RF-12) ---

void test_sensor_failure_during_reverse_stops_without_resume(void) {
  CycleHarness harness{};
  harness.profile = profileSensorFailureInReverse;

  const DispenseResult result = runHarness(&harness, 50.0f);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_FAILURE),
                        static_cast<int>(result.reason));
  // No hay retroceso adicional ni reanudación, y el reintento no se cuenta.
  TEST_ASSERT_EQUAL_UINT(1, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));

  unsigned long reverseMs = 0;
  TEST_ASSERT_TRUE(firstReverseMs(harness, &reverseMs));
  // La parada llega con la tercera inválida consecutiva, dentro del retroceso.
  TEST_ASSERT_EQUAL_UINT32(
      static_cast<unsigned long>(reverseMs + 3 * kSamplePeriodMs),
      lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionMs(harness) < reverseMs + kReverseMs);
}

void test_sensor_failure_detected_during_pause_stops_without_resume(void) {
  CycleHarness harness{};
  harness.profile = profileSensorFailureInPause;

  const DispenseResult result = runHarness(&harness, 50.0f);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_FAILURE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(1, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));

  unsigned long reverseMs = 0;
  TEST_ASSERT_TRUE(firstReverseMs(harness, &reverseMs));
  // La tercera inválida consecutiva llega con la primera lectura de la pausa,
  // antes de la reanudación prevista para el final de los 0,3 s.
  TEST_ASSERT_EQUAL_UINT32(static_cast<unsigned long>(reverseMs + kReverseMs),
                           lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionMs(harness) <
                   reverseMs + kReverseMs + kPauseMs);
}

void test_sensor_failure_started_in_pause_resumes_and_stops_without_reverse(void) {
  CycleHarness harness{};
  harness.profile = profileSensorFailureResumesAfterPause;

  const DispenseResult result = runHarness(&harness, 50.0f);

  // El fallo empieza en la pausa, pero las dos inválidas que caben en ella no
  // completan las 3 consecutivas: el avance se reanuda y el fallo se detecta en
  // el avance, sin retroceso adicional (RF-9).
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_FAILURE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(1, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(2, harness.advanceCount);
  // El reintento se cuenta al reanudar el avance (RF-12, decisión 21).
  TEST_ASSERT_EQUAL_UINT(1, result.retryCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));

  RetryTimeline timeline{};
  TEST_ASSERT_TRUE(firstRetryTimeline(harness, &timeline));
  // Solo dos lecturas caen dentro de la pausa: la tercera inválida ya es la
  // primera lectura del avance reanudado, y ahí se detiene el servo.
  TEST_ASSERT_EQUAL_UINT(2, readsBetween(harness, timeline.stopMs,
                                         timeline.resumeMs));
  TEST_ASSERT_EQUAL_UINT32(static_cast<unsigned long>(timeline.resumeMs),
                           lastActionMs(harness));
}

// --- Cota del ciclo de motor y parada final (RF-8, RNF-3) ---

namespace {

// Cada perfil con su cantidad: la cota de 30 s y la parada final valen para
// todos los desenlaces posibles del ciclo.
struct BudgetCase {
  CellProfile profile;
  float amount;
};

} // namespace

void test_motor_cycle_never_exceeds_budget_and_ends_stopped(void) {
  const BudgetCase cases[] = {
      {profileStalled, 50.0f},
      {profileFlow, 5.0f},
      {profileResolvedStall, 5.0f},
      {profileAlternatingInvalid, 200.0f},
      {profileSensorFailure, 50.0f},
      {profileTargetAndStall, 10.5f},
      {profileTargetInReverse, 10.0f},
      {profileTargetInPause, 10.0f},
      {profileRealisticFlow, 20.0f},
      {profileTransientInReverse, 50.0f},
      {profileSensorFailureInReverse, 50.0f},
      {profileSensorFailureInPause, 50.0f},
      {profileAboveTopInAdvance, 20.0f},
      {profileBelowFloorInAdvance, 20.0f},
      {profileTwoAboveTopOneInside, 20.0f},
      {profileTwoAboveTopOneInvalid, 20.0f},
      {profileTargetAndTop, 10.0f},
      {profileFloorAtStallExpiry, 20.0f},
      {profileAboveTopInReverse, 10.0f},
      {profileAboveTopInPause, 10.0f},
      {profileBelowFloorInReverse, 20.0f},
      {profileBelowFloorInPause, 20.0f},
      {profileFlowFromBaseline, 5.0f},
      {profileSmallDropStalled, 20.0f},
      {profileAllIncrementsNegative, 20.0f},
      {profileHappyPath, 20.0f},
  };

  for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
    CycleHarness harness{};
    harness.profile = cases[i].profile;

    runHarness(&harness, cases[i].amount);

    TEST_ASSERT_GREATER_THAN_UINT(0, harness.advanceCount);
    TEST_ASSERT_TRUE(lastActionIsStop(harness));
    TEST_ASSERT_LESS_OR_EQUAL_UINT32(static_cast<unsigned long>(kMotorBudgetMs),
                                     motorDurationMs(harness));
    // Cota del ciclo completo (RNF-3): 2 s de verificación más el presupuesto de
    // motor, medidos desde el arranque del reloj del arnés. El instante de la
    // última acción registrada es la parada final, que nunca supera los 32 s.
    TEST_ASSERT_LESS_OR_EQUAL_UINT32(
        static_cast<unsigned long>(kVerificationWindowMs + kMotorBudgetMs),
        lastActionMs(harness));
  }
}

// --- Muestreo cada 200 ms en avance, retroceso y pausa (RNF-1) ---

void test_sampling_period_holds_in_all_phases(void) {
  CycleHarness harness{};
  harness.profile = profileStalled;

  runHarness(&harness, 50.0f);

  TEST_ASSERT_GREATER_THAN_UINT(1, harness.readCount);
  for (unsigned i = 1; i < harness.readCount; ++i) {
    const unsigned long delta =
        harness.readTimesMs[i] - harness.readTimesMs[i - 1];
    TEST_ASSERT_LESS_OR_EQUAL_UINT32(static_cast<unsigned long>(kSamplePeriodMs),
                                     delta);
  }

  // Hay lecturas dentro del retroceso y dentro de la pausa.
  RetryTimeline timeline{};
  TEST_ASSERT_TRUE(firstRetryTimeline(harness, &timeline));
  const unsigned long reverseMs = timeline.reverseMs;
  const unsigned long resumeMs = timeline.resumeMs;

  unsigned readsInReverse = 0;
  unsigned readsInPause = 0;
  for (unsigned i = 0; i < harness.readCount; ++i) {
    const unsigned long atMs = harness.readTimesMs[i];
    if (atMs >= reverseMs && atMs < reverseMs + kReverseMs) {
      ++readsInReverse;
    }
    if (atMs >= reverseMs + kReverseMs && atMs < resumeMs) {
      ++readsInPause;
    }
  }
  TEST_ASSERT_GREATER_THAN_UINT(0, readsInReverse);
  TEST_ASSERT_GREATER_THAN_UINT(0, readsInPause);
}

// --- Diagnóstico de la verificación fallida (RF-4, RF-12) ---

void test_verification_failure_fills_diagnostics(void) {
  CycleHarness harness{};
  harness.profile = profileNoSensor;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 50.0f, &diagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(0, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));

  // Tres lecturas sin respuesta cierran la ventana sin fijar línea base.
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(kMaxConsecutiveInvalidReadings),
                         diagnostics.samples);
  TEST_ASSERT_EQUAL_UINT(0, diagnostics.responded);
  TEST_ASSERT_EQUAL_UINT(0, diagnostics.valid);
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(kMaxConsecutiveInvalidReadings),
                         diagnostics.consecutiveInvalid);
  TEST_ASSERT_FALSE(diagnostics.hasLastReading);
  TEST_ASSERT_FALSE(result.baselineAvailable);
  TEST_ASSERT_FALSE(result.finalAvailable);
  TEST_ASSERT_FALSE(result.incrementAvailable);
}

// --- Línea base validada en el ciclo (Spec 016, RF-2, RF-3, RF-4, RF-8) ---
// La ventana de 2 s de la 013 solo abre el ciclo con una base aceptada: cinco
// válidas como mínimo y paso de 1 g como máximo entre las últimas cinco. Todo
// rechazo detiene el servo antes de que arranque y deja el motivo en el
// diagnóstico, que es lo único que lo distingue de un sensor desconectado.

void test_unstable_baseline_rejects_without_moving_servo(void) {
  CycleHarness harness{};
  harness.profile = profileUnstableBaseline;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineStatus::UNSTABLE),
                        static_cast<int>(diagnostics.baselineRejection));
  TEST_ASSERT_EQUAL_STRING("inestable",
                           baselineStatusText(diagnostics.baselineRejection));
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(10), diagnostics.valid);
  // La mediana de todas las válidas queda disponible para el log aunque el
  // veredicto la rechace.
  TEST_ASSERT_TRUE(diagnostics.hasBaseline);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, diagnostics.baselineGrams);
  // El servo no arranca: solo queda la parada del cierre (RF-3, RNF-2).
  TEST_ASSERT_EQUAL_UINT(0, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(1, harness.servoCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
  TEST_ASSERT_FALSE(result.baselineAvailable);
}

void test_four_valid_readings_reject_with_insufficient_readings(void) {
  CycleHarness harness{};
  harness.profile = profileFourValidBaseline;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineStatus::INSUFFICIENT_READINGS),
                        static_cast<int>(diagnostics.baselineRejection));
  TEST_ASSERT_EQUAL_STRING(
      "lecturas_insuficientes",
      baselineStatusText(diagnostics.baselineRejection));
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(4), diagnostics.valid);
  TEST_ASSERT_EQUAL_UINT(0, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(1, harness.servoCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
  TEST_ASSERT_FALSE(result.baselineAvailable);
}

void test_negative_readings_leave_insufficient_baseline(void) {
  CycleHarness harness{};
  harness.profile = profileNegativeReadings;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  // La celda responde en todas las muestras, pero las negativas son inválidas:
  // no entran en la mediana y dejan la ventana sin cinco válidas (RF-4).
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(10), diagnostics.samples);
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(10), diagnostics.responded);
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(4), diagnostics.valid);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineStatus::INSUFFICIENT_READINGS),
                        static_cast<int>(diagnostics.baselineRejection));
  TEST_ASSERT_EQUAL_UINT(0, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(1, harness.servoCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
  TEST_ASSERT_FALSE(result.baselineAvailable);
}

void test_aborted_window_by_invalid_readings_has_no_baseline_verdict(void) {
  CycleHarness harness{};
  harness.profile = profileAbortedBaseline;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  // Cierre de RF-4 de la 013: con cinco válidas previas la mediana existiría y
  // assessBaseline podría aceptar una base de una ventana abortada, así que el
  // aborto por inválidas se resuelve antes y sin veredicto de base.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineStatus::NOT_EVALUATED),
                        static_cast<int>(diagnostics.baselineRejection));
  TEST_ASSERT_EQUAL_STRING("sin_veredicto",
                           baselineStatusText(diagnostics.baselineRejection));
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(kMinValidReadings),
                         diagnostics.valid);
  TEST_ASSERT_EQUAL_UINT(
      static_cast<unsigned>(kMaxConsecutiveInvalidReadings),
      diagnostics.consecutiveInvalid);
  TEST_ASSERT_FALSE(diagnostics.hasBaseline);
  TEST_ASSERT_EQUAL_UINT(0, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(1, harness.servoCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
  TEST_ASSERT_FALSE(result.baselineAvailable);
}

void test_baseline_step_limit_is_one_gram_exactly(void) {
  // 1,0 g exacto entre las últimas cinco: el límite se incluye y el ciclo
  // progresa hasta el objetivo.
  CycleHarness acceptedHarness{};
  acceptedHarness.profile = profileBaselineStepOneGram;

  CycleDiagnostics acceptedDiagnostics{};
  const DispenseResult acceptedResult =
      runHarness(&acceptedHarness, 5.0f, &acceptedDiagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineStatus::ACCEPTED),
                        static_cast<int>(acceptedDiagnostics.baselineRejection));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(acceptedResult.reason));
  TEST_ASSERT_TRUE(acceptedResult.baselineAvailable);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, acceptedResult.baselineGrams);
  TEST_ASSERT_EQUAL_UINT(1, acceptedHarness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, acceptedResult.retryCount);

  // 1,01 g: inestable, sin arranque del servo.
  CycleHarness rejectedHarness{};
  rejectedHarness.profile = profileUnstableBaseline;

  CycleDiagnostics rejectedDiagnostics{};
  const DispenseResult rejectedResult =
      runHarness(&rejectedHarness, 5.0f, &rejectedDiagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineStatus::UNSTABLE),
                        static_cast<int>(rejectedDiagnostics.baselineRejection));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(rejectedResult.reason));
  TEST_ASSERT_EQUAL_UINT(0, rejectedHarness.advanceCount);
}

void test_baseline_median_uses_all_valid_readings_with_even_and_odd_counts(void) {
  // Número par: ocho válidas de 0 a 7 g; la mediana promedia las centrales y da
  // 3,5 g, no los 5,0 g de las últimas cinco.
  CycleHarness evenHarness{};
  evenHarness.profile = profileEvenMedianBaseline;

  CycleDiagnostics evenDiagnostics{};
  const DispenseResult evenResult =
      runHarness(&evenHarness, 5.0f, &evenDiagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineStatus::ACCEPTED),
                        static_cast<int>(evenDiagnostics.baselineRejection));
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(8), evenDiagnostics.valid);
  TEST_ASSERT_TRUE(evenResult.baselineAvailable);
  TEST_ASSERT_EQUAL_FLOAT(3.5f, evenResult.baselineGrams);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(evenResult.reason));

  // Número impar: nueve válidas con el pico fuera de las últimas cinco; la
  // mediana de todas es 0,0 g, no los 2,0 g de las últimas cinco.
  CycleHarness oddHarness{};
  oddHarness.profile = profileOddMedianBaseline;

  CycleDiagnostics oddDiagnostics{};
  const DispenseResult oddResult =
      runHarness(&oddHarness, 5.0f, &oddDiagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineStatus::ACCEPTED),
                        static_cast<int>(oddDiagnostics.baselineRejection));
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(9), oddDiagnostics.valid);
  TEST_ASSERT_TRUE(oddResult.baselineAvailable);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, oddResult.baselineGrams);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(oddResult.reason));
}

// --- Plausibilidad del incremento dentro del ciclo (Spec 016, RF-5, RF-6) ---
// La comprobación se hace en las tres fases del motor, antes del objetivo y del
// atasco. Tres lecturas válidas consecutivas fuera del intervalo [suelo, tope]
// cierran como sensor_no_disponible, sin retroceso, sin reanudación, sin
// reintento y sin declarar objetivo alcanzado.

void test_three_readings_above_top_close_without_reverse_or_resume(void) {
  CycleHarness harness{};
  harness.profile = profileAboveTopInAdvance;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::ABOVE_TOP),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_STRING("plausibilidad_tope",
                           plausibilityCauseText(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_FLOAT(60.0f, diagnostics.topGrams);
  TEST_ASSERT_EQUAL_FLOAT(80.0f, diagnostics.maxIncrementGrams);
  // Tercera lectura del avance: ni retroceso ni reanudación ni reintento.
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_EQUAL_UINT32(
      static_cast<unsigned long>(kVerificationWindowMs + 2 * kSamplePeriodMs),
      lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
  // El peso final se conserva para el log serie; el reporte lo omitirá porque el
  // motivo es sensor_no_disponible (RF-7).
  TEST_ASSERT_TRUE(result.baselineAvailable);
  TEST_ASSERT_TRUE(result.finalAvailable);
  TEST_ASSERT_EQUAL_FLOAT(80.0f, result.finalGrams);
  TEST_ASSERT_TRUE(result.incrementAvailable);
  TEST_ASSERT_EQUAL_FLOAT(80.0f, result.incrementGrams);
}

void test_three_readings_below_floor_close_without_reverse(void) {
  CycleHarness harness{};
  harness.profile = profileBelowFloorInAdvance;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::BELOW_FLOOR),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_STRING("plausibilidad_suelo",
                           plausibilityCauseText(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_FLOAT(60.0f, diagnostics.topGrams);
  // El mayor incremento del ciclo fue el de la subida plausible previa (8 g
  // sobre una base de 12 g); la lectura que cierra cae 12 g por debajo.
  TEST_ASSERT_EQUAL_FLOAT(8.0f, diagnostics.maxIncrementGrams);
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_EQUAL_UINT32(
      static_cast<unsigned long>(kVerificationWindowMs + 5 * kSamplePeriodMs),
      lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
  TEST_ASSERT_TRUE(result.baselineAvailable);
  TEST_ASSERT_EQUAL_FLOAT(12.0f, result.baselineGrams);
  TEST_ASSERT_TRUE(result.incrementAvailable);
  TEST_ASSERT_EQUAL_FLOAT(-12.0f, result.incrementGrams);
}

// Ciclo íntegramente negativo: la bandeja se retira desde la primera muestra del
// motor. El mayor incremento observado es el primero (el menos negativo), no el
// cero con el que arrancaría un máximo sin lectura previa.
void test_all_negative_increments_report_the_least_negative_max(void) {
  CycleHarness harness{};
  harness.profile = profileAllIncrementsNegative;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::BELOW_FLOOR),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_STRING("plausibilidad_suelo",
                           plausibilityCauseText(diagnostics.plausibility));
  // Todos los incrementos son de -12 g: el máximo observado es ese valor y no
  // 0 g, que es solo el valor de partida del seguimiento (solo log).
  TEST_ASSERT_EQUAL_FLOAT(-12.0f, diagnostics.maxIncrementGrams);
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_EQUAL_UINT32(
      static_cast<unsigned long>(kVerificationWindowMs + 2 * kSamplePeriodMs),
      lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
  TEST_ASSERT_TRUE(result.baselineAvailable);
  TEST_ASSERT_TRUE(result.incrementAvailable);
  TEST_ASSERT_EQUAL_FLOAT(-12.0f, result.incrementGrams);
}

void test_two_outside_one_inside_does_not_close_the_cycle(void) {
  CycleHarness harness{};
  harness.profile = profileTwoAboveTopOneInside;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  // La lectura dentro del intervalo reinicia el contador: el ciclo sigue y
  // alcanza el objetivo.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_TRUE(result.incrementAvailable);
  TEST_ASSERT_TRUE(result.incrementGrams >= 20.0f);
}

void test_two_outside_one_invalid_then_outside_does_not_close(void) {
  CycleHarness harness{};
  harness.profile = profileTwoAboveTopOneInvalid;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  // RF-5 exige tres lecturas VÁLIDAS consecutivas: la inválida reinicia el
  // contador aunque no se cuente como lectura fuera de límites.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_TRUE(result.incrementAvailable);
  TEST_ASSERT_TRUE(result.incrementGrams >= 20.0f);
}

void test_top_prevails_over_target_on_same_sample(void) {
  CycleHarness harness{};
  harness.profile = profileTargetAndTop;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 10.0f, &diagnostics);

  // 31 g con orden de 10 g alcanza el objetivo y supera el tope de 30 g en la
  // misma lectura: prevalece el tope y no se declara objetivo alcanzado.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::ABOVE_TOP),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_FLOAT(30.0f, diagnostics.topGrams);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT32(
      static_cast<unsigned long>(kVerificationWindowMs + 2 * kSamplePeriodMs),
      lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

// --- Prioridad de la plausibilidad sobre el objetivo y el atasco (RF-6) ---

// El tope solo puede prevalecer sobre el atasco en una muestra en la que la 013
// lo declararía, y eso es inalcanzable: cualquier incremento mayor que el tope
// (>= cantidad + 10 g) supera también el objetivo, que la 013 comprueba antes del
// atasco, y con tres lecturas por encima del tope la mediana móvil supera el
// progreso mínimo y reinicia la ventana de estancamiento. La prioridad sobre el
// atasco queda fijada con el caso del suelo, que sí puede coincidir con el
// vencimiento de la ventana.
void test_floor_prevails_over_stall_on_same_sample(void) {
  CycleHarness harness{};
  harness.profile = profileFloorAtStallExpiry;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  // La tercera lectura bajo el suelo llega justo al vencer la ventana de
  // estancamiento: la 013 declararía ahí el atasco y retrocedería, pero el
  // cierre por suelo gana y el servo no ejecuta ningún retroceso (RF-6).
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::BELOW_FLOOR),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_EQUAL_UINT32(static_cast<unsigned long>(kBaselineStallExpiryMs),
                           lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

void test_top_during_reverse_stops_without_extra_reverse(void) {
  CycleHarness harness{};
  harness.profile = profileAboveTopInReverse;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 10.0f, &diagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::ABOVE_TOP),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_FLOAT(30.0f, diagnostics.topGrams);
  TEST_ASSERT_EQUAL_FLOAT(50.0f, diagnostics.maxIncrementGrams);
  // Solo el retroceso del atasco previo: ni otro retroceso ni reanudación.
  TEST_ASSERT_EQUAL_UINT(1, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);

  unsigned long reverseMs = 0;
  TEST_ASSERT_TRUE(firstReverseMs(harness, &reverseMs));
  TEST_ASSERT_EQUAL_UINT32(static_cast<unsigned long>(reverseMs + 3 * kSamplePeriodMs),
                           lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionMs(harness) < reverseMs + kReverseMs);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

void test_top_during_pause_stops_without_resuming_advance(void) {
  CycleHarness harness{};
  harness.profile = profileAboveTopInPause;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 10.0f, &diagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::ABOVE_TOP),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_UINT(1, harness.reverseCount);
  // El avance no se reanuda y el reintento no se cuenta.
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);

  unsigned long reverseMs = 0;
  TEST_ASSERT_TRUE(firstReverseMs(harness, &reverseMs));
  // La tercera lectura cae dentro de la pausa y el ciclo se detiene antes de la
  // reanudación prevista para el final de los 0,3 s.
  TEST_ASSERT_EQUAL_UINT32(
      static_cast<unsigned long>(reverseMs + kReverseMs + kSamplePeriodMs),
      lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionMs(harness) <
                   reverseMs + kReverseMs + kPauseMs);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

void test_floor_during_reverse_stops_without_extra_reverse(void) {
  CycleHarness harness{};
  harness.profile = profileBelowFloorInReverse;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::BELOW_FLOOR),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_FLOAT(60.0f, diagnostics.topGrams);
  TEST_ASSERT_EQUAL_UINT(1, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);

  unsigned long reverseMs = 0;
  TEST_ASSERT_TRUE(firstReverseMs(harness, &reverseMs));
  TEST_ASSERT_EQUAL_UINT32(
      static_cast<unsigned long>(kFloorReverseDropMs + 2 * kSamplePeriodMs),
      lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionMs(harness) < reverseMs + kReverseMs);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

void test_floor_during_pause_stops_without_resuming_advance(void) {
  CycleHarness harness{};
  harness.profile = profileBelowFloorInPause;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::SENSOR_UNAVAILABLE),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::BELOW_FLOOR),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_UINT(1, harness.reverseCount);
  // La tercera lectura cae en la pausa: el avance no se reanuda.
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_EQUAL_UINT32(
      static_cast<unsigned long>(kFloorPauseDropMs + 2 * kSamplePeriodMs),
      lastActionMs(harness));
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

void test_plausible_increment_from_baseline_completes_with_measurements(void) {
  CycleHarness harness{};
  harness.profile = profileFlowFromBaseline;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 5.0f, &diagnostics);

  // El incremento se mide respecto de la línea base de 12 g y se mantiene dentro
  // del intervalo: objetivo alcanzado con medidos disponibles.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_TRUE(result.baselineAvailable);
  TEST_ASSERT_EQUAL_FLOAT(12.0f, result.baselineGrams);
  TEST_ASSERT_TRUE(result.incrementAvailable);
  TEST_ASSERT_TRUE(result.incrementGrams >= 5.0f);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

// --- Caso feliz completo (Spec 016): asentamiento ganado, compuerta abierta,
// línea base estable, incremento plausible y «objetivo alcanzado» con medidos
// disponibles en el reporte de la 014.

void test_happy_path_settles_accepts_the_order_and_completes_with_measurements(
    void) {
  // 1) Asentamiento: 14 lecturas válidas estables no bastan y la 15 lo gana.
  SettlementState settlement{};
  invalidateSettlement(&settlement);
  const WeightSample stableSample = makeSample(true, 0, kTestFactor, kTestSign);
  TEST_ASSERT_TRUE(isReadingValid(stableSample));
  for (unsigned i = 1; i < kSettlementReadings; ++i) {
    TEST_ASSERT_EQUAL_INT(
        static_cast<int>(SettlementOutcome::IN_PROGRESS),
        static_cast<int>(recordSettlementSample(&settlement, stableSample)));
  }
  TEST_ASSERT_FALSE(settlementGained(settlement));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::GAINED),
                        static_cast<int>(recordSettlementSample(
                            &settlement, stableSample)));
  TEST_ASSERT_TRUE(settlementGained(settlement));

  // 2) Compuerta de entrada: con asentamiento la orden de dispensación se abre.
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(DispenseEntry::DISPENSE),
      static_cast<int>(decideDispenseEntry(OrderAction::DISPENSE,
                                           settlementGained(settlement))));

  // 3) Ciclo completo: base estable de 0 g, flujo de 1 g/s hasta 20 g y sin
  // reintentos ni retrocesos.
  CycleHarness harness{};
  harness.profile = profileHappyPath;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::COMPLETED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineStatus::ACCEPTED),
                        static_cast<int>(diagnostics.baselineRejection));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_EQUAL_UINT(1, harness.advanceCount);
  TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_UINT(0, result.retryCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
  TEST_ASSERT_TRUE(result.baselineAvailable);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, result.baselineGrams);
  TEST_ASSERT_TRUE(result.finalAvailable);
  TEST_ASSERT_TRUE(result.incrementAvailable);
  // Incremento plausible: alcanza la cantidad pedida y no supera el tope.
  TEST_ASSERT_TRUE(result.incrementGrams >= 20.0f);
  TEST_ASSERT_TRUE(result.incrementGrams <= plausibilityTopGrams(20.0f));
  // RNF-2: el motor no pasa de 30 s ni el ciclo completo de 32 s.
  TEST_ASSERT_LESS_OR_EQUAL_UINT32(static_cast<unsigned long>(kMotorBudgetMs),
                                   motorDurationMs(harness));
  TEST_ASSERT_LESS_OR_EQUAL_UINT32(
      static_cast<unsigned long>(kVerificationWindowMs + kMotorBudgetMs),
      lastActionMs(harness));

  // 4) Reporte de la 014: «objetivo_alcanzado» con los medidos disponibles, que
  // es lo que el servidor usa para descontar el stock.
  const reporting::ReporteCiclo reporte =
      reporting::reporteDesdeResultado(result, true, 7);
  TEST_ASSERT_TRUE(reporte.medidosAvailable);
  TEST_ASSERT_EQUAL_FLOAT(result.incrementGrams, reporte.medidos);
  TEST_ASSERT_TRUE(reporte.solicitadosAvailable);
  TEST_ASSERT_EQUAL_FLOAT(20.0f, reporte.solicitados);
  TEST_ASSERT_EQUAL_UINT(0, reporte.reintentos);

  char json[256];
  TEST_ASSERT_TRUE(reporting::construirReporteJson("AA:BB:CC:DD:AB:1F", reporte,
                                                   json, sizeof(json)));
  TEST_ASSERT_NOT_NULL(std::strstr(json, "\"order_id\":7"));
  TEST_ASSERT_NOT_NULL(std::strstr(json, "\"motivo\":\"objetivo_alcanzado\""));
  TEST_ASSERT_NOT_NULL(std::strstr(json, "\"gramos_medidos\":"));
}

void test_small_negative_increment_inside_floor_keeps_013_behaviour(void) {
  CycleHarness harness{};
  harness.profile = profileSmallDropStalled;

  CycleDiagnostics diagnostics{};
  const DispenseResult result = runHarness(&harness, 20.0f, &diagnostics);

  // -3 g está dentro del intervalo: no cierra por suelo y el estancamiento se
  // resuelve como en la 013, con retrocesos y reintentos.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(diagnostics.plausibility));
  TEST_ASSERT_GREATER_THAN_UINT(0, harness.reverseCount);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::STALL_UNRESOLVED),
                        static_cast<int>(result.reason));
  TEST_ASSERT_EQUAL_UINT(static_cast<unsigned>(kMaxStallRetries),
                         result.retryCount);
  TEST_ASSERT_TRUE(lastActionIsStop(harness));
}

void test_invalid_factor_does_not_touch_ports(void) {
  // Caso (d) en la llamada directa al ciclo, como la 013: el factor cero,
  // negativo, NaN o infinito se rechaza sin leer la celda ni mover el servo.
  const float factors[] = {0.0f, -1.0f, NAN, INFINITY};
  for (unsigned i = 0; i < sizeof(factors) / sizeof(factors[0]); ++i) {
    CycleHarness harness{};
    harness.profile = profileFlow;

    const DispenseResult result =
        runHarness(&harness, 50.0f, nullptr, factors[i]);

    TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::INVALID_CONFIG),
                          static_cast<int>(result.reason));
    TEST_ASSERT_EQUAL_UINT(0, harness.advanceCount);
    TEST_ASSERT_EQUAL_UINT(0, harness.reverseCount);
    TEST_ASSERT_EQUAL_UINT(0, harness.stopCount);
    TEST_ASSERT_EQUAL_UINT(0, harness.readCount);
  }
}

int main(int, char **) {
  UNITY_BEGIN();
  RUN_TEST(test_cycle_limits_default_to_approved_constants);
  RUN_TEST(test_stall_profile_reverses_with_fixed_sequence);
  RUN_TEST(test_stall_without_retries_gives_up_without_reverse);
  RUN_TEST(test_stall_with_insufficient_retry_budget_gives_up_without_reverse);
  RUN_TEST(test_injected_budget_exhausts_cycle_without_stall);
  RUN_TEST(test_reverse_and_pause_readings_raise_observed_max);
  RUN_TEST(test_readings_during_reverse_and_pause_never_declare_stall);
  RUN_TEST(test_three_consecutive_invalid_readings_fail_without_reverse);
  RUN_TEST(test_invalid_order_does_not_touch_ports);
  RUN_TEST(test_alternating_invalid_readings_never_reverse);
  RUN_TEST(test_flow_profile_reaches_target_without_retries);
  RUN_TEST(test_realistic_flow_with_noise_reaches_target_without_retries);
  RUN_TEST(test_resolved_stall_reaches_target_with_one_retry);
  RUN_TEST(test_target_has_priority_over_stall_on_same_sample);
  RUN_TEST(test_target_reached_during_reverse_stops_the_cycle);
  RUN_TEST(test_target_reached_during_pause_stops_the_cycle);
  RUN_TEST(test_sensor_failure_during_reverse_stops_without_resume);
  RUN_TEST(test_sensor_failure_detected_during_pause_stops_without_resume);
  RUN_TEST(test_sensor_failure_started_in_pause_resumes_and_stops_without_reverse);
  RUN_TEST(test_motor_cycle_never_exceeds_budget_and_ends_stopped);
  RUN_TEST(test_sampling_period_holds_in_all_phases);
  RUN_TEST(test_verification_failure_fills_diagnostics);
  RUN_TEST(test_unstable_baseline_rejects_without_moving_servo);
  RUN_TEST(test_four_valid_readings_reject_with_insufficient_readings);
  RUN_TEST(test_negative_readings_leave_insufficient_baseline);
  RUN_TEST(test_aborted_window_by_invalid_readings_has_no_baseline_verdict);
  RUN_TEST(test_baseline_step_limit_is_one_gram_exactly);
  RUN_TEST(test_baseline_median_uses_all_valid_readings_with_even_and_odd_counts);
  RUN_TEST(test_three_readings_above_top_close_without_reverse_or_resume);
  RUN_TEST(test_three_readings_below_floor_close_without_reverse);
  RUN_TEST(test_two_outside_one_inside_does_not_close_the_cycle);
  RUN_TEST(test_two_outside_one_invalid_then_outside_does_not_close);
  RUN_TEST(test_top_prevails_over_target_on_same_sample);
  RUN_TEST(test_floor_prevails_over_stall_on_same_sample);
  RUN_TEST(test_top_during_reverse_stops_without_extra_reverse);
  RUN_TEST(test_top_during_pause_stops_without_resuming_advance);
  RUN_TEST(test_floor_during_reverse_stops_without_extra_reverse);
  RUN_TEST(test_floor_during_pause_stops_without_resuming_advance);
  RUN_TEST(test_plausible_increment_from_baseline_completes_with_measurements);
  RUN_TEST(test_happy_path_settles_accepts_the_order_and_completes_with_measurements);
  RUN_TEST(test_small_negative_increment_inside_floor_keeps_013_behaviour);
  RUN_TEST(test_all_negative_increments_report_the_least_negative_max);
  RUN_TEST(test_invalid_factor_does_not_touch_ports);
  return UNITY_END();
}
