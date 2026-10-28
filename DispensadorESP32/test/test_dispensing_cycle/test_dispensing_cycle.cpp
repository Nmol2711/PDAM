#include <unity.h>

#include <cmath>

#include "config/dispensing_cycle.h"

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

// El peso salta por encima del objetivo en pleno retroceso.
FakeReading profileTargetInReverse(unsigned long nowMs) {
  if (nowMs < kStallExpiryMs + kSamplePeriodMs) {
    return validGrams(0.0f);
  }
  return validGrams(50.0f);
}

// El peso salta por encima del objetivo ya en la pausa del reintento.
FakeReading profileTargetInPause(unsigned long nowMs) {
  if (nowMs < kStallExpiryMs + 5 * kSamplePeriodMs) {
    return validGrams(0.0f);
  }
  return validGrams(50.0f);
}

// La celda no responde nunca: la verificación no se supera.
FakeReading profileNoSensor(unsigned long nowMs) {
  (void)nowMs;
  return noAnswer();
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
  return UNITY_END();
}
