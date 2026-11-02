# Spec 022 — Resumen y gráfico del panel con datos reales

**Estado:** cerrada — verificada manualmente el 2026-11-01
**Fecha:** 2026-11-01

## Contexto y objetivo

El resumen del panel inventa la mayor parte de sus cifras: los gramos de hoy son la
ración programada, la meta diaria es una regla fija de 300 g por mascota, las comidas
completadas siempre valen 0 y el gráfico semanal se genera con factores fijos, sin
consultar fechas ni la actividad registrada. Sin conexión, el panel muestra una serie
literal y `horarios × 50 g`, y la app rellena huecos con `300.0`.

Objetivo: que el resumen y el gráfico semanal se calculen con la actividad realmente
registrada (spec 014) y con los horarios que el sistema puede dispensar, distinguiendo lo
**programado** de lo **dispensado**, sin valores sintéticos ni en el servidor ni en la
app, y que el modo sin conexión sea honesto sobre lo que sabe y desde cuándo.

## Usuarios

- **Dueño de mascota:** consulta cuánto se dispensó hoy, cuántas comidas del día faltan
  y cómo va la semana.
- **Mantenedor:** confía en que el panel refleja datos verificables y no estimaciones.

## Historias de usuario

- HU-1. Como dueño, quiero ver los gramos realmente dispensados hoy para saber cuánto
  comió mi mascota y no cuánto estaba programado.
- HU-2. Como dueño, quiero saber cuántas comidas dispensables de hoy están pendientes y
  cuántas se completaron, para decidir si debo intervenir.
- HU-3. Como dueño, quiero un gráfico semanal Lun–Dom con lo dispensado en cada día, sin
  barras inventadas, para ver mi semana real.
- HU-4. Como dueño sin conexión, quiero que el panel no me muestre cifras falsas, aunque
  tenga que indicar que el resumen no está disponible.

## Definiciones

- **Dispensación registrada:** registro de actividad de tipo `feeding_dispensed` del
  usuario. Es la única fuente de gramos dispensados, también de mascotas ya eliminadas.
- **Gramos dispensados de un registro:** `measured_grams`; si es nulo,
  `discounted_grams`; si ambos son nulos, el registro no aporta gramos. En la práctica un
  cierre exitoso siempre trae medidos y el respaldo por descontados cubre solo nulos
  inesperados. Un fallo con gramos medidos sí aporta, porque el alimento salió.
- **Horario dispensable:** horario de una mascota del usuario con dispensador vinculado y
  activo, que es el que el servicio de dispensación puede ejecutar hoy.
- **Ocurrencia de hoy:** cada horario dispensable del usuario. Los horarios se repiten
  todos los días (no tienen día de la semana), así que hoy hay tantas ocurrencias como
  horarios dispensables.
- **Ocurrencia completada:** dispensación registrada con resultado éxito, del usuario,
  cuya fecha local es la de hoy y que tiene gramos medidos o, en su defecto, descontados;
  un medido o descontado en 0 cuenta como dato y completa la ocurrencia. Se atribuye a
  una ocurrencia sin emparejar por hora porque el registro no guarda el horario que la
  originó.
- **Programado hoy:** suma de los gramos de los horarios dispensables.
- **Día local del servidor:** día natural en la zona horaria del servidor, la misma con la
  que la spec 014 interpreta la hora de los horarios de comida (RNF-8). Difiere del «día
  local» de 014, que es el del usuario; este prototipo usa el del servidor para el panel.
- **Semana en curso:** de lunes a domingo del día local del servidor, con siete posiciones
  fijas de lunes a domingo.
- **Serie semanal:** siete gramos, uno por día de la semana en curso.
- **Resumen cacheado:** última respuesta del resumen guardada en una colección local
  nueva, con los dos campos de fecha del contrato.

## Requisitos funcionales

- **RF-1:** CUANDO el usuario consulte el resumen del panel, EL SISTEMA devolverá las
  cifras calculadas únicamente a partir de las mascotas, dispensadores, horarios y
  registros de actividad de ese usuario, sin valores de relleno, constantes ni series
  simuladas; si no hay datos, las cifras serán 0.
- **RF-2:** EL SISTEMA calculará `food_dispensed_today` como la suma de los gramos
  dispensados de las dispensaciones registradas cuya fecha local sea la de hoy, incluidas
  las de resultado fallo con gramos medidos y las de hoy con hora posterior a la del
  cálculo, y excluidas las de días posteriores a hoy y las que no tengan gramos medidos ni
  descontados.
- **RF-3:** EL SISTEMA calculará `food_target_today` como la suma de los gramos de los
  horarios dispensables, porque las demás mascotas no pueden dispensar y es la única
  ración por mascota persistida; será 0 si no hay ninguno. El resultado representa lo
  programado, no una prescripción nutricional, y no se derivará del número de mascotas ni
  de ninguna constante.
- **RF-4:** EL SISTEMA calculará `pending_feedings` como las ocurrencias de hoy menos las
  ocurrencias completadas, sin bajar de 0, y `completed_feedings` como las ocurrencias
  completadas; más registros exitosos con gramos que ocurrencias no aumentarán
  `completed_feedings` por encima del número de ocurrencias.
- **RF-5:** EL SISTEMA calculará `weekly_dispensed` con siete posiciones de lunes a
  domingo: cada posición sumará los gramos dispensados de las dispensaciones registradas
  cuyo instante caiga en ese día local de la semana en curso; las posiciones sin actividad
  y las posteriores a hoy valdrán 0; un registro con fecha local posterior a hoy no se
  incluirá aunque caiga dentro de la semana, mientras que un registro de hoy se incluye
  aunque su hora sea posterior a la del cálculo; si no hay actividad, las siete posiciones
  valdrán 0.
- **RF-6:** EL SISTEMA devolverá el resumen con los campos actuales sin cambios de nombre
  ni de tipo y con `weekly_dispensed` de exactamente siete números, y añadirá dos campos
  obligatorios: `today_index`, posición de hoy en la serie (0 lunes a 6 domingo) según el
  día local del servidor, y `calculated_at`, instante del cálculo en UTC. La app usará
  siempre estos campos del servidor o del resumen cacheado y nunca el reloj del
  dispositivo; backend y app se actualizan en la misma entrega, sin periodo dual.
- **RF-7:** MIENTRAS no haya conexión o el servidor no responda, EL SISTEMA mostrará el
  resumen cacheado con el aviso de datos sin conexión y la fecha y hora tomadas de
  `calculated_at`; SI no existe resumen cacheado, ENTONCES mostrará solo las mascotas y
  castradas leídas de los datos locales y 0 en alimento, ocurrencias y serie semanal, sin
  usar literales, sin multiplicar horarios por una cantidad fija y sin estimar ocurrencias
  completadas.
- **RF-8:** SI falla un refresco del resumen mientras hay cifras visibles, ENTONCES EL
  SISTEMA conservará lo mostrado, no lo sustituirá por una caché más antigua y avisará
  del fallo; SI no hay resumen cacheado y falla también la lectura local, ENTONCES mostrará
  un estado de error con texto fijo en español y acción de reintento, sin usar textos de
  excepción.
- **RF-9:** CUANDO el usuario abra el panel, EL SISTEMA mostrará siete posiciones
  etiquetadas Lun, Mar, Mié, Jue, Vie, Sáb y Dom con la altura de los gramos de cada día;
  un día con 0 no dibujará barra ni fondo de barra y conservará su etiqueta; resaltará
  únicamente la posición de `today_index`; SI las siete posiciones son 0, ENTONCES
  mostrará el texto «Sin dispensaciones esta semana» en lugar del gráfico.
- **RF-10:** EL SISTEMA mostrará el porcentaje de cumplimiento, valor derivado que la app
  calcula a partir de lo dispensado hoy y lo programado hoy, redondeado al entero más
  cercano y acotado entre 0 % y 100 %, con la etiqueta «Cumplimiento de lo programado»; SI
  lo programado es 0, ENTONCES mostrará «—»; los gramos se mostrarán sin decimales.
- **RF-11:** EL SISTEMA calculará el día local, la semana en curso y las sumas con la hora
  del servidor en UTC y la zona horaria del servidor: un registro exactamente en la
  medianoche local pertenece al día que empieza, uno del domingo a las 23:59 a la última
  posición y uno del lunes a las 00:00 a la primera de la semana nueva; no usará la fecha
  ni la zona horaria del dispositivo como fuente de verdad.
- **RF-12:** EL SISTEMA, en la app, no inventará cifras: el modelo de datos no aplicará
  valores por defecto distintos de 0 ni usará 300 como meta, y la vista no partirá de una
  meta ni de comidas completadas prefijadas; un campo ausente o desconocido se mostrará
  como 0 o como «—» según RF-10, nunca como una estimación.

## Requisitos no funcionales

- **RNF-1:** Todos los textos visibles estarán en español, sin emojis, y los errores se
  mostrarán con etapa tipada o texto fijo, nunca con el mensaje de una excepción.
- **RNF-2:** El cálculo vivirá fuera de las vistas, en las capas de dominio y servicios,
  como funciones deterministas que reciban el instante actual como parámetro, de modo que
  las pruebas no dependan del reloj real; las vistas solo presentan estado y emiten
  eventos, y solo derivan el porcentaje de RF-10 a partir de dos campos del contrato.
- **RNF-3:** No se añadirán dependencias ni se modificará el esquema de la base de datos
  del servidor: el resumen solo leerá tablas y registros existentes. La app puede crear
  una colección local nueva en Isar para el resumen cacheado, autorizada por esta spec y
  sin modificar las colecciones locales existentes.
- **RNF-4:** El 95 % de las consultas del resumen responderán en menos de 500 ms con
  10 000 registros de actividad del usuario, medido sobre el percentil 95 de 100 consultas
  consecutivas en el entorno de pruebas, apoyándose en el índice `ix_logs_user_id_created_at`.
- **RNF-5:** Cada RF tendrá al menos una prueba automatizada que falle si el requisito se
  incumple; la interfaz exigirá además verificación manual según `AGENTS.md`.

## Casos límite

- **Mascota con dispensador inactivo o sin dispensador:** sus horarios no cuentan como
  ocurrencias ni como programado; sus dispensaciones registradas sí suman gramos.
- **Usuario sin horarios dispensables pero con dispensaciones manuales:** programado 0,
  cumplimiento «—», gramos sumados y completadas 0.
- **Fallo con gramos medidos:** suma gramos y no completa ocurrencia.
- **Registro sin gramos medidos ni descontados (por ejemplo, sin reporte):** no aporta
  gramos ni completa ocurrencias.
- **Más éxitos que ocurrencias:** completadas igual al número de ocurrencias y pendientes
  0.
- **Registro con fecha futura dentro de la semana:** no se incluye; los días posteriores a
  hoy quedan en 0.
- **Día con 0 en el gráfico:** sin barra ni fondo, con su etiqueta visible.
- **Refresco fallido con resumen visible:** se conserva lo mostrado y no se degrada a una
  caché anterior.
- **Sin caché y fallo de la lectura local:** error con texto fijo y reintento.
- **Cambio de zona horaria del servidor:** los registros no se reconvierten; día y semana
  se calculan con la zona vigente.

## Decisiones y limitaciones

- La meta diaria es lo programado y no una prescripción WSAVA, porque el resultado de la
  calculadora de la spec 011 no se persiste por mascota; persistirlo queda fuera de
  alcance.
- La atribución de cada dispensación exitosa a una ocurrencia es agregada porque el
  registro no guarda el horario que la originó, y una dispensación manual puede completar
  una ocurrencia del día.
- El «día local del servidor» de esta spec no es el «día local» del usuario definido en
  014; se usa el del servidor por coherencia con la hora de los horarios de comida.
- El respaldo por `discounted_grams` solo cubre medidos nulos inesperados.
- La caché guarda únicamente el último resumen y no un histórico.

## Fuera de alcance

- Persistir por mascota la prescripción del motor nutricional de la spec 011.
- Horarios por día de la semana o excepciones de calendario.
- Recalcular o corregir cifras históricas ya mostradas.
- Nuevos gráficos, comparativas, exportaciones o notificaciones.
- Cambios en el firmware, en el contrato del historial o en el motor de cálculo.
- Ajustes de stock a partir de lo mostrado en el panel.

## Criterios de finalización

- `pytest`, `flutter test` y `flutter analyze` pasan sin errores y sin regresión en las
  specs 011, 014 y 019.
- Pruebas del endpoint: hoy con datos reales, semana, sin actividad, usuario sin mascotas,
  mascota con dispensador inactivo o sin dispensador, registro con fecha futura, fallo con
  gramos medidos y registro sin gramos.
- Pruebas de límites temporales: registro en la medianoche local, domingo a las 23:59 y
  lunes a las 00:00 con cambio de semana.
- Pruebas de la capa de datos: guardado y lectura de la caché, respuesta sin caché,
  refresco fallido con resumen visible y fallo de la lectura local.
- Pruebas del gráfico: siete posiciones etiquetadas, día en 0 sin barra, resaltado de
  `today_index`, semana vacía con mensaje y porcentaje redondeado con «—» sin programado.
- Verificación manual de la interfaz documentada según `AGENTS.md`.
- Cada RF cubierto por al menos una prueba automatizada según RNF-5.
- `MEMORY.md` actualizado al cerrar la fase.

## Dudas abiertas

Ninguna.

Verificación manual confirmada por el usuario: datos reales, modo sin conexión con y
sin caché, reintento y gráfico de siete días.
