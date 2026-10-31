# Spec 017 — Paleta de colores, tema y apariencia global

**Estado:** aprobada, implementada y finalizada (2026-10-31)
**Cierre:** spec validada RF por RF y auditoría global APTA; 897 pruebas en verde y `flutter analyze` sin errores; el usuario la aprobó como finalizada tras probar la aplicación.

## Contexto y objetivo

El morado dominante no viene solo de la paleta anterior: el tema no fija el esquema y
el sistema aplica sus valores por defecto (`#6750A4`, `#EADDFF`, `#E8DEF8`) en botones,
navegación, cursores y avisos. Además hay literales en el panel, radios y espaciados
dispersos, contraseñas sin ojo y filtros permanentes en el historial.

Esta spec cambia solo la apariencia: paleta, tokens, forma, espaciado, ojo y filtros
plegables. No cambia funcionalidad, datos, navegación ni contratos.

Objetivo:

- Identidad cálida con contraste y un valor único por color, radio y espaciado.
- Forma consistente, ojo de contraseña y filtros plegables.

## Usuarios

- **Dueño y cuidador:** usan la app a diario y necesitan una interfaz natural, segura y
  con estados distinguibles.
- **Persona con baja visión:** necesita contraste suficiente y un fondo que no canse.

## Historias de usuario

- HU-1. Quiero una identidad natural y cercana al cuidado de mi mascota.
- HU-2. Quiero reconocer la acción principal y los estados de cada pantalla.
- HU-3. Quiero leer con comodidad en claro y oscuro.
- HU-4. Quiero comprobar la contraseña que escribo antes de guardarla.
- HU-5. Quiero un historial sin filtros permanentes y una apariencia coherente.

## Definiciones

- **Rol, token y contenido:** un rol es una función visual; un token es su valor único;
  el contenido es el color de texto o icono sobre un relleno. Todos los HEX viven en un
  único archivo de tokens, la sola excepción a la prohibición de colores literales.
- **Acción de creación o compra:** acción principal que crea un registro o inicia una
  compra; es la única que usa el CTA. Lista cerrada: «Guardar Mascota», «Generar Plan
  Automático», y «Añadir al carrito»/«Comprar» cuando exista la compra (hoy no existe).
  Quedan fuera y usan el principal: «Iniciar Sesión», «Registrarse», «Guardar» de
  perfil, «Actualizar Mascota», «Vincular Dispositivo», «Vincular Dispensador
  Inteligente» y «Conectar».
- **Panel de filtros:** bloque plegable del historial con mascota, tipo de evento,
  resultado, rango de fechas y «Limpiar filtros».
- **Radio base:** 8 puntos; botones, campos, tarjetas, chips, botón flotante y aviso
  emergente usan 8; diálogos, hojas y menús usan 12, derivados de él.
- **Escala de espaciado:** 4, 8, 12, 16, 20, 24 y 32. No se aplica a dimensiones fijas,
  al mínimo de accesibilidad de 48 ni a trazos de 1 punto.

## Paleta — modo claro

| Token | HEX | Uso |
| --- | --- | --- |
| Principal | `#2E7D32` | Barras, encabezados, selección y acciones no comerciales |
| Sobre principal | `#FFFFFF` | Texto e iconos (5.13:1) |
| Contenedor principal | `#C8E6C9` | Fondos de apoyo |
| Sobre contenedor principal | `#1B5E20` | Texto (5.85:1) |
| CTA | `#D84315` | Solo relleno de creación o compra |
| Sobre CTA | `#000000` | Texto e iconos (4.73:1) |
| Fondo | `#FAF6F0` | Fondo general |
| Superficie | `#FFFFFF` | Tarjetas, hojas y diálogos |
| Texto y estructura | `#3E2723` | Títulos, textos y base de bordes |
| Texto secundario | `#6B544C` | Texto de apoyo (6.51:1 sobre fondo) |
| Acento | `#0277BD` | Enlaces sobre blanco (4.80:1) e iconos/insignias (4.46:1) |
| Sobre acento | `#FFFFFF` | Texto e iconos (4.80:1) |
| Contenedor de acento | `#D9ECF7` | Insignias y avisos informativos |
| Sobre contenedor de acento | `#01466F` | Texto e iconos (8.21:1) |
| Éxito | `#66BB6A` | Relleno de confirmaciones |
| Sobre éxito | `#3E2723` | Texto e iconos (5.85:1) |
| Alerta | `#FFA726` | Relleno de recordatorios y avisos |
| Sobre alerta | `#3E2723` | Texto e iconos (7.11:1) |
| Error | `#B3261E` | Acciones destructivas y fallos |
| Sobre error | `#FFFFFF` | Texto e iconos (6.54:1) |
| Contenedor de error | `#FFDAD6` | Aviso de error |
| Sobre contenedor de error | `#410002` | Texto (13.26:1) |
| Borde | `#3E2723` al 60 % | Tarjetas y campos (3.82:1 fondo, 3.95:1 superficie) |
| Borde suave | `#3E2723` al 24 % | Divisorias |
| Sombra y velo | `#000000` | Con opacidad |

## Paleta — modo oscuro

Paleta cálida aprobada; no se conserva el modo oscuro neutro anterior.

| Token | HEX | Uso |
| --- | --- | --- |
| Principal | `#81C784` | Barras, encabezados, selección y acciones no comerciales |
| Sobre principal | `#171310` | Texto e iconos (9.18:1) |
| Contenedor principal | `#2E5B31` | Fondos de apoyo |
| Sobre contenedor principal | `#C8E6C9` | Texto (5.88:1) |
| CTA | `#FF8A65` | Solo relleno de creación o compra |
| Sobre CTA | `#171310` | Texto e iconos (7.98:1) |
| Fondo | `#171310` | Fondo general, sin negro puro |
| Superficie | `#221C18` | Tarjetas, hojas y diálogos |
| Texto y estructura | `#F2E9DF` | Títulos, textos y base de bordes |
| Texto secundario | `#C9BCB0` | Texto de apoyo (9.06:1 sobre superficie) |
| Acento | `#4FC3F7` | Enlaces, iconos e insignias (8.40:1 sobre superficie, 9.22:1 sobre fondo) |
| Sobre acento | `#171310` | Texto e iconos (9.22:1) |
| Contenedor de acento | `#0B3A52` | Insignias y avisos informativos |
| Sobre contenedor de acento | `#BCE4F5` | Texto e iconos (8.93:1) |
| Éxito | `#A5D6A7` | Relleno de confirmaciones, distinto del principal |
| Sobre éxito | `#171310` | Texto e iconos (11.24:1) |
| Alerta | `#FFB74D` | Relleno de recordatorios y avisos |
| Sobre alerta | `#171310` | Texto e iconos (10.67:1) |
| Error | `#F2B8B5` | Acciones destructivas y fallos |
| Sobre error | `#601410` | Texto e iconos (7.66:1) |
| Contenedor de error | `#93000A` | Aviso de error |
| Sobre contenedor de error | `#FFDAD6` | Texto (7.24:1) |
| Borde | `#F2E9DF` al 60 % | Tarjetas y campos (5.85:1 sobre superficie) |
| Borde suave | `#F2E9DF` al 24 % | Divisorias |
| Sombra y velo | `#000000` | Con opacidad |

## Ranuras del esquema

El CTA no ocupa ranura: solo se aplica al botón de creación o compra. El verde ocupa
`primary`, `secondary`, sus contenedores y `surfaceTint`; el azul, `tertiary` y su
contenedor. `secondary` repite el verde para que ningún componente tome otro color.

| Ranura | Claro | Oscuro |
| --- | --- | --- |
| `primary` | `#2E7D32` | `#81C784` |
| `onPrimary` | `#FFFFFF` | `#171310` |
| `primaryContainer` | `#C8E6C9` | `#2E5B31` |
| `onPrimaryContainer` | `#1B5E20` | `#C8E6C9` |
| `secondary` y `secondaryContainer` | Repiten `primary` y `primaryContainer` | Lo mismo |
| `onSecondary` y `onSecondaryContainer` | Repiten `onPrimary` y `onPrimaryContainer` | Lo mismo |
| `tertiary` | `#0277BD` | `#4FC3F7` |
| `onTertiary` | `#FFFFFF` | `#171310` |
| `tertiaryContainer` | `#D9ECF7` | `#0B3A52` |
| `onTertiaryContainer` | `#01466F` | `#BCE4F5` |
| `error` | `#B3261E` | `#F2B8B5` |
| `onError` | `#FFFFFF` | `#601410` |
| `errorContainer` | `#FFDAD6` | `#93000A` |
| `onErrorContainer` | `#410002` | `#FFDAD6` |
| `surface` | `#FFFFFF` | `#221C18` |
| `onSurface` | `#3E2723` | `#F2E9DF` |
| `onSurfaceVariant` | `#6B544C` | `#C9BCB0` |
| `surfaceContainerLowest` | `#FFFFFF` | `#100D0B` |
| `surfaceContainerLow` | `#FDF9F5` | `#1C1714` |
| `surfaceContainer` | `#F5EEE6` | `#221C18` |
| `surfaceContainerHigh` | `#EFE6DD` | `#2B2420` |
| `surfaceContainerHighest` | `#E8DED4` | `#352D28` |
| `outline` | `#3E2723` al 60 % | `#F2E9DF` al 60 % |
| `outlineVariant` | `#3E2723` al 24 % | `#F2E9DF` al 24 % |
| `inverseSurface` | `#3E2723` | `#F2E9DF` |
| `onInverseSurface` | `#FAF6F0` | `#3E2723` |
| `inversePrimary` | `#81C784` | `#2E7D32` |
| `surfaceTint` | `#2E7D32` | `#81C784` |
| `scrim` y `shadow` | `#000000` | `#000000` |

Tarjetas, hojas y diálogos usan `surface`; las tarjetas llevan borde de 1 punto con
`outline` y elevación 0. `surfaceContainer*` se reserva para pistas de progreso,
divisorias y fondos de apoyo, nunca como relleno de tarjeta. `shadow` y `scrim` solo se
usan en menús y velos, siempre con opacidad.

## Requisitos funcionales

- **RF-01:** MIENTRAS la aplicación esté en modo claro, EL SISTEMA aplicará exactamente
  los tokens de la tabla de modo claro, con sus HEX y contenidos.
- **RF-02:** MIENTRAS la aplicación esté en modo oscuro, EL SISTEMA aplicará exactamente
  los tokens de la tabla de modo oscuro. La elección y conservación del modo no cambian.
- **RF-03:** EL SISTEMA obtendrá todos los colores de los tokens; ninguna pantalla usará
  literales ni colores por defecto. Excepciones: archivo único de tokens, variantes de
  opacidad y transparente. Sin nombres ni comentarios de la paleta morada anterior.
- **RF-04:** EL SISTEMA respetará la columna «Uso» y estas restricciones: en claro el
  acento será texto solo sobre blanco (4.80:1) y sobre el fondo crema los enlaces usarán
  el principal (4.76:1); en oscuro podrá ser texto (8.40:1 sobre superficie `#221C18` y
  9.22:1 sobre el fondo `#171310`); iconos e insignias lo usarán sobre cualquier fondo
  (4.46:1 claro, 8.40:1 sobre superficie oscura y 9.22:1 sobre el fondo oscuro) y su
  contenedor en insignias y avisos (8.21:1/8.93:1). El CTA nunca será texto, fondo, barra
  ni contenedor. Éxito y alerta serán relleno con su contenido, nunca texto en claro:
  sobre blanco 2.36:1/1.94:1 y sobre el fondo crema 2.20:1/1.80:1; en oscuro sí texto
  (11.24:1/10.67:1). El error solo se usará en destructivas y fallos.
- **RF-05:** CUANDO la acción principal sea de creación o compra, EL SISTEMA la pintará
  con el CTA; si no lo es, con el principal. Las secundarias serán delineadas o de texto
  con el principal; las destructivas, con el error. Una acción principal por pantalla.
- **RF-06:** EL SISTEMA eliminará el morado y los literales del panel. Ninguna pantalla
  mostrará `#6C63FF`, `#6750A4`, `#EADDFF`, `#E8DEF8` ni colores fuera de la paleta.
- **RF-07:** EL SISTEMA fijará todas las ranuras de la tabla del esquema, de modo que
  barras, navegación, botones, tarjetas, campos, cursores, diálogos y avisos usen los
  tokens sin que cada pantalla los pinte. En modo automático seguirá al sistema.
- **RF-08:** EL SISTEMA usará un radio base de 8 del que derivan todos los redondeos.
  Botones, campos, tarjetas, chip de selección, botón flotante y aviso emergente tendrán
  8; diálogos, hojas y menús, 12. El chip dejará de ser píldora, el botón flotante pasará
  de 16 a 8 y el aviso de 4 a 8. Ninguna pantalla declarará un radio literal ni píldoras.
- **RF-09:** EL SISTEMA aplicará la escala 4, 8, 12, 16, 20, 24 y 32 a márgenes, rellenos
  y huecos. El relleno de pantalla será 16 y 24 desde 600 puntos; entre campos, 16; dentro
  de tarjetas, 16; entre secciones, 24. Quedan fuera las dimensiones fijas, el mínimo de
  48 y los trazos de 1 punto.
- **RF-10:** MIENTRAS el usuario escriba en una contraseña, EL SISTEMA ofrecerá un ojo que
  alterna mostrar y ocultar. Estará en login, registro y confirmación, «Contraseña
  nueva» y «Confirmar contraseña nueva», baja y WiFi. Será un widget compartido con
  estado propio, sin estado en vistas principales ni estilos, colores o tamaños
  literales en configuración ni cuenta. Empezará oculto, visible con foco o contenido y
  no desaparecerá al dejar de escribir; no alterará contenido, cursor ni validación; su
  etiqueta alternará «Mostrar contraseña» y «Ocultar contraseña».
- **RF-11:** CUANDO el usuario abra el historial, EL SISTEMA mostrará el panel plegado y un
  botón con icono y texto «Filtros»; al pulsarlo se desplegará con los cuatro filtros y
  «Limpiar filtros», y al volver a pulsarlo se plegará. Sin contador. No se persiste:
  empieza plegado en cada entrada, permanece abierto al filtrar, paginar, recargar o
  reintentar mientras la pantalla siga montada, y se pliega al reentrar. Plegar no altera
  filtros ni resultado.
- **RF-12:** MIENTRAS el panel esté plegado, EL SISTEMA no reservará el espacio de los
  cuatro campos ni de «Limpiar filtros»; la lista lo recupera y solo mantiene la altura
  del botón «Filtros». Los textos de filtros y limpieza se conservan.
- **RF-13:** TODAS las pantallas existentes usarán los tokens, sin estilos literales:
  autenticación, inicio y navegación, mascotas, nutrición, historial, dispositivos y
  configuración, con sus diálogos y avisos. Un cambio de token se propaga a todas.
- **RF-14:** CUANDO se pinte texto o iconos sobre un relleno de rol, EL SISTEMA usará
  exactamente su color de contenido; nunca blanco o negro directos.

## Requisitos no funcionales

- **RNF-01:** Sin cambios funcionales ni de textos, salvo «Filtros», las etiquetas del
  ojo y la retirada de los emojis existentes (`⚠️` ×2 y `💧`), autorizada por el usuario.
  La preferencia de apariencia solo decide el modo y se conserva. Las pruebas se conservan
  salvo las de visibilidad permanente de filtros, que se adaptan.
- **RNF-02:** Backend y firmware intactos; se verifica por diferencia de rutas.
- **RNF-03:** Texto normal ≥4.5:1; texto grande y elementos gráficos ≥3:1 sobre el fondo real.
- **RNF-04:** Sin desbordamientos en 320, 600 y 840 puntos, vertical y horizontal, con
  escalado de texto hasta 1.3.
- **RNF-05:** Cada requisito tendrá una prueba según la tabla de trazabilidad; el análisis
  estático sin errores y la suite en verde.
- **RNF-06:** Las vistas solo componen y emiten eventos; sin lógica de negocio ni acceso a
  datos. El ojo vive en un widget compartido con estado propio.
- **RNF-07:** Sin dependencias ni tipografías nuevas; textos y etiquetas en español, sin emojis.
- **RNF-08:** Sin credenciales ni datos sensibles; la visibilidad es solo de presentación.

## Enmienda a la spec 014

- RF-33 queda enmendado: los filtros dejan de ser permanentes y se rigen por RF-11 y RF-12.
- RF-27 a RF-32 no cambian: filtros, paginación, catálogo, avisos y textos siguen igual.
- Las 9 aserciones de la prueba de vista del historial que buscan los filtros sin desplegar
  se reescriben para abrir el panel; no se elimina ni debilita ninguna prueba funcional.
## Deuda visual detectada

| Deuda | Situación | RF |
| --- | --- | --- |
| Esquema sin fijar | El morado por defecto del sistema llega a botones, navegación, cursores y avisos | 06, 07 |
| Morado y literales | `#6C63FF`, `#0066FF`, `#00C853`, `#FFB300`, `#00B8D4`; más de cien colores predefinidos y 34 HEX sueltos | 03, 06 |
| Radios | Siete valores distintos en 54 usos | 08 |
| Espaciados | Unos 36 rellenos y márgenes fuera de la escala | 09 |
| Contraseñas | Actualización y baja sin ojo; login, registro y WiFi con estado propio en la vista | 10 |
| Filtros | Franja permanente sobre la lista | 11, 12 |

## Casos límite

- **Campo vacío y sin foco:** el ojo puede ocultarse; vuelve con el foco o el contenido.
- **Campo con error:** el ojo sigue visible; alternarlo no borra el error ni valida.
- **Baja con contraseña vacía:** alternar el ojo no habilita la confirmación.
- **Login y registro:** un solo ojo por campo y sin estado de visibilidad en la vista.
- **Panel abierto en 320 puntos:** los cuatro filtros y «Limpiar filtros» no desbordan.
- **Escalado 1.3:** filtros, botones y campos siguen legibles y accionables.
- **Token cambiado:** color o radio nuevo se refleja en todas las pantallas sin tocarlas.
- **Modo automático:** sigue al sistema y conserva la preferencia al cambiar de apariencia.

## Fuera de alcance

- Cambiar funcionalidad, navegación, validaciones, contratos o comportamiento sin conexión.
- Tocar backend o firmware.
- Cambiar tipografía, iconografía, ilustraciones, animaciones o la estructura de las
  pantallas más allá de controles y filtros.
- Añadir otros roles, contenidos, dependencias o tipografías.
- Accesibilidad más allá del contraste, las etiquetas nuevas y el escalado de texto.

## Criterios de finalización

1. RF-01 a RF-09, RF-13 y RF-14: tema, ranuras, radios, escala y ausencia de morado o
   literales; pruebas de tema y forma.
2. RF-10: ojo en los siete campos, etiquetas y comportamiento intacto.
3. RF-11 y RF-12: ciclo del panel y espacio liberado, con la enmienda a la 014 aplicada.
4. RNF-03 y RNF-04: ningún par bajo el umbral y sin desbordamientos a 320, 600 y 840.
5. RNF-01, 02, 05, 06, 07 y 08: sin cambios funcionales ni de backend/firmware, análisis y
   suite en verde.

## Trazabilidad

| Requisito | Prueba |
| --- | --- |
| RF-01 | Tema claro: cada token devuelve su HEX y contenido. |
| RF-02 | Tema oscuro: cada token devuelve su HEX y contenido. |
| RF-03 | Estática: solo el archivo de tokens admite HEX y variantes alfa. |
| RF-04 | Uso de roles: acento, CTA, éxito, alerta y error respetan sus restricciones. |
| RF-05 | Acción principal: creación/compra en CTA; resto en principal; destructivas en error. |
| RF-06 | Ausencia de morado y de literales del panel. |
| RF-07 | Ranuras del esquema y componentes por defecto. |
| RF-08 | Forma: 8 en controles y 12 en diálogos, hojas y menús. |
| RF-09 | Escala de espaciado y relleno de pantalla 16/24. |
| RF-10 | Ojo en siete campos, widget compartido, etiquetas y validación intacta. |
| RF-11 | Panel: plegado al entrar, abierto al filtrar/paginar/recargar, sin contador. |
| RF-12 | Panel plegado: sin campos ni limpieza y lista con el espacio recuperado. |
| RF-13 | Coherencia en todas las pantallas listadas. |
| RF-14 | Contenido correcto sobre cada relleno y contraste 4.5:1. |
| RNF-01/05/07 | Suite completa, preferencia intacta, análisis limpio, sin dependencias. |
| RNF-02 | Diferencia de rutas: sin backend ni firmware. |
| RNF-03 | Contraste WCAG de los pares de las tablas. |
| RNF-04 | 320, 600 y 840, vertical y horizontal, texto 1.3. |
| RNF-06 | Arquitectura y ausencia de estado de visibilidad en vistas. |
| RNF-08 | Almacenamiento cifrado y visibilidad solo de presentación. |

## Dudas abiertas

Ninguna.
