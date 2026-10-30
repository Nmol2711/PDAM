# Spec 016 — Validación de línea base y plausibilidad del dispensado

Estado: borrador

## Contexto y objetivo

El 2026-10-30, tras un arranque, la 013 aceptó una línea base de 0,0 g por caer en el rango 0–5000 g; al terminar el
ciclo la lectura absoluta era 364,7 g para una orden de 17,27 g, el firmware declaró «objetivo alcanzado» y el
servidor descontó 364,66 g. La base era un cero real de la celda, nada acotaba el incremento y la 014 aplicó lo que
recibió. La 013 no exige asentamiento tras el arranque ni tope de plausibilidad.

Objetivo: que la celda deba estar asentada para abrir una dispensación —sin dejar de consultar al servidor—, que un
incremento imposible cierre el ciclo como fallo sin más servo ni éxito, que no se descuente stock y que no se alteren
umbrales, ventanas, presupuesto ni reintentos de la 013.

## Usuarios

- **Dueño de mascota:** recibe la ración pedida y su stock no cae por una medición errónea.
- **Desarrollador:** distingue en el log serie un sensor sin asentar, uno desconectado, un salto imposible y una
  pérdida de masa, sin perseguir un atasco inexistente.

## Historias de usuario

- HU-1. Como dueño de mascota, quiero que no se sirva nada si la báscula no está lista, y que ese intento quede
  registrado como fallo en mi historial, para saber que la comida no salió justo después de encender.
- HU-2. Como dueño de mascota, quiero que un peso imposible cierre el ciclo como fallo para que no se descuente stock
  por alimento que no salió.
- HU-3. Como desarrollador, quiero ver en el log la línea base, el tope, el suelo y la causa del rechazo para corregir
  el montaje sin confundirlo con un atasco.

## Definiciones

- **Lectura válida:** la que la 013 acepta: la celda responde dentro de los 100 ms siguientes al intento, el valor es
  finito, está en 0–5000 g y el ADC no está saturado.
- **Asentamiento:** estado que se gana con una racha de 15 lecturas válidas consecutivas (≈3 s con el muestreo de
  5 lecturas por segundo de la 013) en la que el paso entre cada dos lecturas válidas consecutivas es de 1 g como
  máximo. Es un estado que se gana y se pierde: se pierde al romperse la racha por un paso mayor de 1 g, al acumular
  3 lecturas inválidas consecutivas, al iniciarse un ciclo de dispensación —durante el ciclo el muestreo de
  asentamiento no corre y la celda cambia de peso— y, por decisión explícita, tras un cierre por tope, por suelo o por
  3 lecturas inválidas consecutivas. Se evalúa en segundo plano de forma continua desde el arranque, fuera del ciclo
  de motor, de modo que no añade tiempo muerto al ciclo ni retrasa la consulta periódica.
- **Paso entre lecturas consecutivas:** diferencia absoluta en gramos entre una lectura válida y la lectura válida
  inmediatamente anterior de la misma racha. No es la diferencia entre el máximo y el mínimo del conjunto.
- **Línea base:** mediana de **todas** las lecturas válidas de la ventana de verificación de 2 s de la 013, calculada
  igual que en la 013. Las últimas 5 lecturas válidas solo se usan como condición de estabilidad, no como conjunto de
  la mediana.
- **Tope de plausibilidad:** mayor entre 3 veces la cantidad solicitada y la solicitada más 10 g; para 17,27 g son
  51,81 g. El incremento **supera** el tope solo si es estrictamente mayor.
- **Suelo de plausibilidad:** −10 g. El incremento **cae bajo** el suelo solo si es estrictamente menor que −10 g; por
  debajo, la variación es pérdida de masa y no dispensado (bandeja retirada o mascota comiendo).
- **Cierre por plausibilidad:** cierre del ciclo como fallo con causa `sensor_no_disponible` cuando el incremento se
  sale del intervalo [suelo, tope] en 3 lecturas válidas consecutivas.
- **Motivo del rechazo de línea base:** causa que solo se registra en el log serie: `inestable`, `lecturas_insuficientes`
  o `linea_base_invalida`.
- **Compuerta de asentamiento:** condición que impide abrir una dispensación, no consultar al servidor. La consulta
  periódica de 20 s de la 013 sigue sin cambios.

## Requisitos funcionales

- RF-1: MIENTRAS la celda no haya ganado el asentamiento, EL SISTEMA mantendrá la consulta periódica al servidor cada
  20 s y no abrirá ninguna dispensación; CUANDO esa consulta entregue una orden con `serve: true` sin asentamiento,
  ENTONCES la cerrará como fallo con causa `sensor_no_disponible`, enviará el reporte de la 014 con el `order_id`
  recibido y los gramos medidos como «no disponible», sin mover el servomotor y sin que el servidor descuente stock.
  La compuerta no bloquea la entrega: el equipo sigue recibiendo `reset_wifi` y las comidas programadas, y únicamente
  se rechaza el intento de dispensar.
- RF-2: CUANDO la celda esté asentada y reciba una orden de dispensación válida, EL SISTEMA mantendrá la ventana fija
  de verificación de 2 s de la 013, sin reiniciarla ni extenderla, tomará la línea base como la mediana de todas las
  lecturas válidas de esa ventana y la aceptará solo si la ventana reúne al menos 5 lecturas válidas y el paso entre
  cada dos lecturas válidas consecutivas de las últimas 5 no supera 1 g.
- RF-3: SI la línea base no supera RF-2, ENTONCES EL SISTEMA no moverá el servomotor y cerrará como fallo con causa
  `sensor_no_disponible`; el motivo del rechazo va solo en el log serie y es `inestable` si hay al menos 5 lecturas
  válidas y alguna de las últimas 5 se separa más de 1 g de la lectura válida inmediatamente anterior,
  `lecturas_insuficientes` si la ventana no reúne 5 lecturas válidas, y `linea_base_invalida` si la mediana no puede
  calcularse o queda fuera del intervalo válido 0–5000 g, caso defensivo que evita ocultar la causa real.
- RF-4: EL SISTEMA admitirá una línea base de exactamente 0,0 g si cumple RF-2 —una bandeja vacía y calibrada da
  cero— y rechazará cualquier línea base negativa, que la 013 ya clasifica como lectura inválida y que por tanto no
  entra en la mediana; si esas lecturas negativas dejan la ventana sin 5 lecturas válidas, el motivo del rechazo es
  `lecturas_insuficientes`.
- RF-5: SI el incremento respecto de la línea base supera el tope de plausibilidad o cae bajo el suelo en 3 lecturas
  válidas consecutivas, ENTONCES EL SISTEMA detendrá el servomotor, no lo moverá más, no ejecutará retroceso ni
  reintento, no declarará objetivo alcanzado y cerrará como fallo con causa `sensor_no_disponible`, con los gramos
  medidos como «no disponible» en el reporte. La comprobación se hace en las tres fases del ciclo de motor —avance,
  retroceso y pausa— y una lectura inválida reinicia su contador de lecturas consecutivas. El cierre exige un nuevo
  asentamiento antes de aceptar otra orden.
- RF-6: EL SISTEMA dará prioridad a RF-5 sobre la parada por objetivo de RF-7 de la 013 y sobre el atasco de RF-14 de la
  013; MIENTRAS el incremento se mantenga dentro del intervalo [suelo, tope], las reglas de objetivo, atasco y
  reintento de la 013 siguen sin cambios, y el retroceso sigue reservado al atasco con al menos 5 lecturas válidas y
  medición fiable, según RF-17 de la 013.
- RF-7: CUANDO cierre un ciclo por RF-1, RF-3 o RF-5, EL SISTEMA enviará el reporte de la 014 con el motivo de su
  catálogo —`sensor_no_disponible` en los tres casos—, los gramos solicitados, el número de reintentos y **los gramos
  medidos siempre como «no disponible»**, sin añadir campos al contrato y sin que el servidor descuente stock; la
  línea base, el tope, el suelo y el motivo real del rechazo quedan solo en el log serie.
- RF-8: SI se producen 3 lecturas inválidas consecutivas, ENTONCES EL SISTEMA aplicará el cierre que la 013 ya define
  para ese caso —RF-4 si ocurren en la ventana de verificación, RF-9 si ocurren durante el ciclo de motor—, perderá el
  asentamiento en ese mismo instante y exigirá uno nuevo antes de aceptar otra orden; la misma exigencia de nuevo
  asentamiento se aplica tras cualquier cierre por RF-5. La condición se evalúa tanto en el muestreo continuo del
  asentamiento como en el ciclo, y no atribuye la causa a la celda ni al firmware.

## Requisitos no funcionales

- RNF-1: El asentamiento exigirá 15 lecturas válidas consecutivas con el muestreo de 5 lecturas por segundo de la 013
  (≈3 s) y se evaluará de forma continua en segundo plano desde el arranque, fuera del ciclo de motor, sin añadir
  tiempo muerto al ciclo; la línea base sigue exigiendo al menos 5 lecturas válidas de la ventana de 2 s.
- RNF-2: EL SISTEMA no superará los límites de la 013 —32 s de ciclo completo, 30 s de presupuesto de motor, máximo 3
  reintentos— y validará RF-1 a RF-4 antes del primer arranque del servo.
- RNF-3: Los seis valores nuevos de esta spec —15 lecturas de asentamiento, tolerancia de paso de 1 g, factor 3 del
  tope, margen de 10 g del tope, suelo de −10 g y 3 lecturas consecutivas de plausibilidad— serán constantes
  configurables, documentadas en español y definidas en el mismo único lugar de la 013,
  `DispensadorESP32/src/config/dispensing_utils.h`, sin duplicarlas en ningún otro archivo. Se reutilizan las
  constantes ya existentes sin duplicar su semántica: `kMinValidReadings` para las 5 lecturas válidas,
  `kMedianBufferSize` para el buffer de la mediana y `kMaxConsecutiveInvalidReadings` para las 3 lecturas inválidas
  consecutivas que hacen perder el asentamiento. Nombres propuestos para las nuevas: `kSettlementReadings = 15`,
  `kSettlementMaxStepGrams = 1.0f`, `kPlausibilityFactor = 3.0f`, `kPlausibilityMarginGrams = 10.0f`,
  `kPlausibilityFloorGrams = -10.0f` y `kPlausibilityConsecutiveReadings = 3`. El buffer de la mediana de la 013
  (`validValues`) no es un anillo: se llena con el índice `storedCount` y caben `kMedianBufferSize` = 16 lecturas,
  mientras que en los 2 s de la ventana a 5 lecturas por segundo entran 10–11 válidas, así que cubre «todas las válidas
  de la ventana»; debe preservarse que sea ≥ 11 al tocar constantes, o la mediana dejaría de ser la de todas las válidas.
- RNF-4: Los mensajes del log serie estarán en español, sin emojis, sin credenciales ni datos sensibles, y las
  comprobaciones no añadirán asignación dinámica ni buffers nuevos en el camino de lectura: el estado de asentamiento
  y el de plausibilidad son estructuras de tamaño fijo con contadores y, como mucho, la lectura anterior en gramos, y
  la mediana se calcula sobre el buffer de la 013, sin reservas en el montón ni llamadas que asignen memoria en cada
  muestra.
- RNF-5: La lógica de validación será verificable con pruebas nativas sobre lógica pura, con lecturas inyectadas y sin
  hardware, incluida la decisión de entrada que impide abrir el ciclo sin asentamiento; el comportamiento real de la
  celda se valida en físico.

## Casos límite

- **Línea base 0,0 g:** se acepta si hay asentamiento y la ventana cumple RF-2; el incidente no se detectó por
  inestabilidad, sino porque el salto a 364,7 g supera el tope en 3 lecturas.
- **Orden al arrancar, antes de ganar el asentamiento:** se cierra como fallo `sensor_no_disponible` con el `order_id`
  recibido; el servo no se mueve, el servidor no descuenta y el log muestra la ausencia de asentamiento. La app ve el
  registro y la siguiente comida programada llega a la consulta siguiente.
- **Presión sobre la bandeja a mitad de ciclo:** el incremento supera el tope sin alimento dispensado; RF-5 cierra sin
  retroceso, sin éxito y sin descuento.
- **Bandeja retirada a mitad de ciclo:** el incremento cae bajo el suelo; RF-5 cierra igual, sin confundirlo con un
  atasco. Solo se detecta si la línea base está 10 g o más por encima de cero; ver «Limitaciones aceptadas».
- **Sobrepeso medido dentro del tope:** no es implausible. La 014 solo usa `entrega_incompleta` cuando los medidos son
  menores que los solicitados, así que un incremento mayor que la cantidad solicitada pero dentro del tope cierra como
  éxito y descuenta lo medido.
- **Objetivo y tope en la misma lectura:** una lectura que alcanza el objetivo y supera el tope cumple ambos; prevalece
  el tope y no se declara objetivo alcanzado.
- **Tope o suelo durante el retroceso o la pausa:** también cierra por RF-5, detiene el servo y no ejecuta un retroceso
  adicional ni reanuda el avance.
- **Incremento negativo pequeño, dentro del suelo:** por ejemplo −3 g; no es implausible y se comporta como la 013: el
  progreso frente al máximo observado lo interpreta como estancamiento y puede declarar un atasco.
- **Dos lecturas fuera de límites y una dentro:** el contador de plausibilidad se reinicia con la lectura válida
  dentro del intervalo, aunque esté entre el suelo y el tope.
- **Asentamiento perdido con el ciclo en marcha:** el ciclo continúa; la estabilidad solo se exige para aceptar una
  línea base y el asentamiento para abrir un ciclo nuevo.
- **Nuevo asentamiento tras un cierre por tope, suelo o 3 inválidas:** mientras no se gane, cualquier orden se cierra
  como fallo `sensor_no_disponible`; el equipo vuelve a dispensar cuando la racha se completa, unos 3 s después.
- **Sin asentamiento y sensor desconectado:** ambos cierran con `sensor_no_disponible`; solo el log serie los
  distingue, con la ausencia de asentamiento o con `lecturas_insuficientes`/`linea_base_invalida`.
- **Peso residual sobre la bandeja:** una línea base alta no es un problema; el incremento es relativo a la base y el
  tope y el suelo se aplican sobre el incremento, no sobre el peso absoluto.

## Modificaciones explícitas a la 013

Esta spec **no es una extensión neutra**: cambia tres comportamientos de la 013 y declara además una consecuencia
defensiva, y los enumera aquí para que la revisión no los lea como regresión.

- **(a) Condición de superación de la verificación (RF-3 de la 013):** además de reunir 5 lecturas válidas sin 3
  inválidas consecutivas, la ventana debe dejar una línea base estable, es decir, con la racha de las últimas 5
  lecturas válidas sin pasos mayores de 1 g. Antes bastaba con 5 válidas cualesquiera.
- **(b) Comprobación de plausibilidad dentro de la evaluación de objetivo y atasco (RF-7 y RF-14 de la 013):** en cada
  lectura válida se evalúa primero el intervalo [suelo, tope]; si se sale en 3 lecturas consecutivas, el cierre gana
  al objetivo y al atasco. Antes ninguna magnitud acotaba el incremento.
- **(c) Incremento negativo:** con la 013, una bajada de peso se interpretaba siempre como estancamiento y podía
  declarar atasco y reintento; ahora, si cae bajo −10 g en 3 lecturas consecutivas, cierra como fallo por suelo sin
  retroceso. Por encima de −10 g el comportamiento de la 013 no cambia.
- **(d) Factor de calibración inválido o no finito:** con un factor de calibración inválido (cero) o no finito (NaN o
  infinito) la celda nunca produce lecturas válidas, de modo que no se gana el asentamiento y el cierre se reporta como
  `sensor_no_disponible` en lugar de `orden_invalida` (o del cierre que la 013 daría con lecturas). Se acepta porque el
  factor es una constante de compilación válida hoy y el caso es defensivo; además, quien despliega un factor inválido ya
  no puede dispensar nada, que es el lado seguro del fallo.

Lo que queda intacto: umbrales de atasco (gracia de 2 s, ventana de 5 s, progreso mínimo de 2 g, mediana móvil de 5,
mínimo de 5 válidas, retroceso de 1,2 s, pausa de 0,3 s, 3 reintentos, presupuesto de 30 s y mínimo de reintento de
3,5 s), ventana de verificación de 2 s no reiniciable, presupuesto de motor, retroceso y temporizador de consulta de
20 s.

## Relación con 013 y 014

- **Con la 013:** la amplía con la compuerta de asentamiento y la plausibilidad del incremento, y modifica los tres
  primeros puntos de la sección anterior, además de la consecuencia defensiva (d). El resto de su comportamiento
  —ventanas, umbrales, presupuesto, reintentos, temporizador de 20 s y una medición plausible— se conserva tal cual.
- **Con la 014:** no enmienda su catálogo de causas, su comparación ni su cálculo de stock; los tres cierres nuevos
  usan la causa existente `sensor_no_disponible`, el reporte lleva solo sus campos, los medidos van como «no
  disponible» y cualquier dato extra se ignora, así que el diagnóstico real vive en el log serie.

## Limitaciones aceptadas

- **Suelo con línea base baja:** si la línea base es menor que 10 g, retirar la bandeja no cruza el suelo de −10 g
  respecto de la base y el cierre por pérdida de masa no se detecta; la prueba física del suelo se hará con la
  bandeja cargada por encima de 10 g. Acotar el suelo a un porcentaje de la base se descartó porque con una base de
  0,0 g el suelo también valdría 0 g.
- **Asentamiento tras un bloqueo del bucle:** durante el arranque y los bloqueos de WiFi, BLE o el propio ciclo de
  motor no hay muestreo, así que el asentamiento se pierde y tarda unos 3 s en recuperarse. Una orden que llegue en
  ese intervalo se cierra como fallo `sensor_no_disponible`; es el precio de no bloquear la consulta y de no añadir
  concurrencia al firmware.
- **Causa reportada frente a causa real:** el servidor y la app ven `sensor_no_disponible` también en un salto
  imposible o en una bandeja retirada, porque el catálogo de la 014 es cerrado y no se toca; la causa real
  (`plausibilidad_tope`, `plausibilidad_suelo`, `inestable`, `lecturas_insuficientes`, `linea_base_invalida`) solo
  aparece en el log serie.
- **Ciclo consumido por un rechazo:** una orden que llega sin asentamiento se cierra como fallo y no se reintenta; la
  comida programada que la originó no se vuelve a encolar.
- **Factor de calibración inválido o no finito:** con un factor cero, NaN o infinito la celda no produce lecturas
  válidas, no se gana el asentamiento y el cierre se reporta como `sensor_no_disponible` en lugar de `orden_invalida`;
  se acepta porque el factor es una constante de compilación válida hoy y el caso es defensivo, y porque el fallo cae
  del lado seguro: no se dispensa ni se descuenta nada.

## Fuera de alcance

- Recalibración automática o multipunto del factor de calibración.
- Hardware nuevo, segunda celda o sensor de presencia de alimento.
- Ajuste manual de stock y corrección de descuentos ya aplicados.
- Cambios en el catálogo de causas de la 014, en la comparación medidos/solicitados o en el cálculo de stock.
- Detección de depósito vacío distinto del peso y rediseño mecánico del tornillo sin fin.
- Cambios en la app móvil o en la interfaz del historial.
- Muestreo del asentamiento durante el ciclo de motor o mediante una tarea concurrente con memoria compartida.

## Criterios de finalización

- `pio run` compila y `pio test -e native` pasa en verde, con las suites de la 013 y de la 014 sin regresión.
- **RF-1:** prueba nativa de que, sin asentamiento, la decisión de entrada de una orden `serve: true` es cerrar el
  intento con `sensor_no_disponible` y no iniciar el ciclo, y de que `reset_wifi`, el reposo y la orden inválida no
  cambian; revisión de código de que la tarea sigue consultando cada 20 s y de que el cierre se envía con el
  `order_id` recibido. No se prueba «no consultar»: la compuerta es lógica pura y lo verificable en nativo es que el
  servicio no arranca el ciclo.
- **RF-2 y RF-3:** pruebas nativas con lecturas inyectadas de línea base estable, mediana de todas las válidas con
  número par e impar, 5 lecturas válidas con paso de 1 g exacto, paso de 1,01 g, cuatro lecturas válidas, base fuera
  de rango y base negativa, comprobando la aceptación, los motivos `inestable`, `lecturas_insuficientes` y
  `linea_base_invalida` en el log y el servo inmóvil.
- **RF-4:** prueba nativa de línea base 0,0 g aceptada con 5 válidas estables y de línea base negativa rechazada con
  el motivo de RF-3.
- **RF-5 y RF-6:** pruebas nativas de 3 lecturas consecutivas por encima del tope y por debajo del suelo, con parada
  del servo sin retroceso ni reintento, sin «objetivo alcanzado» y con medidos «no disponible»; de 2 lecturas fuera y
  una dentro sin cierre; del tope prevaleciendo sobre el objetivo en la misma lectura y sobre el atasco; de tope y
  suelo durante el retroceso y la pausa; y de un incremento plausible dentro del intervalo que termina con «objetivo
  alcanzado» y descuenta lo medido.
- **RF-7 y RF-8:** pruebas de que el reporte lleva solo los campos de la 014, con `sensor_no_disponible` y sin
  `gramos_medidos` en los tres cierres, conservando solicitados y reintentos; prueba nativa de que la transición de
  asentamiento pasa a perdido con 3 lecturas inválidas consecutivas y tras un cierre por tope o por suelo, y de que no
  vuelve a estar ganado hasta completar 15 lecturas nuevas; verificación de que la base, el tope y los motivos
  `plausibilidad_tope`, `plausibilidad_suelo`, `inestable`, `lecturas_insuficientes` y `linea_base_invalida` solo
  aparecen en el log serie.
- **RNF-1:** prueba nativa de que la racha se gana exactamente a las 15 lecturas válidas consecutivas con paso ≤1 g y
  no antes, y revisión de que el muestreo vive fuera del ciclo de motor y no altera el periodo de 200 ms del ciclo.
- **RNF-2:** pruebas nativas de que el ciclo completo sigue acotado a 32 s y el motor a 30 s con los nuevos cierres, y
  de que la compuerta y la validación de línea base ocurren antes del primer arranque del servo.
- **RNF-3:** revisión de que las seis constantes nuevas están en `dispensing_utils.h`, documentadas en español, y de
  que se reutilizan `kMinValidReadings`, `kMedianBufferSize` y `kMaxConsecutiveInvalidReadings` sin valores duplicados
  en ningún otro archivo.
- **RNF-4:** inspección del log de una dispensación completa y revisión de código de que el camino de lectura no
  reserva memoria, no crea buffers nuevos y usa solo estructuras de tamaño fijo; los mensajes, en español y sin
  emojis.
- **RNF-5:** `pio test -e native` en verde con las pruebas de asentamiento, línea base, plausibilidad y decisión de
  entrada sobre lógica pura, sin hardware; el comportamiento real de la celda se valida en físico.
- **Caso feliz:** prueba nativa completa de asentamiento alcanzado, orden aceptada, línea base estable, incremento
  plausible y «objetivo alcanzado» con medidos disponibles y descontados por el servidor.
- **Prueba física (a):** encender la placa y pedir una orden de inmediato; el servo no se mueve, el intento se cierra
  como `sensor_no_disponible` con el `order_id` recibido, no hay descuento, el log muestra la ausencia de asentamiento
  y el equipo sigue consultando.
- **Prueba física (b):** presionar la bandeja con la mano durante el ciclo para forzar un incremento imposible; falla
  por el tope, sin retroceso, con `plausibilidad_tope` en el log y sin descuento.
- **Prueba física (c):** con la bandeja cargada por encima de 10 g, retirarla a mitad de ciclo; falla por el suelo con
  `plausibilidad_suelo` en el log.
- **Prueba física (d):** arranque normal y dispensación correcta, comprobando que la celda real alcanza las 15
  lecturas con paso ≤1 g y que el ciclo termina con «objetivo alcanzado» y descuento de lo medido.
- **No regresión:** las pruebas nativas y físicas de la 013 y de la 014 siguen cumpliéndose, y el catálogo de causas,
  la comparación medidos/solicitados y el cálculo de stock no cambian.

## Dudas abiertas

- Ninguna.
