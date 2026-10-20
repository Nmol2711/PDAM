# Tareas — Spec 007: Sistema de Estimación de Alimento Restante (Sin Sensor) y Notificaciones In-App Reutilizables

- [x] **T1. Actualización de modelos, esquemas y servicio en el Backend (FastAPI).** RF-1, RF-2, RF-3, RF-4
  - Validación frente a la constitución: Clean Architecture, pruebas unitarias obligatorias en `pytest`, validación estricta de límites (5000g).
  - Hecho cuando: Los esquemas Pydantic y modelos ORM soportan `current_food_grams` con validación de máximo 5000g y tests en `pytest` pasan en verde.

- [x] **T2. Implementación de pruebas unitarias para la lógica de stock y descuento en el Backend.** RF-1, RF-4
  - Validación frente a la constitución: Cobertura obligatoria de pruebas en todos los módulos de la API.
  - Hecho cuando: Los tests de reabastecimiento, límite de 5kg y descuento automático por dispensación ejecutan correctamente con `pytest`.

- [x] **T3. Creación de la entidad de dominio y funciones puras de conversión y cálculo en Flutter.** RF-1, RF-4, RF-7
  - Validación frente a la constitución: Clean Architecture (capa domain), funciones puras aisladas, sin lógica en UI.
  - Hecho cuando: La entidad `DispenserFoodStatus` y las funciones puras de conversión (g/kg), validación de 5kg y cálculo de raciones restantes están implementadas y cubiertas por tests unitarios en Flutter.

- [x] **T4. Actualización del modelo Isar y repositorio con estrategia Offline-First y aviso no invasivo.** RF-3, RF-8
  - Validación frente a la constitución: Arquitectura *Offline-First* con Isar, manejo robusto de desconexión sin bloquear la UI.
  - Hecho cuando: El modelo Isar local persiste el stock de alimento y el repositorio maneja la sincronización remota/local informando mediante un aviso no invasivo.

- [x] **T5. Creación del componente reutilizable de notificaciones In-App y barra de progreso crítica.** RF-5, RF-6, RNF-3
  - Validación frente a la constitución: Uso de tema y colores globales de la app, cero dependencias externas (Firebase).
  - Hecho cuando: El widget reutilizable `InAppNotificationBanner` y la barra de progreso minimalista (con umbral crítico < 20%) están desarrollados y verificados visualmente.

- [x] **T6. Implementación del BLoC de dispensadores para la gestión de alimento y reabastecimiento.** RF-1, RF-2, RF-3, RF-5, RF-7
  - Validación frente a la constitución: Separación estricta de responsabilidades (BLoC gestionando estados de reabastecimiento, umbrales y notificaciones).
  - Hecho cuando: `DispenserBloc` procesa correctamente los eventos de reabastecimiento, actualización de stock, cálculo de raciones y emisión de alertas in-app.

- [x] **T7. Desarrollo de la interfaz de usuario de detalles del dispensador y selector de reabastecimiento.** RF-1, RF-2, RF-5, RF-7, RF-8
  - Validación frente a la constitución: Vistas limpias (sin código espagueti ni `setState` global), uso estricto del sistema de diseño global en español.
  - Hecho cuando: La vista de detalles muestra la barra de progreso, selector de gramos/kilogramos con validación de 5kg, el cálculo de raciones restantes y el banner no invasivo de sincronización.

- [x] **T8. Pruebas unitarias y de widgets en Flutter para la gestión de alimento y notificaciones.** RF-1, RF-5, RF-6, RF-7, RF-8
  - Validación frente a la constitución: Cobertura obligatoria de pruebas unitarias e integración en la aplicación móvil antes de fusionar.
  - Hecho cuando: Todos los tests unitarios y de widgets para dispensadores y estimación de alimento pasan al 100% en verde con `flutter test`.

- [x] **T9. Verificación integral del flujo completo (Backend, App y Sincronización).** RF-1 a RF-8, RNF-1 a RNF-4
  - Validación frente a la constitución: Trazabilidad estricta bajo el Modelo en V, verificación de cumplimiento de la Constitución.
  - Hecho cuando: Tanto `pytest` como `flutter test` ejecutan con éxito total y se valida el funcionamiento operativo del módulo.
