# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
* #### Dirección MAC Única por Dispensador (`specs/003-mac-unica-dispensador`) — **Completado y Corregido (Desactivación y Eliminación Offline en UI)**
  * Especificación actualizada e implementada al 100%: alta, cambio de MAC, desactivación y eliminación exigen conexión obligatoria.
  * Corregido `PetDetailView` y `DispenserBloc`: al intentar desactivar o eliminar sin conexión, el BLoC emite `DispenserFailure` conservando el dispensador en el estado (`dispenser: _lastLoadedDispenser`) para evitar que la UI borre la tarjeta visualmente, y `PetDetailView` muestra correctamente el componente reutilizable `AppNoticeDialog`.
  * Pruebas completas: 52 pytest y 98 flutter test en verde. Flutter analyze limpio en `lib/`.

## Decisiones (y por qué)
- Preservar la base de datos local Isar en logout para cumplir estrictamente con el principio Offline-First.
- Validación de cambio de usuario en `UserRepositoriesImpl.login` para limpiar Isar únicamente cuando cambia el email.
- Unicidad de MAC garantizada tanto a nivel de servicio como de base de datos con `mac_normalized`.

## Aprendizajes y errores a evitar
- Nunca vaciar bases de datos locales en operaciones de cierre de sesión ordinarias.
- Las migraciones en SQLite se hacen en el listener `connect`. Las críticas (`mac_normalized`) propagan `RuntimeError`.
- `scrollable: true` en `AlertDialog` y constraints explícitas (`BoxConstraints`) para evitar overflow con fuentes grandes.

## Próximos pasos
- Spec 003 totalmente completada. Preparado para siguientes requerimientos del sistema.
