# Tareas 019 — Recarga manual y automática del historial

Orden: T1 → T2 → T3. Tests primero en cada tarea.

- [x] **T1. Dominio y BLoC del refresco: ventana de 4 s, generación de consulta, ajuste de página y error frente a sin conexión.** RF-1, RF-2, RF-3, RF-4, RF-5, RF-6
- Incluye: utilidad pura de refresco, evento y estado del refresco, BLoC y pruebas de dominio y BLoC (CP-6 a CP-13).
- Hecho cuando: `flutter test` de las pruebas de dominio y BLoC del historial en verde, `flutter analyze` sin errores y cada CP-6 a CP-13 cubierto por al menos una prueba.
- Depende de: nada.

- [x] **T2. Vista: gesto de recarga, refresco al mostrarse la pestaña o reanudar la app e indicador único.** RF-1, RF-2, RF-4, RNF-2
- Incluye: vista del historial y sus pruebas de widget (CP-1 a CP-5 y CP-9); se adapta
  `logs_view_test.dart:805-832` a «una consulta automática y panel plegado por 017», sin
  borrar aserciones de plegado.
- Hecho cuando: `flutter test test/features/logs` en verde, con CP-1 a CP-5 y CP-9 cubiertos, sin debilitar las aserciones de plegado de la prueba adaptada, y `flutter analyze` sin errores.
- Depende de: T1.

- [x] **T3. Cierre y verificación.** RF-1 a RF-6, RNF-1 a RNF-6
- Incluye: suite completa, checklist manual en el móvil y actualización de `MEMORY.md`.
- Hecho cuando: `flutter analyze` con 0 errores, `flutter test` completo en verde, checklist manual cumplido y `MEMORY.md` actualizado con las decisiones de la 019.
- Depende de: T2.
