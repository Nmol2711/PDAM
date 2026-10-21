# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
* #### Spec 007 (Sistema de Estimación de Alimento Restante Sin Sensor y Notificaciones In-App Reutilizables) — **Completado, Corregido y Verificado al 100%**
  * Corrección de falso positivo en banner offline (`isOfflineCached` ya no está forzado a true en el repositorio local).
  * Corrección en el reabastecimiento (`refillFood`) para establecer directamente la cantidad ingresada en el depósito.
  * T1 & T2: Backend implementado con campo `current_food_grams`, validación de límite de 5kg y descuento automático. `pytest` pasando 58/58 en verde.
  * T3: Entidad de dominio `DispenserFoodStatus` y funciones puras de conversión (g/kg con límite 5kg) y cálculo de raciones (`calculateRemainingRations`, `convertAndValidateRefill`, `applyDispensationDiscount`) con tests unitarios en verde.
  * T4: Modelo Isar `LocalDispenser` actualizado con `currentFoodGrams` y `isOfflineCached`, con estrategia *Offline-First* en `DispensersRepositoryImpl`.
  * T5: Componente reutilizable `InAppNotificationBanner` y barra de progreso minimalista `DispenserFoodProgressBar` con cambio a color de advertencia cuando < 20%.
  * T6: `DispensersBloc` actualizado con eventos y manejadores de reabastecimiento (`RefillFoodEvent`) y descuento de stock.
  * T7: Interfaz de usuario (`DeviceCardWidget`, modales de reabastecimiento con selección g/kg y validación de 5kg, "más detalles" de raciones y banner no invasivo de sincronización local).
  * `flutter test` pasando 108/108 tests en verde.

## Decisiones (y por qué)
* Uso de Isar y arquitectura Offline-First para persistencia local de stock de alimento.
* Notificaciones in-app locales y modulares en lugar de servicios push externos (cumpliendo RNF-3).
* Validación matemática estricta de 5,000 g (5 kg) en reabastecimientos.

## Aprendizajes y errores a evitar
* Ejecutar build_runner siempre que se modifiquen modelos de Isar (`LocalDispenser`).
* Mantener textos en español y diseño Material 3 acorde a la constitución del proyecto.

## Próximos pasos
* T8 (Pruebas unitarias y de widgets en Flutter adicionales) y T9 (Verificación integral).
