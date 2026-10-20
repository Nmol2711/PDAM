# Tareas — Spec 006: Interfaz de Dispositivos, Visualización de Dispensadores Vinculados y Gestión de Credenciales WiFi

- [x] **T1 [RF-01]: Frontend — Renombrar etiqueta de navegación a "Dispositivos"**
  - **Descripción:** Actualizar `app/app_movil_pdam/lib/core/presentation/widgets/main_navigation_shell.dart` y las configuraciones de GoRouter para cambiar la etiqueta y título de la sección de "Dispensadores" a **"Dispositivos"**.
  - **Validación Constitución:** Cumplimiento de nomenclatura de UI en español y directrices de navegación.
  - **Hecho cuando:** La barra de navegación inferior y las rutas muestran correctamente "Dispositivos" y compilan sin errores.

- [x] **T2 [RF-02, RNF-03]: Frontend — Crear componentes UI reutilizables con Material Design 3**
  - **Descripción:** Desarrollar o refactorizar los componentes visuales de tarjetas de dispositivos utilizando la paleta de colores global (`AppColors`), temas Material Design 3 y adaptabilidad responsive mediante `LayoutBuilder` / `MediaQuery`.
  - **Validación Constitución:** Separación lógica-interfaz (vistas limpias, sin código espagueti) y uso de temas globales.
  - **Hecho cuando:** Los componentes de la vista de dispositivos respetan los temas claro/oscuro y se adaptan a diferentes tamaños de pantalla.

- [x] **T3 [RF-03]: Frontend — Mostrar dispensadores vinculados a mascotas en la vista de Dispositivos**
  - **Descripción:** Conectar la vista de dispositivos con el caso de uso y repositorio para listar los dispensadores que se encuentran actualmente vinculados a las mascotas del usuario.
  - **Validación Constitución:** Clean Architecture (separación entre dominio, datos y presentación).
  - **Hecho cuando:** La vista de dispositivos lista correctamente los dispensadores vinculados obtenidos de la fuente de datos.

- [x] **T4 [RF-04]: Frontend — Incluir indicador de estado "Aún no se han proporcionado las credenciales de wifi"**
  - **Descripción:** Implementar en la tarjeta del dispositivo la lógica visual para mostrar condicionalmente el texto exacto **"Aún no se han proporcionado las credenciales de wifi"** cuando el dispositivo requiera configuración de red.
  - **Validación Constitución:** Textos en perfecto español y lógica de presentación limpia.
  - **Hecho cuando:** Las tarjetas muestran el indicador de credenciales pendientes de forma clara y coherente con el estado del dispositivo.

- [x] **T5 [RF-05]: Frontend & Backend — Implementar botón funcional para eliminar credenciales WiFi**
  - **Descripción:** Añadir un botón interactivo en la tarjeta del dispositivo que invoque el caso de uso para eliminar/resetear las credenciales WiFi (consumiendo el endpoint del backend correspondiente) y actualice de forma reactiva el estado en la interfaz mediante BLoC.
  - **Validación Constitución:** Cobertura de comunicación cliente-servidor y manejo de errores robusto.
  - **Hecho cuando:** Al pulsar el botón, se ejecuta la llamada al backend, se actualiza la interfaz y se muestra la confirmación correspondiente en español.

- [x] **T6 [RNF-01, RNF-02]: Frontend — Soportar funcionamiento Offline-First con Isar**
  - **Descripción:** Asegurar que la persistencia local con Isar almacene y recupere correctamente los datos de los dispositivos cuando no haya conexión con el servidor.
  - **Validación Constitución:** Arquitectura Offline-First obligatoria del proyecto.
  - **Hecho cuando:** La app puede consultar los dispositivos guardados localmente cuando el backend no está disponible.

- [x] **T7 [RNF-06]: Pruebas — Escribir y ejecutar pruebas unitarias y de widgets**
  - **Descripción:** Desarrollar pruebas unitarias y de widgets en `app/app_movil_pdam/test/` para verificar el comportamiento del BLoC de dispositivos, el renderizado de la tarjeta con el indicador de WiFi y la interacción del botón de eliminación de credenciales.
  - **Validación Constitución:** Política de tests obligatoria en frontend antes de finalizar el módulo.
  - **Hecho cuando:** Todos los tests ejecutados con `flutter test` pasan al 100% en verde.

- [x] **T8 [General]: Verificación integral y actualización de memoria**
  - **Descripción:** Ejecutar la suite completa de pruebas de backend (`pytest`) y frontend (`flutter test`), verificar el correcto funcionamiento visual de la interfaz de dispositivos y actualizar `MEMORY.md`.
  - **Validación Constitución:** Trazabilidad estricta y actualización del estado del proyecto en memoria.
  - **Hecho cuando:** Todas las pruebas pasan exitosamente, `MEMORY.md` está actualizado y la spec 006 queda preparada.
