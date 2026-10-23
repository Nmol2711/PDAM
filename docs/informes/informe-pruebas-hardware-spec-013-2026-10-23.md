# Informe — Pruebas de hardware pendientes (Spec 013: dispensado por peso)

## 1. Metadatos

| Campo | Valor |
|---|---|
| Fecha | 2026-10-23 |
| Spec | [Spec 013 — Dispensado por peso con celda de carga](../../specs/013-dispensado-por-peso-hx711/spec.md) |
| Plan | [Plan 013](../../specs/013-dispensado-por-peso-hx711/plan.md) |
| Tareas | [Tasks 013](../../specs/013-dispensado-por-peso-hx711/tasks.md) |
| Subsistema | PlatformIO / ESP32 (hardware) |
| Alcance | Checklist físico T10: exactitud, fallos de sensor, muestreo, no regresión BLE/WiFi y temporizador |
| Estado | **No ejecutadas** |
| Motivo | El hardware no está armado: falta montar la celda de carga, el módulo HX711, el servo con alimentación externa y la bandeja de prueba |
| Informe relacionado | [Calibración de la celda de carga (HX711)](informe-calibracion-hx711-2026-10-23.md) |

> Este documento es un procedimiento de prueba, no un registro de resultados. No contiene mediciones reales ni evidencia de T10. Los fragmentos de log que aparecen son plantillas de formato; no deben interpretarse como pruebas ejecutadas.

---

## 2. Resumen

La Spec 013 sustituye el dispensado por tiempo fijo de 10 segundos por un dispensado por peso medido con una celda de carga de 5 kg y un amplificador HX711. El firmware ya está implementado y la lógica pura está cubierta por pruebas nativas, pero la validación física sigue pendiente.

### 2.1 Cambios que se validan

| Área | Cambio implementado | Qué debe confirmarse en hardware |
|---|---|---|
| Pines HX711 | Datos en GPIO19 (DT/DOUT) y reloj en GPIO18 (SCK) | Cableado correcto, lecturas estables y detección de módulo desconectado |
| Servo | MG966R en GPIO4, con `startServo()` a 0° y `stopServo()` a 90° | Arranque solo tras la verificación y parada en toda salida |
| Ventana de verificación | 2 segundos fijos, no reiniciables | No se mueve el servo si la celda no responde; línea base por mediana |
| Muestreo | Periodo máximo de 200 ms y timeout de lectura de 100 ms | Al menos 5 intentos de lectura por segundo |
| Límite de giro | 30 segundos desde el arranque del servo | Parada por tiempo y motivo `objetivo no alcanzado` |
| Confirmación | 3 lecturas consecutivas para objetivo y para fallo de sensor | No se detiene por un pico aislado; sí se detiene ante 3 inválidas consecutivas |
| API | `serve`, `amount` en gramos y `reset_wifi` con prioridad | Dispensado con la cantidad solicitada y reinicio BLE sin mover el servo |
| Temporizador | Siguiente consulta 20 segundos después de terminar el ciclo | No hay consulta inmediata tras una dispensación |

### 2.2 Estado automatizado

Según la verificación registrada en `tasks.md` el 2026-10-23:

- **T1–T9 cerradas.** `pio test -e native` pasa **65/65** y `pio run` en `esp32dev` termina en **SUCCESS**.
- **T10 no ejecutada.** No hay resultados físicos de exactitud, fallo de sensor, frecuencia de muestreo ni no regresión.
- La única dependencia nueva es `bogde/HX711 @ ^0.7.5`; el resto del firmware conserva el comportamiento anterior salvo el reemplazo explícito del dispensado por tiempo.

La comprobación física de RF-5, RF-9, RF-11, RF-12, RF-13, RNF-1, RNF-4 y RNF-5, la exactitud de 50 g y la no regresión quedan exclusivamente en este checklist.

---

## 3. Hardware y cableado

### 3.1 Módulo HX711 y celda de 5 kg

| HX711 | ESP32 | Observación |
|---|---|---|
| VCC | 3V3 | Preferible alimentar el módulo a 3.3 V para que DOUT no supere el nivel lógico del ESP32 |
| GND | GND | Masa común con el ESP32 y con la fuente del servo |
| DT / DOUT / DAT | GPIO19 | Línea de datos; el firmware configura `INPUT_PULLUP` para detectar el módulo desconectado |
| SCK / CLK | GPIO18 | Línea de reloj |

| Celda de carga | HX711 | Observación |
|---|---|---|
| E+ | E+ | Excitación positiva; el color del hilo es orientativo |
| E- | E- | Excitación negativa; verificar la hoja de datos de la celda |
| A+ | A+ | Señal diferencial positiva |
| A- | A- | Señal diferencial negativa |

La celda es de **4 hilos**. Los colores varían entre fabricantes: no confiar solo en el color, contrastar con la hoja de datos o con la serigrafía. Si se cruzan A+ y A-, la lectura cambia de sentido; si se cruzan E+ y E-, también se invierte la excitación y cambia el sentido de la señal. Verificar el conexionado antes de energizar.

### 3.2 Servo MG966R y alimentación

| MG966R | Conexión |
|---|---|
| V+ (rojo) | Fuente externa de 5–6 V con margen para el pico de arranque |
| GND (negro o marrón) | GND común con el ESP32 y el HX711 |
| PWM (naranja o amarillo) | GPIO4 |

Advertencias eléctricas:

- **No alimentar el servo desde el regulador del ESP32.** El pico de corriente del servo puede provocar reinicios, lecturas erráticas o caídas de WiFi.
- **Unir las masas** de la fuente del servo, el ESP32 y el HX711. Sin masa común, la señal PWM y las lecturas de la celda son inestables.
- **Preferir HX711 a 3.3 V.** Si el módulo se alimenta a 5 V y su DOUT entrega 5 V, usar un level shifter o un divisor resistivo antes de GPIO19; el ESP32 no tolera 5 V en sus entradas.
- **No superar los 5 kg de la celda.** El peso de la bandeja también cuenta. Evitar golpes, cargas laterales y sobrecargas.
- Desconectar la alimentación antes de cambiar cables o de mover la celda.

### 3.3 Montaje mecánico

- La celda debe medir el alimento que sale del dispensador, no el peso del depósito interno.
- La bandeja o el punto de pesaje deben quedar libres de roces con la estructura.
- Los cables no deben tirar de la celda ni pasar por zonas de vibración del servo.
- La superficie de apoyo debe ser estable y horizontal.

---

## 4. Preparación del banco

### 4.1 Backend

```bash
cd api
source venv/bin/activate
uvicorn app.main:app --reload --port 8000 --host 0.0.0.0
```

Verificación rápida del servicio:

```bash
curl -s http://<IP>:8000/
```

La respuesta debe ser un JSON de estado del servidor. El backend debe escuchar en `0.0.0.0` para que el ESP32 pueda alcanzarlo desde la red local.

### 4.2 Firmware

```bash
cd DispensadorESP32
pio test -e native
pio run
pio run --target upload
pio device monitor -b 115200
```

El monitor debe mostrar la inicialización y la MAC del equipo. Si el puerto no se detecta automáticamente, indicar el puerto serie de la placa.

### 4.3 Red y configuración

- El PC y el ESP32 deben estar en la **misma red local de 2.4 GHz**.
- Evitar redes con aislamiento de clientes o firewall que bloquee el puerto 8000.
- En [`src/config/config.h`](../../DispensadorESP32/src/config/config.h), `BASE_URL` debe apuntar a la IP del PC y conservar la ruta que el firmware concatena con la MAC:

```cpp
const char* const BASE_URL = "http://<IP>:8000/dispenserscheck-taks/";
```

La ruta real registrada por FastAPI es `/dispenserscheck-taks/<MAC>` (sin una barra adicional entre `dispensers` y `check-taks`). No agregar ni quitar barras sin verificar la ruta en el backend.

- La MAC visible en el monitor debe coincidir con la registrada en el backend. Para la base de datos se usa la forma **normalizada: mayúsculas y sin separadores**.
- El `amount` que envía el backend está en gramos.

### 4.4 Aprovisionamiento BLE/WiFi

1. Arrancar el ESP32 sin credenciales guardadas o después de un reseteo de WiFi.
2. En la app, escanear el dispositivo `PDAM-Config-<MAC>`.
3. Enviar `<SSID>` y `<PASSWORD>`.
4. Esperar la conexión WiFi y la validación HTTP del servidor.

No registrar credenciales reales en este informe ni en capturas de pantalla.

---

## 5. Cómo provocar una orden

### 5.1 Flujo normal desde la app

1. Programar una comida en la app para un horario cercano.
2. El planificador del backend revisa los horarios cada minuto y marca `pending_dispensing` cuando corresponde.
3. El ESP32 consulta cada 20 segundos y recibe `serve: true` con el `amount` del horario.
4. La orden real descuenta stock y limpia la bandera al entregarse.

Este es el flujo recomendado para el checklist principal porque valida el camino completo app → backend → firmware.

### 5.2 Disparo manual reproducible por SQLite

Este procedimiento sirve para repetir pruebas sin esperar al planificador. El backend debe estar **detenido** mientras se edita SQLite para evitar bloqueos y carreras con el planificador.

1. Detener `uvicorn` con `Ctrl+C`.
2. Ejecutar el siguiente bloque desde `api/`:

```bash
cd api
source venv/bin/activate
python - <<'PY'
import sqlite3

MAC = "<MAC>"  # Mayúsculas y sin separadores
with sqlite3.connect("app/db/pdam.db") as conn:
    cur = conn.execute(
        "UPDATE dispensers SET pending_dispensing = 1 WHERE mac_normalized = ?",
        (MAC,),
    )
    if cur.rowcount == 0:
        raise SystemExit("No existe un dispensador con esa MAC normalizada")
    conn.commit()
print("pending_dispensing activado para", MAC)
PY
```

3. Volver a iniciar el backend.
4. Esperar a que el ESP32 consulte (hasta 20 segundos) y ejecutar la prueba.

Condiciones y advertencias:

- El dispensador debe tener una mascota y **al menos un horario** asociado. Si no hay horario, `check_pending_task` devuelve `serve: false` y no limpia la bandera.
- Si `pending_wifi_reset` está activo, el backend devuelve primero la orden de reseteo y no dispensa. Verificar y limpiar esa bandera antes de las pruebas de peso.
- El endpoint real **descuenta stock y limpia `pending_dispensing`** al entregar la orden. Para cada repetición hay que volver a ejecutar el `UPDATE` o reabastecer.
- No editar la base de datos con el backend en ejecución.

### 5.3 Endpoint de prueba

El backend expone un endpoint de prueba que devuelve la orden **sin descontar stock ni limpiar la bandera**:

```text
GET http://<IP>:8000/dispenserscheck-taks-test/<MAC>
```

Para usarlo con el firmware hay que cambiar temporalmente `BASE_URL` a:

```cpp
const char* const BASE_URL = "http://<IP>:8000/dispenserscheck-taks-test/";
```

Advertencia: mientras `pending_dispensing` siga activo, el ESP32 puede **repetir la dispensación cada 20 segundos**. No se recomienda para el checklist principal; sirve para depurar la respuesta HTTP o para una prueba aislada. Después de usarlo, restaurar `BASE_URL` y recompilar.

### 5.4 Verificación con `curl`

Para comprobar la respuesta sin consumir la orden real:

```bash
curl -s "http://<IP>:8000/dispenserscheck-taks-test/<MAC>"
```

La respuesta tendrá la forma:

```json
{"serve": true, "amount": 50.0}
```

o, si no hay orden pendiente:

```json
{"serve": false, "amount": 0}
```

No usar el endpoint real con `curl` antes de que consulte el ESP32: la orden se consumiría y el firmware ya no la recibiría.

---

## 6. Checklist P1–P12

| ID | Requisito | Objetivo | Procedimiento | Resultado esperado | Evidencia |
|---|---|---|---|---|---|
| P1 | RNF-4, RNF-6 | Confirmar que el firmware compila, la suite nativa pasa y la placa flashea. | `cd DispensadorESP32`<br>`pio test -e native`<br>`pio run -t clean && pio run`<br>`pio run --target upload` | 65/65 en nativo; `pio run` SUCCESS; carga completa; monitor a 115200. | Salida de terminal y primeras líneas del monitor. |
| P2 | RF-11 | Calibrar la celda y verificar la conversión con un peso conocido. | Ejecutar el [informe de calibración](informe-calibracion-hx711-2026-10-23.md). Verificar con 500 g o 1 kg usando el sketch de raw. | Factor positivo, signo coherente, lectura que sigue al peso y error operativo no mayor que 2 % (10 g en 500 g). | Tabla de raw, valores finales de `config.h` y monitor. |
| P3 | RF-1, RF-6, RF-7, RF-12, RNF-1, RNF-2 | Validar el camino feliz de 50 g. | Bandeja vacía; solicitar 50 g; medir la comida entregada en una báscula externa; repetir 3 veces limpiando la bandeja. | 3/3 entre 50 g y 55 g; log con `incremento` en ese rango y motivo `objetivo alcanzado`; servo detenido. | Tres líneas `Despacho:` y tres mediciones externas. |
| P4 | RF-8, RNF-3 | Validar el tope de 30 s con depósito vacío. | Vaciar el depósito; solicitar 50 g; cronometrar desde el arranque del giro. | Parada a los 30 s, sin superarlos; motivo `objetivo no alcanzado`; incremento cercano a 0; ciclo total no mayor que 32 s. | Log y tiempo medido. |
| P5 | RF-4, RF-12 | Validar el fallo de sensor al arranque. | Desconectar el **módulo HX711 del ESP32** (DT/SCK; idealmente también VCC/GND), no solo la celda; reiniciar y solicitar 50 g. | El servo no se mueve; en un máximo de 2 s aparece `sensor no disponible`; línea base, peso final e incremento como `no disponible`. | Monitor y video u observación directa. |
| P6 | RF-9, RNF-3 | Validar el fallo de sensor a mitad del giro. | Con una dispensación válida en curso, desconectar el módulo HX711 durante el giro; medir desde la desconexión (cota conservadora) y, si hay instrumentación, desde la primera de las 3 lecturas inválidas. Repetir 5–10 veces. | Parada en menos de 1 s desde la primera inválida y, en la práctica, en menos de 1 s desde la desconexión; motivo `fallo del sensor durante la dispensacion`; sin esperar los 30 s. | Logs y video con cronómetro. |
| P7 | RF-9 (inválida aislada) | Confirmar que una inválida aislada no detiene el ciclo. | Aflojar un cable de la celda durante el giro menos de 3 muestras (menos de 600 ms) y reconectarlo. | El ciclo continúa; no aparece el motivo de fallo de sensor. Si no se genera una inválida, registrar `no concluyente` porque el módulo puede entregar lecturas plausibles. | Log de la dispensación. |
| P8 | RNF-1 | Medir la frecuencia de muestreo. | Analizador lógico en D18 (SCK) y D19 (DT/DOUT); medir ráfagas y periodo. Sin instrumento, usar instrumentación temporal no commiteada. | Al menos 5 intentos de lectura por segundo; en 2 s, al menos 10 intentos y al menos 5 válidas en la verificación; periodo no mayor que 200 ms. | Captura del analizador o contadores temporales. |
| P9 | RF-13 | Confirmar que el aprovisionamiento BLE no tiene regresiones. | Flashear un build nuevo para forzar el borrado de NVS por cambio de `build_stamp` (o ejecutar P11); arrancar sin credenciales; aprovisionar desde la app; esperar la conexión WiFi y la validación HTTP. | Aparece `PDAM-Config-<MAC>`; WiFi conectado; `Validación HTTP exitosa (Status 200). Entrando en estado normal.`; el servo no se mueve. | Monitor y app. |
| P10 | RF-13 | Confirmar la reconexión WiFi y el rollback a BLE. | Con WiFi conectado, apagar el router; esperar la detección y el intento de reconexión; restaurar el router. Repetir una vez con el router restaurado antes de la ventana de 10 s y otra después, para observar ambos caminos. | Si vuelve a tiempo: `Reconexion WiFi exitosa` y validación 200. Si no: rollback a aprovisionamiento BLE. Sin movimiento del servo. | Monitor y estado del router. |
| P11 | RF-10, RF-13 | Confirmar el reseteo de credenciales y su prioridad. | Desde la app o `POST /dispensers/{id}/reset-wifi` con sesión autenticada, con el equipo inactivo; opcionalmente poner también `pending_dispensing = 1` para probar la prioridad. Limpiar esa bandera al terminar si se dejó activa. | NVS borrada; reinicio; aparece `PDAM-Config-<MAC>`; el servo no se mueve; `reset_wifi` gana sobre `serve`. | Monitor. |
| P12 | RF-13 | Confirmar que la siguiente consulta ocurre 20 s después del fin. | Tras una dispensación, medir el tiempo hasta el siguiente `Consultando ordenes pendientes en el servidor...`. | Aproximadamente 20 s después del fin (20–21 s), no inmediato; sin reinicio del dispositivo. | Log con marcas de tiempo externas o cronómetro. |

Notas sobre criterios:

- El criterio de 2 % para el peso patrón es un criterio operativo de este informe; la spec solo fija 50–55 g para la prueba de 50 g.
- P7 es opcional y puede resultar no concluyente si al aflojar solo la celda el módulo sigue entregando valores plausibles.
- P8 no puede sustituirse por una inspección visual del log actual: el firmware no imprime una línea por muestra.
- P10 puede tardar hasta 20 s en detectar la pérdida de WiFi porque la comprobación ocurre al vencer el temporizador de consulta.

---

## 7. Evidencia esperada

### 7.1 Formato exacto del log de dispensación

No hay fragmentos reales porque T10 no se ha ejecutado. El formato exacto que emite el firmware es:

```text
Despacho: solicitado=%.1f g, linea_base=%s, peso_final=%s, incremento=%s, motivo=%s
```

Plantilla para el camino feliz:

```text
Despacho: solicitado=<g> g, linea_base=<g> g, peso_final=<g> g, incremento=<g> g, motivo=objetivo alcanzado
```

Plantilla para el fallo al arranque:

```text
Despacho: solicitado=<g> g, linea_base=no disponible, peso_final=no disponible, incremento=no disponible, motivo=sensor no disponible
```

Plantilla para el fallo a mitad de giro:

```text
Despacho: solicitado=<g> g, linea_base=<g> g, peso_final=<g> g, incremento=<g> g, motivo=fallo del sensor durante la dispensacion
```

Plantilla para el límite de tiempo:

```text
Despacho: solicitado=<g> g, linea_base=<g> g, peso_final=<g> g, incremento=<g> g, motivo=objetivo no alcanzado
```

Los textos de motivo son literales del código; `dispensacion` aparece sin tilde en el log.

### 7.2 Otros mensajes esperados

```text
HX711 inicializado: DT=19, SCK=18.
```

```text
Consultando ordenes pendientes en el servidor...
```

```text
Servomotor en giro continuo (0°).
```

```text
Servomotor detenido en 90°.
```

```text
Validación HTTP exitosa (Status 200). Entrando en estado normal.
```

```text
Orden recibida: [reset_wifi = true]. Borrando credenciales NVS y reiniciando en modo BLE.
```

### 7.3 Evidencia mínima por prueba

| Prueba | Evidencia |
|---|---|
| P1 | Salida de `pio test -e native` y `pio run`; confirmación de carga. |
| P2 | Tabla de raw vacío y con peso patrón; valores finales de factor y signo. |
| P3 | Tres líneas `Despacho:` y tres mediciones en báscula externa. |
| P4 | Línea `Despacho:` con `objetivo no alcanzado` y tiempo medido. |
| P5 | Línea `Despacho:` con `sensor no disponible` y video del servo inmóvil. |
| P6 | 5–10 líneas `Despacho:` con fallo de sensor y video con cronómetro. |
| P7 | Línea `Despacho:` sin fallo de sensor o anotación de no concluyente. |
| P8 | Captura de SCK/DOUT o tabla de contadores temporales. |
| P9 | Monitor con BLE, conexión y validación 200. |
| P10 | Monitor con pérdida, reconexión o rollback, y validación posterior. |
| P11 | Monitor con borrado de NVS y aparición de `PDAM-Config-<MAC>`. |
| P12 | Log con marcas de tiempo o cronómetro entre el fin y la siguiente consulta. |

No adjuntar credenciales, tokens, direcciones IP reales ni MAC reales en capturas o transcripciones.

---

## 8. Registro de resultados

Rellenar únicamente después de ejecutar cada prueba. No completar con valores supuestos.

| Fecha | Prueba | Resultado (aprobado / fallido / no concluyente) | Medición | Log o evidencia | Notas |
|---|---|---|---|---|---|
|  | P1 |  |  |  |  |
|  | P2 |  |  |  |  |
|  | P3 |  |  |  |  |
|  | P4 |  |  |  |  |
|  | P5 |  |  |  |  |
|  | P6 |  |  |  |  |
|  | P7 |  |  |  |  |
|  | P8 |  |  |  |  |
|  | P9 |  |  |  |  |
|  | P10 |  |  |  |  |
|  | P11 |  |  |  |  |
|  | P12 |  |  |  |  |

---

## 9. Criterios de aprobado y fallido

### 9.1 Aprobado

Se considera aprobado cuando:

- P1 pasa con 65/65 y `pio run` SUCCESS.
- P2 deja un factor positivo y un signo coherente, con lectura verificada contra peso patrón.
- P3 entrega 50–55 g en las tres repeticiones y el log muestra el incremento correspondiente.
- P4 detiene el servo a los 30 s, sin superar el límite, y registra `objetivo no alcanzado`.
- P5 no mueve el servo y registra `sensor no disponible` en un máximo de 2 s.
- P6 detiene el servo en menos de 1 s en todas las repeticiones y registra el fallo de sensor.
- P8 demuestra al menos 5 intentos de lectura por segundo.
- P9, P10 y P11 no muestran regresiones de BLE, WiFi, validación de servidor ni reseteo.
- P12 muestra la siguiente consulta aproximadamente 20 s después del fin.
- El log de las pruebas está en español, sin emojis y sin credenciales ni datos sensibles.
- P7 es opcional; si se ejecuta, no debe detener el ciclo por una inválida aislada.

### 9.2 Fallido

Se considera fallido si ocurre cualquiera de estos casos:

- El servo se mueve con el módulo HX711 desconectado al arranque.
- El servo sigue girando más de 1 s después de la primera de las 3 lecturas inválidas.
- El servo supera los 30 s de giro.
- La dispensación de 50 g entrega menos de 50 g o más de 55 g de forma sostenida.
- El log no incluye los cinco campos o usa un motivo distinto al definido.
- El log contiene emojis, credenciales o datos sensibles.
- La consulta siguiente ocurre de inmediato o el dispositivo se reinicia tras dispensar.
- El aprovisionamiento BLE, la reconexión WiFi o el reseteo de credenciales dejan de funcionar.

### 9.3 Qué hacer si falla

- **No cambiar la lógica de las 3 lecturas para "arreglar" un sobrepeso.** Esa lógica evita paradas por ruido; el sobrepeso suele venir de calibración, mecánica, vibración o alimento que sigue cayendo después de detener el servo.
- Revisar primero la calibración con el [informe de calibración](informe-calibracion-hx711-2026-10-23.md).
- Revisar el montaje de la celda, los roces de la bandeja, la fijación del servo y el flujo del tornillo sin fin.
- Si el fallo es de detección de sensor, confirmar que se desconectó el **módulo completo** y no solo la celda.
- Si la frecuencia de muestreo es baja, revisar el cableado, la alimentación y el modo de salida del HX711 antes de tocar el periodo.
- Registrar el log completo, la medición externa y la repetición exacta; reportar al revisor sin marcar T10 como completada.
- Si el sobrepeso es por alimento en caída después de la parada, documentarlo: el plan de la Spec 013 admite hasta 10 % de sobrepeso (55 g para una orden de 50 g), pero por encima de ese límite la prueba falla.

---

## 10. Seguridad

- Mantener las manos, el cabello y la ropa lejos del tornillo sin fin, del servo y de la salida de alimento.
- Ante un giro descontrolado, **cortar la alimentación del servo**; no depender solo de un comando de software.
- Desconectar la alimentación antes de cambiar cables, mover la celda o ajustar el montaje.
- No superar los 5 kg de la celda; incluir el peso de la bandeja en el límite.
- Usar una fuente externa adecuada para el servo y verificar la masa común antes de energizar.
- No probar con la mascota presente ni con las manos dentro del dispensador.
- Asegurar los cables para que no se enganchen en partes móviles.
- No dejar el banco de pruebas desatendido durante una dispensación.

---

## 11. Cierre y trazabilidad

Cuando todas las pruebas obligatorias pasen:

1. Actualizar `MEMORY.md` con el estado de T10, los valores finales de calibración y los pendientes que queden.
2. Marcar T10 como `[x]` en [`tasks.md`](../../specs/013-dispensado-por-peso-hx711/tasks.md).
3. Actualizar el estado de la [spec 013](../../specs/013-dispensado-por-peso-hx711/spec.md) para reflejar que la validación física está completa.
4. Adjuntar la evidencia y este informe al registro de la spec.
5. Commitear solo si el usuario lo solicita.

Mientras T10 no se ejecute, debe permanecer como `[ ]` y la spec debe seguir indicando que la validación física está pendiente. Este informe no modifica `MEMORY.md`, `tasks.md`, la spec ni el firmware.
