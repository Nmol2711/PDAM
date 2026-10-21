# Veredicto Reviewer — Spec 007

## Resumen general
**VEREDICTO: CAMBIOS NECESARIOS**

La implementación backend cumple la mayoría de los requerimientos funcionales (RF-2, RF-3, RF-4) y todos los tests unitarios pasan en verde (58/58). Sin embargo, existe un incumplimiento crítico en RF-1 que requiere atención.

## Detalle por RF

### RF-1: ⚠️ PARCIALMENTE CUMPLIDA
- **Problema:** El backend no convierte de kg a gramos. El esquema `DispenserRefillRequest` recibe `current_food_grams` asumiendo gramos puros.
- **Spec:** *"CUANDO el usuario ingresa una cantidad de alimento al reabastecer el dispensador especificando la unidad (gramos o kilogramos), EL SISTEMA valida y realiza la conversión interna a gramos"*.
- **Hueco actual:** Si alguien envía `6.0` sin convertir, la validación `le=5000.0` lo aceptaría como 6.0g en lugar de rechazarlo como exceso de kg.
- **Ubicación:** `api/app/schemas/dispenser.py` (`DispenserRefillRequest`), `api/app/services/dispenser_service.py` (`refill_dispenser`).
- **Notas:** El plan.md muestra `convertAndValidateRefill` en Dart (frontend), pero el backend debería manejar o documentar claramente el flujo. Se sugiere agregar campo `unit` al esquema o robustecer la validación.

### RF-2: ✅ CUMPLIDA
- Validación de límite 5000g funciona en esquema y servicio.
- Tests: `test_refill_request_valid_amounts`, `test_refill_request_invalid_amounts` ✅

### RF-3: ✅ CUMPLIDA
- Backend actualiza `current_food_grams` en SQLite al registrarse reabastecimiento.
- Flujo offline-first cubierto en frontend (Isar), backend OK.

### RF-4: ✅ CUMPLIDA
- `check_pending_task` descuenta y acota a 0 gramos automáticamente.
- Test: `test_check_pending_task_discounts_food_automatically` ✅

## Constitución (docs/constitution.md)
- ✅ Clean Architecture respetada
- ✅ Todos los tests pasan en verde (58/58)
- ✅ Sin hardcodeos arbitrarios
- ✅ Idioma español en mensajes

## Tests ejecutados
```
cd /home/deox/development/Projects/PDAM/api && source venv/bin/activate && python -m pytest tests/ -v
# Resultado: 58 passed, 109 subtests passed en 2.37s
```

## Archivo generado
REVIEWER_VERDICT_007.md