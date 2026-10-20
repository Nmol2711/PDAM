# Spec 006 — Interfaz de Dispositivos, Visualización de Dispensadores Vinculados y Gestión de Credenciales WiFi

Estado: borrador

## Contexto y objetivo

El sistema PDAM gestiona dispensadores de comida para mascotas vinculados mediante hardware ESP32 y una aplicación móvil en Flutter. Actualmente, la sección de navegación hace referencia a "Dispensadores", y la interfaz de usuario requiere mejoras visuales significativas para alinearse plenamente con los estándares de Material Design 3, los temas globales y la adaptabilidad responsive del proyecto.

El objetivo de esta especificación es actualizar la navegación principal renombrando "Dispensadores" a "Dispositivos", rediseñar la vista de dispositivos con componentes limpios y reutilizables, mostrar los dispensadores ya vinculados a las mascotas del usuario, incluir un indicador claro de estado ("Aún no se han proporcionado las credenciales de wifi") cuando corresponda, y proporcionar un botón funcional en la tarjeta del dispositivo para eliminar las credenciales WiFi consumiendo el endpoint correspondiente del backend y actualizando la interfaz de manera reactiva.

## Usuarios

* **Dueño de mascota / Usuario de la App:** Desea visualizar y gestionar sus dispositivos vinculados en una interfaz moderna y clara, identificar rápidamente si un dispositivo carece de configuración WiFi y poder reiniciar o eliminar las credenciales cuando sea necesario.

## Historias de usuario

* **HU-1.** Como usuario, quiero que la opción en la barra de navegación principal se denomine "Dispositivos" en lugar de "Dispensadores" para reflejar de forma más precisa la gestión general del hardware.
* **HU-2.** Como usuario, quiero visualizar una interfaz de dispositivos moderna, limpia y responsive, construida bajo los lineamientos de Material Design 3 y respetando los colores y temas globales de la aplicación.
* **HU-3.** Como usuario, quiero ver en la lista de la vista de Dispositivos los dispensadores que ya se encuentran vinculados a mis mascotas.
* **HU-4.** Como usuario, quiero ver claramente un indicador en la tarjeta del dispositivo que muestre el texto "Aún no se han proporcionado las credenciales de wifi" cuando el dispositivo requiera dicha configuración.
* **HU-5.** Como usuario, quiero presionar un botón en la tarjeta del dispositivo para eliminar las credenciales de wifi, ejecutando la solicitud al backend y reflejando el cambio de estado inmediatamente en la interfaz.

## Requisitos funcionales (EARS)

* **RF-01 (Renombramiento de Sección de Navegación):** EL SISTEMA debe mostrar la opción de navegación principal renombrada de "Dispensadores" a **"Dispositivos"** tanto en la barra de navegación inferior (`BottomNavigationBar`) como en el menú responsive de la aplicación móvil.
* **RF-02 (Rediseño Visual Material Design 3):** EL SISTEMA debe presentar la vista de dispositivos aplicando componentes limpios, reutilizables y alineados estrictamente con el sistema de diseño Material Design 3, respetando los temas globales (claro y oscuro) y la paleta de colores corporativa.
* **RF-03 (Listado de Dispensadores Vinculados):** EL SISTEMA debe consultar y mostrar en la vista de Dispositivos todos los dispensadores que estén asociados y vinculados a las mascotas del usuario autenticado.
* **RF-04 (Indicador de Estado de Credenciales WiFi):** EL SISTEMA debe incluir de manera visible en la tarjeta de cada dispositivo un indicador o texto con el mensaje exacto **"Aún no se han proporcionado las credenciales de wifi"** cuando el dispositivo no tenga configurada su red WiFi o se encuentre en estado pendiente de aprovisionamiento.
* **RF-05 (Eliminación de Credenciales WiFi):** CUANDO el usuario pulse el botón de eliminar credenciales WiFi ubicado en la tarjeta del dispositivo, EL SISTEMA debe invocar el endpoint correspondiente del backend para procesar el reseteo de credenciales y actualizar de forma reactiva el estado en la interfaz de usuario.

## Requisitos no funcionales

* **RNF-01 (Clean Architecture):** La implementación de la interfaz, la gestión de estado y las peticiones al backend deben mantener una separación estricta de responsabilidades acorde a la Clean Architecture y las directrices de la constitución del proyecto.
* **RNF-02 (Idioma en Español):** Todos los textos visibles en la interfaz de usuario, etiquetas, mensajes de estado y descripciones deben estar redactados en perfecto español.
* **RNF-03 (Adaptabilidad Responsive):** La vista de dispositivos debe adaptarse correctamente a diferentes factores de forma (teléfonos móviles y tabletas) utilizando contenedores flexibles y `LayoutBuilder` / `MediaQuery`.

## Fuera de alcance

* Modificaciones estructurales en el protocolo de aprovisionamiento Bluetooth (BLE) de bajo nivel del ESP32 (ya definido en especificaciones anteriores).
* Cambios en la lógica de negocio general de otras secciones no relacionadas con la gestión visual y de credenciales WiFi de los dispositivos.

## Criterios de finalización

1. La barra de navegación principal muestra la etiqueta "Dispositivos" en lugar de "Dispensadores".
2. La vista de dispositivos cuenta con un diseño renovado basado en Material Design 3, componentes limpios y temas globales.
3. Se listan correctamente los dispensadores vinculados a las mascotas del usuario.
4. Las tarjetas de los dispositivos muestran el indicador "Aún no se han proporcionado las credenciales de wifi" según su estado.
5. El botón de eliminación de credenciales WiFi en la tarjeta del dispositivo funciona correctamente, consume el endpoint del backend y actualiza la UI.

## Dudas abiertas

* Ninguna. Los requerimientos están completamente definidos y alineados con el backend existente y los estándares de la arquitectura del proyecto.
