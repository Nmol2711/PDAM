# Spec 015 — Gestión de usuario básica y menú de configuración

**Estado:** cerrada (T1–T10 implementadas; T10 corregida el 2026-10-30 tras el QA de la implementación y la auditoría general final)
**Fecha de revisión:** 2026-10-30 (revisión 5, tras la auditoría general final)

## Contexto y objetivo

Hoy la aplicación no tiene ninguna pantalla de cuenta. El usuario solo ve su correo como
saludo en el panel principal: no puede consultar sus datos, no puede modificarlos y no
puede darse de baja. El único control de apariencia, el modo claro y oscuro, vive en la
cabecera de ese panel, de modo que desde el resto de pantallas principales no se puede
cambiar el tema, y comparte sitio con el cierre de sesión.

Esta spec añade la gestión de usuario básica (consulta del perfil, actualización del
perfil y eliminación de la cuenta) y un menú de configuración global, accesible desde
cualquier pantalla principal, con cuatro opciones en un orden fijo. Además traslada el
modo claro y oscuro a ese menú, para que la apariencia deje de depender de la pantalla en
la que esté el usuario.

Objetivo:

1. Un único punto de entrada a la configuración de la cuenta, presente y consistente en
   todas las pantallas principales, sin duplicar controles y sin depender del factor de
   forma del dispositivo.
2. Consultar, actualizar y eliminar la cuenta desde ese menú, con mensajes en español y
   validaciones explícitas antes de aplicar cualquier cambio, sin datos inventados cuando
   no hay conexión.
3. Que la eliminación de la cuenta sea una operación segura: explícita, irreversible, con
   las consecuencias visibles antes de ejecutarla, confirmada con la contraseña actual,
   verificada por el servidor, idempotente, sin datos huérfanos y sin dejar sesiones
   utilizables.
4. Que el modo claro y oscuro viva en el menú de configuración, se aplique al instante y
   se conserve entre ejecuciones de la aplicación, incluso después de eliminar la cuenta.
5. Una interfaz minimalista, construida con los temas y colores globales, sin lógica de
   negocio en las vistas, legible y sin desbordamientos en móvil y en pantallas anchas.

## Usuarios

- **Dueño de mascota:** consulta los datos de su cuenta, corrige su correo o su contraseña
  y decide cuándo darse de baja.
- **Usuario que abandona el servicio:** elimina su cuenta y todos sus datos de forma
  definitiva y sin depender de soporte técnico.

Las restricciones propias del sistema —un único punto de configuración, ausencia de datos
huérfanos, ausencia de credenciales expuestas y exigencia de conexión en las mutaciones—
se recogen en los requisitos funcionales y no funcionales, no como una persona usuaria.

## Historias de usuario

- HU-1. Como dueño de mascota, quiero llegar a la configuración desde cualquier pantalla
  principal para no tener que volver al panel cada vez.
- HU-2. Como dueño de mascota, quiero ver los datos de mi cuenta en un solo lugar para
  saber con qué correo estoy registrado y en qué estado está la cuenta.
- HU-3. Como dueño de mascota, quiero cambiar mi correo y mi contraseña sin cerrar sesión
  para mantener mi cuenta al día.
- HU-4. Como dueño de mascota, quiero que la aplicación me avise si el correo nuevo ya está
  en uso, en lugar de aceptarlo y dejarme sin acceso después.
- HU-5. Como dueño de mascota, quiero que al cambiar mi contraseña la sesión actual siga
  abierta y el acceso sin conexión siga funcionando con la contraseña nueva.
- HU-6. Como dueño de mascota, quiero eliminar mi cuenta con una advertencia clara de lo que
  voy a perder y confirmando con mi contraseña, para no hacerlo por accidente ni por un
  tercero.
- HU-7. Como dueño de mascota, quiero que al eliminar mi cuenta se borren también los datos
  que la aplicación guarda en mi dispositivo, sin perder mi preferencia de apariencia.
- HU-8. Como dueño de mascota, quiero elegir el modo claro, oscuro o automático desde el
  menú de configuración y que se mantenga la próxima vez que abra la aplicación.
- HU-9. Como dueño de mascota, quiero consultar mi perfil sin conexión y ver mis datos
  reales guardados en el dispositivo, no unos datos inventados.
- HU-10. Como dueño de mascota, quiero que la aplicación me diga con claridad cuándo una
  operación necesita conexión y conserve lo que he escrito, para no perder mi trabajo ni
  creer que un cambio se aplicó cuando no fue así.

## Definiciones

- **Pantallas principales:** las pantallas de primer nivel de la navegación de la
  aplicación, es decir, inicio, mascotas, historial y dispositivos. Las pantallas de
  detalle, los formularios y los flujos de aprovisionamiento no son pantallas
  principales.
- **Menú de configuración:** pantalla única de configuración de la cuenta y de la
  apariencia, con el título visible «Configuración», exactamente cuatro filas y en el orden
  fijado en RF-02. Es global porque se abre desde la entrada única de RF-01 y su contenido
  no depende de la pantalla desde la que se abrió. No incluye el cierre de sesión ni las
  tres opciones de apariencia en línea: estas viven en el diálogo de modo de apariencia.
- **Entrada al menú:** control único de acceso al menú de configuración. En pantallas de
  menos de 600 puntos de ancho vive en la cabecera de cada pantalla principal; en pantallas
  de 600 puntos o más vive únicamente en la barra superior del contenedor de navegación que
  envuelve las cuatro pantallas principales. Nunca hay dos entradas visibles a la vez.
- **Diálogo de modo de apariencia:** diálogo que se abre desde la cuarta fila del menú y
  que contiene exactamente las tres opciones de apariencia. No es una subpantalla ni una
  pantalla independiente.
- **Perfil:** pantalla de solo consulta con los datos de la cuenta.
- **Actualización de perfil:** pantalla con el formulario que modifica los datos de la
  cuenta, limitado al correo electrónico y a la contraseña.
- **Eliminación de cuenta:** acción irreversible que borra físicamente la cuenta y todos
  sus datos asociados, previa confirmación con la contraseña actual verificada por el
  servidor.
- **Borrado físico total:** eliminación definitiva de la fila de la cuenta y de todas sus
  entidades dependientes en el servidor, sin conservación de copias, sin anonimización y
  sin periodo de gracia. El correo electrónico de la cuenta eliminada queda libre y puede
  registrarse de nuevo como una cuenta nueva, sin recuperar ningún dato anterior.
- **Borrado idempotente:** propiedad de la eliminación por la que repetir la petición de
  baja de una cuenta que ya no existe produce el mismo resultado observable que la primera
  vez, es decir, éxito, sin error y sin efectos adicionales, incluso cuando el token con el
  que se pide la baja pertenece a la cuenta ya eliminada. Es lo que permite reintentar sin
  riesgo cuando se pierde la respuesta del servidor.
- **Correo normalizado:** forma canónica del correo electrónico que resulta de eliminar los
  espacios al principio y al final y convertir todas las letras a minúsculas. Se aplica al
  registrar, al actualizar el correo y al comparar duplicados, y también al iniciar sesión,
  de modo que `User@X.com` y `user@x.com` son la misma cuenta. Los espacios interiores no
  se eliminan y un correo con espacios interiores no es válido.
- **Contraseña vigente:** contraseña que el servidor acepta en ese momento para la cuenta.
  Cambiarla invalida la anterior con conexión en todos los dispositivos y sin conexión
  únicamente en el dispositivo donde se cambió, porque es el único cuyas credenciales
  cifradas se actualizan. Un dispositivo sin conexión que conserve las credenciales
  antiguas seguirá permitiendo el acceso sin conexión hasta su siguiente petición al
  servidor, que las rechazará.
- **Token de sesión:** credencial que el servidor emite al iniciar sesión y que la
  aplicación envía en cada petición autenticada. Identifica la cuenta por una identidad
  estable de la cuenta y no por su correo, de modo que liberar y volver a registrar el mismo
  correo no rehabilita ningún token anterior. Cada dispositivo guarda el token de su propia
  sesión; al cambiar el correo, el servidor emite uno nuevo que sustituye únicamente al
  usado en esa petición y en ese dispositivo.
- **Sesión:** estado que mantiene al usuario dentro de la aplicación tras iniciar sesión y
  que termina al cerrar sesión o al eliminar la cuenta.
- **Sin sesiones abiertas (alcance de la baja):** tras eliminar la cuenta, el servidor
  rechaza con HTTP 401 cualquier token emitido para esa cuenta en la siguiente petición, y
  el dispositivo donde se realizó la baja cierra la sesión y borra sus datos locales. La
  única excepción es la propia operación de baja, que responde éxito aunque el token
  corresponda a la cuenta ya eliminada (RF-18), para que la baja sea idempotente; el resto
  de peticiones autenticadas con ese token reciben 401 `unauthorized`. No incluye el cierre
  remoto proactivo ni la notificación a otros dispositivos, que quedan fuera de alcance:
  esos dispositivos pierden el acceso en su siguiente petición al servidor.
- **Perfil cacheado:** último perfil real descargado del servidor y guardado en el
  dispositivo, compuesto por el correo normalizado de la cuenta y su estado. Es la única
  fuente admitida para mostrar el perfil sin conexión; no se admite ningún dato de relleno,
  marcador de posición ni correo ficticio.
- **Estado de la cuenta:** valor informativo derivado del indicador booleano de cuenta
  activa del servidor (`is_active`), con dos etiquetas visibles: «Activa» cuando el
  indicador es verdadero e «Inactiva» cuando es falso. No es un estado de sesión y esta spec
  no lo usa para permitir ni impedir el inicio de sesión.
- **Datos asociados a la cuenta:** mascotas del usuario, dispensadores vinculados a esas
  mascotas, horarios de comida, comidas en espera, órdenes de dispensación,
  reabastecimientos registrados y registros de actividad del usuario.
- **Datos locales de la cuenta:** credenciales cifradas para el acceso sin conexión, token
  de sesión, perfil cacheado y datos guardados en el dispositivo de mascotas,
  dispensadores, horarios e historial.
- **Preferencia de apariencia del dispositivo:** modo claro, oscuro o automático elegido en
  este dispositivo. Es una preferencia del dispositivo y no de la cuenta: no se borra al
  eliminar la cuenta ni cambia al iniciar sesión con otra cuenta.
- **Fila huérfana:** cualquier fila de mascotas, horarios de comida, comidas en espera,
  órdenes de dispensación, reabastecimientos o registros de actividad que conserve una
  referencia a la cuenta eliminada, ya sea mediante una clave foránea, mediante una columna
  de propietario sin clave foránea o mediante una clave foránea anulable que siga apuntando
  a ella. Tras la baja, el número de filas huérfanas de la cuenta eliminada debe ser cero en
  todas esas tablas.
- **Confirmación destructiva:** confirmación adicional exigida antes de eliminar la cuenta,
  compuesta por un diálogo con el aviso de irreversibilidad, el listado de datos que se
  pierden y el reingreso de la contraseña actual de la cuenta. No basta con pulsar la opción
  del menú ni con un botón de confirmación sin contraseña. Es el único punto de esta spec en
  el que se pide la contraseña actual.
- **Marca de baja pendiente:** registro persistido en el almacenamiento del dispositivo que
  se escribe antes de intentar la limpieza local de la baja y que solo se borra cuando esa
  limpieza termina. Su presencia indica que la cuenta ya se eliminó en el servidor pero
  quedan datos locales por borrar, y es lo que impide el acceso sin conexión con esas
  credenciales aunque la aplicación se reinicie.

### Catálogo de estados de la cuenta

| Indicador `is_active` del servidor | Etiqueta visible |
| --- | --- |
| verdadero | Activa |
| falso | Inactiva |

El indicador es booleano: no existen otros valores de servidor ni etiquetas intermedias. El
estado se muestra solo de forma informativa en Perfil (RF-06). Esta spec no cambia el
inicio de sesión ni bloquea el acceso de las cuentas inactivas: una cuenta inactiva sigue
pudiendo iniciar sesión como hoy, y su menú de configuración muestra las cuatro filas sin
ocultar ninguna.

### Catálogo de modos de apariencia

| Código | Etiqueta visible | Comportamiento |
| --- | --- | --- |
| `light` | Claro | La aplicación se muestra siempre en claro. |
| `dark` | Oscuro | La aplicación se muestra siempre en oscuro. |
| `system` | Automático | La aplicación sigue la apariencia del sistema operativo y se actualiza cuando esta cambia. |

`system` es el valor por defecto de un dispositivo que nunca ha elegido modo.

### Catálogo de mensajes visibles

Los textos marcados como reutilizados se reproducen literalmente como existen hoy en la
aplicación. Los textos nuevos son los únicos admitidos para estas pantallas: no se
introducirán variantes, sinónimos ni traducciones alternativas.

| Texto exacto | Dónde aparece | Origen |
| --- | --- | --- |
| Configuración | Título visible del menú de configuración | nuevo |
| Abrir configuración | Etiqueta accesible y descripción emergente de la entrada al menú | nuevo |
| Perfil | Primera fila del menú | nuevo |
| Actualización de perfil | Segunda fila del menú | nuevo |
| Eliminación de cuenta | Tercera fila del menú | nuevo |
| Modo claro y oscuro | Cuarta fila del menú | nuevo |
| Modo de apariencia | Título del diálogo de modo | nuevo |
| Claro / Oscuro / Automático | Opciones del diálogo de modo | nuevo |
| Correo electrónico | Etiqueta del campo y del dato en Perfil | nuevo |
| Estado de la cuenta | Etiqueta del estado en Perfil | nuevo |
| Activa / Inactiva | Valor del estado en Perfil | nuevo |
| Estás viendo datos guardados en este dispositivo. | Aviso del perfil sin conexión | nuevo |
| No hay datos de tu cuenta guardados en este dispositivo. Conéctate para consultarlos. | Perfil sin conexión y sin datos locales | nuevo |
| Reintentar | Acción de reintento | nuevo |
| Contraseña nueva | Campo del formulario de actualización | nuevo |
| Confirmar contraseña nueva | Campo del formulario de actualización | nuevo |
| Guardar / Cancelar | Acciones del formulario de actualización | nuevo |
| Tus datos se actualizaron correctamente. | Confirmación de la actualización | nuevo |
| No has modificado ningún dato. Escribe un correo nuevo o una contraseña nueva. | Envío sin cambios (RF-11) | nuevo |
| Confirma la contraseña nueva. | Falta la confirmación (RF-11) | nuevo |
| Escribe la contraseña nueva. | Falta la contraseña nueva (RF-11) | nuevo |
| La contraseña debe tener al menos 8 caracteres. | Contraseña por debajo del mínimo (RF-11) | nuevo, sustituye al texto de 4 caracteres vigente |
| La contraseña es demasiado larga. | Contraseña por encima del máximo (RF-11) | nuevo |
| Introduce un correo electrónico válido. | Correo con formato inválido (RF-11) | nuevo |
| El correo es obligatorio | Correo vacío en el cliente (RF-11) | reutilizado |
| Las contraseñas no coinciden | Contraseña y confirmación distintas (RF-11) | reutilizado |
| Confirma tu contraseña | Confirmación vacía en el registro | reutilizado |
| La contraseña es obligatoria | Contraseña vacía en el registro | reutilizado |
| El correo electrónico ya está registrado. | Correo en uso (RF-12) | reutilizado |
| Correo o contraseña incorrectos | Inicio de sesión rechazado (`invalid_credentials`) | reutilizado |
| Cerrar sesión | Acción de cierre de sesión del panel | reutilizado |
| Se requiere conexión con el servidor para completar esta operación. | Mutación sin conexión (RF-13, RF-20) | nuevo |
| Esta acción es irreversible y no se puede deshacer. | Aviso de la pantalla y del diálogo de baja | nuevo |
| Se eliminarán tu cuenta, tus mascotas, tus dispensadores, tus horarios, las comidas en espera, tus órdenes, tus reabastecimientos y todo tu historial. | Listado de datos en riesgo | nuevo |
| Eliminar mi cuenta | Acción que abre el diálogo de confirmación | nuevo |
| Escribe tu contraseña actual para confirmar la eliminación. | Indicación del diálogo de baja | nuevo |
| Contraseña actual | Campo de contraseña del diálogo de baja | nuevo |
| Eliminar cuenta | Acción de confirmación del diálogo de baja | nuevo |
| La contraseña no es correcta. | Contraseña actual incorrecta (RF-17) | nuevo |
| Tu cuenta y todos sus datos se eliminaron de forma definitiva. | Confirmación tras la baja (RF-18) | nuevo |
| No se pudo completar la operación. Inténtalo de nuevo. | Error del servidor (RF-21) | nuevo |
| La sesión no es válida. Vuelve a iniciar sesión. | Token rechazado en una petición autenticada (RF-05, RF-19) | nuevo |
| Tu cuenta se eliminó, pero no se pudieron borrar todos los datos de este dispositivo. Se cerró la sesión para proteger tu información. | Fallo de la limpieza local (RNF-10) | nuevo |

Nota técnica del límite de contraseña: el almacenamiento de contraseñas del proyecto admite
como máximo 72 bytes en UTF-8 por contraseña, y los bytes que exceden ese límite se
ignoran en silencio al verificar. Para que dos contraseñas distintas que compartan los
primeros 72 bytes no se acepten indistintamente, el límite es parte de la regla de
validación: se rechaza toda contraseña cuya representación en UTF-8 supere 72 bytes, con el
mensaje «La contraseña es demasiado larga.». El mínimo de 8 caracteres se cuenta sobre
caracteres, no sobre bytes.

### Catálogo de errores de la API

Hereda el contrato de la spec 014: los rechazos de negocio se devuelven con el cuerpo
`detail={code,message}`, con el mensaje visible en español. Ningún rechazo de negocio
responde 422. El 5xx queda reservado a los fallos de escritura y al conflicto de
concurrencia de la actualización de perfil, para que el cliente pueda reintentar sin
ambigüedad. Los errores de validación del correo y de la contraseña se comprueban de forma
explícita para que no caigan en la validación automática del framework.

| Código | HTTP | Mensaje visible | Cuándo se usa |
| --- | --- | --- | --- |
| `invalid_email` | 400 | Introduce un correo electrónico válido. | Correo con formato inválido en la actualización (RF-11), cuando el cliente no lo detectó. Nunca para el correo vacío enviado desde la aplicación, que se rechaza en el cliente sin petición; una petición directa con el correo vacío se rechaza con este código como salvaguarda del contrato (ver nota). |
| `weak_password` | 400 | La contraseña debe tener al menos 8 caracteres. | Contraseña nueva con menos de 8 caracteres, en el registro y en la actualización (RF-11), cuando el cliente no lo detectó. |
| `password_too_long` | 400 | La contraseña es demasiado larga. | Contraseña nueva de más de 72 bytes UTF-8, en el registro y en la actualización (RF-11), cuando el cliente no lo detectó. |
| `empty_update` | 400 | No has modificado ningún dato. Escribe un correo nuevo o una contraseña nueva. | Envío sin correo nuevo y con los dos campos de contraseña vacíos (RF-11), cuando el cliente no lo detectó. |
| `email_already_registered` | 400 | El correo electrónico ya está registrado. | Correo nuevo que ya pertenece a otra cuenta, comparado en forma normalizada (RF-12). Validación exclusiva del servidor. |
| `invalid_password` | 400 | La contraseña no es correcta. | Contraseña actual incorrecta en la confirmación de la baja (RF-17). |
| `invalid_credentials` | 401 | Correo o contraseña incorrectos | Inicio de sesión con un correo o una contraseña que no corresponden a ninguna cuenta. Se usa solo en el inicio de sesión. |
| `unauthorized` | 401 | La sesión no es válida. Vuelve a iniciar sesión. | Petición autenticada sin token, con token inválido o caducado, o con un token emitido para una cuenta eliminada (RF-05, RF-19). Es exclusivo de peticiones autenticadas con token y nunca se usa en el inicio de sesión. Única excepción: la baja de RF-18, que responde éxito. |
| `conflict` | 500 | No se pudo completar la operación. Inténtalo de nuevo. | Solo la actualización de perfil que compite con otra actualización simultánea y cuya transacción no se aplicó; el cliente puede reintentar (RF-21). Nunca se usa en la baja. |
| `server_error` | 500 | No se pudo completar la operación. Inténtalo de nuevo. | Cualquier otro fallo del servidor al escribir (RF-21). |

El correo vacío se rechaza en el cliente con «El correo es obligatorio» y la aplicación
no envía la petición. El correo con formato inválido se valida en el cliente y en el
servidor, y solo el servidor responde `invalid_email` cuando el cliente no lo detectó.

Nota de salvaguarda del contrato: el correo vacío se rechaza en el cliente sin petición;
si una petición directa llega al servidor con el correo vacío —por ejemplo, desde una
herramienta externa que no pasa por la aplicación—, el servidor la rechaza con
`invalid_email` para no aceptar un correo vacío en la cuenta. La aplicación nunca usa esa
respuesta porque ya validó el campo antes de enviar, y no existe un código ni un mensaje
de servidor específico para el correo vacío.

El registro mantiene además su rechazo vigente de correo duplicado con HTTP 400 y el
mensaje «El correo electrónico ya está registrado.», ahora con el código
`email_already_registered` y comparación normalizada, y pasa a exigir 8 caracteres y el
límite de 72 bytes según este catálogo.

## Requisitos funcionales

### A. Acceso global y menú (RF-01 a RF-05)

- **RF-01:** MIENTRAS el usuario tenga una sesión iniciada y se encuentre en cualquiera de
  las pantallas principales, EL SISTEMA mostrará exactamente una entrada al menú de
  configuración —el menú con el título «Configuración»—, con el mismo icono y la misma
  etiqueta accesible fija «Abrir configuración» en todas ellas: SI el ancho de la pantalla
  es menor que 600 puntos, ENTONCES la entrada estará en la cabecera de la pantalla
  principal visible; SI el ancho es de 600 puntos o más, ENTONCES la entrada estará
  únicamente en la barra superior del contenedor de navegación que envuelve las cuatro
  pantallas principales. En ningún caso habrá dos entradas visibles a la vez, no se añadirá
  ninguna opción nueva a la barra de navegación inferior ni al menú lateral, y la etiqueta
  accesible será la misma con independencia del factor de forma y de la pantalla.
- **RF-02:** CUANDO el usuario abra el menú de configuración, EL SISTEMA mostrará el título
  «Configuración» y exactamente cuatro filas visibles y en este orden: 1) Perfil,
  2) Actualización de perfil, 3) Eliminación de cuenta, 4) Modo claro y oscuro. No
  intercalará ninguna otra opción entre ellas, no las reordenará, no ocultará ninguna por el
  estado de la cuenta —una cuenta inactiva muestra las cuatro filas— y no incluirá el cierre
  de sesión, que permanece en la cabecera del panel principal. Las tres opciones de
  apariencia no aparecerán como filas del menú: la cuarta fila es una sola y abre el diálogo
  definido en RF-24. El contenido del menú será idéntico con independencia de la pantalla
  principal desde la que se abra.
- **RF-03:** CUANDO el usuario seleccione una de las cuatro filas del menú, EL SISTEMA
  abrirá la pantalla o el diálogo correspondiente a esa fila; CUANDO el usuario vuelva al
  menú, EL SISTEMA lo mostrará de nuevo con el título «Configuración», las mismas cuatro
  filas en el mismo orden y la cuarta fila indicando el modo de apariencia activo en ese
  momento, de modo que un cambio de modo hecho en el diálogo se refleje al volver.
- **RF-04:** EL SISTEMA retirará el control de modo claro y oscuro de la cabecera del panel
  principal y no lo ofrecerá en ninguna otra pantalla fuera del menú de configuración y su
  diálogo de modo; el saludo y el cierre de sesión de esa cabecera se conservan sin cambios,
  y la cabecera conserva además la entrada al menú de configuración que exige RF-01 cuando
  el ancho es menor que 600 puntos.
- **RF-05:** SI el usuario no tiene una sesión iniciada, ENTONCES EL SISTEMA no mostrará la
  entrada al menú de configuración ni permitirá abrirlo, y si se fuerza la navegación a
  cualquiera de sus pantallas o al diálogo de modo, la redirigirá al inicio de sesión sin
  mostrar su contenido; SI la sesión termina mientras el menú, una de sus pantallas o el
  diálogo de modo está abierto, ENTONCES EL SISTEMA los cerrará y llevará al usuario a la
  pantalla de inicio de sesión; SI el servidor rechaza el token con HTTP 401 y el código
  `unauthorized` en cualquier petición autenticada distinta de la baja de RF-18, ENTONCES EL
  SISTEMA cerrará la sesión, mostrará el mensaje «La sesión no es válida. Vuelve a iniciar
  sesión.» y llevará al usuario al inicio de sesión.

### B. Perfil (RF-06 a RF-08)

- **RF-06:** CUANDO el usuario abra Perfil, EL SISTEMA mostrará el correo electrónico
  normalizado de la cuenta, su estado con la etiqueta «Activa» o «Inactiva» del catálogo de
  estados según el indicador booleano de cuenta activa del servidor, y un avatar con la
  inicial del correo; no mostrará la contraseña, el token ni ninguna credencial, no ofrecerá
  ningún control de edición en esa pantalla y no mostrará nombre visible ni foto de perfil,
  porque la cuenta no los tiene. El estado es informativo: no habilita ni impide ninguna
  acción de esta spec y no altera el inicio de sesión.
- **RF-07:** SI no hay conexión o el servidor no responde al abrir Perfil, ENTONCES EL
  SISTEMA mostrará el perfil cacheado real de la cuenta —su correo normalizado y su
  estado— con el aviso «Estás viendo datos guardados en este dispositivo.», sin bloquear la
  pantalla ni mostrar un error invasivo; SI la consulta al servidor responde correctamente,
  ENTONCES guardará el perfil recibido como perfil cacheado antes de mostrarlo. SI el token
  era válido y la cuenta dejó de existir, de modo que el servidor responde HTTP 401 con el
  código `unauthorized`, ENTONCES EL SISTEMA tratará la respuesta como una sesión inválida y
  cerrará la sesión según RF-05, sin mostrar el perfil cacheado como si la cuenta siguiera
  existiendo. EL SISTEMA no mostrará en ningún caso un correo, un estado ni ningún otro dato
  que no provenga del servidor o del perfil cacheado de la cuenta, y en particular no usará
  ningún correo de relleno ni de marcador de posición.
- **RF-08:** SI no hay perfil cacheado de la cuenta y tampoco hay conexión, ENTONCES EL
  SISTEMA mostrará el mensaje «No hay datos de tu cuenta guardados en este dispositivo.
  Conéctate para consultarlos.» con la acción «Reintentar», en lugar de una pantalla vacía
  o de datos inventados.

### C. Actualización de perfil (RF-09 a RF-15)

- **RF-09:** CUANDO el usuario abra Actualización de perfil, EL SISTEMA mostrará un
  formulario con el correo actual precargado —tomado del perfil recibido del servidor o, si
  no hay conexión, del perfil cacheado real, nunca de un dato de relleno— y los campos
  «Contraseña nueva» y «Confirmar contraseña nueva» vacíos, junto con las acciones
  «Guardar» y «Cancelar»; no ofrecerá ningún otro campo editable, como nombre visible o foto
  de perfil, y no pedirá la contraseña actual, porque basta la sesión activa para cambiar el
  correo o la contraseña.
- **RF-10:** CUANDO el usuario envíe el formulario con datos válidos y conexión disponible,
  EL SISTEMA aplicará los cambios en la cuenta, confirmará la operación con «Tus datos se
  actualizaron correctamente.», reflejará los nuevos datos en Perfil y en el saludo del panel
  principal, mantendrá la sesión activa sin pedir un nuevo inicio de sesión y volverá al menú
  de configuración con la confirmación visible y los datos refrescados. SI la operación
  incluye un correo nuevo, ENTONCES el servidor emitirá un token de sesión nuevo para esa
  sesión, EL SISTEMA lo guardará en ese dispositivo, el token que se usó en esa petición
  dejará de ser aceptado y el perfil cacheado pasará a tener el correo nuevo; los demás
  dispositivos no se ven afectados y conservan su token hasta que caduque, de modo que esto
  no es un cierre remoto de sesiones. SI el correo no cambia, ENTONCES el token vigente se
  conserva.
- **RF-11:** CUANDO el usuario envíe el formulario, EL SISTEMA aplicará primero las
  validaciones de cliente de la tabla siguiente, en ese orden de precedencia, sin enviar
  ninguna petición al servidor cuando alguna falle, sin aplicar ningún cambio y mostrando a
  la vez todos los mensajes de campo que correspondan, cada uno junto a su campo y con el
  texto exacto del catálogo de mensajes, conservando lo escrito en el resto de campos y sin
  cerrar la pantalla. Las validaciones de cliente son la obligatoriedad del correo, su
  formato, la confirmación de la contraseña nueva, la coincidencia entre contraseña y
  confirmación, la longitud mínima y el límite de bytes. Las validaciones exclusivas del
  servidor son el correo duplicado y la identidad del token; su resultado llega después del
  envío y se muestra junto al campo correspondiente, sin que la aplicación repita esa
  comprobación. El servidor valida las mismas reglas que el cliente y, si el cliente no las
  detectó, responde con el código del catálogo de errores correspondiente a la primera que
  falle según ese mismo orden de precedencia. Ningún rechazo de negocio responderá 422.

  | Correo normalizado | Contraseña nueva | Confirmación | Validación | Resultado |
  | --- | --- | --- | --- | --- |
  | vacío | cualquiera | cualquiera | cliente | «El correo es obligatorio»; no se envía petición y no se aplica nada. |
  | con formato inválido | cualquiera | cualquiera | cliente y servidor | `invalid_email`, «Introduce un correo electrónico válido.»; no se aplica nada. |
  | igual al actual | vacía | vacía | cliente y servidor | `empty_update`, «No has modificado ningún dato. Escribe un correo nuevo o una contraseña nueva.»; no se aplica nada. |
  | igual al actual | rellena | vacía | cliente | «Confirma la contraseña nueva.»; no se aplica nada. |
  | igual al actual | vacía | rellena | cliente | «Escribe la contraseña nueva.»; no se aplica nada. |
  | igual al actual | rellena | rellena y no coincide | cliente | «Las contraseñas no coinciden»; no se aplica nada. |
  | igual al actual | rellena | rellena, coincide y tiene menos de 8 caracteres | cliente y servidor | `weak_password`, «La contraseña debe tener al menos 8 caracteres.»; no se aplica nada. |
  | igual al actual | rellena | rellena, coincide y supera 72 bytes UTF-8 | cliente y servidor | `password_too_long`, «La contraseña es demasiado larga.»; no se aplica nada. |
  | igual al actual | rellena | rellena, coincide y es válida | — | Se cambia solo la contraseña (RF-14). |
  | distinto y válido | vacía | vacía | — | Se cambia solo el correo (RF-10). |
  | distinto y válido | rellena | vacía | cliente | «Confirma la contraseña nueva.»; no se aplica nada, tampoco el correo. |
  | distinto y válido | vacía | rellena | cliente | «Escribe la contraseña nueva.»; no se aplica nada, tampoco el correo. |
  | distinto y válido | rellena | rellena, coincide y es válida | — | Se cambian correo y contraseña en la misma operación (RF-10, RF-14). |
  | distinto, válido y ya registrado | cualquiera | cualquiera | servidor | `email_already_registered` según RF-12; no se aplica nada. |

  Un correo que solo difiere del actual en mayúsculas o en espacios exteriores cuenta como
  igual al actual, porque ambos se comparan en forma normalizada.
- **RF-12:** SI el correo nuevo, comparado en forma normalizada, ya pertenece a otra cuenta,
  ENTONCES EL SISTEMA no aplicará ningún cambio, ni del correo ni de la contraseña, y
  mostrará el mensaje «El correo electrónico ya está registrado.» junto al campo de correo;
  el servidor responderá HTTP 400 con el código `email_already_registered`. Es una
  comprobación exclusiva del servidor: la aplicación no la repite antes de enviar.
- **RF-13:** SI no hay conexión o el servidor no responde al guardar, ENTONCES EL SISTEMA no
  aplicará cambios en el dispositivo ni dejará la actualización pendiente de sincronizar,
  conservará lo escrito en el formulario y avisará con «Se requiere conexión con el servidor
  para completar esta operación.».
- **RF-14:** CUANDO se actualice la contraseña, EL SISTEMA mantendrá la sesión activa,
  actualizará las credenciales locales cifradas usadas por el acceso sin conexión en ese
  dispositivo, y la contraseña anterior dejará de permitir el inicio de sesión con conexión
  en todos los dispositivos y sin conexión únicamente en el dispositivo donde se cambió,
  porque es el único cuyas credenciales cifradas se actualizan; un dispositivo sin conexión
  que conserve las credenciales antiguas seguirá permitiendo el acceso sin conexión hasta su
  siguiente petición al servidor, que las rechazará. La contraseña no se guardará en texto
  plano fuera del almacenamiento cifrado ni se mostrará en ningún mensaje o registro. SI la
  actualización incluye correo y contraseña a la vez, ENTONCES el acceso sin conexión pasará
  a usar el correo normalizado nuevo y la contraseña nueva, y se aplicará el token nuevo de
  RF-10.
- **RF-15:** CUANDO el usuario cancele la actualización, ENTONCES EL SISTEMA no aplicará
  ningún cambio y volverá al menú de configuración.

### D. Eliminación de cuenta (RF-16 a RF-21)

- **RF-16:** CUANDO el usuario abra Eliminación de cuenta, EL SISTEMA mostrará la advertencia
  «Esta acción es irreversible y no se puede deshacer.», enumerará los datos que se perderán
  con el texto «Se eliminarán tu cuenta, tus mascotas, tus dispensadores, tus horarios, las
  comidas en espera, tus órdenes, tus reabastecimientos y todo tu historial.» y exigirá una
  confirmación destructiva: un diálogo con el aviso de irreversibilidad, la indicación
  «Escribe tu contraseña actual para confirmar la eliminación.», el campo «Contraseña
  actual» y la acción «Eliminar cuenta», sin la cual no se podrá confirmar la eliminación. La
  acción de confirmación permanecerá deshabilitada mientras el campo esté vacío.
- **RF-17:** SI el usuario cancela, no completa la confirmación o la contraseña actual
  introducida no es correcta, ENTONCES EL SISTEMA no eliminará nada, conservará la cuenta,
  sus datos y la sesión y permitirá reintentar sin cerrar el diálogo. La contraseña actual la
  verifica el servidor: SI no es correcta, ENTONCES responderá HTTP 400 con el código
  `invalid_password` y el mensaje «La contraseña no es correcta.», que la aplicación mostrará
  junto al campo.
- **RF-18:** CUANDO el usuario confirme la eliminación con la contraseña actual correcta y
  conexión disponible, EL SISTEMA borrará físicamente la cuenta y todos sus datos asociados
  en el servidor —mascotas, dispensadores vinculados a esas mascotas, horarios, comidas en
  espera, órdenes de dispensación, reabastecimientos y registros de actividad— en una sola
  transacción, sin conservar copias, sin anonimizar y sin dejar filas huérfanas ni datos
  accesibles desde ninguna otra cuenta; los dispensadores vinculados a las mascotas del
  usuario se borran en esa misma transacción y no se conservan desvinculados, de modo que su
  MAC deja de estar registrada y un reporte posterior de esas MAC se rechazará como
  `mac_no_registrada` según la spec 014; liberará el correo electrónico para un registro
  futuro; cerrará la sesión en el dispositivo; borrará del dispositivo los datos locales de
  la cuenta, con la marca de baja pendiente de RNF-10; conservará la preferencia de
  apariencia del dispositivo; y llevará al usuario a la pantalla de inicio de sesión con el
  mensaje «Tu cuenta y todos sus datos se eliminaron de forma definitiva.». La baja no se
  bloqueará por tener dispensadores vinculados ni por tener una orden pendiente, y no
  responderá con el conflicto `pet_has_dispenser` que protege el borrado de mascotas: la baja
  borra mascotas y dispensadores en la misma transacción. La petición de baja se autentica
  con el token de la sesión: SI la cuenta ya no existe cuando llega la petición, ENTONCES el
  servidor responderá éxito con HTTP 200 aunque el token corresponda a la cuenta ya
  eliminada; esta es la única excepción al rechazo 401 de RF-19 y existe precisamente para
  que la baja sea idempotente y tolere respuestas perdidas; la aplicación limpiará los datos
  locales, cerrará la sesión y mostrará «Tu cuenta y todos sus datos se eliminaron de forma
  definitiva.», nunca «La sesión no es válida. Vuelve a iniciar sesión.».
- **RF-19:** EL SISTEMA no permitirá volver a iniciar sesión con las credenciales de una
  cuenta eliminada, ni con conexión ni sin ella, no ofrecerá ninguna acción de reactivación
  en esta spec, y permitirá registrar de nuevo el mismo correo como una cuenta nueva y vacía,
  sin recuperar ningún dato de la cuenta anterior. El servidor rechazará con HTTP 401 y el
  código `unauthorized` cualquier token emitido para la cuenta eliminada en toda petición
  autenticada, salvo la baja de RF-18, que responde éxito por idempotencia, aunque el mismo
  correo se registre de nuevo, y la cuenta nueva no heredará ninguna sesión anterior. En un
  401 de una petición autenticada, EL SISTEMA borrará el token, las credenciales cifradas y
  el perfil cacheado, de modo que se rechace el acceso sin conexión con esa cuenta, y
  conservará los datos de la aplicación —mascotas, horarios e historial— para
  resincronizarlos tras volver a iniciar sesión. Sin conexión, el acceso con credenciales
  cacheadas de una cuenta eliminada en este dispositivo se rechaza porque la baja borra esas
  credenciales (RF-18, RNF-10); si la cuenta se eliminó desde otro dispositivo y este no
  tiene conexión, el acceso sin conexión sigue funcionando con los datos cacheados hasta la
  siguiente petición al servidor, que rechazará el token con 401 y hará que la aplicación
  cierre la sesión y aplique la limpieza de sesión anterior.
- **RF-20:** SI no hay conexión o el servidor no responde al confirmar la eliminación,
  ENTONCES EL SISTEMA no eliminará nada, mantendrá la sesión y los datos intactos, y avisará
  con «Se requiere conexión con el servidor para completar esta operación.».
- **RF-21:** SI la eliminación falla en el servidor, ENTONCES la cuenta y sus datos
  permanecerán intactos, la sesión se mantendrá y EL SISTEMA mostrará «No se pudo completar
  la operación. Inténtalo de nuevo.» con una acción de reintento; SI la respuesta del
  servidor se pierde después de que la baja se aplicó, ENTONCES el reintento responderá
  éxito según la idempotencia de RF-18, sin error y sin efectos adicionales; SI dos bajas de
  la misma cuenta llegan a la vez, ENTONCES ambas responderán éxito, porque la segunda
  encuentra la cuenta ya inexistente y aplica la idempotencia de RF-18, sin ningún conflicto;
  SI el servidor responde HTTP 500 con el código `server_error`, ENTONCES la aplicación
  ofrecerá el mismo reintento. El código `conflict` no se usa en la baja: queda reservado a
  la actualización de perfil.

### E. Modo claro y oscuro (RF-22 a RF-25)

- **RF-22:** CUANDO el usuario elija Claro, Oscuro o Automático en el diálogo de modo de
  apariencia, EL SISTEMA aplicará el cambio de inmediato en toda la aplicación, incluido el
  propio diálogo y el menú, sin reiniciar ni cerrar sesión; SI elige Automático, ENTONCES
  seguirá la apariencia del sistema operativo y se actualizará cuando esta cambie; SI cierra
  el diálogo sin elegir, ENTONCES el modo no cambiará.
- **RF-23:** CUANDO el usuario cierre y vuelva a abrir la aplicación, EL SISTEMA conservará
  el último modo elegido en ese dispositivo, incluido el modo automático, con independencia
  de la cuenta con la que inicie sesión; la preferencia de apariencia no se borra al eliminar
  la cuenta ni al cerrar sesión, porque pertenece al dispositivo y no a la cuenta.
- **RF-24:** CUANDO el usuario seleccione la cuarta fila del menú, EL SISTEMA abrirá el
  diálogo «Modo de apariencia» con exactamente tres opciones —Claro, Oscuro y Automático—,
  marcará la que esté activa en ese momento y aplicará el cambio al elegirla según RF-22, de
  modo que el usuario no tenga que deducir el modo activo del aspecto de la pantalla; la
  cuarta fila del menú mostrará además el modo activo como texto secundario, sin desplegar
  las tres opciones en el propio menú.
- **RF-25:** EL SISTEMA aplicará el modo elegido a todas las pantallas del menú y de la
  gestión de usuario usando los temas y colores globales de la aplicación, sin colores,
  tipografías ni estilos literales en las vistas nuevas, y mantendrá la legibilidad en los
  modos claro y oscuro: el texto normal tendrá un contraste mínimo de 4.5:1 contra su fondo,
  y el texto grande —de 18 puntos o más, o de 14 puntos o más en negrita— y los componentes
  gráficos tendrán un contraste mínimo de 3:1. El contraste se medirá sobre los colores del
  tema global efectivamente aplicados en cada modo.

## Requisitos no funcionales

- **RNF-01:** Todos los textos visibles estarán en español, sin emojis, y los mensajes de
  error indicarán qué corregir y cómo continuar, nombrando el campo afectado cuando el error
  sea de un campo.
- **RNF-02:** La interfaz del menú y de las pantallas de gestión de usuario será minimalista:
  jerarquía clara, espaciado y tipografía de los temas globales, sin adornos innecesarios. Se
  verificará sin desbordamientos, sin recortes de texto y sin desplazamiento horizontal en
  anchos de 320, 600 y 840 puntos, en orientación vertical y horizontal, y con el escalado de
  texto del sistema hasta 1.3; con escalado 1.3 las cuatro filas del menú, las tres opciones
  del diálogo de modo, las etiquetas del perfil y las acciones del formulario seguirán siendo
  legibles y accionables.
- **RNF-03:** Las vistas solo presentarán estado y emitirán eventos; la lógica de validación,
  de actualización y de eliminación vivirá en las capas de dominio y de estado del proyecto,
  y la navegación se resolverá con el enrutador, sin lógica en las pantallas principales.
- **RNF-04:** La solución respetará la arquitectura limpia: dominio puro sin dependencia del
  framework, del almacenamiento ni de la red, y casos de uso con una única responsabilidad.
- **RNF-05:** Cada RF y cada RNF tendrá al menos una prueba automatizada que falle si el
  requisito se incumple; las operaciones de consulta, actualización y eliminación de la cuenta
  tendrán además pruebas de API, y las pantallas tendrán pruebas de interfaz en Flutter. Las
  pruebas visuales no sustituyen a las automatizadas.
- **RNF-06:** No se guardarán credenciales, tokens ni datos sensibles en el código; las
  contraseñas solo se almacenarán cifradas y nunca se mostrarán en texto plano, en mensajes ni
  en registros, salvo en el campo de entrada con visibilidad controlada por el usuario. La
  contraseña reingresada para confirmar la eliminación se usa solo para esa verificación y no
  se persiste.
- **RNF-07:** No se añadirán dependencias externas nuevas; las validaciones, la normalización
  del correo y los mensajes se resolverán con funciones del propio proyecto.
- **RNF-08:** No habrá regresión: las pruebas de la spec 014 y del resto de specs siguen
  pasando, y el historial, el stock, el dispensado y el arranque de la aplicación no cambian
  de comportamiento.
- **RNF-09:** Las operaciones de actualización y eliminación serán atómicas: o se aplican por
  completo o no se aplican, sin estados intermedios visibles para el usuario. El borrado
  físico de la cuenta y de todos sus datos asociados, incluidos los dispensadores vinculados,
  las tablas que guardan el propietario sin clave foránea y las claves foráneas anulables, se
  resolverá en una sola transacción, de modo que no pueda quedar una cuenta sin sus datos ni
  datos sin su cuenta.
- **RNF-10:** La limpieza local de la baja será atómica respecto de su efecto: se borrarán el
  token de sesión, las credenciales cifradas, el perfil cacheado y los datos locales de la
  cuenta —mascotas, dispensadores, horarios e historial— y se conservará la preferencia de
  apariencia del dispositivo. Antes de intentar la limpieza, EL SISTEMA escribirá en el
  almacenamiento del dispositivo una marca de baja pendiente, que solo se borrará cuando la
  limpieza termine; SI la limpieza local falla, ENTONCES la marca sobrevivirá al reinicio, EL
  SISTEMA informará con «Tu cuenta se eliminó, pero no se pudieron borrar todos los datos de
  este dispositivo. Se cerró la sesión para proteger tu información.», forzará el cierre de
  sesión en memoria y, al arrancar de nuevo, no permitirá el acceso sin conexión con las
  credenciales de esa cuenta y reintentará la limpieza hasta completarla. En ningún caso
  quedará operativo el acceso sin conexión con credenciales de una cuenta eliminada.

## Casos límite

- **Menú abierto desde una pantalla principal distinta del panel:** muestra el título
  «Configuración», las mismas cuatro filas, en el mismo orden, con el mismo aspecto y con el
  modo activo en la cuarta fila.
- **Cuenta inactiva:** el menú muestra igualmente las cuatro filas, sin ocultar ninguna, y el
  inicio de sesión no cambia de comportamiento.
- **Pantalla de 320 puntos:** la entrada al menú está en la cabecera de la pantalla principal
  visible y no hay ninguna otra entrada visible.
- **Pantalla de 600 puntos o más:** la única entrada al menú está en la barra superior del
  contenedor de navegación y las cabeceras de las pantallas principales no muestran una
  segunda entrada; el menú y sus pantallas se abren desde esa única entrada.
- **Menú abierto:** muestra el título «Configuración», no muestra el cierre de sesión, que
  sigue disponible en la cabecera del panel principal, y no despliega las tres opciones de
  apariencia como filas.
- **Usuario sin sesión que intenta abrir el menú o el diálogo de modo:** no se muestra la
  entrada y, si se fuerza la navegación, se redirige al inicio de sesión sin mostrar el
  contenido.
- **Sesión que termina con el menú abierto:** el menú, sus pantallas y el diálogo de modo se
  cierran y se vuelve al inicio de sesión.
- **Token rechazado con 401 `unauthorized` en una petición distinta de la baja:** la sesión se
  cierra, se eliminan el token, las credenciales cifradas y el perfil cacheado de la sesión,
  se conservan mascotas, horarios e historial, se muestra «La sesión no es válida. Vuelve a
  iniciar sesión.» y se vuelve al inicio de sesión.
- **Perfil con un token de una cuenta eliminada:** el servidor responde 401 `unauthorized`, la
  aplicación trata la respuesta como sesión inválida, cierra la sesión y va al inicio de
  sesión; no muestra el perfil cacheado como si la cuenta existiera.
- **Perfil sin conexión con perfil cacheado:** se muestran el correo normalizado y el estado
  cacheados con el aviso de datos guardados en el dispositivo.
- **Perfil sin conexión y sin perfil cacheado:** mensaje «No hay datos de tu cuenta guardados
  en este dispositivo. Conéctate para consultarlos.» con acción de reintento, sin pantalla
  vacía y sin ningún correo de relleno.
- **Perfil con el servidor respondiendo:** se muestra el perfil del servidor y se actualiza el
  perfil cacheado.
- **Formulario con el correo precargado sin conexión:** se precarga el correo del perfil
  cacheado real; si no hay perfil cacheado, el campo aparece vacío y no se rellena con ningún
  dato inventado.
- **Envío sin cambios:** correo igual al actual y los dos campos de contraseña vacíos; no se
  aplica nada y se muestra «No has modificado ningún dato. Escribe un correo nuevo o una
  contraseña nueva.».
- **Correo solo con mayúsculas o espacios distintos:** se normaliza, cuenta como igual al
  actual y, si además no hay contraseña, produce el aviso de envío sin cambios.
- **Correo vacío:** el cliente muestra «El correo es obligatorio» junto al campo, no envía
  ninguna petición y no se aplica nada.
- **Correo con formato inválido:** el cliente muestra «Introduce un correo electrónico
  válido.»; si el cliente no lo detectara, el servidor responde 400 `invalid_email` con el
  mismo texto; no se aplica nada.
- **Varios errores de cliente a la vez:** se muestran todos los mensajes de campo
  correspondientes al mismo tiempo, cada uno junto a su campo, sin enviar la petición y
  conservando lo escrito.
- **Actualización solo de contraseña:** el correo se conserva, la contraseña anterior deja de
  servir con conexión en todos los dispositivos y sin conexión en el dispositivo donde se
  cambió, y la sesión actual sigue abierta; un dispositivo sin conexión con las credenciales
  antiguas seguirá entrando hasta su siguiente petición al servidor.
- **Actualización solo de correo:** la contraseña se conserva, se recibe un token nuevo que la
  aplicación guarda en ese dispositivo, el token usado en esa petición deja de ser aceptado,
  los demás dispositivos conservan el suyo hasta que caduque y el acceso sin conexión pasa a
  usar el correo normalizado nuevo.
- **Actualización de correo y contraseña a la vez:** ambos cambios se aplican en la misma
  operación, con token nuevo y credenciales locales cifradas actualizadas.
- **Actualización correcta:** se vuelve al menú de configuración con «Tus datos se
  actualizaron correctamente.» visible y los datos refrescados en el menú, en Perfil y en el
  saludo del panel principal.
- **Correo nuevo ya registrado:** no se aplica nada, ni el correo ni la contraseña, y se
  muestra «El correo electrónico ya está registrado.» junto al campo de correo, con el código
  `email_already_registered`.
- **Solo uno de los dos campos de contraseña relleno:** el aviso aparece junto al campo que
  falta —«Confirma la contraseña nueva.» o «Escribe la contraseña nueva.»— y no se aplica
  nada, tampoco el correo.
- **Contraseña nueva y confirmación distintas:** no se aplica nada y el aviso aparece junto al
  campo de confirmación.
- **Contraseña nueva por debajo de 8 caracteres:** no se aplica nada y el aviso aparece junto
  al campo de contraseña, tanto en el registro como en la actualización.
- **Contraseña nueva de más de 72 bytes UTF-8:** no se aplica nada y se muestra «La contraseña
  es demasiado larga.».
- **Actualización sin conexión:** no se aplica nada, no queda pendiente y se avisa que se
  requiere conexión, conservando lo escrito.
- **Actualización que compite con otra:** el servidor responde 500 `conflict` y el cliente
  puede reintentar; no se aplica nada a medias.
- **Eliminación cancelada en el diálogo de confirmación:** la cuenta y sus datos quedan
  intactos y se vuelve al menú.
- **Contraseña incorrecta en el diálogo de eliminación:** el servidor responde 400
  `invalid_password`, no se elimina nada, la cuenta y sus datos permanecen intactos, la sesión
  se mantiene y se muestra «La contraseña no es correcta.» junto al campo, con la posibilidad
  de reintentar.
- **Diálogo de eliminación con la contraseña vacía:** la acción de confirmar permanece
  deshabilitada y no se ejecuta ninguna petición.
- **Eliminación confirmada sin conexión:** no se elimina nada, la sesión se mantiene y se
  avisa que se requiere conexión.
- **Eliminación que falla en el servidor:** cuenta y datos intactos, sesión mantenida, mensaje
  de error con reintento; el código `conflict` no se usa en la baja.
- **Respuesta de la baja perdida tras aplicarse:** el reintento responde éxito, sin error, sin
  segundo borrado y sin efectos adicionales; la aplicación limpia, cierra sesión y muestra la
  confirmación de la baja.
- **Baja de una cuenta que ya no existe:** el servidor responde éxito con HTTP 200 aunque el
  token corresponda a la cuenta ya eliminada; la aplicación limpia los datos locales, cierra
  la sesión y muestra «Tu cuenta y todos sus datos se eliminaron de forma definitiva.», nunca
  «La sesión no es válida. Vuelve a iniciar sesión.».
- **Dos bajas simultáneas de la misma cuenta:** ambas responden éxito, porque la segunda
  encuentra la cuenta ya inexistente y aplica la idempotencia; ninguna responde 500 y no hay
  efectos adicionales.
- **Eliminación correcta:** se borran físicamente la cuenta y todos sus datos asociados en una
  sola transacción, no queda ninguna fila huérfana en mascotas, horarios, comidas en espera,
  órdenes, reabastecimientos ni registros —incluidas las tablas que guardan el propietario sin
  clave foránea y las claves foráneas anulables—, el historial deja de existir y de ser
  consultable, se libera el correo, se borran los datos locales de la cuenta, se conserva la
  preferencia de apariencia, se cierra la sesión y se llega al inicio de sesión con la
  confirmación.
- **Baja con dispensadores vinculados y con una orden pendiente:** la baja no se bloquea, no
  responde `pet_has_dispenser` y borra mascotas y dispensadores en la misma transacción; los
  dispensadores vinculados se borran y no se conservan desvinculados.
- **Reporte de un dispensador borrado por la baja:** su MAC deja de estar registrada, el
  servidor rechaza el reporte con `mac_no_registrada` según la spec 014 y el firmware lo
  descarta, sin registro nuevo.
- **Fallo de la limpieza local tras una baja correcta:** se escribe antes la marca de baja
  pendiente, se informa con el mensaje correspondiente y se fuerza el cierre de sesión en
  memoria; la marca sobrevive al reinicio, la aplicación no permite el acceso sin conexión con
  las credenciales de esa cuenta y reintenta la limpieza hasta completarla.
- **Reinicio con una marca de baja pendiente:** la aplicación no permite el acceso sin conexión
  con las credenciales de la cuenta eliminada, reintenta la limpieza y solo borra la marca
  cuando la limpieza termina.
- **Correo de una cuenta eliminada que se registra de nuevo:** se crea una cuenta nueva y
  vacía, sin mascotas, dispensadores, horarios ni historial, sin ningún dato de la anterior y
  sin heredar sesiones: un token emitido para la cuenta eliminada sigue siendo rechazado con
  401 en toda petición autenticada salvo la baja, aunque el correo vuelva a existir.
- **Intento de inicio de sesión con una cuenta eliminada:** se rechaza con conexión; sin
  conexión se rechaza en el dispositivo donde se hizo la baja porque las credenciales
  cacheadas se borraron, y en otro dispositivo sin conexión se rechaza en su siguiente
  petición al servidor, que con su 401 borra el token, las credenciales cifradas y el perfil
  cacheado de ese dispositivo y conserva mascotas, horarios e historial para resincronizarlos
  tras volver a iniciar sesión.
- **Inicio de sesión con credenciales incorrectas:** el servidor responde 401 con el código
  `invalid_credentials` y el mensaje «Correo o contraseña incorrectos», nunca con
  `unauthorized`.
- **Cambio de modo con el diálogo abierto:** el diálogo y el menú cambian de apariencia al
  instante y la opción activa queda marcada.
- **Cierre del diálogo de modo sin elegir:** el modo no cambia y la cuarta fila sigue
  mostrando el modo anterior.
- **Modo automático con el sistema en modo oscuro:** la aplicación se muestra oscura y cambia
  si el sistema cambia de apariencia, sin que el usuario vuelva a elegir.
- **Cambio de modo seguido de cierre de la aplicación:** al reabrir se mantiene el último
  modo, incluido el automático.
- **Modo elegido y cuenta eliminada:** tras la baja, la aplicación conserva el modo elegido en
  el dispositivo y lo aplica en la pantalla de inicio de sesión.
- **Pantalla estrecha de 320 puntos y pantalla ancha de 600 y 840 puntos, con escalado de texto
  1.3:** el menú, el diálogo de modo y las pantallas de cuenta se adaptan sin desbordamientos,
  sin recortes y sin desplazamiento horizontal, en vertical y en horizontal.
- **Contraste en ambos modos:** el texto normal alcanza al menos 4.5:1 y el texto grande y los
  componentes gráficos al menos 3:1 con los colores del tema global.

## Relación con otras specs

- **Spec 014 (registros y validación del dispensado):** se distinguen dos planos. En el plano
  de las reglas, la 014 sigue siendo la única fuente de verdad del catálogo de eventos, de la
  generación de registros, del cierre de órdenes, del descuento de stock, de la consulta del
  historial y de sus códigos de error; esta spec no cambia ninguna de esas reglas. En el plano
  de la existencia de los datos, esta spec decide que al eliminar una cuenta sus datos —entre
  ellos sus registros y sus dispensadores vinculados— dejan de existir; eso no contradice a la
  014, que no define la baja de usuario ni la conservación de datos de una cuenta inexistente.
  La baja de cuenta de esta spec no es el purgado de registros que la 014 deja fuera de
  alcance: el purgado es una retención programada sobre cuentas existentes, mientras que la
  baja es una eliminación solicitada por el usuario que borra la cuenta y todo lo suyo. Si en
  el futuro se quiere auditar la baja como un evento del historial, se hará en una spec
  posterior que amplíe el catálogo de la 014. Esta spec hereda de la 014 el contrato de errores
  `detail={code,message}`, la regla de que ningún rechazo de negocio responde 422 y el rechazo
  `mac_no_registrada` de su RF-21 para los reportes de dispensadores borrados por la baja, que
  el firmware descarta según su RF-39.
- **Specs 001 y 002 (arquitectura y persistencia sin conexión):** la consulta del perfil
  mantiene el comportamiento sin conexión, pero solo con el perfil cacheado real; las
  mutaciones de la cuenta exigen conexión, igual que el registro, para no dejar el servidor y
  el dispositivo desincronizados.
- **Autenticación existente:** se reutilizan el inicio y el cierre de sesión y el
  almacenamiento cifrado de credenciales. Cambian cuatro cosas y solo cuatro: el correo se
  compara en forma normalizada al iniciar sesión, el mínimo de contraseña pasa a 8 caracteres
  con el límite de 72 bytes, el token identifica la cuenta por una identidad estable y no por
  el correo —para que un token de una cuenta eliminada no vuelva a valer si el correo se
  registra de nuevo—, y el rechazo del inicio de sesión pasa a usar el código
  `invalid_credentials` con HTTP 401 y el mensaje «Correo o contraseña incorrectos», quedando
  `unauthorized` reservado a las peticiones autenticadas con token. El resto del contrato de
  inicio de sesión no cambia.
- **Cierre de sesión y «sin sesiones abiertas»:** el cierre remoto de sesiones sigue fuera de
  alcance. «Sin sesiones abiertas» significa que el servidor rechaza el token de la cuenta
  eliminada en la siguiente petición y que el dispositivo donde se hace la baja cierra la
  sesión y borra sus datos locales; no significa que la aplicación vaya a cerrar sesiones de
  otros dispositivos de forma proactiva, que no se promete ni se implementa. La única
  excepción al rechazo 401 de esos tokens es la propia operación de baja, que responde éxito
  para ser idempotente. Del mismo modo, el token nuevo que se emite al cambiar el correo
  sustituye solo al de la petición y el dispositivo que la hizo: no es un cierre de sesiones
  remotas.
- **Prevalencia:** la 014 prevalece en el historial, las órdenes, el stock y sus catálogos; la
  015 prevalece en la configuración de la cuenta, la apariencia y la existencia de los datos de
  una cuenta eliminada.

## Decisiones cerradas

- **Borrado de cuenta:** físico y total, sin copias ni anonimización; el correo queda libre.
  No hay periodo de gracia ni anonimización.
- **Confirmación de la eliminación:** diálogo destructivo con la contraseña actual, verificada
  por el servidor, que responde 400 `invalid_password` cuando no es correcta.
- **Contraseña actual fuera de la actualización:** no se pide para cambiar el correo ni la
  contraseña; basta la sesión activa. Solo se pide para eliminar la cuenta.
- **Historial:** se elimina junto con la cuenta; no hay exportación ni conservación.
- **Modo de apariencia:** el menú tiene cuatro filas y la cuarta, «Modo claro y oscuro», abre
  un diálogo con tres opciones: Claro, Oscuro y Automático. No es una subpantalla.
- **Título del menú:** «Configuración», visible en el menú y usado en RF-01, RF-02 y RF-03.
- **Campos editables:** solo correo y contraseña; sin nombre visible ni foto de perfil.
- **Entrada al menú:** una sola entrada, nunca duplicada. En menos de 600 puntos, en la
  cabecera de cada pantalla principal; en 600 puntos o más, únicamente en la barra superior del
  contenedor de navegación. Sin quinta pestaña ni opción nueva en el menú lateral.
- **Etiqueta accesible de la entrada:** «Abrir configuración», fija en todas las pantallas y
  factores de forma.
- **Cierre de sesión:** permanece en la cabecera del panel principal y no forma parte del
  menú.
- **Etiqueta de la tercera opción:** «Eliminación de cuenta».
- **Perfil sin conexión:** se muestra el perfil cacheado real (correo y estado). Se elimina
  cualquier dato de relleno o ficticio, incluido el correo de marcador de posición que usaba la
  aplicación.
- **Formulario de actualización:** si un campo de contraseña queda vacío no se cambia la
  contraseña; si los dos están vacíos y el correo no cambia, no se realiza la operación y se
  avisa; si solo se rellena uno, el error aparece junto al campo que falta.
- **Validaciones de cliente y de servidor:** las de cliente —obligatoriedad, formato,
  confirmación, coincidencia, longitud mínima y límite de bytes— se muestran todas a la vez
  junto a su campo y bloquean el envío; las exclusivas del servidor —correo duplicado e
  identidad del token— llegan después y se muestran junto al campo correspondiente. El
  servidor valida las mismas reglas y responde con el código correspondiente solo si el
  cliente no las detectó.
- **Correo vacío y formato inválido:** el correo vacío se rechaza en el cliente con «El correo
  es obligatorio», sin petición al servidor y sin código de API; el formato inválido se valida
  en cliente y en servidor con «Introduce un correo electrónico válido.» y el código
  `invalid_email`.
- **Correo normalizado:** recorte de espacios exteriores y minúsculas al registrar, al
  actualizar y al comparar duplicados e iniciar sesión; `User@X.com` y `user@x.com` son la
  misma cuenta.
- **Contraseña:** mínimo de 8 caracteres y máximo de 72 bytes UTF-8, aplicado en la app y en el
  servidor, incluido el registro; sustituye la regla vigente de 4 caracteres de la vista de
  registro.
- **Alcance de la contraseña al cambiarla:** la anterior deja de servir con conexión en todos
  los dispositivos y sin conexión solo en el dispositivo donde se cambió, porque es el único
  cuyas credenciales cifradas se actualizan; otro dispositivo sin conexión sigue entrando hasta
  su siguiente petición al servidor.
- **Textos:** los mensajes nuevos son los del catálogo de mensajes y no admiten variantes; los
  de autenticación se reutilizan literalmente.
- **Token al cambiar el correo:** el servidor devuelve un token nuevo, la aplicación lo guarda
  en ese dispositivo y la sesión continúa sin re-login; el token usado en esa petición deja de
  ser aceptado y los demás dispositivos conservan el suyo hasta que caduque. No es un cierre
  remoto de sesiones.
- **Identidad del token:** la cuenta se identifica por una identidad estable e irrepetible que
  no se reutiliza al registrar de nuevo el mismo correo; el correo no es la identidad del
  token. Una cuenta nueva no hereda sesiones de la anterior.
- **Baja con dispensadores u orden pendiente:** no se bloquea, no responde
  `pet_has_dispenser` y borra mascotas y dispensadores en la misma transacción. Los
  dispensadores vinculados a las mascotas se borran y no se conservan desvinculados; su MAC
  deja de estar registrada y sus reportes posteriores se rechazan como `mac_no_registrada`
  según la 014.
- **Idempotencia de la baja:** la baja se autentica con el token de la sesión y, si la cuenta
  ya no existe, el servidor responde éxito con HTTP 200 aunque el token corresponda a la cuenta
  ya eliminada. Es la única excepción al rechazo 401 de tokens de cuentas eliminadas y existe
  para tolerar respuestas perdidas. La aplicación limpia, cierra sesión y muestra la
  confirmación, nunca el mensaje de sesión inválida. Dos bajas simultáneas responden ambas
  éxito.
- **Códigos de sesión y de acceso:** `unauthorized` es exclusivo de peticiones autenticadas con
  token inválido, caducado o de cuenta eliminada; el inicio de sesión rechazado usa
  `invalid_credentials` con HTTP 401. No se usa `account_not_found`: si el token era válido y
  la cuenta desapareció, la aplicación trata el 401 como sesión inválida y cierra sesión.
- **Código de conflicto:** `conflict` queda reservado a la actualización de perfil que compite
  con otra; la baja nunca lo devuelve.
- **Preferencia de apariencia:** es del dispositivo y se conserva tras eliminar la cuenta; no
  se borra la clave de modo del almacenamiento local.
- **Limpieza local:** se borran token, credenciales cifradas, perfil cacheado y datos locales
  de la cuenta; se conserva la preferencia de apariencia; antes de limpiar se escribe una
  marca de baja pendiente que solo se borra al terminar, de modo que un fallo sobrevive al
  reinicio, bloquea el acceso sin conexión con esas credenciales y reintenta la limpieza.
- **Estado de la cuenta:** se muestra como «Activa» o «Inactiva» según el indicador booleano
  `is_active` del servidor; esta spec no cambia el inicio de sesión ni bloquea cuentas
  inactivas.
- **Destino tras guardar:** la actualización correcta vuelve al menú de configuración con la
  confirmación visible y los datos refrescados.
- **Huérfanos:** se define fila huérfana de forma verificable y la baja debe dejar cero filas
  huérfanas, incluidas las tablas con propietario sin clave foránea y las claves foráneas
  anulables, todo en una transacción.

## Dudas abiertas

Ninguna: todas las decisiones están cerradas en la sección Decisiones cerradas.

## Compatibilidad

No hay contrato público que romper: la API incorpora la consulta, la actualización y la
eliminación de la cuenta propia, y el control de tema se traslada de la cabecera del panel al
menú de configuración en la misma entrega. No hay periodo de compatibilidad porque la
aplicación móvil se actualiza junto con la API.

Cambios de contrato que un cliente anterior podría notar: el registro pasa a exigir 8
caracteres y a rechazar contraseñas de más de 72 bytes; el registro, el inicio de sesión y la
comparación de duplicados normalizan el correo; el inicio de sesión rechazado responde 401 con
el código `invalid_credentials`, mientras `unauthorized` queda reservado a las peticiones
autenticadas con token; la eliminación de la cuenta responde éxito con HTTP 200 cuando la
cuenta ya no existe, incluso con el token de esa cuenta eliminada, y es la única excepción a
ese 401; no se introduce el código `account_not_found`; y los rechazos de negocio de estas
operaciones usan el catálogo de errores con `detail={code,message}` y nunca 422. El código
`conflict` deja de aplicarse a la baja y queda solo para la actualización de perfil. El inicio
de sesión compara el correo recibido y el almacenado en forma normalizada, de modo que una
cuenta existente cuyo correo se guardó sin normalizar sigue pudiendo entrar, y los correos se
normalizan al aplicarse la actualización de datos correspondiente.

## Fuera de alcance

- Nombre visible y foto de perfil: la cuenta no incorpora esos campos y no se añaden.
- Recuperación de contraseña por correo, verificación del correo nuevo y doble factor.
- Historial de sesiones, dispositivos conectados, revocación proactiva o cierre remoto de
  sesiones en otros dispositivos.
- Preferencia de idioma, notificaciones, exportación de datos o baja programada con periodo de
  gracia.
- Conservación anonimizada, archivado o auditoría de los datos de una cuenta eliminada, y
  purgado o retención programada de registros, que pertenece a la 014 y no es una baja.
- Reactivación de cuentas eliminadas o gestión de otros usuarios.
- Bloqueo del inicio de sesión de cuentas inactivas.
- Cambios en mascotas, dispensadores, horarios, historial o firmware, salvo el borrado de los
  dispensadores vinculados que produce la baja.
- Cambios en el motor nutricional o en el cálculo de ración.

## Criterios de finalización

- `flutter test`, `flutter analyze` y `pytest` pasan sin errores nuevos.
- No hay regresión en las pruebas de las specs 001 a 014.
- La entrada al menú de configuración es única y funciona desde las cuatro pantallas
  principales: en menos de 600 puntos en la cabecera de cada una y en 600 puntos o más solo en
  la barra superior del contenedor de navegación.
- El menú muestra el título «Configuración» y exactamente cuatro filas en el orden fijado, sin
  cierre de sesión y sin ocultar ninguna por el estado de la cuenta; la cuarta abre el diálogo
  de modo con Claro, Oscuro y Automático, y el control de tema ya no aparece en la cabecera del
  panel principal.
- Las tres operaciones de cuenta (consulta, actualización y eliminación) tienen pruebas de
  interfaz y de API; la eliminación exige la contraseña actual verificada por el servidor, es
  idempotente, borra los dispensadores vinculados y deja el dispositivo y el servidor sin datos
  de la cuenta, conservando la preferencia de apariencia.
- Cada RF y cada RNF tiene al menos una prueba asociada según los mapeos siguientes.
- `MEMORY.md` actualizado al cerrar la fase.

### Mapeo RF a prueba

- **RF-01:** prueba de interfaz de que existe exactamente una entrada al menú —cuyo título es
  «Configuración»—, con la etiqueta accesible «Abrir configuración», en las cuatro pantallas
  principales con ancho menor que 600 y únicamente en la barra superior del contenedor con
  ancho de 600 o más, y de que no se añade ninguna opción a la navegación inferior ni al menú
  lateral.
- **RF-02:** prueba de interfaz del título «Configuración», del orden exacto y del número de
  filas del menú (cuatro), de la ausencia del cierre de sesión en él, de que las tres opciones
  de apariencia no aparecen como filas, y de que con una cuenta inactiva se siguen mostrando
  las cuatro filas sin ocultar ninguna.
- **RF-03:** prueba de navegación de cada una de las cuatro filas, del regreso al menú con el
  título «Configuración», las cuatro filas en el mismo orden y de que la cuarta fila refleja el
  modo activo actualizado tras un cambio en el diálogo.
- **RF-04:** prueba de interfaz de que la cabecera del panel ya no contiene el control de tema
  y de que el saludo, el cierre de sesión y la entrada al menú siguen presentes.
- **RF-05:** prueba de que sin sesión no hay entrada al menú y de que la navegación forzada al
  menú, a sus pantallas y al diálogo de modo redirige al inicio de sesión sin mostrar contenido;
  prueba de que el cierre de sesión con el menú abierto lo cierra; prueba de que un 401
  `unauthorized` en una petición distinta de la baja cierra la sesión con el mensaje del
  catálogo, y de que el éxito de la baja no muestra ese mensaje.
- **RF-06:** prueba de interfaz de los datos mostrados en Perfil, del estado «Activa» e
  «Inactiva» derivado del indicador booleano del servidor, de la ausencia de credenciales, de
  controles de edición, de nombre visible y de foto de perfil, y de que el estado no altera el
  inicio de sesión.
- **RF-07:** prueba de que sin conexión se muestra el perfil cacheado real con su aviso y de que
  el correo mostrado coincide exactamente con el último perfil descargado, sin ningún correo de
  relleno; prueba de que una consulta correcta actualiza el perfil cacheado; prueba de que un
  401 por cuenta eliminada se trata como sesión inválida y cierra la sesión sin mostrar el
  perfil cacheado.
- **RF-08:** prueba del mensaje sin perfil cacheado y de la acción de reintento, sin pantalla
  vacía ni datos inventados.
- **RF-09:** prueba de interfaz del formulario con el correo precargado desde el perfil del
  servidor y desde el perfil cacheado, los dos campos de contraseña vacíos, la ausencia de
  petición de contraseña actual y ningún otro campo editable.
- **RF-10:** prueba de actualización correcta con confirmación, regreso al menú con los datos
  refrescados, refresco del perfil y del saludo, sesión mantenida, token nuevo guardado en ese
  dispositivo tras cambiar el correo y rechazo del token usado en esa petición; prueba de que
  otro dispositivo conserva su token hasta que caduque.
- **RF-11:** una prueba por fila de la matriz de validación, con el mensaje exacto junto al
  campo, sin aplicar cambios y conservando el resto del formulario; prueba de que los errores
  de cliente se muestran todos a la vez y de que no se envía petición cuando alguno falla;
  prueba de que el correo vacío no llega a la API; prueba de que el servidor responde el código
  correspondiente a la primera regla que falle y nunca 422.
- **RF-12:** prueba de correo duplicado comparado en forma normalizada, con el mensaje exacto,
  el código `email_already_registered` y sin cambios en correo ni contraseña, comprobando que
  la validación es del servidor.
- **RF-13:** prueba de que sin conexión no se aplica nada, no queda pendiente y se muestra el
  aviso de conexión conservando lo escrito.
- **RF-14:** prueba de que tras cambiar la contraseña la sesión sigue activa y las credenciales
  locales cifradas se actualizan en ese dispositivo; prueba de que la contraseña anterior deja
  de iniciar sesión con conexión y sin conexión en ese dispositivo, y de que otro dispositivo
  sin conexión sigue entrando hasta su siguiente petición; prueba de la actualización conjunta
  de correo y contraseña.
- **RF-15:** prueba de que cancelar no aplica cambios y vuelve al menú.
- **RF-16:** prueba de la advertencia, del listado de datos en riesgo, de que no se puede
  confirmar sin reingresar la contraseña actual y de que la acción está deshabilitada con el
  campo vacío.
- **RF-17:** pruebas de que cancelar, no completar la confirmación y una contraseña incorrecta no
  eliminan nada, conservan la cuenta y la sesión, y de que la contraseña incorrecta produce 400
  `invalid_password` con «La contraseña no es correcta.» junto al campo.
- **RF-18:** prueba de API del borrado físico total en una sola transacción, del recuento cero
  de filas huérfanas en todas las tablas afectadas —incluidas las de propietario sin clave
  foránea y las claves foráneas anulables—, del borrado de los dispensadores vinculados y del
  rechazo posterior de su MAC con `mac_no_registrada`, de la liberación del correo, de la
  ausencia de `pet_has_dispenser` y de la idempotencia: una cuenta ya inexistente responde 200
  incluso con el token de la cuenta eliminada; prueba de interfaz de la limpieza local, la
  conservación de la preferencia de apariencia, el cierre de sesión y el mensaje de
  confirmación, sin el mensaje de sesión inválida.
- **RF-19:** prueba de que el inicio de sesión de una cuenta eliminada se rechaza con conexión y
  sin conexión en el dispositivo donde se hizo la baja; prueba de que el mismo correo puede
  registrarse de nuevo como cuenta vacía y de que un token emitido para la cuenta eliminada
  sigue recibiendo 401 `unauthorized` en toda petición autenticada salvo la baja, después del
  nuevo registro; prueba de que un 401 borra token, credenciales cifradas y perfil cacheado,
  rechaza el inicio de sesión sin conexión con las credenciales antiguas y conserva mascotas,
  horarios, historial y la preferencia de apariencia.
- **RF-20:** prueba de eliminación sin conexión que no altera nada y muestra el aviso de
  conexión.
- **RF-21:** prueba de fallo del servidor con cuenta, datos y sesión intactos y reintento
  disponible; prueba de respuesta perdida tras aplicar la baja en la que el reintento responde
  éxito sin segundo borrado; prueba de dos bajas simultáneas que responden ambas éxito y de que
  la baja nunca devuelve `conflict`.
- **RF-22:** prueba de que el cambio de modo se aplica de inmediato en toda la aplicación, de
  que el modo automático sigue al sistema y de que cerrar el diálogo sin elegir no cambia nada.
- **RF-23:** prueba de persistencia del modo, incluido el automático, tras reiniciar la
  aplicación, con independencia de la cuenta, y de que se conserva tras eliminar la cuenta.
- **RF-24:** prueba de que la cuarta fila abre el diálogo —no una subpantalla— con exactamente
  tres opciones, marca la activa y que el menú muestra el modo activo como texto secundario sin
  desplegar las opciones.
- **RF-25:** prueba de que las pantallas nuevas usan los temas globales sin estilos literales y
  prueba de contraste calculado sobre los colores del tema en ambos modos: 4.5:1 para texto
  normal y 3:1 para texto grande y componentes gráficos.

### Mapeo RNF a prueba

- **RNF-01:** prueba que recorre los textos visibles de las pantallas nuevas y comprueba que
  están en español, sin emojis, y que cada mensaje de error nombra el campo y la acción.
- **RNF-02:** pruebas de widget a 320, 600 y 840 puntos de ancho, en vertical y horizontal y con
  escalado de texto 1.3, que fallan si aparece un desbordamiento, un recorte de texto o un
  desplazamiento horizontal, y que comprueban que las cuatro filas, las tres opciones del
  diálogo, las etiquetas del perfil y las acciones del formulario siguen siendo accionables.
- **RNF-03:** prueba de que las vistas nuevas solo reciben estado y emiten eventos, sin
  validación ni llamadas a repositorios, y de que la navegación se resuelve con el enrutador.
- **RNF-04:** prueba de que el dominio nuevo no importa framework, red ni almacenamiento y de que
  cada caso de uso tiene una única responsabilidad.
- **RNF-05:** prueba de que cada RF y cada RNF del mapeo tiene al menos una prueba asociada y de
  que las tres operaciones de cuenta tienen pruebas de API y de interfaz.
- **RNF-06:** prueba de que ningún texto, registro ni respuesta contiene la contraseña ni el
  token, y de que la contraseña reingresada para la baja no se persiste.
- **RNF-07:** prueba de que las dependencias declaradas del proyecto no cambian.
- **RNF-08:** ejecución completa de las suites de las specs 001 a 014 sin fallos nuevos.
- **RNF-09:** pruebas con fallo inyectado en la transacción de la baja que verifican que no queda
  ni cuenta sin datos ni datos sin cuenta —incluidos los dispensadores vinculados—, y que la
  actualización no deja estados intermedios.
- **RNF-10:** prueba de que tras la baja se borran token, credenciales cifradas, perfil cacheado
  y datos locales de la cuenta, de que la preferencia de apariencia se conserva, y de que la
  marca de baja pendiente se escribe antes de limpiar y solo se borra al terminar; prueba de
  que un fallo de la limpieza local informa con el mensaje del catálogo, fuerza el cierre de
  sesión en memoria y, tras reiniciar la aplicación, mantiene la marca, impide el acceso sin
  conexión con esas credenciales y reintenta la limpieza.
