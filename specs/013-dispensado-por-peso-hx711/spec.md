# Spec 013 — Dispensado por peso con celda de carga

Estado: implementada (T1–T9; T10 pendiente de hardware)

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

El objetivo es que cada orden de dispensación entregue la cantidad solicitada, medida
por peso, deteniendo el motor al alcanzarla, y que nunca se dispense a ciegas: si la
celda no responde antes de iniciar, no se mueve el servo, y si falla de forma sostenida
a mitad de la dispensación, el servo se detiene sin esperar el límite de giro. Todo
ello con un límite máximo de 30 segundos de giro por si la celda falla o no hay
alimento, y sin romper el aprovisionamiento BLE, la conexión WiFi ni la consulta
periódica a la API.

## Usuarios
- **Dueño de mascota:** recibe una ración ajustada a la cantidad solicitada, sin
  depender del tiempo de giro ni del tipo de alimento.
- **Desarrollador / Ingeniero de hardware:** integra y calibra la celda de carga,
  dispone de un registro serie con la línea base, el peso final y el motivo de
  finalización para diagnosticar cada dispensación.

## Historias de usuario
- HU-1. Como dueño de mascota, quiero que el dispensador entregue la cantidad de
  alimento solicitada en gramos para que la ración real coincida con la calculada.
- HU-2. Como dueño de mascota, quiero que el dispensador se detenga solo al alcanzar
  la cantidad pedida para no servir más comida de la necesaria.
- HU-3. Como dueño de mascota, quiero que el sistema no dispense si el sensor de peso
  no funciona, para no servir una cantidad arbitraria.
- HU-4. Como dueño de mascota, quiero que el giro del dispensador nunca dure más de 30
  segundos, además de la ventana fija de 2 segundos de verificación previa del sensor,
  para que un fallo no deje el motor girando indefinidamente; el ciclo completo no
  supera los 32 segundos.
- HU-5. Como desarrollador, quiero un registro serie con la línea base, el peso
  final, el incremento, la cantidad solicitada y el motivo de finalización para
  diagnosticar fallos.
- HU-6. Como desarrollador, quiero ajustar la calibración con un factor configurable
  para adaptar la lectura de la celda al montaje sin comandos por puerto serie.

## Definiciones
- **Cantidad solicitada:** valor del campo `amount` de la respuesta de la API,
  expresado en gramos.
- **Ventana de verificación:** intervalo fijo de exactamente 2 segundos, previo al
  giro y no reiniciable. La verificación se supera si dentro de la ventana se obtienen
  al menos 5 lecturas válidas y no hay 3 lecturas inválidas consecutivas; una lectura
  inválida no reinicia ni extiende la ventana.
- **Línea base:** mediana de las lecturas válidas de la ventana de verificación, fijada
  justo antes del giro. Si la dispensación se aborta antes de fijarla, se registra como
  no disponible.
- **Mediana:** para un número impar de muestras, el valor central al ordenarlas; para un
  número par, el promedio de los dos valores centrales.
- **Peso final:** última lectura válida en el instante de detener el servo; si hubo
  fallo del sensor, la última lectura válida anterior al fallo; si no hubo ninguna
  lectura válida durante el giro, se registra como no disponible.
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
  segundos y un giro de hasta 30 segundos; arranca el servo solo si la verificación se
  supera, mide el incremento de peso de forma continua y detiene el servo al
  alcanzar el objetivo o al cumplirse el límite de giro.

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
  de las lecturas válidas de esa ventana justo antes de poner el servo en giro.
- RF-4: SI al terminar la ventana fija de 2 segundos no se cumple la condición de RF-3,
  ENTONCES EL SISTEMA abortará la dispensación sin mover el servo, mantendrá el servo
  detenido y registrará el motivo «sensor no disponible»; 3 lecturas inválidas
  consecutivas dentro de la ventana la dan por no superada, y la ventana no se reinicia
  ni se extiende.
- RF-5: CUANDO la celda entregue lecturas válidas y la línea base esté tomada, EL
  SISTEMA pondrá el servomotor en giro continuo para dispensar alimento.
- RF-6: MIENTRAS el servomotor esté girando, EL SISTEMA medirá el peso del alimento
  dispensado de forma continua y calculará el incremento de peso respecto a la línea
  base.
- RF-7: CUANDO el incremento de peso sea igual o mayor que la cantidad solicitada en
  gramos en al menos 3 lecturas consecutivas, EL SISTEMA detendrá el servomotor y dará
  la dispensación por completada.
- RF-8: SI transcurren 30 segundos desde el inicio del giro sin que se alcance el
  objetivo, ENTONCES EL SISTEMA detendrá el servomotor y registrará el resultado
  como objetivo no alcanzado, indicando el incremento de peso logrado.
- RF-9: SI durante el giro se producen 3 lecturas inválidas consecutivas, ENTONCES EL
  SISTEMA detendrá el servomotor sin esperar a que se cumpla el límite de 30 segundos,
  dentro de 1 segundo desde la primera de esas 3 lecturas, y registrará el motivo
  «fallo del sensor durante la dispensación»; con el periodo de muestreo de RNF-1 y el
  plazo de respuesta de 100 ms, 3 lecturas inválidas consecutivas se detectan en menos
  de 1 segundo. Una lectura inválida aislada no detiene el ciclo.
- RF-10: SI la respuesta de la API indica `reset_wifi: true`, ENTONCES EL SISTEMA
  borrará las credenciales almacenadas y reiniciará en modo de aprovisionamiento,
  sin mover el servomotor y con prioridad sobre `serve` y `amount`, tanto si `serve` es
  `true` como si es `false` o `amount` es cero.
- RF-11: EL SISTEMA aplicará un factor de calibración configurable, ajustable
  manualmente por el desarrollador antes de compilar, para convertir la lectura de la
  celda en gramos; no ofrecerá comandos de calibración por el puerto serie. SI el
  factor de calibración no es positivo, ENTONCES EL SISTEMA no dispensará y registrará
  un error de configuración.
- RF-12: CUANDO finalice una dispensación, sea por objetivo alcanzado, por límite de
  30 segundos, por fallo del sensor o por aborto en la verificación previa, EL SISTEMA
  registrará por el puerto serie la línea base, el peso final medido, el incremento de
  peso, la cantidad solicitada y el motivo de finalización; si no hubo ninguna lectura
  válida durante el giro, el peso final y el incremento se registrarán como no
  disponibles; si la dispensación se aborta antes de fijar la línea base, la línea base
  se registrará como no disponible, igual que el peso final y el incremento.
- RF-13: EL SISTEMA conservará sin regresiones el aprovisionamiento BLE, la conexión
  y reconexión WiFi, la validación de conectividad con el servidor, el reseteo de
  credenciales y la consulta periódica a la API en el intervalo ya definido; tras
  cualquier dispensación, completada o fallida, reanudará la consulta periódica
  reiniciando su temporizador, de modo que la siguiente consulta se realizará 20
  segundos después de finalizar el ciclo y no de inmediato, sin reiniciar el
  dispositivo.

## Requisitos no funcionales
- RNF-1: Mientras la celda esté operativa, el sistema aplicará un periodo de muestreo
  máximo de 200 milisegundos, es decir, un mínimo efectivo de 5 lecturas por segundo,
  tanto durante la ventana de verificación como durante el giro. La detección del
  objetivo no se basa en una única lectura de 200 milisegundos: exige 3 lecturas
  consecutivas (RF-7). En la ventana de 2 s, a 5 Hz se obtienen aproximadamente 10
  lecturas, de las que se exigen al menos 5 válidas.
- RNF-2: El objetivo se considerará alcanzado solo cuando el incremento de peso sea
  igual o mayor que la cantidad solicitada en al menos 3 lecturas consecutivas, para
  no detener el servo por un pico de ruido o vibración.
- RNF-3: El giro del servomotor no superará en ningún caso los 30 segundos por
  dispensación; la ventana fija de verificación de 2 segundos es independiente y no se
  descuenta de ese límite, por lo que el ciclo completo no supera los 32 segundos, sin
  excepciones.
- RNF-4: No se agregarán dependencias distintas de la necesaria para leer la celda de
  carga; el resto del firmware y su comportamiento actual se mantienen, con dos
  excepciones explícitas: (a) el dispensado por tiempo de 10 segundos (RF-07 de la spec
  008) queda reemplazado por el dispensado por peso descrito en esta spec; (b) el
  temporizador de la consulta periódica se reinicia al terminar el ciclo, de modo que la
  siguiente consulta ocurre 20 segundos después del fin y no 20 segundos después de la
  consulta anterior.
- RNF-5: Los mensajes de registro serie estarán en español, sin emojis, y no
  incluirán credenciales ni datos sensibles.
- RNF-6: La lógica de decisión de inicio, parada y tiempo límite será verificable con
  pruebas automatizadas sobre lógica pura, sin requerir hardware; la exactitud del
  pesaje se validará con una prueba física.

## Casos límite
- Depósito vacío o alimento que no fluye: no se alcanza el objetivo; a los 30 s de giro
  se detiene el servo y se registra «objetivo no alcanzado» con incremento cercano a
  cero.
- Ruido o vibración del motor que produce lecturas inestables: no se detiene el servo
  hasta que el objetivo se sostiene en lecturas consecutivas; el límite de 30 s de
  giro sigue vigente.
- Cantidad solicitada mayor de la que el mecanismo puede entregar en 30 s de giro: se
  detiene por tiempo, se registra el incremento parcial logrado y la dispensación se da
  por no completada.
- Alimento en caída después de detener el servo: el peso final puede superar el
  objetivo; el registro serie permite detectar el sobrepeso.
- Ciclo completo: 2 s de ventana fija de verificación más 30 s de giro, es decir, 32 s
  como máximo; la verificación no consume el límite de giro.
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
  objetivo y el ciclo continúa hasta alcanzarlo o hasta el límite de 30 s de giro.
- Línea base tan alta que la línea base más la cantidad solicitada supera los 5000 g: el
  objetivo no puede alcanzarse dentro del rango válido de medición y el ciclo termina,
  como máximo, por el límite de 30 s de giro; si la celda satura antes, aplica RF-9.
- Factor de calibración no positivo: error de configuración; no se dispensa y se
  registra.
- Celda que falla a mitad de la dispensación: 3 lecturas inválidas consecutivas
  detienen el servo dentro de 1 s desde la primera, sin esperar los 30 s, y se registra
  el motivo.
- Lectura inválida aislada durante el giro: no detiene el ciclo; solo 3 lecturas
  inválidas consecutivas se consideran fallo del sensor.
- Ninguna lectura válida durante el giro (caso defensivo): el peso final y el
  incremento se registran como no disponibles; la línea base de la verificación, la
  cantidad solicitada y el motivo sí se registran.
- `serve: false` o `amount` igual a cero sin `reset_wifi:true`: reposo normal del
  backend; no se dispensa, no se mueve el servo y no se registra error.
- `serve: true` con `amount` ausente, no numérico o negativo: no se dispensa y se
  registra una advertencia de orden de dispensación inválida.
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
  del incremento de peso y de la parada por objetivo sostenido en 3 lecturas
  consecutivas.
- RF-8: prueba automatizada de que a los 30 s de giro se detiene el servo y se registra
  «objetivo no alcanzado».
- RF-9: prueba automatizada de que 3 lecturas inválidas consecutivas detienen el servo
  dentro de 1 s desde la primera, sin esperar los 30 s, y de que una lectura inválida
  aislada no detiene el ciclo.
- RF-10: prueba automatizada de que `reset_wifi:true` prevalece sobre `serve:true` y el
  servo no se mueve, y de que `reset_wifi:true` con `serve:false` o `amount` igual a
  cero también reinicia las credenciales sin mover el servo.
- RF-11: prueba automatizada de que la lectura en bruto multiplicada por el factor de
  calibración se convierte en gramos, y de que un factor no positivo no dispensa y
  registra el error de configuración.
- RF-12: prueba automatizada de que el registro incluye línea base, peso final,
  incremento, cantidad solicitada y motivo; de que peso final e incremento se registran
  como no disponibles cuando no hubo ninguna lectura válida durante el giro; y de que la
  línea base se registra como no disponible si la dispensación se aborta antes de
  fijarla.
- RF-13: verificación de no regresión de aprovisionamiento BLE, conexión y reconexión
  WiFi, validación de conectividad con el servidor, reseteo de credenciales y consulta
  periódica mediante un checklist manual reproducible o las pruebas existentes de esas
  funciones; prueba automatizada de que, tras finalizar el ciclo, la siguiente consulta
  ocurre 20 s después del fin y no 20 s después de la consulta anterior.
- `pio test -e native` pasa en verde con las pruebas de la lógica de decisión de
  inicio, parada por objetivo, parada por tiempo y parada por fallo del sensor.
- Prueba física con un peso patrón: con una cantidad solicitada de 50 g, el incremento
  de peso medido está entre 50 g y 55 g, es decir, con un sobrepeso máximo del 10 %.
- Prueba física de frecuencia: durante la ventana de verificación y el giro se observa
  un periodo de muestreo máximo de 200 ms, es decir, al menos 5 lecturas por segundo de
  forma efectiva.
- Prueba física de fallo: con el módulo HX711 desconectado del ESP32 (DT/SCK;
  idealmente también VCC/GND) al arranque el servo no se mueve; desconectando el
  módulo a mitad de la dispensación el servo se detiene antes de los 30 s, dentro de
  1 s desde la primera de las 3 lecturas inválidas consecutivas. Desconectar solo la
  celda con el módulo alimentado puede dar lecturas plausibles y no es una prueba
  determinista.
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
  cantidad solicitada y motivo de finalización.

## Dudas abiertas
- Ninguna.
