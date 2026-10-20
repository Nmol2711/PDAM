# Plan Técnico — Spec 006: Interfaz de Dispositivos, Visualización de Dispensadores Vinculados y Gestión de Credenciales WiFi

## 1. Resumen de Arquitectura y Componentes Afectados

La implementación de la mejora visual y funcional para la gestión de dispositivos en la aplicación móvil PDAM abarca los siguientes componentes, respetando estrictamente la Clean Architecture, el enfoque Offline-First y las directrices de `docs/constitution.md` y `AGENTS.md`:

1. **Frontend (Flutter + BLoC + GoRouter + Isar):**
   - **Navegación (`core/router/` y `core/presentation/widgets/main_navigation_shell.dart`):** Actualización de la etiqueta de navegación de "Dispensadores" a **"Dispensadores" -> "Dispositivos"**.
   - **Módulo de Dispensadores / Dispositivos (`features/dispensers/`):**
     - **Domain:** Entidades y casos de uso para listar dispensadores vinculados y eliminar/resetear credenciales WiFi.
     - **Data:** Repositorios y fuentes de datos (remota vía Dio y local vía Isar con enfoque Offline-First).
     - **Presentation:** Rediseño completo de la vista de dispositivos (`dispensers_page.dart` o renombrada a dispositivos) utilizando componentes limpios, reutilizables, Material Design 3, paleta de colores global (`AppColors`, `AppTheme`), adaptabilidad responsive (`LayoutBuilder` / `MediaQuery`), incorporación del indicador de estado **"Aún no se han proporcionado las credenciales de wifi"**, y un botón funcional de eliminación de credenciales que invoca el endpoint correspondiente del backend (`/api/v1/dispensers/{id}/reset-wifi` o equivalente).

2. **Backend (FastAPI):**
   - Verificación y soporte del endpoint de reseteo/eliminación de credenciales WiFi (`POST /dispensers/{id}/reset-wifi` o `PUT` equivalente) para asegurar que el backend procesa correctamente la orden solicitada por el usuario desde la tarjeta del dispositivo.

---

## 2. Fases de Implementación

### Fase 1: Actualización de Navegación y Estructura Base
- **Renombramiento en Navegación:** Modificar `main_navigation_shell.dart` y las rutas asociadas en `GoRouter` para cambiar la etiqueta de "Dispensadores" a "Dispositivos".
- **Revisión de Casos de Uso y Repositorios:** Asegurar que los contratos de dominio y la capa de datos expongan los métodos necesarios para consultar dispensadores vinculados a mascotas y ejecutar la eliminación de credenciales WiFi.

### Fase 2: Rediseño Visual y Componentes Material Design 3
- **Componentes Reutilizables:** Construir tarjetas de dispositivos (`DeviceCardWidget` o similar) limpias, reutilizables y desacopladas de lógica de negocio (respetando la regla de vistas limpias).
- **Indicador de Credenciales:** Implementar la visualización condicional del texto **"Aún no se han proporcionado las credenciales de wifi"** en la tarjeta del dispositivo según el estado de la conexión/credenciales.
- **Botón de Eliminación de Credenciales:** Añadir el botón interactivo con diálogo de confirmación (si aplica) que consuma el caso de uso correspondiente para eliminar credenciales WiFi mediante el backend y actualice de forma reactiva la UI mediante BLoC.
- **Adaptabilidad y Tema:** Aplicar la paleta de colores global y asegurar compatibilidad responsive para diferentes dispositivos móviles y tablets.

### Fase 3: Persistencia Offline-First y Pruebas Automatizadas
- **Isar:** Sincronizar el estado local de los dispositivos con Isar para garantizar la disponibilidad offline.
- **Pruebas Unitarias y de Widgets (`flutter test`):** Cobertura de pruebas para el BLoC de dispositivos, vistas rediseñadas y simulación de consumo del endpoint de reseteo WiFi.

---

## 3. Decisiones Técnicas y Alternativas Descartadas

* **Decisión 1:** Uso de BLoC para la gestión de estado de la vista de dispositivos.
* *Alternativa descartada:* Uso de `setState` dentro de las vistas principales. Se descarta por violar las reglas de la constitución y AGENTS.md (prohibición estricta de `setState` en vistas principales).
* **Decisión 2:** Renombrar la sección de "Dispensadores" a "Dispositivos" manteniendo la robustez de los repositorios de datos existentes (`features/dispensers/`).
* *Alternativa descartada:* Crear un módulo completamente nuevo desde cero descartando la lógica BLE y de sincronización ya probada en la Spec 005. Se reutiliza la arquitectura existente adaptando la interfaz visual y la terminología.

---

## 4. Estrategia de Pruebas y Trazabilidad (RF a Pruebas)

| Requisito Funcional | Componente Afectado | Tipo de Prueba | Herramienta / Framework | Caso de Prueba Asociado |
|---------------------|---------------------|----------------|--------------------------|-------------------------|
| **RF-01** | Frontend (GoRouter / Navigation Shell) | Prueba de Widget / Integración | `flutter test` | CP-01 |
| **RF-02** | Frontend (UI / Material Design 3 Theme) | Prueba de Widget | `flutter test` | CP-02 |
| **RF-03** | Frontend / Backend (Vinculación con Mascotas) | Prueba Unitaria / Integración | `flutter test`, `pytest` | CP-03 |
| **RF-04** | Frontend (Indicador de Credenciales WiFi) | Prueba de Widget | `flutter test` | CP-04 |
| **RF-05** | Frontend / Backend (Eliminación de Credenciales WiFi) | Prueba de Integración / API | `flutter test`, `pytest` | CP-05 |
| **RNF-03** | Frontend (Responsive Layout) | Prueba de Widget | `flutter test` | CP-02 |
