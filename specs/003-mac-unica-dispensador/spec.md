# Spec 003 — Dirección MAC Única por Dispensador y Aviso Reutilizable al Usuario

Estado: implementada

## Contexto y objetivo

Hoy el registro de un dispensador puede completarse aunque el dispositivo no esté registrado en el servidor: la aplicación guarda el dispensador de forma local y lo marca como pendiente de sincronizar. Además, la revisión de la dirección MAC se hace comparando el texto recibido tal cual, por lo que dos direcciones equivalentes escritas con formatos distintos pueden pasar inadvertidas y provocar que un mismo dispensador quede asociado a dos mascotas o a dos usuarios distintos.

El objetivo de esta especificación es definir los requisitos para que:

1. La dirección MAC de un dispensador sea un identificador único global, validado de forma robusta y siempre en el servidor (no se puede validar solo del lado del usuario porque otro usuario podría tener ese mismo dispensador registrado y se generarían conflictos).
2. El registro de un dispensador solo sea posible cuando exista conexión con el servidor, ya que la unicidad no puede verificarse sin conexión.
3. El usuario reciba, en los casos de rechazo, una ventana emergente reutilizable con estilo Material Design 3 (MD3) que explique el problema de forma sencilla y no como una alerta "fea y roja".

Esta especificación **anula** el requisito RF-07 de `specs/002-offline-data-persistence-fix` (registro y persistencia offline de la dirección MAC del dispensador). Offline-First se mantiene intacto para el resto de operaciones (consultas de dispensadores ya vinculados, mascotas, horarios y logs), excluyendo la desactivación y la eliminación de dispensadores, que ahora exigen conexión obligatoria al igual que el registro y el cambio de MAC.

## Usuarios

* **Usuario dueño de una mascota:** Registra y vincula un dispensador a su mascota escaneando el código QR del dispositivo; necesita entender con claridad por qué una operación fue rechazada y qué puede hacer al respecto.
* **Administrador del sistema:** Garantiza la integridad de los datos de Hardware; depende de que no existan dos registros con la misma dirección MAC en todo el sistema.

## Historias de usuario

* **HU-1.** Como usuario, quiero que la aplicación me informe, con un mensaje claro y no técnico, cuando el dispensador que intento registrar ya está registrado en el sistema, para saber qué hacer a continuación en lugar de ver un error genérico.
* **HU-2.** Como usuario, quiero que la aplicación me informe, con un mensaje claro, cuando el intento de cambiar la dirección MAC de un dispensador que ya tengo fue rechazado porque esa dirección ya está en uso, para corregir los datos introducidos.
* **HU-3.** Como usuario, quiero que la aplicación me indique de forma amable que necesito conexión a internet para registrar o modificar un dispensador, para no esperar un registro exitoso que nunca llegará.
* **HU-4.** Como usuario, quiero que los avisos del sistema tengan un Aspecto consistente, Material Design 3 y fácil de entender, en lugar de alertas rojas sin contexto.
* **HU-5.** Como administrador, quiero que sea imposible que dos mascotas (de cualquier usuario) compartan la misma dirección MAC, para que cada dispositivo de alimentación esté asociado a una sola mascota.
* **HU-6.** Como usuario, quiero que los dispensadores que guardé sin conexión en versiones anteriores y que nunca fueron validados desaparezcan solos de mi lista, en lugar de aparecer como válidos y fallar al usarlos.

## Definiciones

* **MAC:** Identificador de 12 dígitos hexadecimales del dispositivo dispensador, escrito con separadores variables (dos puntos, guiones, puntos o sin separadores).
* **Forma normalizada:** Representación única obtenida de una MAC quitando espacios y separadores y unificando mayúsculas/minúsculas; dos MAC con la misma forma normalizada se consideran la misma dirección.
* **Conflicto de MAC:** Situación en la que la forma normalizada de la MAC recibida ya está registrada en el sistema asociada a otra mascota o a otro registro de dispensador.
* **Operación con validación de MAC:** Alta de un dispensador o modificación de la dirección MAC de un dispensador existente.
* **Aviso de diálogo:** Ventana emergente modal informativa o de advertencia, con estilo Material Design 3, icono, título, descripción y una acción principal, usada en lugar de avisos brutos de error.

## Requisitos funcionales (EARS)

* **RF-01 (Unicidad global de la MAC):** EL SISTEMA debe garantizar que una misma forma normalizada de dirección MAC no esté asociada a dos mascotas ni a dos registros de dispensador en todo el sistema, independientemente del usuario propietario y del formato en que se haya escrito.
* **RF-02 (Normalización de la dirección MAC):** CUANDO el sistema compare direcciones MAC con el fin de detectar duplicados, EL SISTEMA debe comparar sus formas normalizadas (sin espacios, sin dos puntos, sin guiones y sin distinguir mayúsculas de minúsculas).
* **RF-03 (Validación en el registro):** CUANDO un usuario registre un dispensador, EL SISTEMA debe validar en el servidor la unicidad de la forma normalizada de la dirección MAC antes de persistir el registro; SI la forma normalizada ya está registrada, ENTONCES EL SISTEMA debe rechazar el registro y devolver una respuesta de error identificable de forma unívoca como "conflicto de MAC ya registrada" (caso 1).
* **RF-04 (Validación en la modificación):** CUANDO un usuario modifique un dispensador existente, EL SISTEMA debe validar en el servidor la unicidad de la forma normalizada de la nueva dirección MAC; SI la nueva forma normalizada está registrada en otro dispensador, ENTONCES EL SISTEMA debe rechazar la modificación y devolver una respuesta de error identificable de forma unívoca como "conflicto de MAC en uso" (caso 2).
* **RF-05 (Modificación sin cambio de MAC):** SI la dirección MAC de una modificación es igual a la almacenada o solo difiere en mayúsculas, espacios o separadores (misma forma normalizada), ENTONCES EL SISTEMA debe considerar que la dirección no cambió y no debe rechazar la operación por este motivo.
* **RF-06 (Formato de MAC inválido distinguible del conflicto):** SI la dirección MAC recibida no está formada por exactamente 12 dígitos hexadecimales tras eliminar espacios y separadores, ENTONCES EL SISTEMA debe rechazarla y devolver una respuesta de error identificable de forma unívoca como "formato de MAC inválido", distinta de los errores de conflicto de RF-03 y RF-04.
* **RF-07 (Garantía bajo concurrencia):** SI dos operaciones de validación con MAC conflictiva se procesan de forma simultánea, ENTONCES EL SISTEMA debe asegurar que solo una de ellas queda persistida y la otra recibe el error de conflicto, sin depender únicamente de la comprobación previa.
* **RF-08 (Consistencia de la normalización):** EL SISTEMA debe aplicar la misma forma normalizada en cualquier comparación de direcciones MAC que realice (alta, modificación, consulta y sincronización), de modo que el comportamiento hacia el dispositivo físico y hacia la aplicación no cambie por el formato en que se reciba la dirección.
* **RF-09 (Componente reutilizable de aviso):** EL SISTEMA debe disponer de un componente de ventana emergente reutilizable por cualquier funcionalidad, con estilo Material Design 3, que presente icono, título breve, descripción en español y una acción principal, y que permita elegir entre un carácter informativo y uno de advertencia.
* **RF-10 (Aviso en el caso 1):** CUANDO el servidor rechace el registro de un dispensador por conflicto de MAC, ENTONCES EL SISTEMA debe mostrar el componente de RF-09 con un título y una descripción, en español y sin jerga, que expliquen que ese dispensador ya está registrado y que el usuario debe escanear el código QR del dispensador correcto o revisar con quién está vinculado.
* **RF-11 (Aviso en el caso 2):** CUANDO el servidor rechace la modificación de un dispensador por conflicto de MAC, ENTONCES EL SISTEMA debe mostrar el componente de RF-09 con un título y una descripción, en español y sin jerga, que expliquen que la dirección nueva ya está siendo usada por otro dispensador y que el usuario debe verificar la dirección introducida.
* **RF-12 (Aviso de formato inválido):** CUANDO el servidor rechace la operación por formato de MAC inválido (RF-06), ENTONCES EL SISTEMA debe mostrar el componente de RF-09 con un mensaje distinto al de conflicto, orientado a corregir los datos introducidos y a mostrar un ejemplo válido de dirección MAC.
* **RF-13 (Registro de dispensador solo en línea):** SI no existe conexión con el servidor al intentar registrar un dispensador, ENTONCES EL SISTEMA debe impedir el registro, no debe crear ningún registro de dispensador local, no debe crear ningún registro marcado como pendiente de sincronizar y debe mostrar el componente de RF-09 indicando que se necesita conexión a internet para registrar el dispensador.
* **RF-14 (Cambio de MAC solo en línea):** SI no existe conexión con el servidor al intentar cambiar la dirección MAC de un dispensador existente, ENTONCES EL SISTEMA debe impedir la operación, no debe dejar el dispensador localmente modificado y debe mostrar el componente de RF-09 indicando que se necesita conexión a internet para modificar la dirección del dispensador.
* **RF-13.1 (Desactivación de dispensador solo en línea):** SI no existe conexión con el servidor al intentar desactivar un dispensador, ENTONCES EL SISTEMA debe impedir la operación, no debe modificar el estado local del dispensador y debe mostrar el componente de RF-09 indicando que se necesita conexión a internet para desactivar el dispensador.
* **RF-13.2 (Eliminación de dispensador solo en línea):** SI no existe conexión con el servidor al intentar eliminar un dispensador, ENTONCES EL SISTEMA debe impedir la operación, no debe eliminar el registro local ni marcarlo como pendiente y debe mostrar el componente de RF-09 indicando que se necesita conexión a internet para eliminar el dispensador.
* **RF-15 (Sin registros de dispensador pendientes de envío):** EL SISTEMA no debe generar nuevos registros locales de dispensador marcados como pendientes de sincronización, ni intentar enviarlos al servidor como nuevos registros, tras la aplicación de esta especificación.
* **RF-16 (Privacidad del aviso de conflicto):** EL SISTEMA no debe incluir en la respuesta de conflicto información sobre la mascota, el usuario o cualquier otro dato del propietario del dispensador en conflicto; el mensaje solo debe describir el problema y la acción sugerida para el usuario que intentó la operación.
* **RF-17 (Offline-First preservado):** EL SISTEMA debe mantener la disponibilidad sin conexión de las demás operaciones (consulta de mascotas, horarios, logs y dispensador ya vinculado), excluyendo explícitamente la desactivación y la eliminación de dispensadores (que junto con el registro y cambio de MAC exigen conexión obligatoria), sin que ello degrade el comportamiento offline del resto del sistema.
* **RF-18 (Limpieza de dispensadores locales huérfanos):** CUANDO el usuario consulte sus dispensadores, EL SISTEMA debe detectar los registros locales de dispensador que no han sido validados por el servidor (nunca sincronizados) y eliminarlos localmente, dejando constancia en un registro de diagnóstico que incluya la dirección MAC del registro eliminado.
* **RF-19 (Los huérfanos no se sincronizan ni se muestran):** SI un dispensador local es eliminado por RF-18, ENTONCES EL SISTEMA no debe intentar enviarlo al servidor, no debe crear ninguna marca de pendiente de sincronización a partir de él y no debe mostrarlo al usuario en ninguna lista o pantalla.
* **RF-20 (Alcance de la limpieza):** RF-18 y RF-19 deben aplicarse únicamente a los registros de dispensador huérfanos y no deben eliminar ni alterar ningún otro dato local (mascotas, horarios, registros de actividad, sesión o credenciales).

## Requisitos no funcionales

* **RNF-01 (Clean Architecture):** La lógica de validación de MAC y la decisión entre operación en línea u operación local deben residir en las capas de dominio y datos; el componente de aviso de RF-09 debe ser únicamente de presentación y las vistas principales no deben contener lógica de negocio.
* **RNF-02 (Reutilización real):** El componente de aviso de RF-09 debe ser utilizable por cualquier funcionalidad sin depender del módulo de dispensadores ni de sus tipos de datos, parametrizando el tipo de aviso (informativo o advertencia), el icono, el título, la descripción y la acción.
* **RNF-03 (Estilo Material Design 3):** El aviso debe seguir las pautas de Material Design 3: jerarquía visual de título y descripción, icono asociado al significado del aviso, botón de acción principal y cierre mediante la misma acción.
* **RNF-04 (Consistencia visual del tema):** El aviso debe utilizar exclusivamente la paleta de colores y la tipografía globales de la aplicación, y verse correctamente en modo claro y en modo oscuro.
* **RNF-05 (Sin avisos brutos):** Los casos de RF-10, RF-11, RF-12, RF-13, RF-14, RF-13.1 y RF-13.2 deben mostrarse mediante la ventana emergente de RF-09 (`AppNoticeDialog`) y no mediante avisos de error genéricos con color rojo como único indicador; el color, por sí solo, no debe ser el único medio de transmitir el significado.
* **RNF-06 (Texto legible y adaptable):** El contenido del aviso debe ser legible en pantallas estrechas y con tamaño de fuente ampliado, sin desbordes, recortes ni texto cortado, y con un ancho de contenido acotado en pantallas grandes.
* **RNF-07 (Accesibilidad):** Los elementos interactivos del aviso deben tener un área táctil mínima de 48 dp y un nombre accesible; el icono del aviso debe tener una descripción accesible coherente con su significado.
* **RNF-08 (Robustez verificable de la normalización):** La equivalencia de formatos debe quedar demostrada mediante pruebas automatizadas para el 100 % de los formatos definidos en Casos límite (CL-1 a CL-3), sin falsos positivos ni falsos negativos.
* **RNF-09 (Trazabilidad):** Cada requisito funcional debe quedar asociado a al menos una prueba automatizada y a un componente verificable del sistema antes de declarar la especificación como implementada.

## Casos límite

* **CL-1 (Formatos equivalentes en alta):** Registrar un dispensador con la MAC `AA:BB:CC:DD:EE:FF` cuando ya existe `aa:bb:cc:dd:ee:ff` debe detectarse como el mismo dispensador y rechazarse con conflicto (RF-03).
* **CL-2 (Formato sin separadores):** Registrar un dispensador con la MAC `AABBCCDDEEFF` cuando ya existe `AA:BB:CC:DD:EE:FF` debe rechazarse con conflicto (RF-02, RF-03).
* **CL-3 (Formato con guiones o espacios):** Registrar o consultar con `aa-bb-cc-dd-ee-ff`, `aa bb cc dd ee ff` o con punto como separador debe tratarse como la misma dirección que su equivalente con dos puntos.
* **CL-4 (Modificación sin cambio real):** Enviar en una modificación la misma MAC con mayúsculas distintas, con guiones en lugar de dos puntos o con espacios adicionales debe considerarse la misma dirección: la operación no debe fallar por conflicto (RF-05).
* **CL-5 (Modificación a una MAC en uso):** Cambiar la MAC de un dispensador propio a la de otro dispensador ya existente debe rechazarse con el aviso de caso 2, sin modificar ningún dato del dispensador (RF-04, RF-11).
* **CL-6 (Dos usuarios, misma MAC):** Dos usuarios que intentan registrar la misma dirección MAC, uno de los cuales ya la tiene registrada, deben obtener un resultado exitoso y un conflicto respectivamente, sin que ambos queden persistidos (RF-01, RF-07).
* **CL-7 (MAC inválida):** Una MAC con longitud distinta de 12 dígitos hexadecimales, con caracteres no hexadecimales, vacía o ausente debe rechazarse con el aviso de formato inválido, nunca con el mensaje de conflicto (RF-06, RF-12).
* **CL-8 (Sin conexión en el registro):** Sin conexión con el servidor, el intento de registro debe mostrar el aviso de conexión requerida y no dejar ningún rastro local del dispensador ni una marca de pendiente de envío (RF-13, RF-15).
* **CL-9 (Sin conexión en la modificación de MAC):** Sin conexión con el servidor, el intento de cambiar la dirección MAC debe mostrar el aviso de conexión requerida y el dispensador debe conservar su dirección anterior (RF-14).
* **CL-10 (Operaciones offline conservadas):** Sin conexión, consultar el dispensador ya vinculado y consultar mascotas, horarios y logs debe seguir funcionando con la disponibilidad actual (RF-17).
* **CL-10.1 (Sin conexión en la desactivación):** Sin conexión con el servidor, el intento de desactivar un dispensador debe mostrar el aviso de conexión requerida (`AppNoticeDialog`, RF-09) y el dispensador debe conservar su estado anterior sin alterarse localmente (RF-13.1).
* **CL-10.2 (Sin conexión en la eliminación):** Sin conexión con el servidor, el intento de eliminar un dispensador debe mostrar el aviso de conexión requerida (`AppNoticeDialog`, RF-09) y el registro local del dispensador no debe ser eliminado ni marcado como pendiente (RF-13.2).
* **CL-11 (MAC liberada tras eliminar):** Si un usuario elimina su dispensador, esa dirección MAC debe quedar disponible nuevamente para ser registrada por cualquier usuario (RF-01).
* **CL-12 (Reintento tras un conflicto):** Si el usuario reintenta la misma operación después de un conflicto, el sistema debe volver a responder con el conflicto y no debe crear registros duplicados ni parciales (RF-07).
* **CL-13 (Legibilidad del aviso):** Con tamaño de fuente ampliado y en una pantalla estrecha, el aviso debe mostrarse completo, sin desbordes ni texto recortado, y su acción debe seguir siendo accesible (RNF-06).
* **CL-14 (Privacidad en el conflicto):** La respuesta de conflicto no debe revelar el nombre de la mascota, el usuario ni el identificador del dispensador en conflicto (RF-16).
* **CL-15 (Dispensadores pendientes de versiones anteriores):** Registros locales de dispensador que quedaron marcados como pendientes de sincronización en versiones anteriores de la aplicación (comportamiento eliminado por esta especificación). Al consultar los dispensadores del usuario, esos registros deben eliminarse localmente y debe quedar registrada en el diagnóstico la línea `dispensador huérfano eliminado - MAC:<dirección>` (RF-18), sin mostrarse ni enviarse (RF-19, DO-1 resuelta).
* **CL-16 (La limpieza no afecta a otros datos):** Al aplicar RF-18, las mascotas, horarios, registros de actividad, sesión y credenciales del usuario deben permanecer intactos y disponibles sin conexión (RF-20).
* **CL-17 (Registro huérfano con MAC no normalizada):** Si el registro huérfano eliminado tiene una dirección MAC en un formato cualquiera, el diagnóstico debe incluirla y el resto del sistema debe seguir funcionando con normalidad (RF-18, RF-08).
* **CL-18 (Varias consultas consecutivas):** Si el usuario consulta sus dispensadores varias veces, la limpieza no debe volver a eliminar nada ni generar diagnósticos duplicados una vez que no queden huérfanos (RF-18, RF-19).

## Aclaraciones

* **AC-1 (Código de respuesta de los conflictos de MAC):** Los dos conflictos de MAC —dirección ya registrada en el alta (RF-03) y dirección en uso en la modificación (RF-04)— se responden con el **código de conflicto HTTP 409**, cada uno con su propio identificador (`mac_already_registered` y `mac_in_use`).
* **AC-2 (Formato de MAC inválido):** Una dirección MAC con formato inválido (RF-06) se responde con el **código HTTP 400** y el identificador `mac_invalid_format`; nunca con 409, para que el usuario pueda distinguir "te equivocaste al escribirla" de "ya está en uso".
* **AC-3 (Resto de validaciones de la petición):** Los demás rechazos por datos de la petición (por ejemplo, que la mascota ya tenga un dispensador, `pet_already_has_dispenser`) se responden con el **código HTTP 400** y su propio identificador, manteniendo el mensaje actual sin datos de terceros.
* **AC-4 (Error estructurado):** A partir de esta especificación, el cuerpo de error de los endpoints de dispensador pasa de un texto suelto a un objeto con dos campos: `code` (identificador estable y unívoco del motivo) y `message` (texto en español). La aplicación clasifica el fallo por `code` y nunca por la comparación de textos (RF-16).
* **AC-5 (Eliminación del validador de formato previo):** El rechazo por formato de MAC inválido pasa a generarse de forma única y controlada por el sistema, de modo que la respuesta sea siempre la de AC-2 (`400` con `mac_invalid_format`) y no una respuesta genérica de validación que impida distinguirla de un conflicto.
* **AC-6 (Caso 2 sin validación manual en esta iteración):** No se entrega en esta iteración ninguna pantalla ni campo nuevo para editar la dirección MAC de un dispensador ya vinculado. El comportamiento de RF-04 y RF-14 queda cubierto por pruebas automatizadas en los niveles de dominio, datos y servidor; la interfaz de edición se pospone a una iteración posterior. En consecuencia, la verificación manual de esta iteración cubre los avisos de alta (caso 1), formato inválido y falta de conexión, y el aviso del caso 2 solo se valida de forma automatizada.

## Fuera de alcance

* Modificaciones al firmware, al protocolo de comunicación o al código del prototipo ESP32.
* Migración o re-normalización de los datos de dispensador ya almacenados en el servidor (decisión DO-2: el servidor conserva el texto original y añade una forma normalizada para comparar).
* Sustitución de los avisos de error de otros módulos (mascotas, horarios, logs, autenticación) por el nuevo componente reutilizable; este queda disponible para uso futuro.
* Rediseño de las pantallas de registro y edición de dispensador más allá de mostrar los avisos aquí especificados.
* Pantalla, campo o flujo de edición de la dirección MAC de un dispensador ya vinculado, y la activación o eliminación del dispensador desde ese campo (AC-6): quedan pospuestos a una iteración posterior.
* Cualquier modificación del motor de dosificación nutricional, del cálculo de raciones o del hardware del dispositivo.
* Reestructurar la sincronización offline de mascotas, horarios o logs.

## Criterios de finalización

* Existen pruebas automatizadas que demuestran que no es posible persistir dos registros con la misma forma normalizada de MAC, tanto en alta como en modificación, y que los casos CL-1 a CL-7 y CL-11 se comportan según lo especificado.
* Existen pruebas automatizadas que demuestran que el registro de un dispensador sin conexión no crea ningún registro local ni marca de pendiente de envío (CL-8, RF-13, RF-15).
* Existen pruebas automatizadas que demuestran que un dispensador local huérfano se elimina al consultar los dispensadores del usuario, que queda registrado en el diagnóstico con su dirección MAC, que no se envía al servidor, que no se muestra y que no afecta a los demás datos locales (CL-15, CL-16, CL-17, CL-18, RF-18, RF-19, RF-20).
* Existen pruebas automatizadas que demuestran que cada motivo de rechazo llega con su código de respuesta y su identificador correctos: 409 `mac_already_registered`, 409 `mac_in_use`, 400 `mac_invalid_format` y 400 `pet_already_has_dispenser` (AC-1, AC-2, AC-3, AC-4).
* Existen pruebas automatizadas del componente de aviso que demuestran que se muestra con el contenido correcto en los casos 1, 2, formato inválido y falta de conexión (incluyendo intentos offline de desactivación y eliminación), y que no se muestran avisos brutos genéricos en esos casos (RNF-05).
* Verificación en dispositivo o emulador real de los avisos con interfaz disponible (caso 1, formato inválido, falta de conexión en registro, desactivación y eliminación), con revisión de legibilidad en pantalla pequeña y con tamaño de fuente ampliado, sin desbordes (RNF-06, RNF-07). El aviso del caso 2 se valida únicamente con pruebas automatizadas (AC-6).
* Verificación de que la aplicación sigue operando sin conexión en el resto de funciones permitidas (CL-10, CL-10.1, CL-10.2) y de que ninguna prueba existente del proyecto se rompe.
* Verificación con dos usuarios distintos de que la misma dirección MAC no puede quedar vinculada a dos mascotas (HU-5, CL-6).
* Matriz de trazabilidad requisito → prueba → componente completada y revisada (RNF-09).

## Dudas resueltas

- [RESUELTO] **DO-1. Dispensadores pendientes de versiones anteriores.** Se **eliminan localmente** al consultar los dispensadores del usuario, con registro en el diagnóstico de la línea `dispensador huérfano eliminado - MAC:<dirección>` (RF-18). No se conservan como lectura, no se intentan sincronizar y no se muestran (RF-19). La limpieza se limita a los registros huérfanos de dispensador y nunca vacía el resto de los datos locales (RF-20).
- [RESUELTO] **DO-2. Formato canónico de almacenamiento de la MAC.** El servidor conserva el **texto original** recibido y añade una **forma normalizada autoritativa** usada solo para comparar, sin reescribir lo que el usuario ve. (Cambio de esquema aprobado por el usuario antes de su ejecución.)
- [RESUELTO] **DO-3. Alcance de la exigencia de conexión.** El **alta de un dispensador, el cambio de su dirección MAC, la desactivación y la eliminación** exigen conexión obligatoria. La consulta de dispensadores ya vinculados, mascotas, horarios y logs siguen operando sin conexión (RF-17).
- [RESUELTO] **DO-4. Privacidad del aviso de conflicto.** El mensaje es **siempre genérico**: nunca menciona mascota, usuario ni identificador del dispensador en conflicto, ni el cuerpo de la respuesta (RF-16, CL-14).
