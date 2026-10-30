# Spec 016 — Validación de línea base y plausibilidad del dispensado

Estado: borrador

## Contexto y objetivo

El 2026-10-30, tras un arranque, la 013 aceptó una línea base de 0,0 g por caer en el rango 0–5000 g; al terminar el
ciclo la lectura absoluta era 364,7 g para una orden de 17,27 g, el firmware declaró «objetivo alcanzado» y el
servidor descontó 364,66 g. La base era un cero real de la celda, nada acotaba el incremento y la 014 aplicó lo que
recibió. La 013 no exige asentamiento tras el arranque ni tope de plausibilidad.

Objetivo: que no se consulte ni se dispense sin asentamiento, que un incremento imposible cierre el ciclo como fallo
sin más servo ni éxito, que no descuente stock y que no altere umbrales, ventanas, presupuesto ni reintentos de la 013.

## Usuarios

- **Dueño de mascota:** recibe la ración pedida y su stock no cae por una medición errónea.
- **Desarrollador:** distingue en el log serie un sensor no asentado, uno desconectado y un salto imposible.

## Historias de usuario

- HU-1. Como dueño de mascota, quiero que no se sirva nada si la báscula no está lista, para no recibir una cantidad
  arbitraria justo después de encender.
- HU-2. Como dueño de mascota, quiero que un peso imposible cierre el ciclo como fallo para que no se descuente stock
  por alimento que no salió.
- HU-3. Como desarrollador, quiero ver en el log la línea base, el tope y la causa del rechazo para corregir el montaje
  sin perseguir un atasco inexistente.

## Definiciones

- **Asentamiento:** racha de 15 lecturas válidas consecutivas (≈3 s a 5 Hz) en la que cada lectura difiere de la anterior
  en 1 g como máximo; se pierde al romperse la racha.
- **Tope de plausibilidad:** mayor entre 3 veces la cantidad solicitada y la solicitada más 10 g; para 17,27 g son 51,81 g.
- **Suelo de plausibilidad:** −10 g; por debajo, la variación es pérdida de masa y no dispensado (bandeja retirada o
  mascota comiendo).

## Requisitos funcionales

- RF-1: MIENTRAS la celda no haya alcanzado el asentamiento, EL SISTEMA no consultará al servidor ni abrirá dispensación;
  SI llega igualmente una orden (bandera heredada o caso forzado), ENTONCES la cerrará como fallo con causa
  `sensor_no_disponible`, sin mover el servomotor.
- RF-2: CUANDO la celda esté asentada y reciba una orden válida, EL SISTEMA mantendrá la ventana de 2 s de la 013 y
  aceptará la línea base, mediana de sus lecturas válidas, solo si las últimas 5 lecturas válidas varían entre sí 1 g como
  máximo y la anterior no difiere de la mediana en más de 1 g.
- RF-3: SI la línea base no supera RF-2, ENTONCES EL SISTEMA no moverá el servomotor y cerrará como fallo con causa
  `sensor_no_disponible`; el motivo del rechazo va solo en el log serie: `inestable` si hay 5 lecturas válidas que varían
  más de 1 g, `lecturas_insuficientes` si no se reúnen 5 válidas.
- RF-4: EL SISTEMA admitirá una línea base de exactamente 0,0 g si cumple RF-2 y rechazará cualquier línea base negativa
  por ser lectura inválida según la 013.
- RF-5: SI el incremento supera el tope o cae bajo el suelo en 3 lecturas válidas consecutivas, ENTONCES EL SISTEMA
  detendrá el servomotor, no lo moverá más, no ejecutará retroceso ni reintento, no declarará objetivo alcanzado y cerrará
  como fallo con causa `sensor_no_disponible`, con los medidos como «no disponible».
- RF-6: EL SISTEMA dará prioridad a RF-5 sobre la parada por objetivo de RF-7 y sobre el atasco de RF-14 de la 013;
  MIENTRAS el incremento se mantenga entre el suelo y el tope, las reglas de objetivo, atasco y reintento de la 013 siguen
  sin cambios, y el retroceso sigue reservado al atasco con al menos 5 lecturas válidas y medición fiable, según RF-17 de
  la 013.
- RF-7: CUANDO cierre un ciclo por RF-1, RF-3 o RF-5, EL SISTEMA enviará el reporte de la 014 con el motivo de su catálogo,
  los gramos solicitados, los medidos solo cuando sean fiables y los reintentos, sin añadir campos al contrato; la línea base,
  el tope y el motivo del rechazo quedan solo en el log serie y el stock no se descuenta.
- RF-8: SI se producen 3 lecturas inválidas consecutivas por fallo de la celda, ENTONCES EL SISTEMA aplicará el cierre de la
  013 y, al recuperarse el sensor, exigirá un nuevo asentamiento.

## Requisitos no funcionales

- RNF-1: El asentamiento exigirá 15 lecturas válidas consecutivas (≈3 s) y la línea base 5, con el muestreo de 5 lecturas por
  segundo de la 013, sin añadir tiempo muerto al ciclo de motor.
- RNF-2: EL SISTEMA no superará los límites de la 013 —32 s de ciclo completo, 30 s de presupuesto de motor, máximo 3
  reintentos— y validará RF-1 a RF-4 antes del primer arranque del servo.
- RNF-3: Los siete valores de esta spec —15 lecturas, tolerancia de 1 g, 5 lecturas para la línea base, factor 3, margen de
  10 g, suelo de −10 g y 3 lecturas consecutivas— serán constantes configurables, documentadas en español y definidas en un
  único lugar.
- RNF-4: Los mensajes del log serie estarán en español, sin emojis, sin credenciales ni datos sensibles; las comprobaciones no
  harán crecer la memoria del dispositivo.
- RNF-5: La lógica de validación será verificable con pruebas nativas sobre lógica pura, con lecturas inyectadas y sin
  hardware; el comportamiento real de la celda se valida en físico.

## Casos límite

- **Línea base 0,0 g:** se acepta si cumple RF-2; el incidente no se detectó por inestabilidad, sino porque el salto a 364,7 g
  supera el tope en 3 lecturas.
- **Presión sobre la bandeja a mitad de ciclo:** el incremento supera el tope sin alimento dispensado; RF-5 cierra sin retroceso,
  sin éxito y sin descuento.
- **Bandeja retirada a mitad de ciclo:** el incremento cae bajo el suelo; RF-5 cierra igual, sin confundirlo con un atasco.
- **Sobrepeso medido dentro del tope:** no es implausible; lo resuelve la 014 con `entrega_incompleta` o descontando lo medido.
- **Objetivo y tope en la misma lectura:** prevalece el tope; no se declara objetivo alcanzado.
- **Asentamiento perdido con el ciclo en marcha:** el ciclo continúa; la estabilidad solo se exige para aceptar la línea base.
- **Sin asentamiento y sensor desconectado:** ambos cierran con `sensor_no_disponible`; solo el log serie los distingue.

## Relación con 013 y 014

- **Con la 013:** la extiende en dos puntos y no la reescribe: (a) la compuerta que impide consultar y dispensar sin asentamiento
  y (b) la plausibilidad del incremento. Umbrales, ventanas, presupuesto, reintentos y temporizador de 20 s quedan intactos, y una
  medición plausible se comporta como la 013 dice.
- **Con la 014:** no enmienda su catálogo de causas, su comparación ni su cálculo de stock; el reporte lleva solo sus campos y
  cualquier dato extra se ignora, así que el diagnóstico vive en el log serie.

## Fuera de alcance

- Recalibración automática o multipunto del factor de calibración.
- Hardware nuevo, segunda celda o sensor de presencia de alimento.
- Ajuste manual de stock y corrección de descuentos ya aplicados.
- Cambios en el catálogo de causas, en la comparación medidos/solicitados o en el cálculo de stock.
- Detección de depósito vacío distinto del peso y rediseño mecánico del tornillo sin fin.
- Cambios en la app móvil o en la interfaz del historial.

## Criterios de finalización

- `pio run` compila y `pio test -e native` pasa en verde.
- RF-1 y RF-2: prueba nativa con lecturas inyectadas de que sin 15 lecturas consecutivas estables no se consulta al servidor, no
  se abre la ventana de verificación y no se mueve el servo.
- RF-3 y RF-4: pruebas nativas con línea base estable, cero estable, negativa, inestable y sin 5 lecturas válidas, comprobando
  mediana aceptada, motivo del rechazo en el log y servo inmóvil.
- RF-5 y RF-6: pruebas nativas de que 3 lecturas consecutivas fuera de los límites detienen el servo sin retroceso ni reintento, de
  que el tope prevalece sobre objetivo y atasco, y de que un incremento plausible termina con «objetivo alcanzado».
- RF-7 y RF-8: prueba automatizada de que el reporte lleva solo los campos de la 014, con el motivo del catálogo y los medidos «no
  disponible» en los cierres por tope o suelo; prueba nativa de que el fallo de sensor no dispara retroceso y de que la recuperación
  exige nuevo asentamiento.
- Prueba física (a): encender la placa y pedir una orden de inmediato; no se consulta, no hay servo, no hay descuento y el log muestra
  la ausencia de asentamiento.
- Prueba física (b): presionar la bandeja con la mano durante el ciclo para forzar un incremento imposible; falla por el tope, sin
  retroceso y sin descuento.
- Prueba física (c): retirar la bandeja a mitad de ciclo; falla por el suelo.
- No regresión: las pruebas nativas y físicas de la 013 y de la 014 siguen cumpliéndose.

## Dudas abiertas

- Ninguna.
