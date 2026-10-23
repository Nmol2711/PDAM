# Tareas 012 — Stock del dispensador en tiempo real y limpieza de la tarjeta

- [x] **T1. Reabastecimiento aditivo con tope en el backend.**
  RF-7
  - Hecho cuando: `refill_dispenser` suma la cantidad al stock y acota a 5000 g;
    los tests de suma, tope y valores inválidos pasan con `pytest`.

- [x] **T2. Funciones puras de formato y de reabastecimiento en el dominio.**
  RF-3, RF-7
  - Hecho cuando: los tests de `formatGrams`, `formatKilograms` y `applyRefill`
    pasan.

- [x] **T3. Datasources y repositorio: refresco y refill remoto.**
  RF-4, RF-7, RF-8, RF-10
  - Hecho cuando: `refreshDispensers` consulta y cachea; `refillFood` exige
    conexión, llama al endpoint y cachea la respuesta; los tests del repositorio
    pasan.

- [x] **T4. BLoC: evento de refresco silencioso y aviso de refill.**
  RF-4, RF-7
  - Hecho cuando: `RefreshDispensersEvent` actualiza la lista sin loading y el
    refill exitoso emite la lista con `refillSuccess`; los tests del BLoC pasan.

- [x] **T5. Tarjeta limpia y barra con g/kg.**
  RF-1, RF-2, RF-3
  - Hecho cuando: la tarjeta no muestra conexión ni estado WiFi, conserva el
    botón de reset y la barra muestra ambas unidades; los tests de widgets
    pasan.

- [x] **T6. Pantalla de Dispositivos con sondeo, pull-to-refresh y retorno del
  escaneo.**
  RF-4, RF-5, RF-6, RF-9, RNF-1, RNF-2
  - Hecho cuando: la lista se refresca cada 5 s con la pantalla visible, admite
    pull-to-refresh, se refresca al volver a primer plano y se restaura al
    cerrar el escaneo BLE.

- [x] **T7. Validación integral y memoria.**
  Criterios de finalización
  - Hecho cuando: `pytest`, `flutter test` y `flutter analyze` pasan sin errores
    nuevos y `MEMORY.md` queda actualizado.

## Revisión: reabastecimiento offline y límite de capacidad

- [x] **T8. Reabrir la Spec 012 con los nuevos requisitos.**
  RF-7, RF-8, RF-11, RF-12, RF-13
  - Hecho cuando: `spec.md`, `plan.md` y `tasks.md` reflejan el rechazo por
    capacidad, la cola offline y los mensajes de límite/éxito.

- [x] **T9. Backend: rechazar el reabastecimiento que supere 5000 g.**
  RF-7, RF-8
  - Hecho cuando: `refill_dispenser` responde 400 con
    `code=refill_exceeds_capacity`, no modifica el stock y los tests de suma,
    límite exacto, rechazo y 404 pasan.

- [x] **T10. Dominio: excepción y validación de capacidad.**
  RF-7, RF-8, RF-13
  - Hecho cuando: `applyRefill` y `convertAndValidateRefill` lanzan
    `RefillLimitException` al superar el límite o con cantidad inválida, y sus
    tests pasan.

- [x] **T11. Isar: campo `pendingRefillGrams` y mapeo.**
  RF-11, RNF-7
  - Hecho cuando: el campo se guarda, se conserva al cachear y se limpia con
    `0`; `local_dispenser.g.dart` está regenerado y los tests pasan.

- [x] **T12. Repositorio: cola offline y sincronización de pendientes.**
  RF-7, RF-8, RF-10, RF-11, RF-12
  - Hecho cuando: el refill offline valida y encola; el online envía
    `pendiente + nuevo`; `refreshDispensers` envía pendientes, reconcilia por
    límite y conserva el pendiente ante fallo de red.

- [x] **T13. BLoC y UI: mensajes de límite y éxito.**
  RF-8, RF-13
  - Hecho cuando: el diálogo muestra el límite sin cerrarse, el BLoC no emite
    errores genéricos de refill y la página muestra "El reabastecimiento supera
    el límite de 5 kg" o "Reabastecimiento con éxito".

- [x] **T14. Validación integral y memoria de la revisión.**
  Criterios de finalización
  - Hecho cuando: `pytest`, `flutter test` y `flutter analyze` pasan sin errores
    nuevos y `MEMORY.md` queda actualizado.
