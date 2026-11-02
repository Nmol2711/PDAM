# Spec 021 — Vencimiento de la solicitud rápida que nunca se entrega

Estado: implementada y verificada (2026-11-01)

## Contexto y objetivo

La spec 020 dejó aceptada una deuda: una solicitud rápida que el dispensador nunca
consulta —equipo apagado, sin red o sin batería— queda pendiente para siempre. No se
dispone nada, no deja registro y no se avisa al dueño. El daño real es otro: mientras siga
pendiente, su cantidad sigue restando en la reserva de stock, así que con el tiempo el
dispensador rechaza solicitudes nuevas con `stock_insuficiente` sin que nada lo explique en
la aplicación.

El objetivo es que una solicitud rápida que no se entrega en un plazo razonable se
descarte sola, libere su reserva y deje constancia visible para el dueño, sin romper la
cola programada, la cobertura de horarios ni el contrato vigente de la dispensación
rápida.

## Usuarios

- **Dueño de mascota:** quiere que una solicitud que nunca llegó al equipo no le bloquee
  el stock y quiere saber que no se dispensó.
- **Mantenedor del sistema:** quiere que las solicitudes huérfanas no se acumulen ni
  bloqueen dispensaciones, sin intervención manual.

## Historias de usuario

- HU-1. Como dueño, quiero que una solicitud rápida que el dispensador no consultó se
  descarte sola, para que no me bloquee el stock para siempre.
- HU-2. Como dueño, quiero ver en el historial que esa solicitud no se dispensó, para no
  creer que mi mascota comió.
- HU-3. Como mantenedor, quiero que la limpieza la haga el servidor con la infraestructura
  que ya existe, para no añadir tareas, dependencias ni migraciones.

## Definiciones

- **Solicitud vigente:** solicitud rápida no consumida cuyo plazo de entrega no ha vencido;
  puede entregarse al dispositivo.
- **Solicitud vencida:** solicitud rápida no consumida cuyo plazo de entrega ya venció; no
  se entrega nunca y solo espera su descarte.
- **Plazo de entrega de la solicitud:** 15 minutos contados desde el instante de recepción
  de la solicitud en el servidor, en UTC, con el límite inclusivo: en el instante exacto del
  límite la solicitud sigue vigente. *(Por qué 15 minutos: el equipo consulta de forma
  periódica y reinicia su temporizador al terminar cada ciclo, así que el plazo cubre varias
  consultas perdidas y sigue siendo tres veces el plazo de 5 minutos de una orden de la
  014, sin descartar solicitudes por un corte breve de red.)*
- **Descarte por vencimiento:** transición de solicitud vencida a consumida que libera la
  reserva, escribe el registro de actividad y **no** crea orden de dispensación.
- **Consumida:** solicitud ya reclamada, sea entregada o descartada, con el mismo marcador
  de solicitud reclamada que usa la 020; no se añade estado nuevo. La diferencia entre
  entregada y descartada queda en el registro solo en el descarte por vencimiento, porque el
  descarte por reasignación de la 020 no escribe registro.
- **Barrido de vencimiento periódico:** el ciclo de 30 segundos que ya existe, que pasa a
  descartar también las solicitudes vencidas.
- **Barrido de vencimiento perezoso:** descarte de las solicitudes vencidas de un
  dispensador concreto, ejecutado al consultar el dispositivo y al evaluar una nueva
  solicitud rápida de ese dispensador.
- **Reserva de stock:** stock actual del dispensador menos la suma de las cantidades de sus
  solicitudes no consumidas (020). Su fórmula no cambia; a sus efectos, «pendiente» de la
  020 se lee desde ahora como «no consumida y no vencida».
- **Mascota del registro:** la mascota guardada en la solicitud. Si el dispensador se
  reasignó y esa mascota se eliminó después, el registro conserva su referencia y muestra el
  nombre como «no disponible».

### Catálogo de causas (ampliación del de la 014)

| Código | Etiqueta visible | Resultado | Origen |
| --- | --- | --- | --- |
| `solicitud_vencida` | Solicitud vencida | fallo | servidor |

*(Por qué: ninguna causa vigente describe «se pidió y nunca se entregó»; `sin_reporte`
significa que sí hubo orden y no llegó reporte. Crece el catálogo cerrado de la 014, que
exige modificar la spec para ampliarse.)*

El **catálogo de errores no cambia**: no se añade ningún código nuevo.

## Requisitos funcionales

- **RF-1:** CUANDO el instante del servidor supere en más de 15 minutos el instante de
  recepción de una solicitud rápida no consumida, EL SISTEMA la considerará vencida; en el
  instante exacto del límite y antes seguirá vigente y podrá entregarse.
- **RF-2:** CUANDO una solicitud vencida sea detectada, EL SISTEMA la descartará en una única
  transacción: la marcará consumida con el instante del descarte, escribirá el registro de
  RF-9 y no creará orden de dispensación, no descontará stock ni escribirá un segundo
  registro. El descarte sí cambia el estado de la solicitud, por lo que el registro no
  incumple RF-2 de la 014.
- **RF-3:** EL SISTEMA descartará las solicitudes vencidas en el mismo ciclo de barrido
  periódico que ya existe, sin tarea ni temporizador nuevos, y además de forma perezosa y
  limitada al dispensador implicado, al consultar el dispositivo y al evaluar una nueva
  solicitud rápida.
- **RF-4:** CUANDO el dispositivo consulte y su dispensador tenga solicitudes no consumidas,
  EL SISTEMA descartará primero las vencidas de ese dispensador y solo después evaluará la
  entrega, de modo que nunca entregue una solicitud vencida; la consulta de diagnóstico, que
  no escribe, tampoco entrega una solicitud vencida y responde sin dispensación.
- **RF-5:** SI la entrega y el descarte coinciden en la solicitud, ENTONCES EL SISTEMA
  aplicará una única transición con ganador definido por el reloj, no por el orden de
  llegada: la reclamación de entrega exige que la solicitud siga vigente, de modo que en el
  instante exacto del límite gana la entrega y en cualquier instante posterior gana el
  descarte aunque la consulta haya llegado antes; la parte que pierde no escribe orden,
  registro ni liberación.
- **RF-6:** CUANDO una solicitud se descarte por vencimiento, EL SISTEMA dejará de contarla en
  la reserva en esa misma transacción, y al evaluar una nueva solicitud rápida descartará
  antes las vencidas de ese dispensador; así deja de rechazar con `stock_insuficiente` por
  una reserva caducada. La cifra de stock que se muestra al dueño no cambia.
- **RF-7:** CUANDO llegue un identificador de operación ya registrado para el dispensador, EL
  SISTEMA responderá antes que cualquier otra comprobación con el mismo contrato y el mismo
  estado de aceptación de la 020 (HTTP 202) aunque la solicitud ya esté descartada, sin
  resucitarla, sin crear orden, sin cubrir horarios, sin reservar de nuevo y sin segundo
  registro; el stock informado en esa respuesta será el del instante del reintento. Un
  reintento no dispara el descarte de otras solicitudes del dispensador.
  *(Por qué: la deduplicación solo necesita la solicitud ya registrada, y ampliarla a otras
  solicitudes convertiría un reintento en una escritura con efectos ajenos.)*
- **RF-8:** CUANDO el dueño consulte el historial, EL SISTEMA mostrará el registro del
  descarte con la etiqueta de tipo «Comida dispensada», resultado «Fallo», causa «Solicitud
  vencida», mascota, MAC parcial, gramos solicitados y stock resultante, también cuando los
  datos provengan de la caché local; no habrá pantalla, aviso modal ni mensaje nuevo en la
  hoja «Dispensar ahora».
- **RF-9:** EL SISTEMA escribirá el registro del descarte con fecha y hora del servidor, dueño
  y mascota del registro, dispensador con su MAC parcial, descripción «Solicitud rápida
  vencida sin entregar» y contexto con los gramos reservados, el instante de recepción y el
  límite de entrega; el identificador de orden figurará como ausente y los gramos medidos, los
  descontados y los reintentos como «no disponible» (RNF-1 de la 014), el stock resultante
  será el stock actual del dispensador y no se incluirán credenciales, tokens ni la MAC
  completa.
- **RF-10:** SI el descarte de una solicitud falla al escribir el registro o la marca,
  ENTONCES EL SISTEMA no dejará ni marca ni registro parciales: la solicitud seguirá sin
  consumir con su reserva y el siguiente barrido lo reintentará, sin impedir el descarte del
  resto de las solicitudes del ciclo.
- **RF-11:** EL SISTEMA conservará sin cambios la cola de comidas programadas, la cobertura de
  la ventana de coincidencia de 10 minutos, el contrato y el cuerpo de la respuesta de la
  dispensación rápida, la respuesta al dispositivo, el plazo de 5 minutos de las órdenes y su
  cierre `sin_reporte`.

## Requisitos no funcionales

- **RNF-1:** Cada RF tendrá al menos una prueba automatizada en el módulo que corresponda, que
  falle si el requisito se incumple.
- **RNF-2:** No se añadirán dependencias nuevas, tablas, columnas, endpoints ni tareas
  programadas: se reutilizan la solicitud rápida, su marca de reclamada, el ciclo de barrido
  de 30 segundos y la consulta del dispositivo que ya existen.
- **RNF-3:** La regla del plazo y el descarte se resolverán fuera de las vistas, con el
  instante del servidor recibido como parámetro; las vistas solo presentan estado.
- **RNF-4:** Los textos visibles nuevos estarán en español, sin emojis, y no incluirán datos
  sensibles.
- **RNF-5:** El descarte será concurrentemente seguro e idempotente: la transición exigirá
  que la solicitud siga sin consumir, de modo que dos barridos simultáneos, dos procesos o un
  barrido repetido produzcan una sola transición, un solo registro y una sola liberación. Cada
  solicitud se resuelve en su propia transacción y una solicitud no bloquea al resto.
- **RNF-6:** El descarte ocurrirá en el siguiente ciclo del barrido periódico, con el mismo
  margen que la 014 admite para el cierre por vencimiento (a más tardar 60 segundos después de
  cumplirse el plazo), y de forma inmediata en la consulta del dispositivo y al aceptar una
  solicitud del mismo dispensador; no se introduce ningún temporizador nuevo.
- **RNF-7:** Los contratos existentes no cambian: la aceptación sigue siendo HTTP 202 con
  `{status, requested_grams, stock_grams}` y la consulta del dispositivo sigue devolviendo
  `{serve, amount, order_id, reset_wifi}`.
- **RNF-8:** Todos los instantes del plazo y del descarte serán los del servidor en UTC
  (RNF-8 de la 014); nunca el reloj del móvil ni el del dispositivo.
- **RNF-9:** El firmware no cambia y sus pruebas siguen en verde.

## Casos límite

- Solicitud en el instante exacto del límite: vigente, se entrega. Un segundo después:
  vencida y se descarta.
- Consulta que llega antes del descarte pero después del límite: no entrega y el descarte
  gana la transición.
- Consulta y barrido en el mismo instante del límite: gana la entrega; en cualquier instante
  posterior gana el descarte.
- Equipo que nunca consulta: la solicitud se descarta en el siguiente ciclo del barrido
  periódico, deja su registro y libera la reserva.
- Equipo que consulta después del vencimiento y no tiene nada que entregar: responde sin
  dispensación con el contrato sin cambios, y el descarte ya hecho no se repite.
- Equipo encendido después del plazo: no recibe nada de esa solicitud y el dueño ve el
  registro de vencimiento.
- Barrido ejecutado dos veces seguidas: un único registro y una única liberación.
- Dos procesos barriendo a la vez: gana uno y el otro no escribe nada.
- Varias solicitudes vencidas del mismo dispensador: un registro por solicitud.
- Solicitud vencida mientras hay una orden en curso: se descarta igual y no toca la orden.
- Dispensador desactivado con solicitud pendiente: vence y se descarta igual, porque la
  solicitud es un «ahora» y no una comida en espera; al reactivarlo ya no se entrega. (La
  comida programada en espera de la 014 RF-25 no cambia.)
- Stock 0 con solicitud vencida: se descarta, el stock sigue en 0 y una solicitud nueva se
  rechaza por stock.
- Reserva caducada que bloqueaba una solicitud nueva (stock 100, solicitud de 100 vencida,
  solicitud nueva de 100): el descarte perezoso previo permite aceptar la nueva.
- Reintento con el mismo identificador de operación de una solicitud vencida: mismo 202, mismo
  `status` y `stock_grams` del instante del reintento, sin resurrección, sin reserva nueva y
  sin segundo registro; con otro identificador se crea una solicitud nueva y se valida contra
  el stock ya liberado.
- Fallo al escribir el registro del descarte: no queda marca ni registro; la solicitud sigue
  reservando y el siguiente barrido lo reintenta.
- Dispensador eliminado antes del vencimiento: la baja en cascada borra sus solicitudes y no
  hay registro (020 RF-16).
- Dispensador reasignado antes del vencimiento: si el equipo consulta primero, el descarte es
  silencioso (020 RF-16); si vence primero, se escribe el registro de vencimiento con la
  mascota original.
- Dispensador reasignado y mascota original eliminada después: el registro conserva la
  referencia de esa mascota y muestra su nombre como «no disponible».
- Solicitudes pendientes creadas antes de esta spec y ya vencidas: el primer barrido las
  descarta y escribe su registro, sin migración ni limpieza manual.
- Zona horaria: el plazo se cuenta en UTC con el reloj del servidor y no depende de la hora
  local ni del equipo.

## Relación con las specs 013, 014, 019 y 020

- **013:** mantiene el firmware y el presupuesto de motor de 30 segundos; su consulta
  periódica es la referencia del plazo. No se toca nada del dispositivo.
- **014:** esta spec amplía su catálogo cerrado de causas con `solicitud_vencida` y reutiliza
  su tipo de evento, su formato de registro con descripción y contexto, su exclusión mutua y
  su regla de instantes del servidor. No cambia el plazo de las órdenes, ni `sin_reporte`, ni
  el descuento de stock.
- **019:** el dueño ve el registro sin recargar a mano porque el historial se refresca al
  mostrar su pestaña.
- **020:** esta spec sustituye a la 020 solo en: la definición «solicitud pendiente» que no
  vence, la definición «evento», que deja de exigir una orden cerrada, RF-9, el caso límite
  «equipo que nunca consulta: queda pendiente sin vencimiento» y la línea de fuera de alcance
  sobre caducidad de solicitudes pendientes. **Amplía** RF-14: la idempotencia pasa a cubrir
  también una solicitud ya descartada. Todo lo demás de la 020 sigue vigente: reserva de
  stock, cobertura de la ventana de 10 minutos, precedencia de la solicitud sobre la comida
  programada, cascada de la baja del dispensador, 409 `pet_has_dispenser` y descarte
  silencioso por reasignación. El 202 y su cuerpo no cambian.

## Fuera de alcance

- Cancelación manual de una solicitud por el dueño.
- Reprogramar, reintentar o resucitar una solicitud vencida.
- Vencimiento o caducidad de la comida programada en espera (sigue rigiendo la 014 RF-25).
- Notificaciones push, correos o avisos proactivos cuando el equipo no consulta.
- Avisos, insignias o textos nuevos en la ficha de la mascota o en la hoja «Dispensar ahora».
- Cambios en el catálogo de errores, en el contrato de la dispensación rápida o en la
  consulta del dispositivo.
- Cambios en el firmware o en el protocolo del ESP32.
- Agrupar varios vencimientos en un único registro o purgar registros históricos.
- Reconciliar de forma especial las solicitudes que ya quedaron bloqueadas antes de esta
  spec: las resuelve el barrido normal.

## Criterios de finalización

- RF-1 a RF-11 implementados y con sus pruebas automatizadas en verde.
- `pytest` completo sin regresiones y `flutter test` completo en verde.
- `flutter analyze` sin errores.
- Sin cambios de firmware: `pio test -e native` y `pio run` siguen en verde.
- Verificación manual: con un dispensador que no consulta, la solicitud se descarta en el
  siguiente ciclo del barrido y el historial muestra «Solicitud vencida» con resultado
  «Fallo», los gramos solicitados y el stock resultante; una solicitud nueva por la misma
  cantidad se acepta con la reserva ya liberada; el reintento con el mismo identificador no
  duplica el registro.
- `MEMORY.md` actualizado al cerrar la fase.

### Mapeo RF a prueba

| RF | Prueba |
|----|--------|
| RF-1 | Fronteras del plazo: en el límite exacto vigente y entregable; 1 s después vencida; instante inyectado, no reloj real. |
| RF-2 | Descarte: marca consumida, un único registro, sin orden de dispensado y sin descuento de stock. |
| RF-3 | El ciclo de barrido existente descarta sin tarea ni temporizador nuevos; la consulta del dispositivo y la aceptación descartan de forma perezosa solo su dispensador. |
| RF-4 | Con una solicitud vencida y otra vigente, la consulta descarta la vencida y entrega la vigente; la consulta de diagnóstico nunca entrega una vencida y responde sin dispensación. |
| RF-5 | Carrera entrega/descarte: en el límite exacto gana la entrega, un instante después gana el descarte aunque la consulta llegue antes, y nunca hay doble transición. |
| RF-6 | La reserva deja de contar tras el descarte; la aceptación con reserva caducada ya no se rechaza con `stock_insuficiente`; la cifra mostrada no cambia. |
| RF-7 | Mismo identificador de una solicitud vencida: mismo 202, mismo `status`, `stock_grams` del instante del reintento, sin orden, sin cobertura, sin reserva, sin segundo registro y sin descartar otras solicitudes. |
| RF-8 | El registro se muestra con «Comida dispensada», «Fallo» y «Solicitud vencida», con mascota, MAC parcial y gramos; también desde la caché local; sin avisos nuevos en la hoja. |
| RF-9 | El registro contiene descripción, contexto, stock resultante, identificador de orden ausente y «no disponible» en medidos, descontados y reintentos, sin MAC completa ni datos sensibles; mascota eliminada tras reasignar aparece con referencia conservada y nombre «no disponible». |
| RF-10 | Fallo de escritura del descarte: sin marca ni registro parciales, la solicitud sigue reservando y el barrido siguiente lo resuelve. |
| RF-11 | No regresión: cola programada, cobertura de 10 minutos, contrato de la dispensación rápida, respuesta al dispositivo, plazo de 5 minutos y `sin_reporte`. |
| RNF-5 | Dos barridos simultáneos y un barrido repetido sobre la misma solicitud: una sola transición, un solo registro y una sola liberación. |
| RNF-6 | El descarte ocurre en el siguiente ciclo del barrido y nunca después de 60 segundos de cumplirse el plazo. |
| RNF-1 a RNF-9 | Suites completas de backend, app y firmware, `flutter analyze`, revisión de textos y verificación manual. |

## Dudas abiertas

- Ninguna.
