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
| Estado | **Parcialmente ejecutadas (2026-10-24)** |
| Motivo | Se ejecutó el arranque BLE/WiFi/HTTP y el camino de verificación/objetivo con el firmware corregido; faltan la exactitud con alimento real y las pruebas de fallo y no regresión |
| Incidencia previa (2026-10-24) | Primera prueba física fallida por calibración (factor y signo incorrectos). Corregida; ver §2.3 |
| Ejecución parcial (2026-10-24) | 12 ciclos con verificación superada y motivo `objetivo alcanzado`, con carga manual por falta de alimento seco; ver §2.5 |
| Informe relacionado | [Calibración de la celda de carga (HX711)](informe-calibracion-hx711-2026-10-23.md) |

> Este documento es un procedimiento de prueba con un registro parcial de resultados. La ejecución del 2026-10-24 (§2.5) cubre el arranque BLE/WiFi/HTTP y el camino de verificación/objetivo con carga manual; **no hay evidencia completa de T10**: falta la exactitud con alimento real, las pruebas de fallo de sensor, el muestreo y la no regresión, entendida esta última como P10 (reconexión WiFi/rollback) y P11 (`reset_wifi`); P9 (aprovisionamiento BLE, WiFi y HTTP 200) sí se observó. Los fragmentos de log de §7.1 y §7.2 son plantillas de formato salvo donde se indique lo contrario; el log de la incidencia del §2.3 y las líneas citadas en §2.5 corresponden a ejecuciones reales.

---

## 2. Resumen

La Spec 013 sustituye el dispensado por tiempo fijo de 10 segundos por un dispensado por peso medido con una celda de carga de 5 kg y un amplificador HX711. El firmware ya está implementado y la lógica pura está cubierta por pruebas nativas. La validación física es parcial (2026-10-24): el ciclo completo funciona con carga aplicada a mano, pero la exactitud con alimento real y las pruebas de fallo siguen pendientes.

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

Según la verificación registrada en `tasks.md` el 2026-10-24, tras la corrección de calibración:

- **T1–T9 cerradas.** `pio test -e native` pasa **136/136** (110 `test_dispensing_utils`, 21 `test_dispensing_cycle` y 5 `test_provisioning_utils`) y `pio run` en `esp32dev` termina en **SUCCESS** (RAM 19.7 %, Flash 63.8 %).
- **T10 parcialmente ejecutada.** El firmware corregido se flasheó el 2026-10-24 y el arranque BLE/WiFi/HTTP y el camino de verificación/objetivo funcionaron (§2.5). Siguen pendientes la exactitud con alimento real, los fallos de sensor, la frecuencia de muestreo y la no regresión de P10 (reconexión WiFi/rollback) y P11 (`reset_wifi`); P9 (aprovisionamiento BLE, WiFi y HTTP 200) sí se observó. La primera prueba física falló por calibración y se corrigió el 2026-10-24 (§2.3).
- La única dependencia nueva es `bogde/HX711 @ ^0.7.5`; el resto del firmware conserva el comportamiento anterior salvo el reemplazo explícito del dispensado por tiempo.

> Nota de conteos: el 136/136 de esta sección (110 `test_dispensing_utils`, 21 `test_dispensing_cycle` y 5 `test_provisioning_utils`) y el 136/136 del §2.3 corresponden a la ejecución del 2026-10-24. El estado actual de la suite nativa es **137/137** con **22** pruebas de `test_dispensing_cycle`.

La comprobación física de RF-5, RF-9, RF-11, RF-12, RF-13, RNF-1, RNF-4 y RNF-5, la exactitud de 50 g y la no regresión quedan exclusivamente en este checklist.

### 2.3 Incidencia detectada en la primera prueba y corrección aplicada

Log observado en la primera prueba física, repetido en cada consulta:

```text
HX711 inicializado: DT=19, SCK=18.
Despacho: solicitado=50.0 g, linea_base=no disponible, peso_final=no disponible, incremento=no disponible, motivo=sensor no disponible
```

El servo no se movió y el firmware cerró la ventana de verificación con `sensor no disponible` aunque el módulo HX711 respondía. Un sketch independiente leyó el sensor y confirmó que la celda y el servo funcionan: RAW ≈ 160658 con la bandeja vacía y ≈ 260500 con ~206.8 g (≈ 482.7 cuentas/g, signo `+1`).

**Causa raíz.** El firmware tenía el placeholder del plan: factor `7050` y signo `-1`. Con el RAW real de ≈ 160658, la conversión daba ≈ −22.8 g, fuera del rango válido de 0–5000 g, así que `isReadingValid` descartaba todas las lecturas y la línea base nunca se completaba. No era un problema de sensor ni de cableado.

**Corrección aplicada.**

- `DispensadorESP32/src/config/config.h`: `hx711CalibrationFactor = 482.7f` y `hx711RawSign = 1.0f`.
- `initHx711()` imprime ahora factor y signo al inicializar, para que el log muestre la calibración activa.
- La ventana de verificación imprime un diagnóstico cuando falla.
- 7 pruebas nativas nuevas con los valores reales: `pio test -e native` pasa 136/136.

**Valores esperados con la corrección.** Con la bandeja vacía, la conversión absoluta es ≈ 332.8 g (línea base). Para 50 g el objetivo es ≈ 382.8 g y el RAW objetivo ≈ 184793 (`160658 + 50 × 482.7 = 184793`). Son cálculos, no mediciones de dispensación: deben confirmarse en P3.

**Diagnóstico nuevo al fallar la verificación.** El firmware imprime, solo cuando la verificación falla:

```text
Verificacion HX711: muestras=<n>, respondidas=<n>, validas=<n>, invalidas_consecutivas=<n>, ultimo_raw=<entero|sin_lectura>, ultimo_g=<g|sin_lectura>, factor=<factor>, signo=<signo>
Causa probable: <texto>
```

Cómo interpretarlo:

| Señal en el log | Interpretación |
|---|---|
| `respondidas=0` y `Causa probable: el modulo HX711 no respondio` | El módulo no responde: revisar alimentación y DT/SCK antes de tocar la calibración |
| `respondidas > 0` y `validas=0` | No hubo ninguna lectura válida: la causa se imprime siempre que `validCount == 0`, aunque la lectura estuviera en rango y se descartara. Mirar `ultimo_raw` y `ultimo_g` para distinguir rango, saturación o calibración |
| `respondidas > 0`, `validas > 0` e `invalidas_consecutivas` alto | Ventana sin lecturas válidas suficientes: revisar estabilidad, ruido y mecánica |

Si el factor y el signo impresos no son los esperados, el firmware flasheado no es el corregido.

**Alcance.** Esto solo desbloquea la prueba: ninguna prueba P1–P13 queda aprobada solo por este cambio. La ejecución parcial posterior se registra en §2.5 y no cierra T10.

### 2.4 Modo de prueba temporal del endpoint

Para facilitar las pruebas, el endpoint `check-taks/{address_mac}` de `api/app/api/endpoints/dispenser.py`, función `check_dispenser_taks`, devuelve siempre `{"serve": true, "amount": 50}` y la llamada real a `dispenser_service.check_pending_task(...)` está comentada. Ese estado **está commiteado** en la rama `pruebas/endpoint-fijo-hx711` (commit `b009a5b`) y el árbol de `api/` está limpio (`git diff HEAD -- api/` vacío). Antes de mergear a `main` hay que restaurar `check_pending_task` y **commitear esa restauración**.

Consecuencia: el ESP32 recibe una orden cada 20 s sin necesidad de horario, de `pending_dispensing` ni del endpoint `check-taks-test`, y **repetirá la dispensación de 50 g cada 20 s** mientras esté encendido.

Advertencias:

- No dejar el banco desatendido; el ciclo se repite indefinidamente.
- Mantener depósito con alimento y bandeja colocada para no forzar el tope de 30 s una y otra vez.
- Cortar la alimentación del servo si algo va mal; no depender del software.
- Este modo no descuenta stock, no limpia banderas ni respeta `reset_wifi`; sirve solo para observar el ciclo de peso.
- Está commiteado en la rama `pruebas/endpoint-fijo-hx711` en el commit `b009a5b`. Antes de mergear a `main` hay que restaurar `return dispenser_service.check_pending_task(...)` en `check_dispenser_taks`.
- Mientras esté activo, los procedimientos por SQLite (§5.2) y `check-taks-test` (§5.3) no aportan nada distinto: el resultado es siempre `serve:true` con 50 g.

### 2.5 Resultados de la ejecución parcial (2026-10-24)

Ejecución con el firmware corregido (`Build actual de compilacion: Oct 24 2026 23:14:35`) y el modo de prueba del §2.4 activo: el endpoint devolvió `{"serve":true,"amount":50}` en cada consulta. El usuario no disponía de alimento seco, así que aplicó la carga **ejerciendo presión manual sobre la celda**. Eso permite validar el ciclo de verificación y la detección del objetivo, pero **no** la exactitud.

**Arranque y aprovisionamiento.** Al flashear se limpió la NVS y el equipo entró en aprovisionamiento BLE como `PDAM-Config-<MAC>`. Recibió SSID y contraseña por BLE, conectó a WiFi, validó el servidor con código 200 y entró en estado normal. La inicialización del sensor quedó así:

```text
HX711 inicializado: DT=19, SCK=18, factor=482.7, signo=+1.0.
```

**Ciclos de dispensación.** Doce ciclos consecutivos, todos con motivo `objetivo alcanzado`:

| Ciclo | Línea base (g) | Peso final (g) | Incremento (g) | Motivo |
|---|---|---|---|---|
| 1 | 333.1 | 803.6 | 470.5 | objetivo alcanzado |
| 2 | 333.1 | 453.9 | 120.8 | objetivo alcanzado |
| 3 | 333.1 | 490.5 | 157.4 | objetivo alcanzado |
| 4 | 359.7 | 412.3 | 52.6 | objetivo alcanzado |
| 5 | 333.1 | 399.3 | 66.2 | objetivo alcanzado |
| 6 | 333.1 | 385.5 | 52.4 | objetivo alcanzado |
| 7 | 421.7 | 686.4 | 264.8 | objetivo alcanzado |
| 8 | 333.1 | 863.5 | 530.5 | objetivo alcanzado |
| 9 | 333.1 | 689.4 | 356.3 | objetivo alcanzado |
| 10 | 333.1 | 529.8 | 196.7 | objetivo alcanzado |
| 11 | 333.1 | 408.1 | 75.1 | objetivo alcanzado |
| 12 | 333.1 | 385.4 | 52.4 | objetivo alcanzado |

La línea base más el incremento coincide con el peso final salvo ±0.1 g en algunos ciclos, por el redondeo a un decimal de los valores impresos por el firmware.

**Comprobaciones ejecutadas.**

| Comprobación | Observación real | Estado |
|---|---|---|
| Flasheo del build corregido | `Build actual de compilacion: Oct 24 2026 23:14:35` en el arranque | Ejecutada |
| Borrado de NVS | El equipo arrancó sin credenciales y entró en aprovisionamiento | Ejecutada |
| Aprovisionamiento BLE | Anunció `PDAM-Config-<MAC>` y aceptó SSID y contraseña | Ejecutada |
| Conexión WiFi | Conectó a la red local tras el aprovisionamiento | Ejecutada |
| Validación HTTP | `Validación HTTP exitosa (Status 200). Entrando en estado normal.` | Ejecutada |
| Inicialización del HX711 | `HX711 inicializado: DT=19, SCK=18, factor=482.7, signo=+1.0.` | Ejecutada |
| Verificación de la celda | 12/12 ciclos superados; no apareció `sensor no disponible` | Ejecutada |
| Giro del servo | Arrancó y se detuvo en los 12 ciclos | Ejecutada |
| Detección del objetivo | Motivo `objetivo alcanzado` en los 12 ciclos | Ejecutada |
| Respuesta del endpoint de prueba | `{"serve":true,"amount":50}` en cada consulta | Ejecutada |

**Limitación de la medición.**

- Sin alimento seco, la carga se aplicó con presión manual sobre la celda, no con croquetas cayendo por el tornillo sin fin.
- Por eso los incrementos (52.4 g a 530.5 g) **no son una medición de exactitud** ni permiten evaluar el criterio de 50–55 g: dependen de cuánta presión aplicó el usuario y de cuándo la retiró.
- La línea base de 359.7 g y 421.7 g en dos ciclos refleja peso residual sobre la bandeja al iniciar el ciclo, no una deriva de la calibración; el firmware la cancela con la mediana de la ventana de verificación.
- El log serie no incluye marcas de tiempo, así que el intervalo de 20 s no está medido.

**Qué sigue pendiente.** Estas pruebas **no se ejecutaron y no se marcan como aprobadas**:

- **P3 con alimento real**: 50 g solicitados deben entregar 50–55 g medidos en una báscula externa, en tres repeticiones con la bandeja limpia.
- **P5**: fallo de sensor al arranque desconectando el módulo HX711 del ESP32.
- **P6**: fallo de sensor a mitad del giro.
- **P7**: inválida aislada sin detener el ciclo.
- **P8**: frecuencia de muestreo de al menos 5 Hz.
- **P10**: reconexión WiFi y rollback a aprovisionamiento BLE.
- **P11**: `reset_wifi` y su prioridad sobre `serve`.
- **P12**: intervalo de 20 s tras el fin del ciclo, con marcas de tiempo externas.
- **P13**: rechazo de una orden de dispensación inválida sin mover ni retroceder el servo.

Tampoco se completaron P2 (verificación con peso patrón de 500 g o 1 kg) ni P4 (tope de 30 s con depósito vacío): la línea base ≈ 333.1 g solo confirma coherencia en reposo.

**Conclusión.** La corrección de calibración desbloquea la dispensación: la verificación pasa, el servo arranca y se detiene y el objetivo se detecta en 12 de 12 ciclos; el fail-safe `sensor no disponible` ya no se dispara por error. La exactitud con alimento real y las pruebas de fallo físico siguen pendientes, por lo que **T10 permanece abierto**.

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
4. Cuando se restaure la implementación real, la orden descuenta stock y limpia la bandera al entregarse.

Este es el flujo recomendado para el checklist principal porque valida el camino completo app → backend → firmware. Mientras siga activo el modo de prueba del §2.4, los pasos 1–2 no hacen falta y el punto 4 no se cumple; restaurar el endpoint antes de usar este flujo como evidencia.

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
- Cuando se restaure la implementación real, el endpoint **descuenta stock y limpia `pending_dispensing`** al entregar la orden. Para cada repetición hay que volver a ejecutar el `UPDATE` o reabastecer.
- Con el modo de prueba del §2.4 activo, este procedimiento no tiene efecto: el endpoint devuelve `serve:true` con 50 g aunque `pending_dispensing` esté a 0. Sirve como alternativa solo después de restaurar el endpoint.
- No editar la base de datos con el backend en ejecución.

### 5.3 Endpoint de prueba

Cuando se restaure la implementación real, el backend expone un endpoint de prueba que devuelve la orden **sin descontar stock ni limpiar la bandera**:

```text
GET http://<IP>:8000/dispenserscheck-taks-test/<MAC>
```

Para usarlo con el firmware hay que cambiar temporalmente `BASE_URL` a:

```cpp
const char* const BASE_URL = "http://<IP>:8000/dispenserscheck-taks-test/";
```

Advertencia: mientras `pending_dispensing` siga activo, el ESP32 puede **repetir la dispensación cada 20 segundos**. No se recomienda para el checklist principal; sirve para depurar la respuesta HTTP o para una prueba aislada. Después de usarlo, restaurar `BASE_URL` y recompilar.

Con el modo de prueba del §2.4 activo, este endpoint y el real devuelven lo mismo (`serve:true`, 50 g); cambiar `BASE_URL` no aporta nada distinto. Es una alternativa válida solo tras restaurar la implementación real.

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

## 6. Checklist P1–P13

| ID | Requisito | Objetivo | Procedimiento | Resultado esperado | Evidencia |
|---|---|---|---|---|---|
| P1 | RNF-4, RNF-6 | Confirmar que el firmware compila, la suite nativa pasa y la placa flashea. | `cd DispensadorESP32`<br>`pio test -e native`<br>`pio run -t clean && pio run`<br>`pio run --target upload` | 137/137 en nativo; `pio run` SUCCESS; carga completa; monitor a 115200. | Salida de terminal y primeras líneas del monitor. |
| P2 | RF-11 | Calibrar la celda y verificar la conversión con un peso conocido. | Ejecutar el [informe de calibración](informe-calibracion-hx711-2026-10-23.md). Verificar con 500 g o 1 kg usando el sketch de raw. | Factor positivo (vigente `482.7`), signo coherente (`+1`), lectura que sigue al peso y error operativo no mayor que 2 % (10 g en 500 g). | Tabla de raw, valores finales de `config.h` y monitor. |
| P3 | RF-1, RF-6, RF-7, RF-12, RNF-1, RNF-2 | Validar el camino feliz de 50 g. | Bandeja vacía; solicitar 50 g; medir la comida entregada en una báscula externa; repetir 3 veces limpiando la bandeja. | 3/3 entre 50 g y 55 g; log con `incremento` en ese rango y motivo `objetivo alcanzado`; servo detenido. Si falla, el log debe mostrar `Verificacion HX711: ...` con `muestras`, `respondidas`, `ultimo_raw`, `ultimo_g`, `factor` (`482.7`) y `signo` (`+1.0`) antes de concluir la causa. | Tres líneas `Despacho:` y tres mediciones externas; si falla, la línea `Verificacion HX711:`. |
| P4 | RF-8, RNF-3 | Validar el tope de 30 s con depósito vacío. | Vaciar el depósito; solicitar 50 g; cronometrar desde el arranque del giro. | Parada a los 30 s, sin superarlos; motivo `objetivo no alcanzado`; incremento cercano a 0; ciclo total no mayor que 32 s. | Log y tiempo medido. |
| P5 | RF-4, RF-12 | Validar el fallo de sensor al arranque. | Desconectar el **módulo HX711 del ESP32** (DT/SCK; idealmente también VCC/GND), no solo la celda; reiniciar y solicitar 50 g. | El servo no se mueve; en un máximo de 2 s aparece `sensor no disponible`; línea base, peso final e incremento como `no disponible`. | Monitor y video u observación directa. |
| P6 | RF-9, RNF-3 | Validar el fallo de sensor a mitad del giro. | Con una dispensación válida en curso, desconectar el módulo HX711 durante el giro; medir desde la desconexión (cota conservadora) y, si hay instrumentación, desde la primera de las 3 lecturas inválidas. Repetir 5–10 veces. | Parada en menos de 1 s desde la primera inválida y, en la práctica, en menos de 1 s desde la desconexión; motivo `fallo del sensor durante la dispensacion`; sin esperar los 30 s. | Logs y video con cronómetro. |
| P7 | RF-9 (inválida aislada) | Confirmar que una inválida aislada no detiene el ciclo. | Aflojar un cable de la celda durante el giro menos de 3 muestras (menos de 600 ms) y reconectarlo. | El ciclo continúa; no aparece el motivo de fallo de sensor. Si no se genera una inválida, registrar `no concluyente` porque el módulo puede entregar lecturas plausibles. | Log de la dispensación. |
| P8 | RNF-1 | Medir la frecuencia de muestreo. | Analizador lógico en D18 (SCK) y D19 (DT/DOUT); medir ráfagas y periodo. Sin instrumento, usar instrumentación temporal no commiteada. | Al menos 5 intentos de lectura por segundo; en 2 s, al menos 10 intentos y al menos 5 válidas en la verificación; periodo no mayor que 200 ms. | Captura del analizador o contadores temporales. |
| P9 | RF-13 | Confirmar que el aprovisionamiento BLE no tiene regresiones. | Flashear un build nuevo para forzar el borrado de NVS por cambio de `build_stamp` (o ejecutar P11); arrancar sin credenciales; aprovisionar desde la app; esperar la conexión WiFi y la validación HTTP. | Aparece `PDAM-Config-<MAC>`; WiFi conectado; `Validación HTTP exitosa (Status 200). Entrando en estado normal.`; el servo no se mueve. | Monitor y app. |
| P10 | RF-13 | Confirmar la reconexión WiFi y el rollback a BLE. | Con WiFi conectado, apagar el router; esperar la detección y el intento de reconexión; restaurar el router. Repetir una vez con el router restaurado antes de la ventana de 10 s y otra después, para observar ambos caminos. | Si vuelve a tiempo: `Reconexion WiFi exitosa` y validación 200. Si no: rollback a aprovisionamiento BLE. Sin movimiento del servo. | Monitor y estado del router. |
| P11 | RF-10, RF-13 | Confirmar el reseteo de credenciales y su prioridad. | Requiere el endpoint real `check_pending_task` restaurado y commiteado (ver §11, paso 0); con el endpoint fijo activo el equipo dispensaría 50 g en lugar de procesar `reset_wifi`.<br>Desde la app o `POST /dispensers/{id}/reset-wifi` con sesión autenticada, con el equipo inactivo; opcionalmente poner también `pending_dispensing = 1` para probar la prioridad. Limpiar esa bandera al terminar si se dejó activa. | NVS borrada; reinicio; aparece `PDAM-Config-<MAC>`; el servo no se mueve; `reset_wifi` gana sobre `serve`. | Monitor. |
| P12 | RF-13 | Confirmar que la siguiente consulta ocurre 20 s después del fin. | Tras una dispensación, medir el tiempo hasta el siguiente `Consultando ordenes pendientes en el servidor...`. | Aproximadamente 20 s después del fin (20–21 s), no inmediato; sin reinicio del dispositivo. | Log con marcas de tiempo externas o cronómetro. |
| P13 | RF-17 | Confirmar que una orden de dispensación inválida no mueve el servo ni provoca retroceso. | La orden inválida no se puede provocar desde el servidor: `check-taks/{address_mac}` es un endpoint fijo de depuración que no lee la base de datos y el esquema rechaza `amount` menor o igual que 0. Hay que editar el endpoint de forma temporal.<br>1. Con el servidor parado, editar temporalmente `api/app/api/endpoints/dispenser.py` para que `check-taks/{address_mac}` devuelva `{"serve": True, "amount": -5}`.<br>2. Arrancar el servidor (`cd api && uvicorn app.main:app --reload --port 8000 --host 0.0.0.0`), dejar que el ESP32 consulte y observar el log serie.<br>3. Resultado esperado: `Advertencia: orden de dispensacion invalida. No se mueve el servo.`, el servo no gira ni retrocede y el ciclo no se ejecuta.<br>4. Repetir con `{"serve": True, "amount": 0}`: el resultado esperado es `Estado: sin orden de dispensacion` (rama de reposo), sin advertencia y sin movimiento del servo. Este segundo caso no ejercita la rama `INVALID_ORDER`, solo confirma el reposo.<br>5. Restaurar el endpoint al contenido commiteado en la rama de pruebas, `{"serve": True, "amount": 50}`, y confirmar con `git diff api/` que el backend queda sin cambios.<br>Advertencia: el endpoint fijo de depuración está commiteado en la rama de pruebas (commit `b009a5b`) y debe restaurarse a `check_pending_task` antes de mergear a `main`.<br>Nota: la edición del endpoint es un cambio temporal de prueba; no debe commitearse. | Con `amount` negativo el ESP32 rechaza la orden: no gira el servo, no retrocede, el ciclo no se ejecuta y el log muestra `Advertencia: orden de dispensacion invalida. No se mueve el servo.` Con `amount` igual a 0 el log muestra el reposo (`Estado: sin orden de dispensacion`), sin advertencia, y el servo tampoco se mueve ni retrocede; este caso no ejercita la rama `INVALID_ORDER`, solo confirma el reposo. | Monitor y video u observación directa del servo. |

Notas sobre criterios:

- El criterio de 2 % para el peso patrón es un criterio operativo de este informe; la spec solo fija 50–55 g para la prueba de 50 g.
- Si P3 falla, la línea `Verificacion HX711:` (muestras, RAW, gramos, factor y signo) distingue un fallo de calibración de un módulo desconectado; sin esa línea no se puede concluir la causa.
- Con la corrección vigente se espera línea base ≈ 332.8 g, objetivo ≈ 382.8 g y RAW objetivo ≈ 184793. Son cálculos; la aprobación exige la medición externa.
- P7 es opcional y puede resultar no concluyente si al aflojar solo la celda el módulo sigue entregando valores plausibles.
- P8 no puede sustituirse por una inspección visual del log actual: el firmware no imprime una línea por muestra.
- P10 puede tardar hasta 20 s en detectar la pérdida de WiFi porque la comprobación ocurre al vencer el temporizador de consulta.

---

## 7. Evidencia esperada

### 7.1 Formato exacto del log de dispensación

No hay un log de una dispensación aprobada porque T10 sigue abierto. La ejecución parcial del §2.5 produjo 12 líneas `Despacho:` con motivo `objetivo alcanzado`, pero corresponden a carga manual y el log no tiene marcas de tiempo. El otro log real es el de la incidencia del §2.3. El formato exacto que emite el firmware es:

```text
Despacho: solicitado=%.1f g, linea_base=%s, peso_final=%s, incremento=%s, reintentos=%u, motivo=%s
```

Plantilla para el camino feliz:

```text
Despacho: solicitado=<g> g, linea_base=<g> g, peso_final=<g> g, incremento=<g> g, reintentos=0, motivo=objetivo alcanzado
```

Plantilla para el fallo al arranque:

```text
Despacho: solicitado=<g> g, linea_base=no disponible, peso_final=no disponible, incremento=no disponible, reintentos=0, motivo=sensor no disponible
```

Plantilla para el fallo a mitad de giro:

```text
Despacho: solicitado=<g> g, linea_base=<g> g, peso_final=<g> g, incremento=<g> g, reintentos=<n>, motivo=fallo del sensor durante la dispensacion
```

Plantilla para el límite de tiempo:

```text
Despacho: solicitado=<g> g, linea_base=<g> g, peso_final=<g> g, incremento=<g> g, reintentos=<n>, motivo=objetivo no alcanzado
```

Plantilla para el atasco no resuelto:

```text
Despacho: solicitado=<g> g, linea_base=<g> g, peso_final=<g> g, incremento=<g> g, reintentos=<n>, motivo=atasco no resuelto
```

Los textos de motivo son literales del código; `dispensacion` aparece sin tilde en el log. `reintentos` siempre se imprime: las salidas tempranas (orden inválida, calibración inválida o sensor no disponible) muestran `reintentos=0`.

### 7.2 Otros mensajes esperados

```text
HX711 inicializado: DT=19, SCK=18, factor=482.7, signo=+1.0.
```

```text
Consultando ordenes pendientes en el servidor...
```

```text
Servomotor en giro continuo (0°).
```

```text
Servomotor en retroceso (180°) para desatascar.
```

Secuencia de un reintento (retroceso, pausa y reanudación del avance):

```text
Servomotor en retroceso (180°) para desatascar.
Servomotor detenido en 90°.
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
| P13 | Monitor con el rechazo de la orden inválida (o el reposo con `amount` 0) y video del servo inmóvil. |

No adjuntar credenciales, tokens, direcciones IP reales ni MAC reales en capturas o transcripciones.

### 7.4 Pruebas de atasco (T15)

Se ejecutan sobre el firmware final, después de las de T10, y se registran en T15 de [`tasks.md`](../../specs/013-dispensado-por-peso-hx711/tasks.md).

- **Atasco inducido:** con el servo en avance, bloquear la hélice del tornillo sin fin o cuñar una croqueta. Se espera el retroceso de 1,2 s, la pausa de 0,3 s y la reanudación; si el bloqueo persiste, el motivo es `atasco no resuelto` con el incremento logrado y `reintentos` mayor que 0.
- **Atasco resuelto:** liberar el bloqueo durante un reintento. Se espera `objetivo alcanzado` con `reintentos` mayor que 0.
- **Dispensación normal:** sin bloqueo, se espera `objetivo alcanzado` con `reintentos=0`, como no regresión del camino feliz.
- **Peso de la bandeja:** medir antes y después de cada retroceso. El peso no debe disminuir, porque el giro inverso no retira alimento de la bandeja.
- **Cota y muestreo:** el ciclo de motor no supera 30 s ni el completo 32 s, y se observan al menos 5 lecturas por segundo también en retroceso y pausa.

---

## 8. Registro de resultados

Rellenar únicamente después de ejecutar cada prueba. No completar con valores supuestos. Las pruebas que no se ejecutaron quedan como «No ejecutada».

| Fecha | Prueba | Resultado (aprobado / fallido / no concluyente) | Medición | Log o evidencia | Notas |
|---|---|---|---|---|---|
| 2026-10-24 | P1 | aprobado | `pio test -e native` 72/72 en esa ejecución; suite vigente 137/137; `pio run` SUCCESS (RAM 19.7 %, Flash 63.8 %) | Build `Oct 24 2026 23:14:35` en el arranque | Carga completa y arranque correctos; en esta sesión no se repitió `pio run -t clean` |
| — | P2 | No ejecutada | Línea base ≈ 333.1 g en reposo | §2.5 | Factor `482.7` y signo `+1.0` impresos; 160658 / 482.7 ≈ 332.83 g es coherente, pero falta la comprobación con peso patrón de 500 g o 1 kg |
| 2026-10-24 | P3 | no concluyente | 12 ciclos con `objetivo alcanzado`; incrementos de 52.4 g a 530.5 g | §2.5 | Carga por presión manual, sin alimento seco ni báscula externa: no valida el criterio de 50–55 g |
| — | P4 | No ejecutada | — | — | No se forzó el tope de 30 s con depósito vacío |
| — | P5 | No ejecutada | — | — | Pendiente desconectar el módulo HX711 del ESP32 al arranque |
| — | P6 | No ejecutada | — | — | Pendiente desconectar el módulo HX711 durante el giro |
| — | P7 | No ejecutada | — | — | Prueba opcional; no se intentó una inválida aislada |
| — | P8 | No ejecutada | — | — | Sin analizador lógico ni contadores temporales; el log no imprime una línea por muestra |
| 2026-10-24 | P9 | aprobado | `PDAM-Config-<MAC>`, WiFi conectado, `Validación HTTP exitosa (Status 200)` | §2.5 | NVS limpia al flashear; el servo no se movió durante el aprovisionamiento. El canal BLE y la recepción de credenciales se observaron por el monitor serie, pero no se registró si el cliente fue la app móvil; queda como evidencia parcial |
| — | P10 | No ejecutada | — | — | No se cortó el router para observar reconexión ni rollback |
| — | P11 | No ejecutada | — | — | No se probó `reset_wifi` ni su prioridad |
| — | P12 | No ejecutada | — | — | El log no incluye marcas de tiempo; el intervalo de 20 s no está medido |
| — | P13 | No ejecutada | — | — | No se editó el endpoint para forzar la orden inválida |

---

## 9. Criterios de aprobado y fallido

### 9.1 Aprobado

Se considera aprobado cuando:

- P1 pasa con 137/137 y `pio run` SUCCESS.
- P2 confirma factor `482.7` y signo `+1` con lectura verificada contra peso patrón.
- P3 entrega 50–55 g en las tres repeticiones y el log muestra el incremento correspondiente. Si falla, el registro incluye el diagnóstico `Verificacion HX711:` con RAW, gramos, factor y signo.
- P4 detiene el servo a los 30 s, sin superar el límite, y registra `objetivo no alcanzado`.
- P5 no mueve el servo y registra `sensor no disponible` en un máximo de 2 s.
- P6 detiene el servo en menos de 1 s en todas las repeticiones y registra el fallo de sensor.
- P8 demuestra al menos 5 intentos de lectura por segundo.
- P9, P10 y P11 no muestran regresiones de BLE, WiFi, validación de servidor ni reseteo.
- P12 muestra la siguiente consulta aproximadamente 20 s después del fin.
- P13 no mueve ni retrocede el servo con una orden de dispensación inválida.
- El log de las pruebas está en español, sin emojis y sin credenciales ni datos sensibles.
- P7 es opcional; si se ejecuta, no debe detener el ciclo por una inválida aislada.

### 9.1.1 Estado tras la ejecución parcial (2026-10-24)

La ejecución del §2.5 **no cumple el criterio de aprobado** y no cierra T10:

- P1 y P9 se pueden registrar como aprobadas con la evidencia disponible.
- P3 queda `no concluyente`: hubo `objetivo alcanzado` en 12/12 ciclos, pero con presión manual sobre la celda y sin medición externa. El rango observado de incrementos (52.4 g a 530.5 g) no evalúa la exactitud de 50–55 g.
- P2, P4, P5, P6, P7, P8, P10, P11, P12 y P13 siguen sin ejecutar.
- La exactitud con alimento real es la prueba que decide el cierre: mientras no se mida en báscula externa, la spec no puede declararse validada físicamente.

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
- Si el log repite `sensor no disponible` aunque el módulo responde, leer la línea `Verificacion HX711:`: `respondidas=0` apunta al módulo o al cableado, mientras que `validas=0` con `factor` y `signo` impresos apunta a la calibración. Fue la causa de la incidencia del §2.3.
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

0. Orden del endpoint fijo. Hay dos cambios distintos que no deben confundirse:
   - **La restauración de `check_pending_task` sí se commitea.** Antes de mergear `pruebas/endpoint-fijo-hx711` a `main`, restaurar `return dispenser_service.check_pending_task(...)` en `check_dispenser_taks` y commitear esa restauración: es el cambio previo al merge (ver §2.4).
   - **La edición temporal de P13 no se commitea.** Al terminar P13 hay que devolver el endpoint al contenido commiteado en la rama de pruebas, `{"serve": True, "amount": 50}`, y comprobar que `git diff api/` queda vacío.
   - **Orden de ejecución:** P13 se ejecuta con el endpoint fijo activo; P11 se ejecuta **después** de restaurar y commitear `check_pending_task`, porque con el endpoint fijo el equipo dispensaría 50 g en lugar de procesar `reset_wifi`.
1. Actualizar `MEMORY.md` con el estado de T10, los valores finales de calibración y los pendientes que queden.
2. Marcar T10 como `[x]` en [`tasks.md`](../../specs/013-dispensado-por-peso-hx711/tasks.md).
3. Actualizar el estado de la [spec 013](../../specs/013-dispensado-por-peso-hx711/spec.md) para reflejar que la validación física está completa.
4. Adjuntar la evidencia y este informe al registro de la spec.
5. Commitear solo si el usuario lo solicita.

Mientras T10 no se complete, debe permanecer como `[ ]` y la spec debe seguir indicando que la validación física está pendiente. La ejecución del 2026-10-24 es parcial (§2.5) y no autoriza ese cierre. Este informe no modifica el firmware ni la spec; el registro de la ejecución parcial en `MEMORY.md` y `tasks.md` se hace fuera de este documento.

---

## 12. Prueba física con alimento real (2026-10-27)

Montaje: firmware con T1–T14, croqueta de ~3 cm de tamaño, balanza sin calibrar.

| # | Se trabó | Incremento (g) | `reintentos` | Motivo |
|---|---|---|---|---|
| 1 | sí | 57.3 | 1 | objetivo alcanzado |
| 2 | sí | 55.2 | 1 | objetivo alcanzado |
| 3 | no | 54.5 | 0 | objetivo alcanzado |
| 4 | sí | 54.9 | 1 | objetivo alcanzado |
| 5 | sí | 52.4 | 1 | objetivo alcanzado |

Las cinco dispensaciones fueron de 50 g y las cinco terminaron con «objetivo
alcanzado».

Conclusión:

- La detección y el retroceso fueron correctos en 4 de 4 atascos reales: cada uno
  se declaró, se ejecutó el retroceso y la dispensación siguió hasta el objetivo
  con `reintentos=1`.
- El tercer ciclo, el que no se trabó, dio `reintentos=0` y también alcanzó el
  objetivo, de modo que la detección distinguió el ciclo limpio.
- El atasco frecuente con croqueta de ~3 cm es una limitación mecánica del paso de
  la hélice y no un fallo de la detección; por ese motivo no se ajustan umbrales y
  la ventana de gracia se mantiene en 2 s. Los incrementos no se usan como prueba
  de exactitud porque la balanza no está calibrada.

Pendientes que quedan en T15:

- Atasco inducido persistente con motivo «atasco no resuelto», incremento y
  `reintentos` en el log.
- Peso de la bandeja antes y después del retroceso.
- Tiempos del ciclo de motor (≤ 30 s) y del ciclo completo (≤ 32 s).
- Al menos 5 lecturas por segundo en avance, retroceso y pausa.
- Revisión del acoplamiento del tornillo sin fin.
- Repetición de la dispensación normal con alimento que el tornillo transporta sin
  trabarse, como confirmación del ciclo limpio ya observado y no como primera
  obtención de `reintentos=0`.
- Checklist de no regresión de BLE, WiFi, reconexión, validación de servidor, reset
  de credenciales y consulta 20 s después del fin.
- `MEMORY.md` actualizado con el cierre de T15.
