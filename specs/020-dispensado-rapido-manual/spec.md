# Spec 020 — Dispensación rápida manual y acceso a dispositivos

Estado: cerrada — T1–T6 implementadas y verificadas.

## Contexto y objetivo

Hoy el dispensador solo entrega comida programada por horario. El dueño no puede
dar una ración puntual sin crear o modificar un horario, y cuando una comida
programada coincide con una manual podría dispensarse dos veces. Además, la
acción rápida «Dispositivos» del dashboard abre la lista de mascotas en lugar de
la sección de dispensadores.

El objetivo es permitir una dispensación rápida en la que el usuario solo elija
la cantidad, registrarla en el historial como cualquier dispensado y garantizar
que, si un horario coincide con la solicitud, solo se ejecute la opción rápida.
La cantidad es libre dentro de un límite de seguridad.

## Usuarios

Dueño de mascota que usa la aplicación móvil y tiene un dispensador vinculado.

## Historias de usuario

- HU-1. Como dueño, quiero dispensar una cantidad concreta ahora sin crear un
  horario, para dar una ración puntual.
- HU-2. Como dueño, quiero que una comida programada que coincida con mi
  dispensación rápida no se dispense también, para no dar comida de más.
- HU-3. Como dueño, quiero ver la dispensación rápida en el historial como
  cualquier otra comida dispensada.
- HU-4. Como dueño, quiero que el acceso «Dispositivos» del dashboard me lleve a
  mis dispensadores, no a mis mascotas.

## Definiciones

- **Solicitud rápida:** petición autenticada del dueño para dispensar una
  cantidad concreta en gramos, sin cálculo nutricional.
- **Cantidad rápida:** número decimal mayor que 0 y menor o igual a 200 g; se
  guarda como número de punto flotante.
- **Identificador de operación (`operation_id`):** valor único que la aplicación
  genera por operación y repite tal cual al reintentar con la misma cantidad; lo
  renueva si la cantidad cambia. Es obligatorio y sostiene la idempotencia de
  RF-14.
- **Solicitud pendiente:** solicitud rápida aceptada que el dispositivo todavía
  no ha consultado; no vence.
- **Stock reservado:** stock actual del dispensador menos la suma de las
  cantidades de sus solicitudes pendientes.
- **Ventana de coincidencia:** los 10 minutos anteriores al instante de la
  solicitud, con la hora local del servidor y el mismo criterio del planificador:
  `(ahora − 10 min, ahora]`.
- **Ocurrencia programada:** cada cumplimiento de la hora de un horario de la
  mascota dentro de la ventana de coincidencia.
- **Ocurrencia cubierta:** ocurrencia marcada como consumida sin generar orden ni
  evento porque la sustituye la solicitud rápida; no deja rastro visible por
  ocurrencia.
- **Orden en curso:** orden de dispensación pendiente, ya entregada al
  dispositivo y todavía dentro de su plazo, sin reporte.
- **Orden rápida:** orden de dispensación creada al entregar una solicitud
  rápida; es la misma entidad, plazo, reporte, cierre y descuento de la spec 014.
- **Evento:** registro `feeding_dispensed` que se escribe al cerrar la orden con
  el reporte del dispositivo; si no hay reporte, el cierre por plazo escribe
  `sin_reporte`, como en la spec 014.

### Catálogo de errores

Los rechazos de negocio responden HTTP 400 con `detail={code,message}` y el
mensaje visible en español; ningún rechazo responde 422. La 020 amplía el
catálogo cerrado de la spec 014 (RNF-7 de la 014); el resto de sus códigos sigue
vigente.

| Código | Mensaje visible | Cuándo se usa |
| --- | --- | --- |
| `cantidad_rapida_invalida` | La cantidad rápida debe ser mayor que 0 y no superar 200 g. | Cantidad no numérica, `NaN`, infinita, menor o igual que 0 o mayor que 200 g (RF-2). |
| `stock_insuficiente` | La cantidad solicitada supera el stock disponible del dispensador. | Cantidad mayor que el stock reservado (RF-3). |
| `dispensador_desactivado` | El dispensador está desactivado. | Dispensador inactivo (RF-4). |
| `dispensacion_en_curso` | Ya hay una dispensación en curso para este dispensador. | Orden pendiente dentro de su plazo (RF-5). |
| `operacion_invalida` | El identificador de operación es obligatorio y debe ser válido. | `operation_id` ausente, vacío o no válido (RF-14). |

## Requisitos funcionales

- **RF-1:** CUANDO el dueño confirme una cantidad rápida desde la ficha de la
  mascota, EL SISTEMA aceptará la solicitud si el dispensador pertenece al usuario
  y no se cumple ninguna condición de rechazo de RF-2 a RF-5 ni de RF-14, la
  dejará pendiente de entrega al dispositivo y le asignará un identificador
  propio de solicitud.
- **RF-2:** SI la cantidad no es numérica, es `NaN`, es infinita, es menor o
  igual que 0 o supera 200 g, ENTONCES EL SISTEMA rechazará la solicitud con HTTP
  400 y el código `cantidad_rapida_invalida`, sin crear la solicitud, sin cubrir
  horarios y sin escribir eventos.
- **RF-3:** SI la cantidad supera el stock reservado, ENTONCES EL SISTEMA
  rechazará la solicitud con HTTP 400 y el código `stock_insuficiente`, sin
  modificar el stock ni crear la solicitud; dos solicitudes pendientes no podrán
  sumar más que el stock actual. SI el stock es 0, ENTONCES rechazará cualquier
  cantidad.
- **RF-4:** SI el dispensador está desactivado, ENTONCES EL SISTEMA rechazará la
  solicitud con HTTP 400 y el código `dispensador_desactivado`, sin crear la
  solicitud.
- **RF-5:** SI existe una orden en curso para el dispensador, ENTONCES EL SISTEMA
  rechazará la solicitud con HTTP 400 y el código `dispensacion_en_curso`, sin
  encolarla para después. SI la orden pendiente ya venció su plazo, ENTONCES la
  cerrará primero como `sin_reporte` y evaluará la solicitud con el dispensador
  libre.
- **RF-6:** SI la mascota no tiene dispensador o no pertenece al usuario,
  ENTONCES EL SISTEMA rechazará la solicitud sin revelar datos de otra cuenta y
  la aplicación no ofrecerá la acción.
- **RF-7:** CUANDO se acepte una solicitud rápida, EL SISTEMA cubrirá todas las
  ocurrencias programadas de ese dispensador dentro de la ventana de
  coincidencia: las que ya estén en espera se marcarán consumidas sin orden ni
  evento, y las que aún no se hayan encolado quedarán registradas como cubiertas
  para que ninguna otra operación que intente insertar la misma clave la encole
  después. La solicitud y la cobertura se confirman en la misma operación: o se
  aplican ambas o ninguna. La cobertura no deja rastro visible por ocurrencia.
- **RF-8:** CUANDO el dispositivo consulte y no tenga una orden en curso, EL
  SISTEMA le entregará la solicitud rápida antes que cualquier comida programada
  en espera, con la cantidad solicitada y sujeta al presupuesto de motor de la
  spec 013, y la tratará como una orden normal: plazo de 5 minutos, reporte,
  cierre, descuento de stock y evento. El firmware no cambia.
- **RF-9:** SI el dispositivo no consulta, ENTONCES la solicitud rápida
  permanecerá pendiente sin plazo ni vencimiento hasta la primera consulta; la
  aplicación solo confirmará que la orden fue enviada y no prometerá ejecución
  inmediata.
- **RF-10:** CUANDO el dispositivo reporte una orden rápida, EL SISTEMA escribirá
  el evento `feeding_dispensed` con los mismos datos y reglas de la spec 014 y
  descontará el stock solo si el cierre es exitoso, con los gramos medidos
  acotados entre 0 y el stock disponible (014 RF-15); SI el cierre no es exitoso
  (`objetivo_no_alcanzado`, `entrega_incompleta`, `orden_cerrada`, `sin_reporte`,
  entre otros), ENTONCES no descontará stock (014 RF-16, RF-17, RF-19 y RF-20).
  La solicitud por sí sola no escribe ningún evento.
- **RF-11:** La aplicación mostrará en la ficha de la mascota la acción
  «Dispensar ahora» solo si hay dispensador; abrirá un formulario con únicamente
  la cantidad en gramos (admite decimales), el máximo de 200 g y el stock
  disponible, que es el stock actual del dispensador; el stock reservado lo
  calcula y valida el servidor (RNF-9), por lo que un rechazo por reserva puede
  llegar del servidor. Deshabilitará la confirmación mientras la petición esté en
  curso; al aceptar mostrará «Orden de dispensación enviada» y al rechazar el
  mensaje del servidor. Con el dispensador desactivado o el stock en 0 la acción
  estará deshabilitada.
- **RF-12:** SI no hay conexión con el servidor, ENTONCES la aplicación no
  enviará la solicitud y mostrará el aviso de sin conexión; esta función no tiene
  cola local porque la solicitud, el stock reservado y la cobertura viven en el
  servidor: es una excepción justificada al offline-first.
- **RF-13:** CUANDO el usuario pulse «Dispositivos» en las acciones rápidas del
  dashboard, EL SISTEMA abrirá la pestaña de dispensadores del shell, en la ruta
  `/dispensers`, y no la de mascotas.
- **RF-14:** EL SISTEMA exigirá en cada solicitud rápida un `operation_id` único
  por operación; SI falta, está vacío o no es válido, ENTONCES responderá HTTP 400
  con el código `operacion_invalida` sin crear la solicitud ni cubrir horarios;
  CUANDO llegue una solicitud con un identificador ya registrado para ese
  dispensador, ENTONCES devolverá la misma solicitud registrada y el mismo 202 de
  aceptación, sin crear otra ni volver a cubrir horarios; si la solicitud ya fue
  entregada, no se volverá a dispensar. La aplicación reutiliza el identificador
  mientras la hoja permanezca abierta y la cantidad no cambie; al reabrir la hoja
  la operación es nueva.
- **RF-15:** SI una solicitud rápida se rechaza por una regla de negocio,
  ENTONCES EL SISTEMA responderá HTTP 400 con `detail={code,message}` usando el
  catálogo de errores de esta spec o el de la 014, y nunca responderá 422; si el
  dispensador no existe o no pertenece al usuario, responderá 404 sin revelar
  datos de otra cuenta.
- **RF-16:** CUANDO se elimine el dispensador, EL SISTEMA borrará en cascada sus
  solicitudes rápidas pendientes; SI se intenta eliminar una mascota con
  dispensador vinculado, ENTONCES la operación se rechazará con 409
  `pet_has_dispenser` y la solicitud pendiente permanecerá, sin cascada por
  mascota. SI el dispensador se reasigna a otra mascota, la solicitud pendiente con
  el `pet_id` anterior se descartará al intentar entregarse, sin crear orden ni
  evento.

Precedencia de rechazo: cantidad, stock reservado, dispensador desactivado y
orden en curso; se devuelve el primer código aplicable.

## Requisitos no funcionales

- **RNF-1:** Cada RF tendrá al menos una prueba automatizada; el backend con
  `pytest` y la aplicación con `flutter test`.
- **RNF-2:** No se modificará el firmware del ESP32 ni se añadirán dependencias
  nuevas.
- **RNF-3:** La validación de la cantidad, el límite de 200 g, la cobertura de
  horarios y la decisión de entrega residirán fuera de las vistas; la vista solo
  recoge la cantidad y muestra el resultado.
- **RNF-4:** Todos los textos visibles nuevos estarán en español.
- **RNF-5:** La solicitud y la cobertura de ocurrencias serán atómicas y
  concurrentemente seguras: una ocurrencia cubierta no se dispensará después, una
  solicitud no se dispensará dos veces y un fallo no dejará datos parciales.
- **RNF-6:** El cierre y el descuento reutilizarán las reglas de la spec 014 sin
  duplicar eventos ni descuentos; el plazo, el reporte y el cierre por vencimiento
  no cambian.
- **RNF-7:** El formulario y la acción nueva se verán correctamente en pantallas
  de móvil, sin desbordamientos.
- **RNF-8:** La cobertura de una ocurrencia no escribirá evento ni registro
  visible propio; su efecto se verificará con pruebas automatizadas y consulta
  directa a la base de datos.
- **RNF-9:** El stock reservado se calculará solo en el servidor a partir de las
  solicitudes pendientes; el cliente no enviará ni decidirá el stock.

## Casos límite

- Cantidad 0, negativa, no numérica, `NaN`, infinita o mayor que 200 g: se
  rechaza; exactamente 200 g se acepta y 50,5 g se guarda como número de punto
  flotante.
- Cantidad igual al stock reservado: se acepta; mayor que el stock reservado, o
  cualquier cantidad con stock 0: se rechaza.
- Dos solicitudes pendientes: la suma de sus cantidades no puede superar el stock
  actual; la que exceda se rechaza con `stock_insuficiente`.
- Reintento con el mismo `operation_id` y la misma cantidad: devuelve la misma
  solicitud pendiente, sin nueva cobertura ni nuevo evento; con otro identificador
  se crea otra solicitud.
- `operation_id` ausente, vacío o inválido: HTTP 400 con `operacion_invalida`.
- Dispensador desactivado: se rechaza aunque tenga stock.
- Dispensador de otra cuenta o mascota sin dispensador: se rechaza sin revelar
  datos.
- Orden en curso: se rechaza; si estaba vencida, se cierra como `sin_reporte` y
  la solicitud sigue su curso.
- Varias ocurrencias del mismo u otro horario dentro de la ventana: todas se
  cubren y ninguna genera orden ni evento.
- Ocurrencia exactamente en el instante de la solicitud: se cubre. Ocurrencia
  exactamente 10 minutos antes: queda fuera de la ventana y no se cubre.
- Ocurrencia todavía no encolada por el planificador: la cobertura impide que
  cualquier otra operación que intente insertar la misma clave la encole después.
- Ocurrencia cubierta: no deja evento ni rastro visible; se verifica en pruebas y
  en la base de datos.
- Sin horarios en la ventana: la solicitud se acepta y no se cubre nada.
- Dispositivo sin conexión: la solicitud espera; la aplicación informa que fue
  enviada y el resultado aparece en el historial cuando el equipo reporte.
- Equipo que nunca consulta: la solicitud queda pendiente sin vencimiento, igual
  que la cola programada, y no hay evento; es un riesgo aceptado.
- Dispositivo desactivado después de aceptar la solicitud: la orden espera y se
  entrega al reactivarse, según RF-25 de la spec 014.
- Dos solicitudes rápidas antes de que el equipo consulte: se aceptan solo si su
  suma no supera el stock reservado y se dispensan en orden de llegada, cada una
  con su propio evento.
- Reporte con gramos medidos menores que los solicitados: cierra como
  `entrega_incompleta` y no descuenta stock, según la spec 014.
- Límite de 200 g no alcanzado dentro del presupuesto de 30 s de la spec 013: es
  un tope de seguridad, no una promesa; la orden cierra como
  `objetivo_no_alcanzado` o `entrega_incompleta`, sin descuento, y el usuario lo
  ve en el historial.
- Stock modificado entre la solicitud y el reporte: el cierre aplica el descuento
  acotado de la spec 014.
- Dispensador eliminado con solicitud pendiente: la cascada borra la solicitud y
  no se crea evento.
- Intento de eliminar una mascota con dispensador vinculado: 409
  `pet_has_dispenser`; la solicitud pendiente permanece y no hay cascada por
  mascota.
- Dispensador reasignado a otra mascota con solicitud pendiente: la solicitud se
  descarta al intentar entregarse, sin orden ni evento.
- Sin conexión en la aplicación: se bloquea el envío y se muestra el aviso de sin
  conexión.

## Relación con la spec 014

La 020 amplía el catálogo cerrado de errores de la 014 y reutiliza su orden,
plazo, reporte, cierre, descuento y evento. **Prevalencia:** la 020 prevalece
sobre RF-25 de la 014 solo para la ocurrencia programada cubierta por la ventana
de 10 minutos, que no se encola ni se entrega; el resto de RF-25 (orden en curso,
dispensador desactivado y comida en espera) sigue vigente. Fuera de esa ventana
manda la 014, y la 013 sigue siendo la referencia del firmware y de su presupuesto
de motor.

## Fuera de alcance

- Cálculo nutricional WSAVA, límites por ración diaria o validación de condición
  corporal.
- Cambios en el firmware, en el protocolo del dispositivo o en el reporte.
- Cola local sin conexión para solicitudes rápidas, porque la solicitud, el stock
  reservado y la cobertura viven en el servidor.
- Caducidad o vencimiento de las solicitudes pendientes que el equipo nunca
  consulta.
- Aviso visible o registro por cada ocurrencia cubierta; la cobertura solo se
  verifica en pruebas y en la base de datos.
- Seguimiento de conexión del dispositivo en tiempo real o confirmación
  inmediata de ejecución.
- Notificaciones push o avisos cuando el equipo no consulta.
- Un tipo de evento o una etiqueta distinta para la dispensación manual; se usa
  `feeding_dispensed` como en la spec 014.
- Cambios en la creación, edición o eliminación de horarios.
- Nuevos filtros del historial.
- Cambios en el aprovisionamiento BLE distintos de la navegación del acceso
  rápido del dashboard.

## Criterios de finalización

- RF-1 a RF-16 implementados y con sus pruebas automatizadas en verde.
- `pytest` completo sin regresiones y `flutter test` completo en verde.
- `flutter analyze` sin errores.
- Sin cambios de firmware: `pio test -e native` y `pio run` siguen en verde.
- Verificación manual en el móvil: dispensar 50 g desde la ficha, ver el evento y
  el stock actualizado; una solicitud con horario coincidente no duplica la
  comida; una cantidad mayor que 200 g o que el stock reservado se rechaza; el
  reintento con el mismo identificador no duplica la solicitud; «Dispositivos» del
  dashboard abre la sección de dispensadores.
- `MEMORY.md` actualizado al cerrar la fase.

### Mapeo RF a prueba

| RF | Prueba |
|----|--------|
| RF-1 | Solicitud aceptada con dueño, dispensador y datos válidos; endpoint autenticado. |
| RF-2 | Cantidad 0, negativa, texto, `NaN`, infinito, 200 exacto, 200,1 y decimal. |
| RF-3 | Cantidad igual y mayor que el stock reservado; reserva concurrente (stock 300 y dos solicitudes de 200, solo una aceptada); stock 0. |
| RF-4 | Dispensador desactivado. |
| RF-5 | Orden pendiente en plazo y orden vencida que se cierra antes de aceptar. |
| RF-6 | Mascota ajena o sin dispensador; 404 sin datos de otra cuenta. |
| RF-7 | Cobertura en cola, no encolada, varias y fronteras; concurrencia entre dos solicitudes manuales por la misma clave de ocurrencia; ocurrencia inexistente; sin evento por ocurrencia. |
| RF-8 | La consulta del equipo entrega la manual antes que la programada; reclamación única. |
| RF-9 | Solicitud sin consulta permanece pendiente sin vencimiento; la app informa envío. |
| RF-10 | Reporte con evento y descuento solo en cierre exitoso; cierre fallido y `sin_reporte` sin descuento. |
| RF-11 | Hoja con solo cantidad, máximo, stock, decimales, bloqueo al enviar, éxito y errores; botón deshabilitado con stock 0 o inactivo. |
| RF-12 | Sin conexión no se envía y se muestra el aviso. |
| RF-13 | «Dispositivos» abre `/dispensers`. |
| RF-14 | Mismo `operation_id` devuelve la misma solicitud y el mismo 202, sin cobertura nueva ni segundo dispensado; ausente o inválido da 400. |
| RF-15 | 400 con `detail={code,message}` en todos los rechazos; 404 sin filtrar datos. |
| RF-16 | Baja en cascada del dispensador; 409 `pet_has_dispenser` al eliminar una mascota con dispensador y solicitud intacta; reasignación de dispensador con solicitud pendiente. |
| RNF-1 a RNF-9 | Suites completas, `flutter analyze`, `pio test -e native`, `pio run`, revisión de textos y verificación manual. |

## Dudas abiertas

- Ninguna.
