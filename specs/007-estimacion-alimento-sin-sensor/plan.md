# Plan Técnico — Spec 007: Sistema de Estimación de Alimento Restante (Sin Sensor) y Notificaciones In-App Reutilizables

## 1. Arquitectura y Archivos Modificados / Nuevos

### Backend (`api/`)
- **`api/app/models/dispenser.py`** (o equivalente): Añadir campo o propiedad de almacenamiento de stock de alimento (`current_food_grams`, float/int, por defecto 5000.0). **Cubre RF-3, RF-4**
- **`api/app/schemas/dispenser.py`**: Actualizar esquemas Pydantic (`DispenserResponse`, `DispenserUpdate`, `DispenserRefillRequest`) para incluir `current_food_grams` con validación de límite máximo de 5000g. **Cubre RF-1, RF-2, RF-3**
- **`api/app/services/dispenser_service.py`**: Lógica de negocio para procesar reabastecimiento (validando límite de 5kg), actualización de stock y descuento automático tras un evento de dispensación exitosa. **Cubre RF-1, RF-2, RF-3, RF-4**

### Frontend (`app/app_movil_pdam/`)
- **`lib/core/presentation/widgets/in_app_notification_banner.dart` (Nuevo):** Componente reutilizable de notificaciones *in-app* para mostrar alertas flotantes o banners de bajo nivel (< 20%) y eventos del sistema. **Cubre RF-5, RF-6, RNF-3**
- **`lib/features/dispensers/domain/entities/dispenser_food_status.dart` (Nuevo):** Entidad de dominio que encapsula el stock actual, capacidad máxima (5000g), cálculo de porcentaje restante, estado crítico (< 20%) y cálculo de raciones restantes basándose en los `schedules`. **Cubre RF-5, RF-7**
- **`lib/features/dispensers/domain/usecases/`**: Casos de uso para reabastecer alimento (con conversión g/kg y validación de 5kg), calcular raciones restantes y consultar estado *offline-first*. **Cubre RF-1, RF-2, RF-3, RF-7**
- **`lib/features/dispensers/data/models/local_dispenser_model.dart`**: Actualizar esquema Isar para persistir `current_food_grams` y estado de sincronización *offline-first*. **Cubre RF-3, RF-8**
- **`lib/features/dispensers/data/repositories/dispenser_repository_impl.dart`**: Repositorio con estrategia *Offline-First* (Isar + API remota) y emisión de aviso no invasivo cuando se usan datos locales sincronizados previamente. **Cubre RF-3, RF-8**
- **`lib/features/dispensers/presentation/bloc/dispenser_bloc.dart`**: Gestión de estados para reabastecimiento, cálculo de raciones, control de umbral crítico y manejo de notificaciones *in-app*. **Cubre RF-1, RF-2, RF-3, RF-4, RF-5, RF-7, RF-8**
- **`lib/features/dispensers/presentation/views/dispenser_detail_view.dart` & `widgets/`**: Vista de detalles del dispensador con barra de progreso minimalista, indicador de nivel crítico, botón de reabastecimiento (con selector g/kg y validación 5kg), vista de raciones restantes y banner de sincronización *offline-first* no invasivo. **Cubre RF-1, RF-2, RF-5, RF-7, RF-8**

---

## 2. Funciones Puras y Algoritmos (Pseudocódigo)

### A. Conversión y Validación de Reabastecimiento
```dart
double convertAndValidateRefill(double amount, String unit) {
  double grams = unit == 'kg' ? amount * 1000.0 : amount;
  if (grams <= 0) throw ArgumentError('El reabastecimiento debe ser mayor a cero.');
  if (grams > 5000.0) throw ArgumentError('La capacidad máxima es de 5 kg (5000 g).');
  return grams;
}
```
*Cubre RF-1, RF-2*

### B. Cálculo de Raciones Restantes
```dart
int calculateRemainingRations(double currentFoodGrams, List<ScheduledMeal> schedules) {
  if (currentFoodGrams <= 0 || schedules.isEmpty) return 0;
  double dailyConsumption = schedules.fold(0.0, (sum, meal) => sum + meal.portionGrams);
  if (dailyConsumption <= 0) return 0;
  // Promedio por ración o estimación total de raciones restantes
  double averagePortion = dailyConsumption / schedules.length;
  return (currentFoodGrams / averagePortion).floor();
}
```
*Cubre RF-7*

### C. Descuento Automático de Stock
```dart
double applyDispensationDiscount(double currentStockGrams, double dispensedGrams) {
  double newStock = currentStockGrams - dispensedGrams;
  return newStock < 0 ? 0.0 : newStock;
}
```
*Cubre RF-4*

---

## 3. Decisiones Técnicas y Alternativas Descartadas

1. **Uso de Isar para Offline-First en lugar de almacenamiento volátil:**
   - *Decisión:* Persistir el stock de alimento localmente con Isar.
   - *Alternativa descartada:* Guardar únicamente en memoria o depender 100% de la API remota. Descartada por la exigencia de la arquitectura *Offline-First* de la constitución del proyecto.
2. **Notificaciones In-App locales en lugar de Firebase Push:**
   - *Decisión:* Implementar banners y componentes visuales reactivos (*in-app*) gestionados por el BLoC y Isar.
   - *Alternativa descartada:* Firebase Cloud Messaging (FCM). Descartada para evitar dependencias externas complejas y cumplir con RNF-3.
3. **Conversión y validación estricta de 5kg (5000g):**
   - *Decisión:* Permitir ingreso en g o kg con validación matemática exacta en la capa de dominio/esquemas.
   - *Alternativa descartada:* Permitir valores ilimitados. Descartada porque el depósito físico tiene un límite técnico de 5 kg.

---

## 4. Estrategia de Tests

- **Backend (Python / Pytest):**
  - Pruebas unitarias para la validación del límite de 5000g en esquemas y servicios.
  - Pruebas unitarias para el descuento automático de stock tras una dispensación exitosa.
- **Frontend (Flutter / Test):**
  - Pruebas unitarias para funciones puras de conversión (g a kg), validación de 5kg y cálculo de raciones restantes.
  - Pruebas de BLoC y Widgets para el comportamiento *offline-first*, visualización de barra de progreso crítica (< 20%), banner de sincronización no invasivo y visualización del componente de notificaciones *in-app*.
