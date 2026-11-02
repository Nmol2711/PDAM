# Spec 019 — Recarga manual y automática del historial

Estado: implementada

## Contexto y objetivo

El historial de eventos solo se recarga cuando el usuario cambia un filtro, cambia de
página o pulsa reintentar después de un error. La pestaña de historial permanece montada
al navegar a otra sección, por lo que al volver a ella se siguen mostrando los registros
de la primera apertura y el usuario no tiene forma de pedir datos frescos sin tocar un
filtro.

El objetivo es que el usuario pueda recargar el historial deslizando la lista hacia abajo
y que la pantalla se actualice sola al volver a su pestaña o al regresar a la aplicación,
sin perder los filtros aplicados ni vaciar la lista ya visible. Esta spec complementa
RF-33 y RF-34 de la spec 014, que definen qué se muestra al abrir el historial y cómo se
comporta sin conexión, pero no definen ninguna acción de recarga.

## Usuarios

Usuario de la aplicación móvil que consulta la actividad del dispensador.

## Historias de usuario

- HU-1. Como usuario, quiero deslizar la lista del historial hacia abajo para recargar los
  registros sin cambiar filtros, para ver la actividad más reciente.
- HU-2. Como usuario, quiero que el historial se actualice al volver a su pestaña o al
  regresar a la aplicación, para no estar viendo datos viejos sin darme cuenta.

## Definiciones

- **Refresco manual:** gesto de deslizar la lista hacia abajo partiendo de su inicio.
- **Refresco automático:** consulta que se dispara sin acción del usuario al activarse la
  pestaña del historial o al volver la aplicación a primer plano con el historial visible.
- **Pantalla visible:** la pestaña del historial está activa y en primer plano, sin otra
  pantalla ni diálogo por encima.
- **Mostrar la pestaña:** la pestaña pasa de inactiva a activa; el cierre de un diálogo o
  selector no cuenta como mostrarla.
- **Consulta en curso:** hay una petición de historial pendiente de respuesta.
- **Página disponible:** número de página existente para los filtros aplicados según el
  total de registros; sin registros, la página disponible es la 1.
- **Sin vaciar la lista:** no mostrar un estado intermedio vacío; el contenido se sustituye
  solo cuando la consulta termina con éxito.
- **Ventana de 4 s:** separación mínima entre refrescos automáticos consecutivos.

## Requisitos funcionales

- **RF-1:** CUANDO el usuario deslice la lista del historial hacia abajo desde su inicio,
  EL SISTEMA ejecutará un refresco manual con este comportamiento:
  - conservará los filtros aplicados y la página actual, y no vaciará la lista;
  - aplicará el ajuste de página de RF-5;
  - mostrará únicamente el indicador del gesto y ocultará la barra de progreso lineal
    mientras dure;
  - mantendrá el gesto disponible cuando la lista esté vacía o no llene la pantalla.
- **RF-2:** CUANDO se muestre la pestaña del historial, o CUANDO la aplicación vuelva a
  primer plano con el historial visible, EL SISTEMA ejecutará un refresco automático con
  este comportamiento:
  - conservará los filtros aplicados y la página actual, y aplicará el ajuste de página de
    RF-5;
  - mostrará únicamente la barra de progreso lineal existente, sin el indicador del gesto;
  - conservará la posición de desplazamiento de la lista y no la llevará al inicio;
  - no plegará ni desplegará el panel de filtros por sí mismo; el plegado al reentrar seguirá
    rigiéndose por RF-11 de la spec 017.
- **RF-3:** EL SISTEMA respetará una ventana de 4 segundos entre refrescos automáticos:
  - la ventana se mide desde que termina el último refresco automático, no desde que empieza;
  - la carga inicial de la pantalla cuenta como el último refresco automático y no se repite
    al mostrarse la pestaña en la misma apertura;
  - SI la solicitud automática llega dentro de la ventana, ENTONCES se ignorará y no
    actualizará la marca de tiempo;
  - la ventana solo limita refrescos automáticos: un refresco manual se ejecuta siempre y no
    la consume ni la reinicia.
- **RF-4:** MIENTRAS haya un refresco en curso, EL SISTEMA mostrará un único indicador, que
  no insertará ni desplazará contenido de la lista, y atenderá una sola consulta a la vez;
  SI el usuario cambia un filtro o de página, ENTONCES la acción nueva prevalecerá, el
  refresco en curso se descartará y no se apilarán indicadores; una solicitud ignorada
  tampoco actualizará la marca de la ventana de RF-3.
- **RF-5:** SI tras un refresco la página conservada deja de existir, ENTONCES EL SISTEMA
  consultará la última página disponible como máximo una vez más, dentro del mismo refresco
  y sin reiniciar la ventana de RF-3; SI esa consulta extra falla, ENTONCES conservará la
  página previa, la lista y los filtros, y mostrará el aviso de error de RF-6.
- **RF-6:** SI un refresco falla, ENTONCES EL SISTEMA conservará la lista, los filtros y la
  página previos y mostrará el aviso de error con acción de reintento, como RF-33 de la
  spec 014; SI no hay conexión, ENTONCES mostrará el aviso informativo de datos locales sin
  acción de reintento, como RF-34 de la spec 014; ambos avisos se sustituyen entre sí y
  nunca se muestran a la vez, y el refresco manual quedará disponible de nuevo.

## Requisitos no funcionales

- **RNF-1:** Cada RF tendrá al menos una prueba automatizada que lo valide, según la tabla
  CP → RF.
- **RNF-2:** Las pruebas serán deterministas: ventana de 4 s con reloj o intervalo
  inyectable, visibilidad por `TickerMode`, reanudación por ciclo de vida, no duplicación en
  la carga inicial, ajuste de página y conservación en fallo y sin conexión; en niveles BLoC
  y widget, sin red real.
- **RNF-3:** Todos los textos nuevos visibles estarán en español.
- **RNF-4:** No se añadirán dependencias nuevas.
- **RNF-5:** La decisión de refrescar, la ventana de 4 s, el ajuste de página, la
  concurrencia y la conservación de filtros, página y lista residirán fuera de la vista; la
  pantalla solo detecta que está visible, emite la intención de recarga y compone el
  indicador que corresponda.
- **RNF-6:** No se altera ningún comportamiento definido en RF-33 y RF-34 de la spec 014 ni
  en RF-11 de la spec 017: el panel de filtros sigue plegándose al reentrar y el refresco no
  lo despliega. La prueba de plegado al reentrar se adapta a la consulta automática
  conservando todas sus aserciones de plegado, y no se debilita ninguna otra prueba.

## Casos de prueba

| CP | Qué valida | RF |
|----|------------|-----|
| CP-1 | Deslizar recarga conservando filtros y página; solo indicador del gesto, sin barra lineal y sin lista vacía intermedia. | RF-1 |
| CP-2 | El gesto funciona con lista vacía o con menos elementos que el alto de la pantalla. | RF-1 |
| CP-3 | Mostrar la pestaña refresca con barra lineal, sin indicador del gesto y sin mover el scroll; el panel se pliega al reentrar según 017 RF-11 y el refresco no lo despliega. | RF-2 |
| CP-4 | Volver del segundo plano con el historial visible refresca; con otra pestaña o un diálogo encima, no. | RF-2 |
| CP-5 | Cerrar un diálogo o selector no dispara refresco automático. | RF-2 |
| CP-6 | La carga inicial no se duplica al mostrarse la pestaña en la misma apertura. | RF-2, RF-3 |
| CP-7 | Salida y reentrada a la pestaña en menos de 4 s no encadena refresco; la solicitud ignorada no mueve la marca. | RF-3, RF-4 |
| CP-8 | Un refresco manual dentro de la ventana de 4 s se ejecuta y no reinicia la ventana. | RF-3, RF-4 |
| CP-9 | Cambiar filtro o página durante un refresco descarta el refresco en curso y muestra un solo indicador. | RF-4 |
| CP-10 | Página conservada inexistente: una única consulta extra a la última disponible. | RF-5 |
| CP-11 | La consulta extra falla: conserva página, lista y filtros, con error y reintento. | RF-5, RF-6 |
| CP-12 | Fallo de consulta muestra error con reintento; sin conexión muestra aviso local sin reintento; nunca ambos. | RF-6 |
| CP-13 | La ventana de 4 s se mide desde el fin del refresco anterior, aunque la consulta dure más de 4 s. | RF-3 |

## Fuera de alcance

- Cambios en el backend o en el contrato de la consulta de historial.
- Recargar el catálogo de filtros o la lista de mascotas durante el refresco.
- Refresco periódico por temporizador, notificaciones o actualización en tiempo real.
- Nuevos filtros, cambios de paginación o del tamaño de página.
- Cambios en la caché local más allá de conservarla y mostrarla como hoy.
- Refresco manual o automático en pantallas distintas del historial.
- Cambios visuales en la lista, los avisos o el panel de filtros.

## Criterios de finalización

- RF-1 a RF-6 implementados y con las pruebas de la tabla CP en verde.
- `flutter analyze` sin errores y el resto de la suite sin regresiones ni pruebas
  debilitadas.
- Verificación manual en el móvil: deslizar recarga, volver a la pestaña recarga, regresar
  del segundo plano recarga, cerrar un diálogo no recarga, y un fallo de red no borra la
  lista ni los filtros.
- `MEMORY.md` actualizado con las decisiones de la spec.
