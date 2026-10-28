# Spec 013 — Dispensado por peso con celda de carga

Estado: aprobada (T1–T9 y T11–T14 implementadas y revisadas; primera prueba física con alimento real registrada); T15 (checklist físico de atasco) y T10 (checklist físico previo) pendientes.

## Contexto y objetivo
El firmware del dispensador dispensa hoy una cantidad fija de tiempo: al recibir una
orden de servicio mueve el servomotor durante 10 segundos, sin importar cuánto
alimento solicita el servidor. Ese comportamiento está definido en RF-07 de
`specs/008-migracion-arduino-platformio-esp32/spec.md` y **esta spec lo sustituye**:
el dispensado por tiempo deja de ser el comportamiento vigente y pasa a ser dispensado
por peso. El backend ya envía la cantidad solicitada en gramos en el campo `amount`,
pero el firmware la ignora, por lo que la ración real depende del flujo del tornillo
sin fin, del tipo de croqueta y del nivel del depósito.

Se integra una celda de carga de 5 kg con su módulo amplificador para medir el
alimento que sale del dispensador. La celda pesa el alimento dispensado (bandeja o
salida), no el depósito interno, por lo que el objetivo no es un peso absoluto sino un
incremento respecto a una línea base tomada justo antes de arrancar el motor. La
integración incluye la conexión del amplificador al microcontrolador; la asignación
concreta de pines se decidirá en el plan. La calibración se resolverá con un factor
configurable que el desarrollador ajusta manualmente antes de compilar; no habrá
comandos de calibración por el puerto serie.

Deuda conocida y aceptada: el backend descuenta el stock en el momento en que emite la
orden con `serve: true`, es decir, al entregar la orden y no al confirmar el peso real
dispensado. Esta spec reconoce esa diferencia entre stock descontado y peso entregado,
pero no la concilia ni la corrige: queda fuera de alcance.

Durante las pruebas físicas de la implementación se observó un problema nuevo: el
servomotor se traba o se atasca con el alimento, porque la croqueta se cuña entre la
hélice del tornillo sin fin, que es el elemento que empuja el alimento hacia la
balanza, y el tubo que la contiene. El servomotor no dispone de realimentación de
posición, de velocidad ni de corriente, así que el atasco no puede leerse del propio
servo. Se detecta de forma indirecta con la misma celda de carga que ya forma parte de
esta spec: si el servo avanza y el peso no progresa, el alimento no está avanzando. La
resolución es mecánica y usa el mismo servo: un giro inverso corto que libera la
croqueta cuñada, una pausa y la reanudación del avance, sin hardware adicional.

El objetivo es que cada orden de dispensación entregue la cantidad solicitada, medida
por peso, deteniendo el motor al alcanzarla, y que nunca se dispense a ciegas: si la
celda no responde antes de iniciar, no se mueve el servo, y si falla de forma sostenida
a mitad de la dispensación, el servo se detiene sin esperar el presupuesto de motor.
Además, cuando el alimento se atasque, el sistema debe intentar desatascarlo por sí
mismo antes de darse por vencido, para que un atasco puntual no deje la ración corta.
Todo ello con un presupuesto máximo de 30 segundos de motor por si la celda falla, no
hay alimento o el mecanismo se atasca, y sin romper el aprovisionamiento BLE, la
conexión WiFi ni la consulta periódica a la API.

## Usuarios
- **Dueño de mascota:** recibe una ración ajustada a la cantidad solicitada, sin
  depender del tiempo de giro ni del tipo de alimento; si el tornillo sin fin se traba,
  el dispensador lo resuelve por sí mismo en lugar de dejar la ración corta.
- **Desarrollador / Ingeniero de hardware:** integra y calibra la celda de carga,
  dispone de un registro serie con la línea base, el peso final, el motivo de
  finalización y el número de reintentos para diagnosticar cada dispensación, incluidos
  los atascos.

## Historias de usuario
- HU-1. Como dueño de mascota, quiero que el dispensador entregue la cantidad de
  alimento solicitada en gramos para que la ración real coincida con la calculada.
- HU-2. Como dueño de mascota, quiero que el dispensador se detenga solo al alcanzar
  la cantidad pedida para no servir más comida de la necesaria.
- HU-3. Como dueño de mascota, quiero que el sistema no dispense si el sensor de peso
  no funciona, para no servir una cantidad arbitraria.
- HU-4. Como dueño de mascota, quiero que el ciclo de motor del dispensador nunca dure
  más de 30 segundos, incluidos los reintentos por atasco, además de la ventana fija de
  2 segundos de verificación previa del sensor, para que un fallo no deje el motor
  girando indefinidamente; el ciclo completo no supera los 32 segundos.
- HU-5. Como desarrollador, quiero un registro serie con la línea base, el peso
  final, el incremento, la cantidad solicitada y el motivo de finalización para
  diagnosticar fallos.
- HU-6. Como desarrollador, quiero ajustar la calibración con un factor configurable
  para adaptar la lectura de la celda al montaje sin comandos por puerto serie.
- HU-7. Como dueño de mascota, quiero que el dispensador se desatasque solo cuando el
  tornillo sin fin se traba, para que un atasco puntual no deje la ración corta.
- HU-8. Como desarrollador, quiero saber en el registro serie si hubo atasco y cuántos
  reintentos se ejecutaron, para distinguir un atasco de un depósito vacío o de un
  fallo de calibración.

## Definiciones
- **Cantidad solicitada:** valor del campo `amount` de la respuesta de la API,
  expresado en gramos.
- **Ventana de verificación:** intervalo fijo de exactamente 2 segundos, previo al
  avance y no reiniciable. La verificación se supera si dentro de la ventana se obtienen
  al menos 5 lecturas válidas y no hay 3 lecturas inválidas consecutivas; una lectura
  inválida no reinicia ni extiende la ventana.
- **Línea base:** mediana de las lecturas válidas de la ventana de verificación, fijada
  justo antes del avance. Si la dispensación se aborta antes de fijarla, se registra como
  no disponible.
- **Mediana:** para un número impar de muestras, el valor central al ordenarlas; para un
  número par, el promedio de los dos valores centrales.
- **Peso final:** última lectura válida en el instante de la parada definitiva del
  servo; si hubo fallo del sensor, la última lectura válida anterior al fallo; si no
  hubo ninguna lectura válida durante el ciclo de motor, se registra como no disponible.
- **Incremento de peso:** diferencia entre el peso final y la línea base. Si el peso
  final o la línea base no están disponibles, el incremento también se registra como no
  disponible.
- **Objetivo:** incremento de peso igual o mayor que la cantidad solicitada.
- **Lectura válida:** la celda responde dentro de los 100 ms siguientes al intento de
  lectura y el valor convertido es finito, está en el intervalo 0–5000 g y la lectura
  en bruto del ADC no está en el mínimo ni en el máximo de su rango (saturación). Una
  lectura válida puede ser ruidosa; ser válida no implica estar estabilizada, y el ruido
  se filtra aguas abajo.
- **Lectura inválida:** ausencia de respuesta de la celda, valor no finito, valor fuera
  del intervalo 0–5000 g, o saturación.
- **Ausencia de respuesta:** no hay dato disponible dentro de los 100 ms siguientes al
  intento de lectura. Cada intento fallido cuenta como una lectura inválida; una lectura
  inválida aislada no detiene el ciclo.
- **Saturación:** lectura en bruto del ADC del HX711 en el extremo inferior
  (−8 388 608) o superior (8 388 607) de su rango de 24 bits; la lectura no representa
  el peso real.
- **Factor de calibración:** constante editable que convierte la lectura en bruto de
  la celda en gramos. Se ajusta manualmente y se aplica antes de compilar el
  firmware; debe ser positivo, y si no lo es se considera un error de configuración.
- **Reposo:** respuesta sin orden de dispensación, es decir, `serve:false` o `amount`
  igual a cero, y sin `reset_wifi:true`, que es la respuesta normal del backend. No
  mueve el servo ni registra error.
- **Orden inválida:** respuesta con `serve:true` y `amount` ausente, no numérico o
  negativo, y sin `reset_wifi:true`. No dispensa y registra una advertencia.
- **Dispensación por peso:** ciclo compuesto por una ventana fija de verificación de 2
  segundos y un ciclo de motor de hasta 30 segundos; arranca el servo solo si la
  verificación se supera, mide el incremento de peso de forma continua, detiene el servo
  al alcanzar el objetivo o al agotarse el presupuesto de motor y, si detecta un atasco
  durante el avance, intenta resolverlo con retrocesos cortos antes de darse por vencida.
- **Ciclo de motor:** intervalo que va desde el primer arranque del servomotor de una
  dispensación hasta su parada definitiva. Incluye todos los avances, retrocesos y
  pausas; no incluye la ventana de verificación.
- **Presupuesto de motor:** 30 segundos contados desde el primer arranque del
  servomotor. Lo consumen por igual el avance, el retroceso y la pausa. Es un tope de
  seguridad, no un objetivo de duración.
- **Avance:** giro del servomotor en el sentido de dispensado, que empuja el alimento
  hacia la balanza.
- **Retroceso:** giro del servomotor en sentido inverso durante 1,2 segundos, destinado
  a liberar el alimento trabado entre la hélice del tornillo sin fin y el tubo.
- **Pausa:** intervalo de 0,3 segundos con el servomotor detenido que sigue a cada
  retroceso, antes de reanudar el avance.
- **Reintento:** conjunto formado por un retroceso, su pausa y la reanudación del avance.
  Se admiten como máximo 3 reintentos por dispensación. Un retroceso interrumpido por un
  fallo del sensor o por agotamiento del presupuesto no cuenta como reintento, porque el
  avance no llegó a reanudarse.
- **Ventana de gracia:** 2 segundos contados desde cada arranque de avance, el inicial y
  el de cada reintento, durante los cuales no se evalúa el atasco porque el alimento
  todavía puede estar en tránsito hacia la balanza.
- **Mediana móvil:** mediana de las 5 lecturas válidas más recientes del ciclo de motor,
  recalculada tras cada lectura válida. No existe hasta que el ciclo acumula al menos 5
  lecturas válidas.
- **Máximo observado:** mayor valor de la mediana móvil registrado desde el primer
  arranque del servomotor en la dispensación. Se actualiza con cada lectura válida que
  produzca una mediana nueva, también durante el retroceso y la pausa; una lectura
  individual atípica no lo eleva si no desplaza la mediana móvil.
- **Progreso:** diferencia en gramos entre la mediana móvil actual y el máximo observado
  vigente como referencia de la ventana de estancamiento en curso. Es negativo cuando el
  peso actual está por debajo de esa referencia. La referencia se fija al abrir la ventana
  y se renueva cada vez que la ventana se reinicia.
- **Ventana de estancamiento:** 5 segundos contados desde que la ventana se abre o se
  reinicia. Se abre al terminar la ventana de gracia de 2 segundos o, si en ese instante
  todavía no existe la mediana móvil, en el momento en que exista. Se reinicia en el
  instante en que el progreso es igual o mayor que 2 gramos, y en ese mismo instante se
  toma como nueva referencia el máximo observado vigente. Si al terminar los 5 segundos el
  progreso es menor que 2 gramos y hay al menos 5 lecturas válidas desde el último arranque
  de avance, se declara atasco;
  si hay menos de 5 lecturas válidas, no se declara y la ventana se reinicia.
- **Atasco:** condición en la que el servomotor avanza y el peso no progresa hacia la
  balanza, declarada al terminar una ventana de estancamiento con al menos 5 lecturas
  válidas desde el último arranque de avance.
- **Atasco pendiente:** atasco declarado que todavía no ha sido seguido de un progreso
  igual o mayor que 2 gramos. Un reintento resuelve el atasco cuando, después de la
  reanudación del avance, se registra ese progreso antes de una nueva declaración de
  atasco.
- **Atasco no resuelto:** atasco pendiente que no puede intentar resolverse porque no
  quedan reintentos o porque el presupuesto restante no alcanza para el retroceso, su
  pausa y la ventana de gracia. También es el motivo registrado cuando el presupuesto de
  motor se agota con un atasco pendiente.

## Requisitos funcionales
- RF-1: CUANDO la respuesta de la API indique `serve: true` y `amount` sea numérico y
  mayor que cero, EL SISTEMA iniciará una dispensación por peso con esa cantidad
  solicitada en gramos, salvo que `reset_wifi` sea `true`, en cuyo caso aplica RF-10.
- RF-2: SI `serve` es `false`, o `amount` es igual a cero, ENTONCES EL SISTEMA
  permanecerá en reposo, sin mover el servomotor y sin registrar ningún error ni
  advertencia, porque es la respuesta normal del backend, salvo que `reset_wifi` sea
  `true`, en cuyo caso aplica RF-10; SI `serve` es `true` y `amount` está ausente, no
  es numérico o es negativo, ENTONCES EL SISTEMA no dispensará y registrará una
  advertencia de orden de dispensación inválida.
- RF-3: CUANDO reciba una orden de dispensación válida, EL SISTEMA abrirá una ventana
  fija de verificación de exactamente 2 segundos, no reiniciable; la verificación se
  supera si dentro de la ventana se obtienen al menos 5 lecturas válidas y no hay 3
  lecturas inválidas consecutivas, y en ese caso fijará la línea base como la mediana
  de las lecturas válidas de esa ventana justo antes de poner el servo en avance.
- RF-4: SI al terminar la ventana fija de 2 segundos no se cumple la condición de RF-3,
  ENTONCES EL SISTEMA abortará la dispensación sin mover el servo, mantendrá el servo
  detenido y registrará el motivo «sensor no disponible»; 3 lecturas inválidas
  consecutivas dentro de la ventana la dan por no superada, y la ventana no se reinicia
  ni se extiende.
- RF-5: CUANDO la celda entregue lecturas válidas y la línea base esté tomada, EL
  SISTEMA pondrá el servomotor en avance para dispensar alimento.
- RF-6: MIENTRAS el ciclo de motor esté activo, EL SISTEMA medirá el peso del alimento
  dispensado de forma continua, también durante el retroceso y la pausa, y calculará el
  incremento de peso respecto a la línea base.
- RF-7: CUANDO el incremento de peso sea igual o mayor que la cantidad solicitada en
  gramos en al menos 3 lecturas consecutivas, en cualquier instante del ciclo de motor,
  incluidos el retroceso y la pausa, EL SISTEMA detendrá el servomotor y dará la
  dispensación por completada; esta comprobación tiene prioridad sobre la declaración de
  atasco de RF-14.
- RF-8: SI se agota el presupuesto de motor de 30 segundos contados desde el primer
  arranque del servomotor, incluidos avances, retrocesos y pausas, sin que se alcance el
  objetivo, ENTONCES EL SISTEMA detendrá el servomotor y registrará el resultado como
  objetivo no alcanzado, indicando el incremento de peso logrado, salvo que en ese
  momento haya un atasco pendiente, en cuyo caso aplica RF-16 y el motivo registrado es
  «atasco no resuelto».
- RF-9: SI durante el ciclo de motor se producen 3 lecturas inválidas consecutivas,
  ENTONCES EL SISTEMA detendrá el servomotor sin esperar a que se agote el presupuesto
  de motor, dentro de 1 segundo desde la primera de esas 3 lecturas, no ejecutará ningún
  retroceso ni reanudará el avance, y registrará el motivo «fallo del sensor durante la
  dispensación»; con el periodo de muestreo de RNF-1 y el plazo de respuesta de 100 ms,
  3 lecturas inválidas consecutivas se detectan en menos de 1 segundo. Una lectura
  inválida aislada no detiene el ciclo.
- RF-10: SI la respuesta de la API indica `reset_wifi: true`, ENTONCES EL SISTEMA
  borrará las credenciales almacenadas y reiniciará en modo de aprovisionamiento,
  sin mover el servomotor y con prioridad sobre `serve` y `amount`, tanto si `serve` es
  `true` como si es `false` o `amount` es cero.
- RF-11: EL SISTEMA aplicará un factor de calibración configurable, ajustable
  manualmente por el desarrollador antes de compilar, para convertir la lectura de la
  celda en gramos; no ofrecerá comandos de calibración por el puerto serie. SI el
  factor de calibración no es positivo, ENTONCES EL SISTEMA no dispensará y registrará
  un error de configuración.
- RF-12: CUANDO finalice una dispensación, sea por objetivo alcanzado, por agotamiento
  del presupuesto de motor, por atasco no resuelto, por fallo del sensor o por aborto en
  la verificación previa, EL SISTEMA registrará por el puerto serie la línea base, el
  peso final medido, el incremento de peso, la cantidad solicitada, el número de
  reintentos ejecutados en el ciclo con el formato `reintentos=N` y el motivo de
  finalización; si no hubo ninguna lectura válida durante el ciclo de motor, el peso
  final y el incremento se registrarán como no disponibles; si la dispensación se aborta
  antes de fijar la línea base, la línea base se registrará como no disponible, igual
  que el peso final y el incremento; el número de reintentos se registra siempre, con 0
  cuando no hubo ninguno, y un retroceso interrumpido por un fallo del sensor o por
  agotamiento del presupuesto no se cuenta como reintento porque el avance no llegó a
  reanudarse.
- RF-13: EL SISTEMA conservará sin regresiones el aprovisionamiento BLE, la conexión
  y reconexión WiFi, la validación de conectividad con el servidor, el reseteo de
  credenciales y la consulta periódica a la API en el intervalo ya definido; tras
  cualquier dispensación, completada o fallida, reanudará la consulta periódica
  reiniciando su temporizador, de modo que la siguiente consulta se realizará 20
  segundos después de finalizar el ciclo y no de inmediato, sin reiniciar el
  dispositivo.
- RF-14: MIENTRAS el servomotor esté en avance, EL SISTEMA evaluará el progreso en cada
  lectura válida como la diferencia entre la mediana móvil de las últimas 5 lecturas
  válidas y el máximo observado vigente como referencia de la ventana de estancamiento;
  SI el progreso es igual o mayor que 2 gramos, ENTONCES EL SISTEMA reiniciará la ventana
  de estancamiento en ese mismo instante y tomará como nueva referencia el máximo
  observado vigente; SI al terminar una ventana de estancamiento de 5 segundos el
  progreso es menor que 2 gramos y hay al menos 5 lecturas válidas desde el último
  arranque de avance, ENTONCES EL SISTEMA declarará un atasco. La ventana se abre al
  terminar la ventana de gracia de 2 segundos o, si en ese instante todavía no existe la
  mediana móvil, en el momento en que exista; la evaluación no se realiza durante la
  ventana de gracia, ni durante el retroceso, ni durante la pausa.
- RF-15: CUANDO se declare un atasco y queden reintentos y presupuesto suficiente, EL
  SISTEMA ejecutará un retroceso de 1,2 segundos, una pausa de 0,3 segundos con el
  servomotor detenido y reanudará el avance; el retroceso y la pausa consumen el
  presupuesto de motor igual que el avance; el retroceso no modifica la línea base ni el
  criterio de objetivo de RF-7, de modo que un atasco resuelto no impide alcanzar el
  objetivo y el ciclo continúa hasta alcanzarlo o hasta agotar el presupuesto. El máximo
  de 3 reintentos por dispensación es una red de seguridad: con los umbrales aprobados el
  presupuesto de 30 segundos se agota antes de que se pueda declarar un cuarto atasco, por
  lo que el límite efectivo es el presupuesto de motor y no el contador de reintentos.
- RF-16: SI se declara un atasco y no quedan reintentos disponibles, o si el presupuesto
  restante no alcanza para el retroceso, su pausa y la ventana de gracia, es decir, si es
  menor que 3,5 segundos, ENTONCES EL SISTEMA detendrá el servomotor, no ejecutará ningún
  retroceso adicional, no forzará más el giro y registrará el motivo «atasco no resuelto»
  junto con el incremento de peso logrado; lo mismo ocurre si el presupuesto de motor se
  agota con un atasco pendiente. En la práctica, con los umbrales aprobados el presupuesto
  se agota antes de que se pueda declarar un cuarto atasco, de modo que esta condición
  suele cumplirse por presupuesto y no por contador de reintentos.
- RF-17: EL SISTEMA no ejecutará ningún retroceso sin medición fiable ni sin orden
  válida: ante 3 lecturas inválidas consecutivas aplica RF-9 y detiene el ciclo sin
  retroceso, y ante una orden inválida aplica RF-2 y no mueve el servomotor; además, un
  atasco solo se declara con al menos 5 lecturas válidas desde el último arranque de
  avance, de modo que la falta de lecturas nunca se interpreta como atasco.

## Requisitos no funcionales
- RNF-1: Mientras la celda esté operativa, el sistema aplicará un periodo de muestreo
  máximo de 200 milisegundos, es decir, un mínimo efectivo de 5 lecturas por segundo,
  tanto durante la ventana de verificación como durante todo el ciclo de motor, incluidos
  el retroceso y la pausa. La detección del objetivo no se basa en una única lectura de
  200 milisegundos: exige 3 lecturas consecutivas (RF-7). En la ventana de 2 s, a 5 Hz
  se obtienen aproximadamente 10 lecturas, de las que se exigen al menos 5 válidas.
- RNF-2: El objetivo se considerará alcanzado solo cuando el incremento de peso sea
  igual o mayor que la cantidad solicitada en al menos 3 lecturas consecutivas, para
  no detener el servo por un pico de ruido o vibración.
- RNF-3: El ciclo de motor del servomotor no superará en ningún caso los 30 segundos por
  dispensación, contados desde el primer arranque del servo e incluyendo avances,
  retrocesos y pausas; la ventana fija de verificación de 2 segundos es independiente y
  no se descuenta de ese límite, por lo que el ciclo completo no supera los 32 segundos,
  sin excepciones.
- RNF-4: No se agregarán dependencias distintas de la necesaria para leer la celda de
  carga; la detección y la resolución de atascos no añaden ninguna, porque usan el mismo
  servomotor y la misma celda ya previstos; el resto del firmware y su comportamiento
  actual se mantienen, con dos excepciones explícitas: (a) el dispensado por tiempo de
  10 segundos (RF-07 de la spec 008) queda reemplazado por el dispensado por peso
  descrito en esta spec; (b) el temporizador de la consulta periódica se reinicia al
  terminar el ciclo, de modo que la siguiente consulta ocurre 20 segundos después del
  fin y no 20 segundos después de la consulta anterior.
- RNF-5: Los mensajes de registro serie estarán en español, sin emojis, y no
  incluirán credenciales ni datos sensibles.
- RNF-6: La lógica de decisión de inicio, parada, tiempo límite, detección de atasco y
  resolución de atasco será verificable con pruebas automatizadas sobre lógica pura, sin
  requerir hardware; la exactitud del pesaje y el desatasco real del mecanismo se
  validarán con pruebas físicas.
- RNF-7: Las diez constantes de umbral de la detección y la resolución de atascos
  —ventana de gracia de 2 segundos, ventana de estancamiento de 5 segundos, progreso
  mínimo de 2 gramos, tamaño de la mediana móvil de 5 lecturas válidas, mínimo de 5
  lecturas válidas desde el último arranque de avance para declarar atasco, retroceso de
  1,2 segundos, pausa de 0,3 segundos, máximo de 3 reintentos, presupuesto de motor de
  30 segundos y presupuesto mínimo de reintento de 3,5 segundos— serán
  constantes configurables del firmware, documentadas en español y definidas en un único
  lugar, de modo que ajustarlas no requiera cambiar la lógica de decisión.

## Casos límite
- Depósito vacío o alimento que no fluye: el peso no progresa, por lo que la condición
  es indistinguible de un atasco con la única medición disponible; se declaran atascos y
  se ejecutan reintentos, y al agotarse los reintentos o el presupuesto se detiene el
  servo y se registra «atasco no resuelto» con incremento cercano a cero. Distinguirlo
  de un atasco real requeriría sensores que están fuera de alcance.
- Ruido o vibración del motor que produce lecturas inestables: no se detiene el servo
  hasta que el objetivo se sostiene en lecturas consecutivas; como el máximo observado
  es el mayor de la mediana móvil de las últimas 5 lecturas válidas, un pico de ruido
  aislado, o incluso dos, no eleva el máximo ni provoca un falso atasco, y el
  presupuesto de motor de 30 s sigue vigente.
- Cantidad solicitada mayor de la que el mecanismo puede entregar en el presupuesto de
  motor de 30 segundos: se detiene por tiempo, se registra el incremento parcial logrado
  y la dispensación se da por no completada.
- Alimento en caída después de detener el servo: el peso físico sobre la bandeja, una vez
  se asienta el alimento que quedaba en el tubo, puede superar el objetivo; el peso final
  registrado es el de la parada definitiva del servo y el registro serie no mide ese
  sobrepeso posterior. Ese sobrepeso se admite hasta el 10 % en la prueba física de
  exactitud.
- Ciclo completo: 2 s de ventana fija de verificación más 30 s de presupuesto de motor,
  es decir, 32 s como máximo; el presupuesto incluye los retrocesos y las pausas, y la
  verificación no consume ese límite.
- Celda desconectada o sin respuesta al arranque: la ventana fija de 2 s no se supera,
  no se mueve el servo y se registra «sensor no disponible»; la línea base, el peso
  final y el incremento se registran como no disponibles.
- Lecturas inválidas intermitentes durante la verificación: la ventana fija de 2 s no se
  reinicia ni se extiende; si dentro de ella no se obtienen al menos 5 lecturas válidas
  o se acumulan 3 lecturas inválidas consecutivas, se da por no superada y se aborta sin
  mover el servo.
- Cantidad solicitada inferior al menor incremento distinguible por la celda: se aplica
  el mismo criterio `>= amount`; el objetivo puede alcanzarse desde la primera lectura,
  pero la parada se confirma con 3 lecturas consecutivas (RF-7).
- Incremento de peso negativo por bandeja retirada o mascota comiendo: no cuenta para el
  objetivo; como el progreso se mide contra el máximo observado, la bajada se interpreta
  como estancamiento y puede declarar un atasco y un reintento, y el ciclo continúa hasta
  alcanzar el objetivo o agotar el presupuesto de motor. El retroceso no retira alimento
  de la bandeja, por lo que no produce dispensación negativa.
- Línea base alta: si la línea base más la cantidad solicitada supera los 5000 g y las
  lecturas del ciclo salen del intervalo válido 0–5000 g o la celda satura, aplica RF-9 y
  el motivo es «fallo del sensor durante la dispensación»; si la propia línea base supera
  los 5000 g, la verificación no se supera y el motivo es «sensor no disponible», sin
  mover el servo. Mientras el alimento fluya y las lecturas se mantengan dentro del rango
  válido, el peso progresa y no se declara atasco, pero el objetivo sigue siendo
  inalcanzable por rango de medición y el ciclo termina por agotamiento del presupuesto de
  motor con «objetivo no alcanzado».
- Factor de calibración no positivo: error de configuración; no se dispensa y se
  registra.
- Celda que falla a mitad de la dispensación: las 3 lecturas inválidas consecutivas
  completadas detienen el servo dentro de 1 s desde la primera, sin esperar el
  presupuesto de motor, y se registra el motivo. Si esas 3 lecturas inválidas
  consecutivas se completan durante un retroceso o una pausa, tampoco se reanuda el
  avance ni se ejecuta un retroceso adicional. El inicio del fallo, es decir, la primera
  lectura inválida, no impide por sí mismo reanudar: si empieza en la pausa y no llega a
  completar las 3 inválidas consecutivas antes de reanudar, el avance se reanuda y el
  fallo se detecta ya en el avance, como detalla el caso límite del fallo de sensor
  durante el retroceso o la pausa.
- Lectura inválida aislada durante el ciclo de motor: no detiene el ciclo; solo 3
  lecturas inválidas consecutivas se consideran fallo del sensor.
- Ninguna lectura válida durante el ciclo de motor (caso defensivo): el peso final y el
  incremento se registran como no disponibles; la línea base de la verificación, la
  cantidad solicitada, los reintentos y el motivo sí se registran.
- Atasco en el primer segundo de avance: la ventana de gracia de 2 s impide declararlo
  antes de los 2 s, de modo que la primera declaración posible ocurre a los 7 s del
  arranque, es decir, 2 s de gracia más 5 s de estancamiento.
- Atasco tras un reintento: cada reanudación del avance abre una ventana de gracia de 2 s
  y una ventana de estancamiento nuevas, sin heredar los contadores anteriores.
- Ventana sin mediana móvil al terminar la gracia: con lecturas inválidas alternas que no
  llegan a disparar RF-9 y sin 5 lecturas válidas al terminar los 2 s de gracia, no se
  declara atasco; la ventana de estancamiento se abre en el instante en que existe la
  primera mediana móvil.
- Atasco repetido: con los umbrales aprobados el presupuesto de motor de 30 s se agota
  antes de que se pueda declarar un cuarto atasco, de modo que el tope de 3 reintentos es
  una red de seguridad que normalmente no llega a activarse; si el presupuesto se agota
  con un atasco pendiente, o si se declara un atasco sin reintentos disponibles, aplica
  RF-16 y el motivo es «atasco no resuelto»; si el presupuesto se agota sin atasco
  pendiente, el motivo es «objetivo no alcanzado».
- Objetivo alcanzado durante la ventana de gracia: 3 lecturas consecutivas iguales o
  mayores que el objetivo detienen el servo con «objetivo alcanzado» y sin retroceso,
  aunque el progreso sea menor que 2 gramos; RF-7 tiene prioridad sobre RF-14.
- Atasco justo al alcanzar el objetivo: si en la misma muestra se cumplen el objetivo y
  el final de la ventana de estancamiento, prevalece el objetivo y no se ejecuta
  retroceso.
- Fallo de sensor durante el retroceso o la pausa: si las 3 lecturas inválidas
  consecutivas se completan durante el retroceso o la pausa, el servo se detiene
  dentro de 1 s desde la primera de esas 3 lecturas, no se ejecuta ningún
  retroceso adicional ni se reanuda el avance, y el motivo es «fallo del sensor
  durante la dispensación». Como la pausa dura 0,3 s y el muestreo es de 0,2 s,
  dentro de la pausa solo caben 2 lecturas inválidas de las 3 necesarias: si el
  fallo empieza en la pausa y no se completan las 3 inválidas consecutivas antes
  de reanudar, el avance se reanuda y el fallo se detecta ya en el avance, que se
  detiene dentro de 1 s desde la tercera lectura inválida, sin retroceso.
- Presupuesto insuficiente para el reintento: si al declararse el atasco el presupuesto
  restante no alcanza para el retroceso, su pausa y la ventana de gracia, es decir, es
  menor que 3,5 segundos, no se inicia el retroceso, el servo se detiene y se registra
  «atasco no resuelto».
- Presupuesto de motor agotado sin atasco pendiente: el motivo es «objetivo no
  alcanzado», no «atasco no resuelto».
- Cantidad muy pequeña alcanzada antes de la ventana de gracia: si el objetivo se cumple
  en 3 lecturas consecutivas antes de los 2 s, la dispensación termina con «objetivo
  alcanzado» y sin evaluar atascos.
- Cantidad muy pequeña con flujo lento: con cantidades pequeñas y un flujo inferior a
  0,4 g/s, el umbral de 2 g en 5 s puede declarar un atasco antes de alcanzar el objetivo;
  el reintento no impide alcanzarlo, el registro muestra `reintentos` mayor que 0 y el
  umbral es configurable (RNF-7).
- Atasco con el depósito lleno y la croqueta cuñada: el retroceso de 1,2 s libera la
  hélice, la pausa de 0,3 s deja caer el alimento suelto y la reanudación del avance
  permite alcanzar el objetivo; el ciclo no se da por fallido.
- Alimento de tamaño próximo al paso de la hélice: con croqueta de unos 3 cm el
  tornillo sin fin se atasca con frecuencia, porque la croqueta se cuña entre la
  hélice y el tubo. El ciclo lo detecta y lo intenta resolver con el retroceso, la pausa
  y la reanudación: alcanza el objetivo cuando el retroceso libera la croqueta y, si no
  la libera, termina en «atasco no resuelto» (RF-16). Es una limitación mecánica del paso
  de la hélice frente al tamaño del alimento, no un fallo de la detección, y por ese
  motivo no se ajustan los umbrales ni se relaja RF-14.
- Retroceso sin dispensación negativa: el giro inverso devuelve la hélice pero no retira
  el alimento ya depositado en la bandeja; el incremento no disminuye por efecto del
  retroceso, y una disminución solo puede provenir de la celda, es decir, de la mascota
  o de la bandeja.
- `serve: false` o `amount` igual a cero sin `reset_wifi:true`: reposo normal del
  backend; no se dispensa, no se mueve el servo y no se registra error.
- `serve: true` con `amount` ausente, no numérico o negativo: no se dispensa y se
  registra una advertencia de orden de dispensación inválida; tampoco se ejecuta ningún
  retroceso.
- `serve: true` y `reset_wifi: true` en la misma respuesta: prevalece el reseteo de
  WiFi y el servo no se mueve.
- `reset_wifi: true` con `serve: false` o `amount` igual a cero, que es el payload real
  del backend: también reinicia las credenciales y no mueve el servo; `reset_wifi`
  tiene prioridad siempre.
- Reinicio o corte de energía durante una dispensación: el ciclo no se reanuda ni se
  compensa (fuera de alcance).
- Consulta periódica a la API durante una dispensación: no se solapan dos
  dispensaciones; el temporizador de consulta se reinicia al finalizar el ciclo y la
  siguiente consulta ocurre 20 s después, no de inmediato.

## Fuera de alcance
- Reportar al backend el peso real dispensado y conciliar el stock: el backend
  descuenta al emitir la orden con `serve:true`, por lo que la diferencia entre stock
  descontado y peso entregado se acepta como deuda conocida y no se corrige en esta
  spec.
- Cambios en la API del backend o en la aplicación móvil.
- Medir el nivel de alimento del depósito interno.
- Calibración automática o multipunto y comandos de calibración por el puerto serie.
- Recuperación o reanudación de una dispensación interrumpida por reinicio o corte de
  energía.
- Alertas en la aplicación móvil sobre fallos o peso parcial de una dispensación.
- Realimentación del servomotor (encoder, sensor de corriente o de final de carrera) o
  cualquier sensor nuevo para detectar el atasco: el servomotor no la tiene y la
  detección se hace con la celda ya integrada.
- Rediseño mecánico del tornillo sin fin, del tubo o del acoplamiento para evitar los
  atascos.
- Distinguir un depósito vacío de un atasco real mediante sensores de nivel o de
  presencia de alimento.
- Notificar el atasco al backend o a la aplicación móvil, y cualquier cambio en su
  contrato o en su interfaz.
- Ajuste automático o aprendizaje de los umbrales de detección y resolución de atascos.
- Forzar el motor con giros alternos más allá de los 3 reintentos previstos.

## Criterios de finalización
- `pio run` compila el firmware sin errores.
- RF-1: prueba automatizada de que `serve:true` con `amount` numérico y mayor que cero
  inicia la dispensación con esa cantidad solicitada en gramos.
- RF-2: pruebas automatizadas de que `serve:false` y `amount` igual a cero dejan el
  servo detenido y no generan registro de error; `serve:true` con `amount` ausente, no
  numérico o negativo no dispensa y registra la advertencia de orden inválida.
- RF-3: prueba automatizada de que la ventana de verificación dura exactamente 2 s y no
  se reinicia, de que se supera con al menos 5 lecturas válidas y sin 3 lecturas
  inválidas consecutivas, y de que la línea base es la mediana de las lecturas válidas,
  incluyendo el promedio de los dos valores centrales cuando el número de muestras es
  par.
- RF-4: prueba automatizada de que, si al terminar la ventana fija de 2 s no se cumple
  la condición de RF-3, el servo no se mueve y se registra «sensor no disponible», y de
  que 3 lecturas inválidas consecutivas durante la verificación la dan por no superada
  sin reiniciarla.
- RF-5, RF-6 y RF-7: prueba automatizada del arranque tras la verificación, del cálculo
  del incremento de peso, del pesaje continuo durante avance, retroceso y pausa, de la
  parada por objetivo sostenido en 3 lecturas consecutivas y de la prioridad del
  objetivo sobre la declaración de atasco en la misma muestra.
- RNF-2: prueba automatizada de que una sola lectura por encima del objetivo no detiene el
  servo y de que la parada exige 3 lecturas consecutivas iguales o mayores que el objetivo.
- RF-8: prueba automatizada de que al agotarse el presupuesto de motor se detiene el
  servo y se registra «objetivo no alcanzado» cuando no hay atasco pendiente, y «atasco
  no resuelto» cuando lo hay.
- RF-9: prueba automatizada de que 3 lecturas inválidas consecutivas detienen el servo
  dentro de 1 s desde la primera, sin esperar el presupuesto de motor, de que una
  lectura inválida aislada no detiene el ciclo y de que no se ejecuta ningún retroceso
  tras el fallo.
- RF-10: prueba automatizada de que `reset_wifi:true` prevalece sobre `serve:true` y el
  servo no se mueve, y de que `reset_wifi:true` con `serve:false` o `amount` igual a
  cero también reinicia las credenciales sin mover el servo.
- RF-11: prueba automatizada de que la lectura en bruto multiplicada por el factor de
  calibración se convierte en gramos, y de que un factor no positivo no dispensa y
  registra el error de configuración.
- RF-12: prueba automatizada de que el registro incluye línea base, peso final,
  incremento, cantidad solicitada, `reintentos=N` y motivo; de que `reintentos` vale 0,
  1 y 3 según el ciclo; de que un retroceso interrumpido por un fallo del sensor o por
  agotamiento del presupuesto no incrementa `reintentos`; de que peso final e incremento
  se registran como no disponibles cuando no hubo ninguna lectura válida durante el ciclo
  de motor; y de que la línea base se registra como no disponible si la dispensación se
  aborta antes de fijarla.
- RF-13: verificación de no regresión de aprovisionamiento BLE, conexión y reconexión
  WiFi, validación de conectividad con el servidor, reseteo de credenciales y consulta
  periódica mediante un checklist manual reproducible o las pruebas existentes de esas
  funciones; revisión de código de que el temporizador de la consulta periódica se
  reinicia al finalizar el ciclo, tanto en la operación normal como tras la primera
  consulta siguiente a la conexión, de modo que la próxima consulta ocurra 20 s después
  del fin y no de inmediato; prueba física P12 del checklist de que esa consulta ocurre
  20 s después del fin y no de inmediato. El reinicio vive en el bucle de tareas del
  firmware, que no es verificable en el entorno nativo, por lo que no se exige prueba
  automatizada.
- RF-14: prueba automatizada de que no se declara atasco durante la ventana de gracia de
  2 s; de que un progreso igual o mayor que 2 g reinicia la ventana en ese mismo instante y
  renueva la referencia, de modo que un flujo continuo no declara atasco; de que sí se
  declara con progreso menor que 2 g al terminar los 5 s; de que no se declara con menos
  de 5 lecturas válidas; de que la ventana se abre al existir la primera mediana móvil
  cuando al terminar la gracia todavía no existía; de que un pico aislado de ruido hacia
  arriba no eleva el máximo observado porque la mediana móvil lo descarta; y de que la
  evaluación no ocurre durante el retroceso ni la pausa. Evidencia física (2026-10-27):
  en cinco dispensaciones de 50 g con croqueta de ~3 cm se declararon atascos en cuatro
  de los cinco ciclos y el tercero no se atascó, de modo que la detección distinguió el
  ciclo limpio; queda pendiente en T15 el atasco inducido persistente y la repetición de
  la dispensación normal con alimento que el tornillo transporta sin trabarse, que
  confirmaría el ciclo limpio ya observado y no sería la primera obtención de
  `reintentos=0`.
- Detección sin falso atasco: prueba automatizada con un perfil de flujo realista por
  encima de 0,4 g/s, es decir, por encima del umbral de 2 g cada 5 s, que no declara
  ningún atasco y termina con «objetivo alcanzado» y `reintentos=0`.
- RF-15: prueba automatizada sobre lógica pura, inyectando el contador de reintentos y el
  presupuesto restante, de que con presupuesto suficiente y reintentos disponibles se
  ejecuta la secuencia retroceso de 1,2 s, pausa de 0,3 s y reanudación del avance, de que
  retroceso y pausa descuentan del presupuesto de motor, de que un atasco resuelto no
  impide alcanzar el objetivo y de que el contador de reintentos es una red de seguridad
  que no sustituye al presupuesto. Evidencia física (2026-10-27): cuatro atascos reales con
  croqueta de ~3 cm se resolvieron con `reintentos=1` y motivo «objetivo alcanzado», es
  decir, la secuencia de reintento liberó el mecanismo y la dispensación siguió hasta el
  objetivo; queda pendiente en T15 el caso en que el atasco persiste y termina en «atasco
  no resuelto».
- RF-16: prueba automatizada sobre lógica pura, inyectando el contador de reintentos
  agotado y el presupuesto restante, de que con 0 reintentos disponibles, o con menos de
  3,5 s de presupuesto, el servo se detiene sin ejecutar otro retroceso y se registra
  «atasco no resuelto» con el incremento logrado; no se verifica de extremo a extremo.
- RF-17: prueba nativa sobre el ciclo puro con un servo simulado de que no se invoca el
  retroceso cuando el ciclo termina por fallo del sensor, cuando la orden es inválida y
  cuando las lecturas inválidas son alternas y nunca llega a formarse la mediana móvil, y
  de que la falta de lecturas nunca se interpreta como atasco; prueba física de que el
  servo no retrocede ante un fallo de sensor (P5 y P6 del checklist del informe) ni ante
  una orden inválida (P13 del mismo checklist). No se exige prueba del adaptador de
  hardware, que no contiene lógica de decisión. No duplica los criterios de RF-2 ni de
  RF-9: aquellos verifican la clasificación de la orden y la parada por fallo del sensor,
  este verifica la ausencia de la acción de retroceso.
- RNF-1: revisión de código del bucle del servicio, verificando que el periodo de 200 ms
  se impone con vencimientos absolutos y no con esperas relativas, tanto en la verificación
  como en el ciclo de motor, incluidos retroceso y pausa; el ciclo puro cuenta además con
  una prueba nativa del periodo, con reloj virtual, que comprueba que entre lecturas
  consecutivas no pasan más de 200 ms en las tres fases, y su cumplimiento efectivo sobre
  el hardware se confirma con la prueba física de frecuencia.
- RNF-3: prueba automatizada de que la suma de avances, retrocesos y pausas nunca supera
  30 s y de que el ciclo completo no supera 32 s, con independencia del número de
  reintentos.
- RNF-7: revisión de que las diez constantes de umbral están documentadas en
  español, definidas en un único lugar y consumidas por la lógica sin valores duplicados.
- `pio test -e native` pasa en verde con las pruebas de la lógica de decisión de inicio,
  parada por objetivo, parada por tiempo, parada por fallo del sensor, detección de
  atasco y resolución de atasco.
- Prueba física con un peso patrón: con una cantidad solicitada de 50 g, el incremento
  de peso medido está entre 50 g y 55 g, es decir, con un sobrepeso máximo del 10 %.
- Prueba física de frecuencia: durante la ventana de verificación y el ciclo de motor se
  observa un periodo de muestreo máximo de 200 ms, es decir, al menos 5 lecturas por
  segundo de forma efectiva.
- Prueba física de fallo: con el módulo HX711 desconectado del ESP32 (DT/SCK;
  idealmente también VCC/GND) al arranque el servo no se mueve; desconectando el
  módulo a mitad de la dispensación el servo se detiene antes de los 30 s, dentro de
  1 s desde la primera de las 3 lecturas inválidas consecutivas. Desconectar solo la
  celda con el módulo alimentado puede dar lecturas plausibles y no es una prueba
  determinista.
- Prueba física de atasco inducido: con el servo en avance, bloquear la hélice del
  tornillo sin fin o introducir una croqueta cuñada; se observa el retroceso de 1,2 s, la
  pausa de 0,3 s y la reanudación del avance, y si el bloqueo persiste el ciclo termina
  con «atasco no resuelto», el servo queda detenido y el registro muestra el incremento
  logrado y el número de reintentos ejecutados. Se compara el peso de la bandeja antes y
  después del retroceso para comprobar que no disminuye por efecto del giro inverso.
- Prueba física de atasco resuelto: liberando el bloqueo durante un reintento, la
  dispensación alcanza el objetivo, el motivo registrado es «objetivo alcanzado» y
  `reintentos` es mayor que 0.
- Prueba física de dispensación normal sin falso atasco: dispensación con alimento real y
  sin bloqueo inducido; el motivo registrado es «objetivo alcanzado» y `reintentos=0`, es
  decir, el umbral de 2 g en 5 s no declara un atasco en un flujo normal.
- No regresión: las pruebas nativas existentes siguen en verde y las comprobaciones
  físicas previas de exactitud, frecuencia y fallo de sensor siguen cumpliéndose.
- RNF-4: checklist manual reproducible de no regresión que cubra aprovisionamiento BLE,
  conexión y reconexión WiFi, validación de conectividad con el servidor, reseteo de
  credenciales y consulta periódica con el temporizador reiniciado al fin del ciclo, y
  revisión de que la única dependencia añadida es la necesaria para leer la celda de
  carga.
- RNF-5: inspección del log serie de al menos una dispensación completa, verificando que
  los mensajes están en español, no contienen emojis ni incluyen credenciales o datos
  sensibles.
- El checklist manual reproducible de RF-13 confirma que aprovisionamiento BLE, conexión
  y reconexión WiFi, validación de conectividad con el servidor, reseteo de credenciales
  y consulta periódica siguen funcionando como antes de la integración.
- El registro serie de cada dispensación incluye línea base, peso final, incremento,
  cantidad solicitada, número de reintentos y motivo de finalización.

## Dudas abiertas
- Ninguna.
