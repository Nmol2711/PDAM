# Spec 014 — Registro de actividad y validación del descuento de stock

**Estado:** implementada y validada (2026-10-29)
**Fecha de revisión:** 2026-10-28

## Contexto y objetivo

Hoy el historial guarda texto libre sin tipo de evento, resultado ni contexto, y el stock
se descuenta al emitir la orden de dispensación, antes de saber cuánto alimento salió
realmente. La spec 013 midió el peso entregado en el dispositivo y detectó atascos, pero
dejó fuera de alcance reportarlos al servidor; esa deuda es la que cubre esta spec, junto
con la de descontar stock sin confirmación física.

Objetivo:

1. Cada operación relevante deja un registro tipado, con resultado, causa y contexto,
   escrito en la misma transacción que el cambio de estado que lo origina.
2. El stock se descuenta solo cuando el hardware confirma una entrega que alcanza lo
   solicitado, y el descuento es lo medido, no lo solicitado. Cuando la entrega es
   incompleta o el reporte llega tarde, el alimento ya salió y no se descuenta, por lo que
   el stock del servidor queda por encima del real: es un desvío aceptado que no se
   compensa con ajustes automáticos.
3. El historial se consulta con filtros combinables y paginación, rechazando los
   parámetros inválidos de forma explícita y nunca en silencio.
4. Las órdenes sin reporte se cierran por plazo y los reportes del firmware no se pierden
   ni producen efectos duplicados.

## Usuarios

- **Dueño de mascota:** consulta qué ocurrió con cada comida y con qué resultado, y ve un
  stock que refleja lo realmente entregado.
- **Desarrollador de hardware y firmware:** envía el resultado del ciclo con los gramos
  medidos y sabe si su reporte llegó o debe reintentarlo.
- **Mantenedor del sistema:** diagnostica fallos con registros tipados, causas cerradas y
  datos de contexto.

## Historias de usuario

- HU-1. Como dueño de mascota, quiero que la creación, modificación y eliminación de mis
  mascotas quede registrada para saber qué cambió en sus datos y cuándo.
- HU-2. Como dueño de mascota, quiero que la vinculación, modificación, desvinculación y
  el reseteo de WiFi de mis dispensadores quede registrado para auditar los cambios del
  equipo.
- HU-3. Como dueño de mascota, quiero saber si una comida se dispensó y, si falló, cuál
  fue la causa, para distinguir un atasco de un depósito vacío o de un fallo del sensor.
- HU-4. Como dueño de mascota, quiero filtrar el historial por mascota, tipo de evento,
  resultado y rango de fechas para encontrar un episodio concreto.
- HU-5. Como dueño de mascota, quiero que el stock se descuente solo cuando el hardware
  confirme el éxito físico, para que el stock no mienta sobre el alimento entregado.
- HU-6. Como dueño de mascota, quiero que los reabastecimientos hechos sin conexión se
  sincronicen sin duplicar ni perder cantidades.
- HU-7. Como desarrollador de hardware, quiero informar desde el dispositivo el resultado
  del ciclo y los gramos medidos, para que el servidor registre lo que realmente salió.
- HU-8. Como mantenedor del sistema, quiero cerrar por vencimiento las órdenes pendientes
  que nunca reciben reporte, para que el historial no quede indefinidamente abierto.
- HU-9. Como dueño de mascota, quiero seguir viendo los registros históricos anteriores a
  este cambio, aunque no tengan clasificación.
- HU-10. Como dueño de mascota, quiero consultar el historial sin conexión mediante la
  caché local, para revisar lo último descargado cuando el servidor no responde.
- HU-11. Como mantenedor del sistema, quiero que el descuento, el cierre de la orden y el
  registro sean atómicos, para que un fallo de escritura no deje un descuento sin
  trazabilidad.
- HU-12. Como dueño de mascota, quiero que el historial omita credenciales, SSID, tokens
  y correos, para que los datos sensibles no queden expuestos.

## Definiciones

- **Registro de actividad:** unidad del historial compuesta por fecha y hora del servidor,
  usuario, tipo de evento, resultado, causa, mascota, dispensador y contexto del evento.
- **Orden de dispensación:** entidad con identificador propio, mascota, dispensador,
  gramos solicitados, fecha y hora de entrega del servidor y estado. Su ciclo de vida solo
  tiene dos estados: pendiente y cerrada.
- **Entrega de orden:** acto por el que el servidor responde al dispositivo con la orden y
  esta pasa a estado pendiente, sin modificar el stock.
- **Pendiente:** orden entregada que todavía no ha sido cerrada, ni por reporte ni por
  vencimiento del plazo.
- **Cerrada:** orden que ya tiene resultado definitivo, sea éxito o fallo. Una orden
  cerrada no vuelve a cambiar de estado ni de resultado.
- **Plazo:** 5 minutos contados desde la fecha y hora de entrega de la orden, según el
  reloj del servidor. El cierre por vencimiento no depende de que llegue ningún reporte, y
  una tolerancia explícita de hasta 1 segundo después de cumplirse el plazo se considera
  todavía dentro del plazo.
- **Reporte:** mensaje del dispositivo al terminar un ciclo de dispensación, con la MAC del
  dispensador, el identificador de la orden, el motivo, los gramos solicitados, los gramos
  medidos y el número de reintentos. Los gramos medidos pueden faltar cuando el sensor no
  está disponible y los solicitados pueden faltar cuando el dispositivo no conoce la orden,
  de modo que el reporte se admite igualmente como ausencia declarada en ambos casos.
- **Solicitados:** gramos que la orden pidió dispensar y que son la fuente de verdad para
  comparar el éxito del dispensado. Los gramos solicitados que envía el reporte solo se
  auditan y se guardan en el contexto del registro; pueden faltar o llegar como nulos, y en
  ese caso el contexto los registra como «no disponible» sin afectar a la comparación.
- **Medidos:** gramos que el dispositivo declara haber entregado, según su celda de carga.
  Pueden ser nulos o ausentes cuando el sensor no está disponible; en ese caso el registro
  guarda explícitamente «no disponible».
- **Descontados:** gramos que el servidor resta del stock al cerrar una orden con éxito.
  Es igual a los medidos acotado entre 0 y el stock disponible en ese instante, y se
  guarda en un campo distinto del de medidos.
- **Faltante:** diferencia entre medidos y descontados cuando los medidos superan el stock
  disponible. Se refleja en el contexto del registro y no genera stock negativo.
- **Stock:** gramos de alimento que el servidor considera disponibles en un dispensador,
  siempre en el intervalo cerrado de 0 a 5000 g.
- **Firmware antiguo:** versión del firmware que no envía reporte al terminar el ciclo.
  Sus órdenes se cierran por plazo, como cualquier orden sin reporte, sin alterar el stock.
- **Sin clasificar:** etiqueta de presentación de los registros históricos anteriores a
  esta spec que no tienen tipo de evento, resultado ni causa. No es un tipo del catálogo y
  no es filtrable por tipo, resultado ni causa.
- **MAC parcial:** representación del dispensador que conserva solo los dos últimos octetos
  de la MAC, en mayúsculas y separados por dos puntos, y oculta el resto con un prefijo
  literal de exactamente dos asteriscos, `**`, idéntico para cualquier MAC sin importar
  cuántos octetos tenga la original, de modo que `AA:BB:CC:DD:AB:1F` se representa como
  `**:AB:1F`. El servidor normaliza la MAC recibida del dispositivo (mayúsculas, sin
  separadores ni espacios, con el mismo criterio que el resto del sistema) antes de
  buscarla, y la MAC completa no se guarda en el registro de actividad ni se devuelve en la
  consulta de historial.
- **Instante del filtro de fechas:** fecha y hora en formato ISO 8601 con desplazamiento
  explícito respecto de UTC, por ejemplo `2026-10-01T00:00:00-05:00`, o con el sufijo `Z`,
  que se acepta como desplazamiento explícito y equivale a `+00:00`, por ejemplo
  `2026-10-01T00:00:00Z`, y que la app envía como límite del rango. La app resuelve por su
  cuenta el cambio de horario y el servidor solo convierte el instante a UTC.
- **Día local:** intervalo de un día del calendario del usuario, desde las 00:00:00 hasta
  las 23:59:59.999. Solo existe en la interfaz: la app lo traduce a dos instantes con
  desplazamiento antes de consultar y el servidor no interpreta días ni zonas horarias en el
  filtro de fechas.
- **Origen del reabastecimiento:** marca del contexto que indica si el reabastecimiento se
  registró con conexión (`servidor`) o si llegó desde la sincronización sin conexión
  (`sincronizacion_sin_conexion`).
- **Identificador de operación del reabastecimiento:** valor que la app genera una vez por
  reabastecimiento y repite en cada reintento de envío o sincronización. Es lo que permite
  al servidor distinguir un reintento del mismo reabastecimiento de dos reabastecimientos
  distintos con la misma cantidad, y por tanto lo que sostiene la idempotencia de RF-11. Si
  el cliente no lo envía, el servidor aplica el reabastecimiento una sola vez por petición,
  pero no puede deduplicar reenvíos posteriores del mismo pendiente, que se aplicarían de
  nuevo: la deduplicación depende de que el cliente envíe siempre el identificador y lo
  conserve junto al pendiente hasta recibir una respuesta definitiva.
- **Comida programada en espera:** comida programada que coincidió con una orden pendiente
  del mismo dispensador o con el dispensador desactivado y que no se pierde: se entrega
  cuando la orden anterior cierra o vence su plazo y, si el dispensador estaba desactivado,
  al reactivarse.
- **Hora del horario de comida:** hora del día de una programación, interpretada en la zona
  horaria local del servidor; las órdenes, los plazos y los registros siguen usando la hora
  del servidor en UTC. Si el servidor cambia de zona horaria, los horarios existentes se
  interpretan en la nueva zona sin conversión.
- **Desvío de stock aceptado:** situación en la que el alimento salió del depósito pero no
  se descontó, por entrega incompleta o reporte tardío, de modo que el stock del servidor
  queda por encima del real. No se compensa con ajustes automáticos.

### Catálogo de tipos de evento

| Código | Etiqueta visible |
| --- | --- |
| `pet_created` | Mascota creada |
| `pet_updated` | Mascota modificada |
| `pet_deleted` | Mascota eliminada |
| `dispenser_linked` | Dispensador vinculado |
| `dispenser_updated` | Dispensador modificado |
| `dispenser_unlinked` | Dispensador desvinculado |
| `dispenser_wifi_reset` | WiFi del dispensador reiniciado |
| `feeding_dispensed` | Comida dispensada |
| `dispenser_refilled` | Dispensador reabastecido |

«Sin clasificar» no pertenece a este catálogo: es la etiqueta de presentación de los
registros históricos sin tipo, resultado ni causa (RF-41), y no es filtrable por tipo,
resultado ni causa.

### Catálogo de resultados

| Código | Etiqueta visible |
| --- | --- |
| `success` | Éxito |
| `failure` | Fallo |

Los registros sin clasificar no tienen resultado y no aparecen al filtrar por resultado.

### Catálogo de causas

| Código | Etiqueta visible | Resultado asociado | Origen |
| --- | --- | --- | --- |
| `objetivo_alcanzado` | Objetivo alcanzado | éxito | reporte |
| `objetivo_no_alcanzado` | Objetivo no alcanzado | fallo | reporte |
| `atasco_no_resuelto` | Atasco no resuelto | fallo | reporte |
| `sensor_no_disponible` | Sensor no disponible | fallo | reporte |
| `fallo_sensor_dispensacion` | Fallo del sensor durante la dispensación | fallo | reporte |
| `orden_invalida` | Orden inválida | fallo | reporte |
| `entrega_incompleta` | Entrega incompleta | fallo | servidor |
| `sin_reporte` | Sin reporte | fallo | servidor |
| `orden_cerrada` | Orden cerrada | fallo | servidor |
| `orden_desconocida` | Orden desconocida | fallo | servidor |
| `supera_capacidad` | Supera la capacidad | fallo | servidor |
| `cantidad_invalida` | Cantidad inválida | fallo | servidor |

Mapeo de motivo del reporte a causa y resultado: el motivo `objetivo_alcanzado` produce
éxito con causa `objetivo_alcanzado` solo si los medidos son iguales o mayores que los
solicitados de la orden; si son menores, produce fallo con causa `entrega_incompleta`.
Cualquier otro motivo del catálogo produce fallo con la causa homónima. Las causas
`sin_reporte`, `orden_cerrada`, `orden_desconocida`, `entrega_incompleta`,
`supera_capacidad` y `cantidad_invalida` las asigna el servidor y nunca provienen del
reporte. Un motivo que no pertenezca a este catálogo se rechaza según RF-21.

### Catálogo de errores

Los errores de negocio se devuelven con HTTP 400 y el cuerpo `detail={code,message}`, con
el mensaje visible en español. El 5xx queda reservado a los fallos de escritura, para que
el dispositivo reintente. Ningún rechazo de negocio responde 422.

| Código | Mensaje visible | Cuándo se usa |
| --- | --- | --- |
| `cantidad_invalida` | La cantidad debe ser un número mayor que cero. | Reabastecimiento con cantidad menor o igual que cero o no numérica (RF-12). |
| `supera_capacidad` | La cantidad supera la capacidad máxima de 5000 g del dispensador. | Reabastecimiento cuya suma con el stock actual supera 5000 g (RF-12). |
| `tipo_evento_invalido` | El tipo de evento no pertenece al catálogo. | Filtro por un tipo fuera del catálogo cerrado (RF-31). |
| `resultado_invalido` | El resultado no pertenece al catálogo. | Filtro por un resultado fuera del catálogo cerrado (RF-31). |
| `rango_fechas_invalido` | El rango de fechas no es válido: revise el orden de los límites y el desplazamiento horario. | Fecha final anterior a la inicial, límite sin sufijo `Z` ni desplazamiento, o instante inválido (RF-30, RF-31). |
| `pagina_invalida` | El número de página debe ser 1 o mayor. | Página menor que 1 (RF-32). |
| `tamano_pagina_invalido` | El tamaño de página debe estar entre 1 y 100. | Tamaño de página fuera del intervalo de 1 a 100 (RF-32). |
| `motivo_invalido` | El motivo del reporte no pertenece al catálogo. | Reporte con motivo fuera del catálogo cerrado (RF-21, RF-39). |
| `mac_no_registrada` | El dispensador no está registrado. | Reporte cuya MAC normalizada no corresponde a ningún dispensador (RF-21, RF-39). |
| `orden_desconocida` | La orden indicada no existe para el dispensador que reporta. | Reporte cuya orden no existe para ese dispensador (RF-21, RF-39). |
| `stock_fuera_de_rango` | El stock resultante quedaría fuera del intervalo de 0 a 5000 g. | Operación distinta del reabastecimiento de RF-12 que intentaría dejar el stock fuera del intervalo (RF-22). |

## Requisitos funcionales

### A. Generación de registros (RF-1 a RF-12)

- **RF-1:** CUANDO se cierre una orden con éxito, EL SISTEMA aplicará el descuento de
  stock, el cierre de la orden y la escritura del registro en una única transacción; SI la
  escritura del registro falla, ENTONCES no quedará ni descuento ni cierre, el stock y la
  orden conservarán el estado anterior y el dispositivo recibirá una respuesta de error
  del servidor (5xx) para reintentar el reporte; la comida ya entregada no se recoloca ni
  se compensa en el stock.
- **RF-2:** SI una operación se rechaza antes de producir un cambio de estado (orden
  inválida, dispensador no registrado, reporte con motivo inválido, consulta con
  parámetros inválidos o acceso no autorizado), ENTONCES EL SISTEMA no escribirá ningún
  registro, salvo el reabastecimiento rechazado de RF-12 y el registro de fallo con causa
  `orden_desconocida` que exige RF-21; no hay ninguna otra excepción.
- **RF-3:** EL SISTEMA escribirá cada registro con fecha y hora del servidor, usuario
  propietario, tipo de evento del catálogo, resultado del catálogo, causa del catálogo
  cuando aplique, mascota y dispensador afectados con su MAC parcial, una descripción breve
  en español y los datos de contexto del evento; nunca incluirá contraseñas, tokens,
  claves, SSID, credenciales WiFi, correos electrónicos ni la MAC completa.
- **RF-4:** CUANDO se cree una mascota y la operación se confirme, EL SISTEMA escribirá un
  registro de tipo `pet_created` con resultado éxito, sin causa, con la mascota afectada en
  el contexto y sin datos personales del usuario.
- **RF-5:** CUANDO se modifique una mascota y la operación se confirme, EL SISTEMA
  escribirá un registro de tipo `pet_updated` con resultado éxito, sin causa, con la
  mascota afectada y los nombres de los campos modificados en el contexto, sin los valores
  anteriores ni los nuevos.
- **RF-6:** CUANDO se elimine una mascota y la operación se confirme, EL SISTEMA escribirá
  un registro de tipo `pet_deleted` con resultado éxito, sin causa, y conservará la
  referencia de la mascota para que sus registros históricos sigan siendo consultables.
- **RF-7:** CUANDO se vincule un dispensador a una mascota y la operación se confirme, EL
  SISTEMA escribirá un registro de tipo `dispenser_linked` con resultado éxito, sin causa,
  con la mascota y la MAC parcial del dispensador en el contexto.
- **RF-8:** CUANDO se modifique un dispensador y la operación se confirme, EL SISTEMA
  escribirá un registro de tipo `dispenser_updated` con resultado éxito, sin causa, con la
  mascota, la MAC parcial y los nombres de los campos modificados en el contexto, sin
  claves secretas ni credenciales.
- **RF-9:** CUANDO se desvincule un dispensador de su mascota y la operación se confirme,
  EL SISTEMA escribirá un registro de tipo `dispenser_unlinked` con resultado éxito, sin
  causa, con la mascota y la MAC parcial del dispensador en el contexto.
- **RF-10:** CUANDO se solicite el reseteo de WiFi de un dispensador y la operación se
  confirme, EL SISTEMA escribirá un registro de tipo `dispenser_wifi_reset` con resultado
  éxito, sin causa, con la MAC parcial en el contexto y sin SSID ni credenciales.
- **RF-11:** CUANDO se acepte un reabastecimiento, EL SISTEMA escribirá un registro de tipo
  `dispenser_refilled` con resultado éxito, con los gramos añadidos, el stock resultante y
  la marca de origen (`servidor` o `sincronizacion_sin_conexion`) en el contexto; SI el
  reabastecimiento se realizó sin conexión y se sincroniza después, ENTONCES la fecha y
  hora del registro serán las de la sincronización y el contexto indicará que fue sin
  conexión; SI el mismo reabastecimiento pendiente se sincroniza más de una vez, ENTONCES
  se aplicará una sola vez y generará un único registro.
- **RF-12:** SI un reabastecimiento se rechaza porque la cantidad es menor o igual que
  cero o no es numérica, ENTONCES EL SISTEMA responderá HTTP 400 con el código
  `cantidad_invalida`; SI la suma con el stock actual supera 5000 g, ENTONCES responderá
  HTTP 400 con el código `supera_capacidad`; en ambos casos mantendrá el stock intacto y
  escribirá un registro de tipo `dispenser_refilled` con resultado fallo, la causa
  correspondiente del catálogo y la cantidad intentada en el contexto, en una transacción
  independiente de la operación rechazada para que persista aunque la operación no se
  confirme; ningún rechazo de negocio responderá 422 y todos responderán 400 con un código
  del catálogo de errores.

### B. Dispensado y stock (RF-13 a RF-25)

- **RF-13:** CUANDO el servidor entregue una orden de dispensación, EL SISTEMA creará la
  orden con identificador propio, mascota, dispensador, gramos solicitados, fecha y hora de
  entrega del servidor y estado pendiente, sin modificar el stock; el plazo de 5 minutos se
  contará desde esa fecha y hora de entrega.
- **RF-14:** CUANDO el dispositivo envíe un reporte de fin de ciclo, EL SISTEMA aceptará
  únicamente la MAC del dispensador, el identificador de orden, el motivo, los gramos
  solicitados, los gramos medidos y el número de reintentos; los gramos medidos podrán
  faltar o llegar como nulos cuando el sensor no esté disponible, y el sistema admitirá esa
  ausencia declarada sin rechazar el reporte; los gramos solicitados también podrán faltar o
  llegar como nulos, por ejemplo en un cierre con motivo `orden_invalida` en el que el
  dispositivo no conoce la orden, y el sistema admitirá igualmente esa ausencia sin rechazar
  el reporte, la registrará como «no disponible» en el contexto y no la usará para comparar
  el éxito, porque la comparación siempre usa los gramos solicitados guardados en la orden;
  normalizará la MAC recibida y comprobará que corresponde a un dispensador registrado antes
  de procesarlo, con las consecuencias definidas en RF-21.
- **RF-15:** CUANDO un reporte declare el motivo `objetivo_alcanzado` y los gramos medidos
  sean iguales o mayores que los gramos solicitados guardados en la orden, EL SISTEMA
  cerrará la orden como éxito con causa `objetivo_alcanzado`, guardará medidos y
  descontados como campos distintos y descontará del stock los gramos medidos acotados
  entre 0 y el stock disponible, dejando el stock resultante entre 0 y 5000 g; los gramos
  solicitados que envíe el reporte no se usarán para comparar y solo se guardarán en el
  contexto; SI los medidos superan el stock disponible, ENTONCES descontará todo el
  disponible y reflejará el faltante en el contexto del registro.
- **RF-16:** SI un reporte declara `objetivo_alcanzado` pero los gramos medidos son menores
  que los solicitados de la orden, ENTONCES EL SISTEMA cerrará la orden como fallo con
  causa `entrega_incompleta`, conservará los gramos solicitados y medidos en el contexto y
  no descontará stock, aunque el dispositivo haya declarado el objetivo cumplido; SI los
  gramos medidos no están disponibles, ENTONCES tampoco podrá acreditarse el objetivo y la
  orden cerrará como fallo con causa `entrega_incompleta`, sin descuento.
- **RF-17:** SI un reporte declara un motivo distinto de `objetivo_alcanzado`, ENTONCES EL
  SISTEMA cerrará la orden como fallo con la causa correspondiente del catálogo
  (`objetivo_no_alcanzado`, `atasco_no_resuelto`, `sensor_no_disponible`,
  `fallo_sensor_dispensacion` u `orden_invalida`), conservará los gramos medidos en el
  contexto cuando estén disponibles y no descontará stock.
- **RF-18:** CUANDO llegue un reporte de una orden que ya está cerrada, EL SISTEMA
  responderá HTTP 200 con el resultado ya registrado y el indicador `ya_cerrada: true`,
  sin escribir un segundo registro y sin volver a descontar stock, aunque el motivo o los
  gramos medidos difieran de los del primer reporte.
- **RF-19:** CUANDO venza el plazo más la tolerancia de 1 segundo de una orden pendiente sin
  reporte, EL SISTEMA la cerrará como fallo con causa `sin_reporte`, escribirá su registro y
  no modificará el stock; el barrido solo cerrará órdenes pendientes cuyo plazo más la
  tolerancia de 1 segundo ya haya vencido, se ejecutará cada 30 segundos según RNF-3 y el
  cierre ocurrirá a más tardar 60 segundos después de ese instante; el barrido nunca cierra
  una orden cuyo plazo más 1 segundo no haya vencido.
- **RF-20:** SI un reporte de una orden pendiente llega más de 1 segundo después de
  cumplirse el plazo, ENTONCES EL SISTEMA la cerrará como fallo con causa `orden_cerrada`,
  conservará los gramos solicitados y medidos en el contexto, no descontará stock y
  responderá HTTP 200 con el resultado ya registrado y el indicador `ya_cerrada: true`,
  igual que RF-18; un reporte que llegue dentro de la tolerancia de 1 segundo posterior al
  vencimiento se considerará dentro del plazo. La comparación se hace siempre contra el
  plazo más 1 segundo usando la hora de recepción del servidor, con independencia de si el
  barrido de vencimientos ya se ejecutó: si la orden sigue pendiente se cierra con causa
  `orden_cerrada`, y si el barrido ya la cerró se devuelve el resultado ya registrado con
  `ya_cerrada: true` según RF-18, en ambos casos sin descuento y sin segundo registro.
- **RF-21:** SI un reporte se refiere a una orden que no existe para ese dispensador,
  ENTONCES EL SISTEMA escribirá un registro de tipo `feeding_dispensed` con resultado fallo
  y causa `orden_desconocida`, con los datos disponibles en el contexto, sin modificar el
  stock y responderá HTTP 400 con el código `orden_desconocida`; SI el motivo del reporte
  no pertenece al catálogo de causas, ENTONCES responderá HTTP 400 con el código
  `motivo_invalido` sin escribir ningún registro, la orden permanecerá pendiente y cerrará
  por plazo como `sin_reporte`; SI la MAC normalizada no corresponde a un dispensador
  registrado, ENTONCES rechazará el reporte con HTTP 400 y el código `mac_no_registrada`
  sin escribir ningún registro.
- **RF-22:** EL SISTEMA mantendrá el stock de cada dispensador dentro del intervalo cerrado
  de 0 a 5000 g en toda operación, de modo que ningún descuento, reabastecimiento o
  sincronización produzca un valor negativo ni superior a 5000 g; SI una operación distinta
  del reabastecimiento de RF-12 intentara dejar el stock fuera de ese intervalo, ENTONCES
  la rechazará con HTTP 400 y el código `stock_fuera_de_rango`, sin aplicar cambios
  parciales.
- **RF-23:** EL SISTEMA calculará el stock exclusivamente en el servidor a partir de los
  descuentos confirmados y de los reabastecimientos aceptados o sincronizados, y no
  aceptará del cliente ni del dispositivo un valor de stock como fuente de verdad. El stock
  enviado por el cliente en la actualización del dispensador se ignora y tampoco produce
  error; el servidor responde con su propio valor.
- **RF-24:** EL SISTEMA escribirá en el registro de dispensado el identificador de orden,
  los gramos solicitados, los medidos, los descontados, el stock resultante, la causa y el
  número de reintentos; SI un dato no está disponible, incluidos los gramos medidos cuando
  el sensor no estaba disponible, ENTONCES lo registrará explícitamente como «no
  disponible» en el contexto en lugar de omitirlo.
- **RF-25:** MIENTRAS un dispensador tenga una orden pendiente dentro de su plazo, EL
  SISTEMA no le entregará una nueva orden de dispensación y responderá sin dispensación; la
  comida programada que coincida con ese bloqueo no se pierde, queda en espera y se entrega
  cuando la orden anterior cierre o venza su plazo. MIENTRAS un dispensador esté
  desactivado, EL SISTEMA no le dispensará ninguna orden, ni durante el plazo de una orden
  pendiente ni después de que ese plazo venza; el vencimiento libera el bloqueo de la orden
  pendiente pero no habilita por sí solo la dispensación mientras el dispensador siga
  desactivado. La comida programada que coincida con la desactivación, incluida la que quedó
  en espera por una orden pendiente, se mantiene en espera, no se pierde, no se descarta y
  se entrega al reactivarse el dispensador, siempre que en ese momento no haya otra orden
  pendiente dentro de su plazo. La hora de la programación se interpreta en la zona horaria
  local del servidor, según la definición de hora del horario de comida.

### C. Consulta y filtrado (RF-26 a RF-35)

- **RF-26:** CUANDO el usuario consulte el historial, EL SISTEMA devolverá únicamente los
  registros de su propiedad, ordenados del más reciente al más antiguo por fecha y hora del
  servidor.
- **RF-27:** CUANDO el usuario filtre por mascota, EL SISTEMA devolverá únicamente los
  registros asociados a esa mascota, incluidos los de una mascota ya eliminada cuyo
  identificador se conserve.
- **RF-28:** CUANDO el usuario filtre por tipo de evento, EL SISTEMA devolverá únicamente
  los registros de ese tipo del catálogo cerrado, y ningún registro sin clasificar.
- **RF-29:** CUANDO el usuario filtre por resultado, EL SISTEMA devolverá únicamente los
  registros con ese resultado del catálogo cerrado, y ningún registro sin clasificar.
- **RF-30:** CUANDO el usuario filtre por rango de fechas, EL SISTEMA recibirá los límites
  inicial y final como instantes ISO 8601 con desplazamiento explícito, los convertirá a
  UTC y devolverá los registros cuya fecha y hora del servidor, también en UTC, caiga
  dentro de ese intervalo, incluyendo ambos extremos; el sufijo `Z` cuenta como
  desplazamiento explícito y se interpreta como UTC, de modo que
  `2026-10-01T00:00:00Z` equivale a `2026-10-01T00:00:00+00:00`; SI un límite carece de
  sufijo `Z` y de desplazamiento o no es un instante válido, ENTONCES rechazará la consulta
  según RF-31 y no asumirá un desplazamiento ni una zona horaria por su cuenta.
- **RF-31:** CUANDO el usuario combine varios filtros, EL SISTEMA los aplicará en
  conjunción, de modo que el resultado cumpla todos los filtros indicados a la vez; SI un
  tipo de evento no pertenece al catálogo, ENTONCES responderá HTTP 400 con el código
  `tipo_evento_invalido`; SI un resultado no pertenece al catálogo, ENTONCES responderá
  HTTP 400 con el código `resultado_invalido`; SI la fecha final es anterior a la inicial o
  un límite no es un instante con sufijo `Z` o con desplazamiento válido, ENTONCES
  responderá HTTP 400 con el código `rango_fechas_invalido`; el sufijo `Z` se acepta como
  desplazamiento explícito de UTC y solo su ausencia junto con la del desplazamiento produce
  el rechazo; en ningún caso devolverá resultados parciales ni corregirá los valores
  recibidos, y todos los rechazos usarán el catálogo de errores.
- **RF-32:** EL SISTEMA devolverá cada consulta con los ítems de la página, el total de
  registros que cumplen los filtros, el número de página y el tamaño de página; usará 50
  ítems por defecto y un máximo de 100; SI la página es menor que 1, ENTONCES responderá
  HTTP 400 con el código `pagina_invalida`; SI el tamaño de página está fuera del intervalo
  de 1 a 100, ENTONCES responderá HTTP 400 con el código `tamano_pagina_invalido`; en
  ningún caso recortará los valores en silencio.
- **RF-33:** CUANDO el usuario abra la pantalla de historial, EL SISTEMA mostrará una lista
  paginada con fecha y hora, etiqueta del evento, etiqueta del resultado, etiqueta de la
  causa, mascota, MAC parcial y, en los dispensados, gramos solicitados, medidos y
  descontados; ofrecerá cuatro filtros combinables (mascota, tipo de evento, resultado y
  rango de fechas) y un botón «Limpiar filtros» que restablezca la primera página sin
  filtros; mostrará la página actual, el total de páginas y el total de registros, con los
  controles de página anterior y siguiente deshabilitados en los extremos; SI no hay
  registros, mostrará el texto «No hay registros para los filtros seleccionados»; SI la
  consulta falla, mostrará el mensaje de error con una acción de reintento y conservará los
  filtros aplicados; SI los datos provienen de la caché local, mostrará el aviso de datos
  sin conexión; todos los textos estarán en español y la pantalla se adaptará al ancho del
  móvil sin desbordamientos.
- **RF-34:** SI no hay conexión o el servidor no responde, ENTONCES EL SISTEMA mostrará los
  registros de la caché local aplicando los mismos filtros y la misma paginación, con el
  aviso de que son datos locales y sin borrar la lista ya mostrada; el total de registros y
  el número de páginas se calcularán sobre los registros disponibles en la caché local para
  los filtros aplicados, y la interfaz lo indicará junto al aviso de datos locales.
- **RF-35:** CUANDO se descarguen registros del servidor, EL SISTEMA los guardará en la
  caché local para su consulta sin conexión, conservando la última versión descargada de
  cada registro y sin duplicar registros ya almacenados.

### D. Firmware del dispositivo (RF-36 a RF-41)

- **RF-36:** CUANDO finalice un ciclo de dispensación, sea por objetivo alcanzado, objetivo
  no alcanzado, atasco no resuelto, fallo del sensor durante la dispensación, sensor no
  disponible u orden inválida, EL SISTEMA enviará al servidor un reporte con la MAC del
  dispensador, el identificador de la orden, el motivo, los gramos solicitados, los gramos
  medidos cuando estén disponibles y el número de reintentos; SI el sensor no está
  disponible, ENTONCES enviará el motivo `sensor_no_disponible` sin gramos medidos y el
  servidor lo admitirá como ausencia declarada según RF-14; SI el cierre es por
  `orden_invalida` y el dispositivo no dispone de los gramos solicitados de la orden,
  ENTONCES enviará el reporte sin ese campo o con valor nulo, y el servidor lo admitirá y lo
  registrará como «no disponible» en el contexto según RF-14.
- **RF-37:** SI el envío del reporte no obtiene respuesta en 10 segundos o falla por un
  error de red, ENTONCES EL SISTEMA reintentará hasta dos veces más, la primera a los 5
  segundos y la segunda a los 15 segundos del fallo anterior, conservará el reporte
  pendiente en memoria no volátil y lo reenviará tras un reinicio del dispositivo. El
  reenvío del pendiente se intentará una sola vez al arrancar, justo después de conectar a
  la red WiFi y antes de cualquier consulta al servidor, con independencia de que el
  servidor responda o no.
- **RF-38:** EL SISTEMA conservará sin cambios la ventana de verificación de 2 segundos, la
  ventana de gracia de 2 segundos, la ventana de estancamiento de 5 segundos, el presupuesto
  de motor de 30 segundos, las tolerancias de detección y resolución de atascos y el
  reinicio del temporizador de consulta periódica a 20 segundos después de finalizar el
  ciclo, tal como los define la spec 013.
- **RF-39:** SI el servidor responde 200 con el resultado registrado o con el indicador
  `ya_cerrada: true`, incluido el cierre tardío con causa `orden_cerrada` de RF-20, o
  responde HTTP 400 con los códigos `orden_desconocida`, `motivo_invalido` o
  `mac_no_registrada`, ENTONCES EL SISTEMA descartará el reporte y no lo reintentará aunque
  queden reintentos disponibles; SI la respuesta es un error de red, un timeout o un error
  5xx del servidor, ENTONCES mantendrá el reporte y aplicará los reintentos de RF-37.
- **RF-40:** MIENTRAS un dispensador ejecute firmware antiguo, EL SISTEMA cerrará sus
  órdenes por vencimiento del plazo con causa `sin_reporte` y sin modificar el stock, sin
  exigir ningún reporte para cerrarlas.
- **RF-41:** CUANDO el historial contenga registros anteriores a esta spec sin tipo,
  resultado ni causa, EL SISTEMA los mostrará con la etiqueta «Sin clasificar», los
  excluirá de los filtros por tipo de evento y resultado, y los conservará visibles en la
  consulta sin filtros.

## Requisitos no funcionales

- **RNF-1:** Todos los textos visibles y las descripciones de registro estarán en español,
  sin emojis, y no incluirán contraseñas, tokens, claves, SSID, credenciales WiFi, correos
  electrónicos ni la MAC completa del dispensador.
- **RNF-2:** EL SISTEMA resolverá el 95 % de las consultas de historial en menos de 1
  segundo con 10 000 registros del usuario y los cuatro filtros aplicados, medido sobre el
  percentil 95 de 100 consultas consecutivas en el entorno de pruebas.
- **RNF-3:** EL SISTEMA garantizará exclusión mutua entre el cierre por vencimiento y el
  procesamiento de un reporte de la misma orden, de modo que una sola transición de
  pendiente a cerrada gane: dos reportes simultáneos producirán un único cierre y un único
  descuento de stock, y un reporte que compita con el barrido de vencimientos se resolverá
  como reporte procesado dentro de la tolerancia o como orden ya cerrada, nunca con doble
  escritura ni doble descuento. El barrido de vencimientos se ejecutará cada 30 segundos y
  nunca cerrará una orden cuyo plazo más la tolerancia de 1 segundo no haya vencido, de modo
  que el cierre queda garantizado dentro de los 60 segundos posteriores a ese instante; el
  barrido actual del proyecto corre cada 60 segundos y deberá acortarse a 30 segundos para
  cumplir RF-19.
- **RNF-4:** No se añadirán dependencias externas nuevas; las validaciones, el cálculo de
  fechas, la conversión de los instantes recibidos a UTC y la paginación se resolverán con
  funciones del propio proyecto, y la app resolverá por su cuenta el cambio de horario.
  `flutter_localizations` e `intl` provienen del SDK de Flutter y no cuentan como
  dependencia externa.
- **RNF-5:** La lógica de registro, cierre de orden, descuento y filtrado vivirá en las
  capas de dominio y servicios, desacoplada de la interfaz; las vistas solo presentarán
  estado y emitirán eventos, con la gestión de estado del proyecto.
- **RNF-6:** Cada RF tendrá al menos una prueba automatizada que lo valide y que falle si el
  requisito se incumple; los RF cuyo efecto observable es físico (reporte, reintentos y
  persistencia del firmware) o visual (interfaz del historial) exigirán además una prueba
  física o manual documentada, que no sustituye a la automatizada.
- **RNF-7:** El catálogo de tipos de evento, resultados y causas, así como el de errores,
  será cerrado: cualquier valor no incluido se rechazará con HTTP 400 y el código del
  catálogo de errores, y no se escribirá ningún registro con valores libres; ampliar
  cualquiera de los catálogos exigirá modificar esta spec.
- **RNF-8:** Todas las fechas y horas de los registros, de la entrega y el cierre de las
  órdenes y de los plazos serán las del servidor y se almacenarán y compararán en UTC; la
  hora local solo existe en la interfaz, y la fecha y hora del dispositivo o del cliente no
  se usarán como fuente de verdad, salvo los límites del filtro de fechas, que llegan como
  instantes con desplazamiento y el servidor convierte a UTC. La hora de los horarios de
  comida es la única excepción: se interpreta en la zona horaria local del servidor, según
  su definición.

## Casos límite

- **Reporte duplicado idéntico de una orden ya cerrada:** se responde 200 con el resultado
  ya registrado y `ya_cerrada: true`, no se escribe un segundo registro y no se descuenta
  stock otra vez.
- **Reporte duplicado con motivo o gramos distintos:** se ignora el segundo reporte y
  prevalece el primer cierre, sin nuevo registro ni nuevo descuento.
- **Dos reportes simultáneos de la misma orden:** un único cierre y un único descuento; el
  segundo se resuelve como duplicado.
- **Reporte y barrido de vencimientos sobre la misma orden:** gana una sola transición; el
  resultado es cierre por reporte dentro del plazo, cierre como `orden_cerrada` si el
  reporte llega después de la tolerancia y la orden seguía pendiente, o cierre como
  `sin_reporte` si el barrido se adelantó, y en ese último caso el reporte posterior recibe
  200 con el resultado ya registrado y `ya_cerrada: true` según RF-18; nunca hay doble
  registro.
- **Reporte tardío, más de 1 segundo después del plazo:** cierre como fallo `orden_cerrada`,
  sin descuento, con los gramos medidos y solicitados en el contexto, y respuesta HTTP 200
  con `ya_cerrada: true`; el firmware descarta el reporte.
- **Reporte dentro de la tolerancia de 1 segundo posterior al vencimiento:** se procesa
  como dentro del plazo y se cierra por el motivo reportado; la comparación usa la hora de
  recepción del servidor y el límite exacto plazo más 1 segundo, de modo que una recepción
  en ese instante exacto o antes está dentro del plazo, y el barrido no puede haber cerrado
  la orden porque solo cierra después de ese instante.
- **Orden sin reporte con el dispositivo apagado:** cierre como fallo `sin_reporte` a más
  tardar 60 segundos después de cumplirse el plazo más la tolerancia de 1 segundo, sin
  alterar el stock.
- **Dispensador con firmware antiguo:** todas sus órdenes se cierran por plazo con
  `sin_reporte`, sin descuento, sin exigir reporte.
- **Medidos mayores que los solicitados:** cierre como éxito y descuento igual a los
  medidos, no a los solicitados.
- **Solicitados del reporte distintos de los de la orden:** prevalece el valor guardado en
  la orden para comparar el éxito; los del reporte se auditan y quedan en el contexto.
- **Objetivo alcanzado declarado con medidos menores que los solicitados:** cierre como
  fallo `entrega_incompleta` y stock intacto.
- **Objetivo alcanzado declarado sin medidos:** cierre como fallo `entrega_incompleta`, sin
  descuento y con los medidos como no disponibles en el contexto.
- **Reporte con medidos no disponibles (sensor no disponible):** se acepta el reporte, se
  cierra con la causa del motivo, se guarda «no disponible» en el contexto y no se descuenta
  stock.
- **Reporte con motivo fuera del catálogo:** HTTP 400 con `motivo_invalido`, sin registro,
  orden pendiente que cierra por plazo como `sin_reporte`; el firmware lo descarta.
- **Stock en 0 g y medidos mayores que 0:** cierre como éxito con descontados 0, stock 0 y
  faltante igual a los medidos en el contexto.
- **Stock insuficiente (100 g de stock y 150 g medidos):** se descuentan 100 g, el stock
  queda en 0 y el faltante de 50 g queda reflejado en el contexto.
- **Entrega incompleta o reporte tardío con alimento ya entregado:** el alimento salió y no
  se descuenta, por lo que el stock queda por encima de lo real; es un desvío aceptado que
  no se compensa con ajustes automáticos y solo podría corregirse con un reabastecimiento o
  un ajuste manual futuro, fuera de alcance.
- **Stock en 5000 g:** un reabastecimiento que deje el total en 5000 g se acepta; cualquier
  suma que lo supere se rechaza con HTTP 400 y `supera_capacidad`, y el stock no cambia.
- **Mascota eliminada después de entregar la orden:** la orden cierra por su reporte o por
  plazo y el registro conserva la referencia de la mascota eliminada.
- **Mascota eliminada y dispensador desvinculado con orden pendiente:** la orden se cierra
  por plazo con `sin_reporte`, sin descuento, y no se emiten órdenes nuevas.
- **Dispensador eliminado con orden pendiente:** la orden se cierra por plazo sin descuento;
  un reporte posterior de esa MAC se rechaza con `mac_no_registrada` y sin registro.
- **Dispensador reasignado a otra mascota con orden pendiente:** la orden conserva la
  mascota y el dispensador originales, y el descuento se aplica al stock de ese mismo
  dispensador.
- **Comida programada que coincide con una orden pendiente:** no se dispensa, no se pierde,
  queda en espera y se entrega cuando la orden anterior cierre o venza el plazo.
- **Comida programada en espera con el dispensador desactivado:** se mantiene en espera sin
  perderse ni descartarse aunque venza el plazo de la orden pendiente, no se dispensa
  mientras el dispensador siga desactivado y se entrega al reactivarse.
- **Reabastecimiento sin conexión sincronizado dos veces:** se aplica una sola vez, con un
  único registro y un único incremento de stock, porque la app reenvía el mismo
  identificador de operación.
- **Reabastecimiento sincronizado sin identificador de operación:** el servidor no puede
  distinguir un reintento de un reabastecimiento nuevo; aplica la cantidad de la petición
  una vez y cada reenvío posterior del mismo pendiente vuelve a incrementar el stock. La
  idempotencia de RF-11 depende de que el cliente envíe el identificador de operación y lo
  conserve junto al pendiente, así que la app debe enviarlo siempre al sincronizar.
- **Reabastecimiento sin conexión que al sincronizar supera la capacidad:** se rechaza con
  HTTP 400 y `supera_capacidad`, se registra el fallo, se reconcilia el stock con el del
  servidor y se descarta el pendiente, sin duplicar la cantidad.
- **Reabastecimiento con cantidad cero, negativa, no numérica o que supera la capacidad:**
  HTTP 400 con `cantidad_invalida` o `supera_capacidad`, stock intacto y registro de fallo
  escrito aunque la operación se rechace; nunca 422.
- **Consulta con página menor que 1, tamaño fuera de 1 a 100, tipo o resultado fuera del
  catálogo, fecha final anterior a la inicial o límite sin sufijo `Z` ni desplazamiento:** HTTP 400 con
  `pagina_invalida`, `tamano_pagina_invalido`, `tipo_evento_invalido`,
  `resultado_invalido` o `rango_fechas_invalido` según corresponda, sin resultados
  parciales y sin recortar los valores.
- **Consulta con límites en distinta zona horaria o con cambio de horario:** cada límite se
  interpreta por su propio desplazamiento; la app resuelve el cambio de horario y el
  servidor solo compara instantes en UTC.
- **Consulta con un límite en UTC con sufijo `Z`:** `2026-10-01T00:00:00Z` se acepta como
  desplazamiento explícito y se compara igual que `2026-10-01T00:00:00+00:00`; no se rechaza
  por falta de desplazamiento.
- **Consulta sin resultados:** lista vacía, total 0 y página 1, sin mensaje de error.
- **Consulta sin conexión:** se muestran los registros de la caché local con el aviso de
  datos sin conexión, y el total y el número de páginas corresponden a la caché para los
  filtros aplicados; si la caché está vacía, se informa que no hay datos locales.
- **Registros históricos sin clasificación:** se muestran como «Sin clasificar» en la
  consulta sin filtros y no aparecen al filtrar por tipo ni por resultado.
- **Filtro por mascota eliminada:** devuelve sus registros históricos si el identificador
  se conserva.
- **Fallo al escribir el registro de un dispensado exitoso:** no queda descuento ni cierre,
  el dispositivo recibe un 5xx y el reintento posterior cierra la orden una sola vez.
- **Reporte de orden inválida:** cierre como fallo `orden_invalida`, sin descuento y con los
  gramos medidos como no disponibles si no existen.
- **Reporte de orden desconocida:** HTTP 400 con `orden_desconocida`, registro de fallo con
  los datos disponibles y stock intacto; el firmware lo descarta.
- **Reporte con MAC no registrada:** HTTP 400 con `mac_no_registrada`, sin escribir ningún
  registro.
- **Reinicio del dispositivo con un reporte pendiente:** el reporte se reenvía al arrancar
  y, si ya pasó el plazo más la tolerancia y la orden seguía pendiente, se cierra como
  `orden_cerrada` sin descuento; si el barrido la cerró antes, se responde 200 con el
  resultado ya registrado y `ya_cerrada: true` según RF-18.

## Relación con las specs 013 y 012

- **Spec 013 (dispensado por peso):** esta spec implementa lo que 013 dejó fuera de
  alcance, es decir, reportar al backend el peso real dispensado y el motivo del fallo,
  incluidos los atascos, y resuelve la deuda aceptada de 013 de descontar stock al emitir
  la orden. Las causas del catálogo reutilizan los motivos de 013 con código y etiqueta en
  español. Los umbrales, ventanas, tolerancias y el presupuesto de motor de 013 no
  cambian; RF-38 garantiza que no haya regresión.
- **Spec 012 (stock en tiempo real):** 012 sigue siendo la referencia para la tarjeta de
  stock, el reabastecimiento sin conexión y el límite de 5 kg, y esta spec no cambia esa
  interfaz. 014 añade el registro de cada reabastecimiento aceptado o rechazado, define que
  el reabastecimiento sincronizado se registra con la hora de la sincronización e indica en
  el contexto que fue sin conexión, y exige que el pendiente no se aplique dos veces.
- **Prevalencia:** 013 prevalece en el comportamiento del firmware de dispensación, 012 en
  la presentación y el cálculo local del stock, y 014 en la generación de registros, el
  cierre de órdenes y el descuento de stock en el servidor.

## Compatibilidad del contrato de consulta

La consulta vigente del historial, que acepta una única fecha, se sustituye por el nuevo
contrato de rango con instantes ISO 8601 con desplazamiento explícito y paginación descrito
en RF-30 y RF-32. No hay periodo de compatibilidad porque la API es interna: la app móvil
se actualiza en la misma spec y ninguna versión en uso sigue enviando el parámetro único.

## Fuera de alcance

- Purgado, archivado o retención programada de registros.
- Búsqueda de texto libre sobre el historial.
- Notificaciones push o avisos al móvil por fallos de dispensación.
- Autenticación avanzada del dispositivo más allá de la MAC registrada.
- Soporte multiusuario sobre un mismo dispensador.
- Cambios en el motor nutricional de la spec 011.
- Corrección retroactiva de registros históricos o de stocks ya descontados.
- Recolocar en el depósito el alimento ya entregado cuando falla la escritura del registro.
- Ajuste manual de stock para compensar entregas no descontadas o el desvío aceptado.
- Cambios en los umbrales, ventanas o presupuesto de motor de la spec 013.
- Medición del nivel del depósito o detección de depósito vacío distinta del peso.

## Criterios de finalización

- `pytest`, `flutter test`, `flutter analyze` y `pio test -e native` pasan sin errores, y
  `pio run` compila el firmware.
- No hay regresión en las pruebas de las specs 011, 012 y 013.
- `MEMORY.md` actualizado al cerrar la fase.
- Cada RF tiene su prueba automatizada y, cuando aplica, su prueba física o manual
  documentada, según el mapeo siguiente.

### Mapeo RF a prueba

- **RF-1:** prueba automatizada de que un fallo al escribir el registro deja el stock y la
  orden en su estado anterior, devuelve un 5xx al dispositivo y que el reintento posterior
  descuenta una sola vez.
- **RF-2:** prueba automatizada de que una operación rechazada antes del cambio de estado
  (orden inválida, dispensador no registrado, reporte con motivo inválido, consulta
  inválida, acceso no autorizado) no crea registro, de que el reabastecimiento rechazado sí
  lo crea y de que el reporte de orden inexistente de RF-21 es la única otra excepción, con
  su registro de causa `orden_desconocida`.
- **RF-3:** prueba automatizada de que el registro contiene todos los campos obligatorios,
  de que la MAC aparece solo en forma parcial y de que ningún campo incluye credenciales,
  tokens, SSID, correos ni MAC completa.
- **RF-4:** prueba automatizada de que crear una mascota escribe un registro `pet_created`
  con resultado éxito y la mascota en el contexto.
- **RF-5:** prueba automatizada de que modificar una mascota escribe `pet_updated` con
  resultado éxito y los nombres de los campos modificados, sin valores.
- **RF-6:** prueba automatizada de que eliminar una mascota escribe `pet_deleted` y de que
  sus registros históricos siguen siendo consultables.
- **RF-7:** prueba automatizada de que vincular un dispensador escribe
  `dispenser_linked` con MAC parcial y mascota.
- **RF-8:** prueba automatizada de que modificar un dispensador escribe
  `dispenser_updated` sin claves secretas ni credenciales.
- **RF-9:** prueba automatizada de que desvincular un dispensador escribe
  `dispenser_unlinked` con MAC parcial y mascota.
- **RF-10:** prueba automatizada de que el reseteo de WiFi escribe
  `dispenser_wifi_reset` sin SSID ni credenciales.
- **RF-11:** prueba automatizada de que un reabastecimiento aceptado escribe
  `dispenser_refilled` con gramos añadidos, stock resultante y origen `servidor`, de que el
  sincronizado usa la hora de la sincronización y origen `sincronizacion_sin_conexion`, y
  de que el doble envío del mismo pendiente produce un único registro y un único
  incremento.
- **RF-12:** prueba automatizada de que cantidad cero, negativa, no numérica y suma que
  supera 5000 g responden HTTP 400 con `cantidad_invalida` o `supera_capacidad` y
  `detail={code,message}`, dejan el stock intacto, escriben el registro de fallo en
  transacción independiente y de que ninguna de ellas responde 422.
- **RF-13:** prueba automatizada de que entregar una orden crea la orden pendiente con
  identificador, mascota, dispensador, solicitados y hora del servidor, sin tocar el stock.
- **RF-14:** prueba automatizada de que el reporte acepta solo los campos definidos, admite
  la ausencia de gramos medidos cuando el sensor no está disponible y la de gramos
  solicitados en el cierre por `orden_invalida`, registrando ambas como «no disponible» en
  el contexto y sin usar la ausencia de solicitados para comparar el éxito, y de que
  normaliza la MAC antes de comprobar que está registrada.
- **RF-15:** prueba automatizada de que medidos iguales o mayores que los solicitados de la
  orden cierran con éxito, guardan medidos y descontados por separado y descuentan lo
  medido acotado al stock disponible, incluyendo el caso de medidos mayores que el stock y
  el de solicitados del reporte distintos de los de la orden.
- **RF-16:** prueba automatizada de que `objetivo_alcanzado` con medidos menores que
  solicitados cierra como `entrega_incompleta` sin descuento, y de que la ausencia de
  medidos produce el mismo cierre como fallo.
- **RF-17:** prueba automatizada de que cada motivo de fallo del catálogo produce su causa
  correspondiente y ningún descuento de stock.
- **RF-18:** prueba automatizada de que un segundo reporte de una orden cerrada devuelve
  HTTP 200 con el resultado ya registrado y `ya_cerrada: true`, sin segundo registro ni
  segundo descuento.
- **RF-19:** prueba automatizada con reloj del servidor inyectado de que una orden pendiente
  sin reporte se cierra como `sin_reporte` a más tardar 60 segundos después del plazo más la
  tolerancia de 1 segundo, de que el barrido corre cada 30 segundos, de que no cierra una
  orden cuyo plazo más 1 segundo no haya vencido y de que no toca el stock.
- **RF-20:** prueba automatizada con reloj del servidor inyectado de que un reporte recibido
  después del plazo más 1 segundo cierra como `orden_cerrada` sin descuento y responde HTTP
  200 con `ya_cerrada: true`, de que uno recibido en ese instante exacto o antes se procesa
  como dentro del plazo y de que el resultado es el mismo tanto si el barrido ya se ejecutó
  como si no.
- **RF-21:** prueba automatizada de que una orden inexistente genera registro
  `orden_desconocida` y responde 400 con ese código, de que un motivo fuera del catálogo
  responde 400 con `motivo_invalido` sin registro y deja la orden pendiente, y de que una
  MAC no registrada responde 400 con `mac_no_registrada` sin registro.
- **RF-22:** prueba automatizada de que descuentos, reabastecimientos y sincronizaciones
  nunca dejan el stock fuera del intervalo 0 a 5000 g, y de que una operación que lo
  intentara se rechaza con `stock_fuera_de_rango` sin cambios parciales.
- **RF-23:** prueba automatizada de que el stock resultante depende solo de los descuentos
  y reabastecimientos del servidor y de que un valor de stock enviado por el cliente o el
  dispositivo se ignora.
- **RF-24:** prueba automatizada de que el registro de dispensado incluye orden,
  solicitados, medidos, descontados, stock resultante, causa y reintentos, y de que los
  datos ausentes, incluidos los medidos sin sensor, se guardan como «no disponible».
- **RF-25:** prueba automatizada de que no se entrega una nueva orden con otra pendiente en
  plazo, de que la comida programada bloqueada queda en espera y se entrega al cerrar o
  vencer la anterior, de que un dispensador desactivado no dispensa aunque venza el plazo de
  su orden pendiente y de que la comida en espera se conserva sin descartarse y se entrega
  al reactivarse.
- **RF-26:** prueba automatizada de que la consulta solo devuelve registros del usuario
  autenticado y los ordena del más reciente al más antiguo.
- **RF-27:** prueba automatizada de que el filtro por mascota devuelve solo sus registros,
  incluidos los de una mascota eliminada.
- **RF-28:** prueba automatizada de que el filtro por tipo devuelve solo ese tipo del
  catálogo y nunca registros sin clasificar.
- **RF-29:** prueba automatizada de que el filtro por resultado devuelve solo ese resultado
  del catálogo y nunca registros sin clasificar.
- **RF-30:** prueba automatizada de que los límites se reciben como instantes con
  desplazamiento, de que el sufijo `Z` se acepta como UTC y equivale a `+00:00`, de que se
  convierten a UTC, de que el intervalo incluye ambos extremos y de que un límite sin sufijo
  `Z` ni desplazamiento, o inválido, responde 400 con `rango_fechas_invalido`.
- **RF-31:** prueba automatizada de la conjunción de filtros y del HTTP 400 con
  `tipo_evento_invalido`, `resultado_invalido` y `rango_fechas_invalido` según el caso, de
  que un límite con sufijo `Z` no se rechaza y se trata como UTC, y de que no hay recorte
  silencioso ni respuesta fuera del formato `detail={code,message}`.
- **RF-32:** prueba automatizada de la forma de la respuesta (ítems, total, página y
  tamaño), del valor por defecto 50 y del máximo 100, y del HTTP 400 con `pagina_invalida` o
  `tamano_pagina_invalido`.
- **RF-33:** prueba automatizada de widgets de la lista, los cuatro filtros, el botón de
  limpieza, la paginación, los estados vacío y error y los textos en español; prueba manual
  documentada de la adaptación al ancho del móvil sin desbordamientos.
- **RF-34:** prueba automatizada de que sin conexión se muestran los registros de la caché
  con los mismos filtros, la misma paginación y el aviso de datos locales, y de que el
  total y el número de páginas se calculan sobre la caché para los filtros aplicados.
- **RF-35:** prueba automatizada de que los registros descargados se guardan en la caché sin
  duplicados y de que se conserva la última versión.
- **RF-36:** prueba automatizada de que cada motivo de finalización produce el reporte con
  MAC, orden, motivo, solicitados, medidos y reintentos, incluidos el caso sin medidos, el
  caso sin solicitados en el cierre por `orden_invalida` y el del motivo
  `sensor_no_disponible`, que se envía sin medidos; prueba física documentada de que el
  servidor recibe el reporte tras una dispensación real.
- **RF-37:** prueba automatizada del timeout de 10 segundos y de los reintentos a 5 y 15
  segundos, y de que el reporte pendiente se conserva y se reenvía tras reiniciar; prueba
  física documentada con la red caída y el dispositivo reiniciado.
- **RF-38:** pruebas automatizadas de no regresión de las ventanas, el presupuesto de motor
  y el reinicio del temporizador de 20 segundos, ya existentes en la spec 013.
- **RF-39:** prueba automatizada de que el firmware descarta el reporte ante 200 con
  resultado registrado o `ya_cerrada: true`, incluido el cierre tardío de RF-20, y ante 400
  con `orden_desconocida`, `motivo_invalido` o `mac_no_registrada`, y de que un error de
  red, un timeout o un 5xx sí lo reintenta; prueba física documentada de que un reporte
  descartado no se reenvía.
- **RF-40:** prueba automatizada de que una orden de un dispensador con firmware antiguo se
  cierra por plazo sin reporte y sin descuento; prueba física documentada con un firmware
  sin reporte.
- **RF-41:** prueba automatizada de que un registro histórico sin clasificación se muestra
  como «Sin clasificar», aparece sin filtros y no aparece con filtros de tipo ni de
  resultado.
- **Catálogo de errores (transversal):** prueba automatizada de que cada código del
  catálogo devuelve HTTP 400 con `detail={code,message}` y el mensaje en español indicado,
  de que todo código citado por un RF tiene su fila en el catálogo y de que ninguna fila del
  catálogo queda sin uso en un RF, y de que ningún rechazo de negocio responde 422.
- **RNF-1:** prueba automatizada de que los textos y descripciones están en español y no
  contienen patrones de credenciales, tokens, SSID, correos ni MAC completa.
- **RNF-2:** prueba de rendimiento automatizada con 10 000 registros y los cuatro filtros,
  verificando el percentil 95 de 100 consultas por debajo de 1 segundo.
- **RNF-3:** prueba automatizada de concurrencia que confronta dos reportes simultáneos y un
  reporte contra el barrido de vencimientos de la misma orden, verificando una única
  transición a cerrada, un único registro y un único descuento, y de que el barrido corre
  cada 30 segundos y no cierra órdenes con la tolerancia de 1 segundo vigente.
- **RNF-4:** revisión de dependencias del proyecto verificando que no se añadió ninguna
  dependencia externa nueva, incluida la de zonas horarias (`flutter_localizations` e
  `intl` provienen del SDK de Flutter y no cuentan como dependencia externa).
- **RNF-5:** prueba automatizada de que el filtrado, el cierre y el descuento se ejecutan
  sin intervención de la capa de presentación y de que las vistas solo emiten eventos.
- **RNF-6:** revisión de trazabilidad que comprueba que cada RF tiene al menos una prueba
  automatizada asociada y que, cuando aplica, también su prueba física o manual.
- **RNF-7:** prueba automatizada de que un tipo, resultado, causa o código de error fuera
  del catálogo se rechaza con 400 y el código correspondiente, y de que no se escribe
  ningún registro con valores libres.
- **RNF-8:** prueba automatizada de que la fecha y hora de registros, entregas, cierres y
  plazos proviene del servidor, se almacena en UTC y de que la del cliente o del
  dispositivo se ignora como fuente de verdad.

## Dudas abiertas

- Ninguna.
