# Informe — Calibración de la celda de carga (HX711)

## 1. Metadatos

| Campo | Valor |
|---|---|
| Fecha | 2026-10-23 |
| Spec | [Spec 013 — Dispensado por peso con celda de carga](../../specs/013-dispensado-por-peso-hx711/spec.md) |
| Plan | [Plan 013](../../specs/013-dispensado-por-peso-hx711/plan.md) |
| Subsistema | PlatformIO / ESP32 (hardware) |
| Alcance | Calibración manual de la celda de 5 kg con módulo HX711 para el firmware de la Spec 013 |
| Estado | **Medición parcial con peso patrón; procedimiento completo no ejecutado** |
| Motivo | El usuario midió RAW en vacío y con ~206.8 g mediante un sketch independiente; faltan la serie de 10 promedios, el ajuste fino y la prueba física de 50 g |
| Informe relacionado | [Pruebas de hardware pendientes (Spec 013)](informe-pruebas-hardware-spec-013-2026-10-23.md) |

> Los valores vigentes de esta unidad son `hx711CalibrationFactor = 482.7f` y `hx711RawSign = 1.0f`, medidos con un patrón de ~206.8 g. `7050`/`-1` era el placeholder histórico del plan y ya no está en el firmware. Existe una medición real del factor y del signo (sección 3.1), pero el procedimiento completo de este informe (serie de 10 promedios, ajuste fino y prueba de 50 g) sigue sin ejecutarse.

---

## 2. Qué se calibra y qué no

### 2.1 Conversión de cuentas ADC a gramos

El HX711 entrega **cuentas crudas** del ADC de 24 bits. El firmware convierte cada lectura con un factor y un signo configurados antes de compilar. El objetivo no es el peso absoluto de la bandeja, sino el incremento respecto a una línea base.

```text
gramos = (raw * hx711RawSign) / hx711CalibrationFactor
incremento = (raw_final - raw_base) * hx711RawSign / hx711CalibrationFactor
```

- `hx711CalibrationFactor` es una magnitud **positiva**, expresada en **cuentas ADC por gramo**. No es gramos por cuenta.
- `hx711RawSign` es `+1.0f` o `-1.0f`. Corrige el sentido en que cambia el raw al añadir peso y debe ser compatible con el offset para que los gramos absolutos queden entre 0 g y 5000 g.
- El firmware valida que la lectura convertida sea finita y esté entre 0 g y 5000 g; también rechaza la saturación del ADC.

### 2.2 Línea base y ausencia de `tare()`

La celda mide el **incremento** de alimento que sale del dispensador, no el peso absoluto de la bandeja. Antes de arrancar el servo, el firmware abre una ventana fija de 2 segundos y calcula la **mediana** de las lecturas válidas. Esa mediana es la línea base. Al finalizar, el incremento es el peso final menos la línea base.

Por eso:

- El offset del ADC y el peso que ya estuviera sobre la bandeja se cancelan con la línea base.
- **No se usa `tare()`.** No hace falta tarar en cada ciclo y `tare()` puede bloquear o exigir estabilidad, lo que no encaja con la ventana fija de la spec.
- La calibración solo necesita que el raw cambie de forma coherente con el peso y que la conversión quede dentro del rango válido.
- Si el offset es tan grande que la conversión absoluta cae fuera de 0–5000 g, el firmware descarta todas las lecturas aunque el incremento pudiera ser correcto. En ese caso hay que revisar cableado, montaje y factor, y comprobar si algún signo cumple las dos condiciones de la sección 4.2; no añadir `tare()`.

---

## 3. Dónde se configura

La calibración se edita en [`DispensadorESP32/src/config/config.h`](../../DispensadorESP32/src/config/config.h), en el bloque de calibración (líneas 23–28 en el estado actual):

```cpp
// Calibración medida con un peso patrón de ~206.8 g: con la bandeja vacía el
// RAW es 160658 y con el peso es 260500, es decir, unas 482.7 cuentas ADC por
// gramo. El signo es +1.0f porque el RAW aumenta al añadir peso. Si se cambia
// la celda o el montaje, recalcular el factor con un peso conocido.
const float hx711CalibrationFactor = 482.7f;
const float hx711RawSign = 1.0f;
```

| Parámetro | Tipo | Regla |
|---|---|---|
| `hx711CalibrationFactor` | `float` | Debe ser finito y mayor que cero; se expresa en cuentas ADC por gramo. Valor vigente de esta unidad: `482.7f`. |
| `hx711RawSign` | `float` | Debe ser `+1.0f` o `-1.0f`; corrige el sentido del raw y debe dejar los gramos absolutos en 0–5000 g con incremento positivo. Valor vigente de esta unidad: `+1.0f`. |

No cambiar `hx711SckPin` ni `hx711DtPin` sin cambiar también el cableado. En el estado actual son SCK en GPIO18 y DT/DOUT en GPIO19.

### 3.1 Medición real de esta unidad

Medición del usuario con un sketch independiente sobre esta celda y este montaje, antes de flashear el firmware corregido:

| Medición | RAW / valor |
|---|---|
| Bandeja vacía | ≈ 160658 |
| Con ~206.8 g sobre la bandeja | ≈ 260500 |
| Diferencia | ≈ 99842 |
| Factor | ≈ 482.7 cuentas/g |
| Signo | `+1` (el RAW sube al cargar) |

Con esos valores la conversión absoluta da ≈ 332.8 g con la bandeja vacía y ≈ 539.7 g con los 206.8 g de alimento; el incremento es ≈ 206.8 g, coherente con el peso aplicado. La línea base cancela el offset de ≈ 332.8 g, por eso el firmware no necesita `tare()`.

Es una medición puntual, no la serie de 10 promedios de la sección 6.3: falta confirmar estabilidad, ajuste fino y la prueba de 50 g antes de registrar el cierre en la sección 10.

#### Verificación en placa (2026-10-24)

Con el firmware corregido flasheado, la línea base medida durante la ventana de verificación fue **≈ 333.1 g** con la bandeja en reposo. Es coherente con el cálculo `160658 / 482.7 ≈ 332.83 g`, así que el factor y el signo quedan confirmados en reposo: la conversión cae dentro de 0–5000 g y el firmware ya no descarta las lecturas.

Lo que esta comprobación **no** demuestra:

- No valida la exactitud con alimento real ni el ajuste fino de la sección 4.3; para eso hacen falta la verificación con peso patrón de la sección 6.6 y la prueba de 50 g con báscula externa.
- La prueba de dispensación posterior se hizo ejerciendo presión manual sobre la celda porque no había alimento seco. Los incrementos obtenidos así no sirven para ajustar el factor ni para aprobar el rango de 50–55 g; solo confirman que la verificación pasa y que el objetivo se detecta. Detalle en §2.5 del [informe de pruebas de hardware](informe-pruebas-hardware-spec-013-2026-10-23.md).

---

## 4. Fórmulas de calibración

### 4.1 Cálculo del factor

```text
factor = |raw_con_peso - raw_vacio| / gramos_conocidos
```

Se usa el valor absoluto de la diferencia porque el signo se prueba después, con la comprobación de la sección 4.2. El resultado queda en cuentas ADC por gramo y debe ser positivo.

### 4.2 Elección del signo

El signo no se elige solo mirando si el raw sube o baja. El firmware valida cada lectura con `isReadingValid`: los gramos absolutos deben ser finitos y estar entre 0 g y 5000 g, y además el incremento debe ser positivo. Por eso hay que comprobar las dos condiciones a la vez.

Procedimiento:

1. Calcular el factor con la magnitud de la diferencia: `factor = |raw_con_peso - raw_vacio| / gramos_conocidos`.
2. Probar el signo candidato y calcular:

   ```text
   gramos_vacio = raw_vacio * signo / factor
   gramos_peso = raw_con_peso * signo / factor
   ```

3. Elegir el signo que cumpla **las dos condiciones**:

   - `gramos_vacio` y `gramos_peso` dentro de 0–5000 g.
   - `gramos_peso > gramos_vacio` (incremento positivo).

4. Si ningún signo cumple ambas, no es un problema de signo: el offset o el sentido mecánico del raw es incompatible con la validación del firmware. Corregir el cableado/montaje para que el raw tenga el offset y la dirección compatibles (por ejemplo, raw negativo en vacío que se vuelve más negativo al cargar, con signo `-1.0f`), o añadir un offset en el firmware, lo cual queda fuera del alcance de la Spec 013. No usar `tare()` ni cambiar la validación para ocultarlo.

| Comportamiento del raw | Offset | `hx711RawSign` |
|---|---|---|
| El raw promedio **baja** al añadir peso | Negativo en vacío; `gramos_vacio` y `gramos_peso` en 0–5000 g | `-1.0f` |
| El raw promedio **sube** al añadir peso | Positivo en vacío; `gramos_vacio` y `gramos_peso` en 0–5000 g | `+1.0f` |
| Cualquier caso en que ningún signo deje ambos gramos en 0–5000 g y haga `gramos_peso > gramos_vacio` | Incompatible (por ejemplo, raw positivo que baja al cargar) | Ninguno: corregir cableado/montaje o añadir offset en firmware (fuera de la Spec 013) |

Nota práctica: el signo solo corrige la dirección; no arregla un offset incompatible con el rango 0–5000 g del firmware. Si al probar ambos signos no hay uno que deje los gramos absolutos en rango y además haga positivo el incremento (ver el tercer ejemplo de la sección 6.4), el problema es de cableado/montaje o de offset, no de signo. No usar `tare()` ni cambiar la validación para ocultarlo.

### 4.3 Ajuste fino

Después de la calibración inicial, si el firmware mide un peso conocido con error:

```text
factor_nuevo = factor_actual * (gramos_medidos / gramos_reales)
```

- Si mide **bajo**, el cociente es menor que 1 y el factor baja.
- Si mide **alto**, el cociente es mayor que 1 y el factor sube.

Ejemplo ilustrativo (no es el factor vigente): factor de partida `7050`, peso real `500 g` y el cálculo del firmware da `450 g`.

```text
factor_nuevo = 7050 * (450 / 500) = 6345
```

Si en cambio diera `550 g`:

```text
factor_nuevo = 7050 * (550 / 500) = 7755
```

El ajuste fino se hace con datos reales, no con valores de ejemplo. Si el resultado se aleja mucho del valor esperado, repetir la toma de raw y revisar el montaje antes de seguir iterando.

---

## 5. Materiales

| Material | Uso | Nota |
|---|---|---|
| Peso patrón de 500 g o 1 kg | Calcular el factor | Se prefiere 500 g por manejo y por ser un peso cómodo para la celda de 5 kg; 1 kg también sirve |
| Báscula de cocina | Verificar la masa del peso patrón y la comida dispensada | Debe ser estable y tener resolución suficiente |
| Superficie estable y horizontal | Evitar ruido y deriva | No usar una mesa que se mueva con el servo |
| Destornillador | Fijar la celda y el módulo | Adecuado al montaje |
| Cableado firme | Unir celda, HX711 y ESP32 | Sin cables flojos ni tensiones mecánicas |
| PC con PlatformIO y cable USB | Compilar, flashear y leer el monitor serie | Mismo entorno del firmware |
| Multímetro (opcional) | Verificar alimentación y continuidad | Útil si no hay lecturas |

No se necesita una báscula de laboratorio para el prototipo, pero sí un peso patrón razonablemente conocido. No usar alimentos como referencia sin pesarlos antes en una báscula.

---

## 6. Procedimiento paso a paso

### 6.1 Montaje y estabilización

1. Montar la celda en la bandeja o en el punto de salida del alimento, no en el depósito interno.
2. Fijar el módulo HX711 y asegurar que los cables no tiren de la celda.
3. Dejar la bandeja **vacía**.
4. Encender el ESP32 y esperar **2–3 minutos** para que la electrónica y el montaje se estabilicen.
5. No calibrar con el servo girando ni con vibraciones externas.

### 6.2 Sketch temporal para obtener el raw

Crear un proyecto PlatformIO **fuera del repositorio**, en `/tmp/calibracion_hx711`. No commitear este proyecto.

`/tmp/calibracion_hx711/platformio.ini`:

```ini
[env:esp32dev]
platform = espressif32
board = esp32dev
framework = arduino
monitor_speed = 115200
lib_deps =
    bogde/HX711 @ ^0.7.5
```

`/tmp/calibracion_hx711/src/main.cpp`:

```cpp
#include <Arduino.h>
#include <HX711.h>

static const int HX711_DT = 19;
static const int HX711_SCK = 18;

static HX711 scale;

void setup() {
  Serial.begin(115200);
  delay(2000);

  scale.begin(HX711_DT, HX711_SCK);
  pinMode(HX711_DT, INPUT_PULLUP);

  Serial.println("Calibracion HX711: DT=19, SCK=18");
  Serial.println("raw_promedio cada 2 s; no se usa tare().");
}

void loop() {
  const unsigned long inicioCiclo = millis();
  const int objetivo = 10;
  long suma = 0;
  int validas = 0;

  while (validas < objetivo && millis() - inicioCiclo < 1000) {
    if (scale.is_ready()) {
      suma += scale.read();
      ++validas;
    }
    delay(5);
  }

  if (validas == 0) {
    Serial.println("raw_promedio=sin_lecturas");
  } else {
    Serial.printf("raw_promedio=%ld (validas=%d/%d)\n",
                  suma / validas, validas, objetivo);
  }

  const unsigned long transcurrido = millis() - inicioCiclo;
  if (transcurrido < 2000) {
    delay(2000 - transcurrido);
  }
}
```

El sketch cumple estas condiciones:

- Usa el HX711 en DT 19 y SCK 18, igual que el firmware.
- Configura `pinMode(HX711_DT, INPUT_PULLUP)` después de `begin()`.
- Llama a `scale.read()` solo si `scale.is_ready()` es verdadero.
- No usa `tare()` ni comandos de calibración por serie.
- Imprime un promedio cada 2 segundos.

Comandos:

```bash
mkdir -p /tmp/calibracion_hx711/src
cd /tmp/calibracion_hx711
# Crear platformio.ini y src/main.cpp con el contenido anterior.
pio run -t upload
pio device monitor -b 115200
```

La salida tendrá la forma:

```text
raw_promedio=<entero> (validas=<n>/10)
```

o, si no hay lecturas:

```text
raw_promedio=sin_lecturas
```

### 6.3 Toma de datos

1. Con la bandeja vacía, anotar **10 promedios** impresos por el sketch. Cada línea ya es un promedio de hasta 10 lecturas.
2. Colocar el peso patrón de 500 g (o 1 kg) en el centro de la bandeja.
3. Esperar unos segundos a que la lectura se estabilice.
4. Anotar otros **10 promedios**.
5. No mover la bandeja, el módulo ni los cables entre ambas series.

| # | `raw_vacio` | `raw_con_peso` |
|---|---|---|
| 1 |  |  |
| 2 |  |  |
| 3 |  |  |
| 4 |  |  |
| 5 |  |  |
| 6 |  |  |
| 7 |  |  |
| 8 |  |  |
| 9 |  |  |
| 10 |  |  |
| Promedio |  |  |

Si hay un valor claramente anómalo, no descartarlo sin justificarlo: repetir la serie completa. Un ruido alto indica un problema de masa, fuente, cableado o montaje.

### 6.4 Cálculo del factor y del signo

Usar los promedios de las dos columnas:

```text
factor = |promedio_con_peso - promedio_vacio| / gramos_del_patron
```

Ejemplo con el raw subiendo al añadir peso:

```text
raw_vacio = 120000
raw_con_peso = 220000
peso_patron = 500 g

factor = |220000 - 120000| / 500 = 100000 / 500 = 200 cuentas/g
signo = +1.0f
```

Con ese factor, la conversión absoluta da 600 g con la bandeja vacía y 1100 g con el peso. La línea base cancela los 600 g de offset y el incremento es 500 g. Eso es correcto: lo que importa es la diferencia.

Ejemplo con el raw bajando al añadir peso:

```text
raw_vacio = -120000
raw_con_peso = -220000
peso_patron = 500 g

factor = |-220000 - (-120000)| / 500 = 100000 / 500 = 200 cuentas/g
signo = -1.0f
```

Con signo `-1.0f`, la conversión absoluta da 600 g con la bandeja vacía y 1100 g con el peso; el incremento vuelve a ser 500 g. El signo negativo es correcto porque el raw se volvió más negativo al cargar.

Ejemplo con offset incompatible: ningún signo sirve.

```text
raw_vacio = 220000
raw_con_peso = 120000
peso_patron = 500 g

factor = |120000 - 220000| / 500 = 100000 / 500 = 200 cuentas/g

signo = -1.0f
gramos_vacio = 220000 * (-1) / 200 = -1100 g
gramos_peso  = 120000 * (-1) / 200 = -600 g
-> ambos fuera del rango 0–5000 g (inválido)

signo = +1.0f
gramos_vacio = 220000 * (+1) / 200 = 1100 g
gramos_peso  = 120000 * (+1) / 200 = 600 g
-> dentro de rango, pero gramos_peso < gramos_vacio (incremento negativo)
```

Ningún signo cumple las dos condiciones. No es un problema de signo: el offset positivo con un raw que baja al cargar es incompatible con la validación del firmware. Hay que corregir el cableado/montaje para que el raw tenga el offset y la dirección compatibles (por ejemplo, raw negativo en vacío que se vuelve más negativo al cargar, con signo `-1.0f`), o añadir un offset en el firmware, lo cual queda fuera del alcance de la Spec 013. No usar `tare()` ni cambiar la validación para ocultarlo.

### 6.5 Editar y flashear el firmware

1. Abrir [`DispensadorESP32/src/config/config.h`](../../DispensadorESP32/src/config/config.h).
2. Sustituir el valor vigente de `hx711CalibrationFactor` por el factor calculado.
3. Ajustar `hx711RawSign` a `+1.0f` o `-1.0f` según corresponda.
4. Compilar y flashear:

```bash
cd DispensadorESP32
pio run
pio run --target upload
pio device monitor -b 115200
```

El factor debe quedar positivo. El signo no se valida como "positivo": debe cumplir las dos condiciones de la sección 4.2 (gramos absolutos en 0–5000 g e incremento positivo).

### 6.6 Verificación con peso conocido y con 50 g

1. Con el sketch temporal, aplicar la fórmula a los promedios con el peso patrón y comparar con el peso real. Criterio operativo de este informe: error no mayor que 2 % (10 g para 500 g).
2. Si el error es mayor, recalcular el factor con la fórmula de ajuste fino y volver a flashear.
3. Para verificar 50 g, usar el flujo real de dispensado de la Spec 013 descrito en el [informe de pruebas de hardware](informe-pruebas-hardware-spec-013-2026-10-23.md), prueba P3.
4. Criterio de aceptación de la prueba física: **50 g solicitados deben entregar entre 50 g y 55 g** medidos en báscula externa.
5. Si la dispensación supera los 55 g, revisar calibración, vibración, montaje y alimento que sigue cayendo después de detener el servo. No ajustar la lógica de las 3 lecturas para ocultar el sobrepeso.

### 6.7 Cuándo repetir la calibración

Repetir el procedimiento si se cambia cualquiera de estos elementos:

- La celda de carga.
- El módulo amplificador HX711.
- La bandeja o el montaje mecánico.
- La posición de la celda o la sujeción.
- El cableado de la celda.
- Los pines de conexión (solo si se cambia también `config.h`).

El factor es propio de cada conjunto celda-módulo-montaje. No copiarlo de otro equipo sin verificarlo.

---

## 7. Errores frecuentes

| Síntoma | Causa probable | Acción |
|---|---|---|
| `raw_promedio=sin_lecturas` | HX711 sin alimentación, DT/SCK mal conectados o módulo sin responder | Verificar VCC/GND, DT en GPIO19 y SCK en GPIO18; comprobar que el módulo esté alimentado |
| Raw siempre en 0 o sin cambios | DT bloqueado, SCK mal conectado o módulo defectuoso | Revisar continuidad y probar otro módulo |
| Raw saturado en `-8388608` o `8388607` | Cableado de la celda, cortocircuito o sobrecarga | Revisar E+/E-/A+/A-; retirar peso; no superar 5 kg |
| El raw no cambia al añadir peso | Celda mal cableada o señal diferencial cruzada | Revisar A+/A- y E+/E-; confirmar la hoja de datos de la celda |
| Gramos negativos o fuera de 0–5000 g | Signo invertido, offset incompatible o factor incorrecto | Revisar `hx711RawSign` con la comprobación de la sección 4.2, el cableado y el factor; no usar `tare()` para ocultarlo |
| Lecturas ruidosas | Masa común deficiente, fuente inestable, cables largos o vibración | Unir masas, usar fuente adecuada, acortar cables y aislar la celda del servo |
| Deriva lenta del raw | Calentamiento, fluencia mecánica o montaje inestable | Esperar 2–3 min, revisar la fijación y repetir la calibración con el montaje estabilizado |
| Valor plausible con la celda desconectada | Limitación conocida del HX711 alimentado | Para probar el fallo de sensor, desconectar el **módulo HX711 del ESP32**, no solo la celda |
| La conversión da un valor muy distinto al peso real | Factor mal calculado o peso patrón mal medido | Repetir la toma de raw y recalcular; verificar el peso patrón en una báscula |
| El peso medido cambia entre ciclos | Montaje, vibración o flujo irregular | Revisar mecánica y repetir las pruebas; la precisión depende del montaje |

---

## 8. Notas y límites

- **No cambiar los pines** sin cambiar el cableado y `config.h`. El firmware espera DT en GPIO19 y SCK en GPIO18.
- **No usar `tare()`.** El firmware calcula la línea base por mediana en cada ciclo.
- **No calibrar con el servo girando.** La vibración contamina el raw y puede producir un factor incorrecto.
- **No apoyar peso adicional sobre la bandeja durante la línea base.** Si se apoya una mano, una herramienta o un peso y luego se retira, la referencia queda contaminada y el incremento se calcula mal.
- **No superar los 5 kg de la celda.** Incluir el peso de la bandeja.
- **No copiar el factor `482.7` a otra unidad.** Es el valor medido para esta celda y este montaje; recalcular con peso patrón si cambia el conjunto. `7050` era el placeholder histórico y ya no está en el firmware.
- La exactitud final depende de la mecánica, del flujo del tornillo sin fin, de la vibración del servo y del tipo de croqueta. La calibración corrige la escala, no los problemas mecánicos.
- La celda de 5 kg usada para raciones de 50 g puede tener ruido apreciable; por eso el firmware usa mediana, 3 lecturas consecutivas y una ventana de verificación.
- La calibración es por compilación: no hay comandos de calibración por el puerto serie.
- No guardar credenciales, tokens, IP reales ni MAC reales en las tablas de calibración.

---

## 9. Checklist final de calibración

- [ ] Celda, HX711 y ESP32 montados y con cableado firme.
- [ ] Bandeja vacía y superficie estable.
- [ ] Equipo encendido y estabilizado durante 2–3 minutos.
- [ ] Sketch temporal en `/tmp/calibracion_hx711` compilado y flasheado.
- [ ] 10 promedios con bandeja vacía anotados.
- [ ] 10 promedios con peso patrón anotados.
- [ ] Factor calculado y positivo.
- [ ] Signo elegido comprobando gramos absolutos en 0–5000 g e incremento positivo.
- [ ] `config.h` actualizado en el bloque de calibración.
- [ ] `pio run` termina en SUCCESS y el firmware se flashea.
- [ ] Verificación con peso patrón dentro del criterio operativo de 2 %.
- [ ] Prueba de 50 g entre 50 g y 55 g según el informe de pruebas de hardware.
- [ ] Sin lecturas saturadas ni negativas durante la verificación.
- [ ] Valores finales registrados en la tabla de calibración.
- [ ] Procedimiento repetido si cambió la celda, el módulo, la bandeja o el montaje.

---

## 10. Registro de calibración

Completar solo con mediciones reales. No usar valores de ejemplo.

| Fecha | Celda / módulo | Peso patrón | `raw_vacio` promedio | `raw_con_peso` promedio | Factor | Signo | Verificación 500 g | Prueba 50 g | Notas |
|---|---|---|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |  |

---

## 11. Cierre

Cuando la calibración y la verificación de 50 g pasen, registrar los valores finales en este informe y continuar con el [informe de pruebas de hardware](informe-pruebas-hardware-spec-013-2026-10-23.md). La calibración por sí sola no cierra T10: faltan las pruebas de fallo de sensor, frecuencia de muestreo, no regresión BLE/WiFi y temporizador.

Este informe no modifica `config.h`, el firmware, la spec, `tasks.md` ni `MEMORY.md`.
