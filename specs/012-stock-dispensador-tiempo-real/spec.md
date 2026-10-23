# Spec 012 — Stock del dispensador en tiempo real y limpieza de la tarjeta
Estado: aprobada (revisión de reabastecimiento offline y límite de capacidad)

## Contexto y objetivo
La pantalla de Dispositivos muestra el stock de alimento del dispensador, pero el
valor solo se lee de la caché local (Isar) y nunca se refresca desde el servidor.
El servidor ya descuenta el alimento cuando el ESP32 confirma una dispensación,
sin embargo la app no vuelve a consultar ese stock. Además, el reabastecimiento
solo escribe en Isar y no se envía al servidor, por lo que ambos valores
divergen. La tarjeta también muestra un indicador de "Conectado/Desconectado" y
un bloque "Estado de WiFi" que el usuario no desea ver.

En la revisión se corrige que el reabastecimiento no validaba que la suma al
stock superara la capacidad de 5 kg (el servidor la recortaba en silencio) y que
sin conexión se perdía la operación. Ahora el exceso se rechaza con un aviso
claro y el reabastecimiento sin conexión se calcula y guarda localmente para
sincronizarse cuando el servidor esté disponible.

El objetivo es que la pantalla de Dispositivos refleje el stock real del
servidor en un intervalo corto, que el reabastecimiento respete la capacidad del
depósito, funcione sin conexión y se sincronice después, y que la tarjeta muestre
solo la información esencial (incluido el botón de resetear WiFi).

## Usuarios
- **Dueño de mascota:** quiere ver cuánto alimento queda realmente, reabastecer
  sin perder la operación cuando no hay internet y recibir un aviso claro si la
  cantidad no cabe en el depósito.
- **Mantenedor:** quiere que la app y el servidor compartan una única verdad del
  stock, sin descuentos duplicados y sin perder reabastecimientos pendientes.

## Historias de usuario
- HU-1. Como dueño de mascota, quiero ver el stock actualizado tras cada
  dispensación para saber cuándo reabastecer.
- HU-2. Como dueño de mascota, quiero que al reabastecer se sume lo que agregué
  al stock existente, respetando el máximo de 5 kg, y verlo reflejado.
- HU-3. Como dueño de mascota, quiero una tarjeta limpia, sin indicadores de
  conexión ni estado de WiFi, conservando el botón para resetear el WiFi.
- HU-4. Como dueño de mascota, quiero ver el alimento restante tanto en gramos
  como en kilogramos.
- HU-5. Como dueño de mascota, quiero reabastecer aunque no haya conexión y que
  la app sincronice el cambio cuando el servidor vuelva a estar disponible.
- HU-6. Como dueño de mascota, quiero que me avise cuando el reabastecimiento
  supera la capacidad del depósito en lugar de recortar la cantidad en silencio.

## Definiciones
- **Stock actual:** `current_food_grams` del dispensador, acotado entre 0 y
  5000 g.
- **Reabastecer:** sumar la cantidad indicada al stock actual. Si la suma supera
  los 5000 g, la operación se rechaza y el stock no cambia.
- **Reabastecimiento pendiente:** delta de gramos guardado en Isar cuando el
  reabastecimiento se hace sin conexión, a la espera de enviarse al servidor.
- **Refresco silencioso:** consultar y actualizar el stock sin mostrar la
  pantalla de carga de la lista.

## Requisitos funcionales (EARS)
- RF-1: MIENTRAS el usuario visualiza la tarjeta de un dispensador en la
  pantalla de Dispositivos, EL SISTEMA mostrará nombre, MAC, nivel de alimento y
  las acciones de reabastecer y ver detalles, y ocultará el indicador de
  conexión y el bloque de estado de WiFi.
- RF-2: EL SISTEMA conservará el botón "Resetear WiFi" en la tarjeta y su
  confirmación previa antes de enviar la orden.
- RF-3: EL SISTEMA mostrará el alimento restante simultáneamente en gramos y en
  kilogramos, junto con el porcentaje respecto a la capacidad y el aviso de
  nivel crítico cuando corresponda.
- RF-4: CUANDO el stock cambie en el servidor por una dispensación, EL SISTEMA
  actualizará la pantalla de Dispositivos sin intervención del usuario en un
  máximo de 30 segundos mientras esa pantalla esté visible.
- RF-5: CUANDO el usuario deslice hacia abajo en la pantalla de Dispositivos,
  EL SISTEMA consultará el stock del servidor y actualizará la lista.
- RF-6: CUANDO la aplicación vuelva a primer plano con la pantalla de
  Dispositivos visible, EL SISTEMA actualizará la lista desde el servidor.
- RF-7: CUANDO el usuario reabastezca con una cantidad que, sumada al stock
  actual, no supere 5000 g, EL SISTEMA sumará la cantidad y reflejará el nuevo
  valor en la pantalla; con conexión usará la respuesta del servidor y sin
  conexión actualizará el stock local y dejará el delta pendiente.
- RF-8: SI la cantidad ingresada es cero, negativa, no numérica, o la suma con
  el stock actual supera 5000 g, ENTONCES EL SISTEMA no modificará el stock y
  mostrará el aviso "El reabastecimiento supera el límite de 5 kg".
- RF-9: CUANDO el usuario regrese desde la pantalla de escaneo BLE, EL SISTEMA
  volverá a mostrar la lista de dispositivos en lugar del botón "Cargar
  Dispensadores".
- RF-10: SI una consulta de actualización falla, ENTONCES EL SISTEMA conservará
  el último stock local y no mostrará un aviso invasivo.
- RF-11: SI no hay conexión o el dispensador no tiene identificador remoto al
  reabastecer, ENTONCES EL SISTEMA calculará y guardará el nuevo stock y el
  delta pendiente en Isar, y mostrará "Reabastecimiento con éxito".
- RF-12: CUANDO haya conexión y la pantalla de Dispositivos esté visible
  (sondeo, pull-to-refresh o retorno a primer plano), EL SISTEMA enviará los
  deltas pendientes antes de consultar el stock; si el envío funciona limpiará
  el pendiente, si el servidor rechaza por límite reconciliará el stock con el
  servidor y limpiará el pendiente, y si falla la red conservará el pendiente.
- RF-13: MIENTRAS el usuario opera el reabastecimiento, EL SISTEMA solo mostrará
  el aviso de límite o "Reabastecimiento con éxito"; no mostrará mensajes de
  error técnicos ni genéricos de servidor.

## Requisitos no funcionales
- RNF-1: El refresco automático se ejecutará cada 5 segundos y solo mientras la
  pantalla de Dispositivos esté visible y sin diálogos o rutas encima.
- RNF-2: El refresco automático no mostrará la pantalla de carga ni vaciará la
  lista mientras consulta.
- RNF-3: No se agregarán dependencias nuevas; el formato numérico y las
  validaciones se resolverán con funciones puras del proyecto.
- RNF-4: La lógica de sincronización y reabastecimiento vivirá en el repositorio
  y el BLoC; las vistas solo presentarán estado y dispararán eventos.
- RNF-5: El stock se descontará únicamente en el servidor; la app no aplicará
  descuentos locales para evitar dobles conteos.
- RNF-6: Todos los textos visibles estarán en español y se cubrirán con pruebas.
- RNF-7: El reabastecimiento pendiente se persistirá en Isar y sobrevivirá al
  cierre y reapertura de la aplicación.
- RNF-8: El envío de un reabastecimiento pendiente no modificará el stock local
  con una respuesta parcial; si el servidor rechaza por límite se reconciliará
  con el stock real del servidor.

## Casos límite
- Stock actual 4900 g y se agregan 200 g: se rechaza con el aviso de límite y
  el stock permanece en 4900 g.
- Stock actual 1000 g y se agregan 4000 g: el resultado es 5000 g.
- Cantidad 0, negativa o vacía: se rechaza con el mismo aviso de límite.
- Cantidad mayor a 5000 g en una sola operación: se rechaza con el aviso de
  límite.
- Reabastecimiento sin conexión válido: se aplica localmente, queda pendiente y
  se muestra éxito.
- Reabastecimiento sin conexión que supera 5000 g: se rechaza sin cambios.
- Conexión recuperada con delta pendiente: se envía, se limpia y se cachea la
  respuesta del servidor.
- El servidor rechaza el delta pendiente por límite (carrera de stock): se
  consulta el stock real, se cachea y se limpia el pendiente.
- Dispensador sin `pet_id`: no aparece en la lista ni se refresca.
- Dispensador con `pet_id` pero sin identificador remoto: el reabastecimiento se
  guarda local y queda pendiente de sincronizar cuando exista el identificador.
- Sin conexión o servidor no disponible durante el refresco: se conserva el
  stock local.
- Fallo del servidor al reabastecer por una causa distinta al límite: se guarda
  local como pendiente y se muestra éxito.
- Retorno desde escaneo BLE o desde la app en segundo plano: la lista se
  restaura y se refresca.

## Fuera de alcance
- Sincronización instantánea por push o WebSocket (el refresco es por sondeo).
- Indicador visual permanente de "reabastecimiento pendiente" en la tarjeta.
- Refresco automático en la tarjeta del detalle de la mascota.
- Cambios en el firmware del ESP32.

## Criterios de finalización
- La tarjeta no muestra "Conectado/Desconectado" ni "Estado de WiFi", y conserva
  el botón "Resetear WiFi".
- El stock se actualiza solo en la pantalla de Dispositivos en menos de 30 s.
- Reabastecer suma al stock solo si el resultado no supera 5000 g; si lo supera,
  no cambia nada y se muestra "El reabastecimiento supera el límite de 5 kg".
- Sin conexión, el stock se actualiza localmente y el delta queda pendiente en
  Isar; al recuperar conexión se sincroniza sin intervención del usuario.
- Los avisos de reabastecimiento son únicamente el de límite o "Reabastecimiento
  con éxito".
- `flutter test`, `flutter analyze` y `pytest` pasan sin errores nuevos.
- `MEMORY.md` actualizado.

## Dudas abiertas
- Ninguna.
