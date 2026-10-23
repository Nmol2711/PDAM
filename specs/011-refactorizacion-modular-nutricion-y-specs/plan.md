# Plan 011 — Refactorización Modular, Motor Nutricional WSAVA y Sincronización de Especificaciones

## 1. Arquitectura y Archivos Afectados

Siguiendo la Constitución del proyecto (`docs/constitution.md`) y la Clean Architecture (Clean Architecture absoluta, separación estricta de lógica de negocio y presentación, offline-first en frontend con Isar y BLoC, y FastAPI en backend), los archivos afectados y sus responsabilidades son:

### Backend (FastAPI - Python)
- **`api/app/schemas/nutrition_schemas.py`**: Esquemas Pydantic para validación estricta de entradas (BW, densidad calórica, BCS, MCS, nivel de actividad, estatus reproductivo, etapa de vida, comidas diarias y snacks). Cubre RF-1, RF-2.
- **`api/app/services/nutrition_service.py`**: Lógica de negocio pura para el motor WSAVA (cálculo de RER, MER con factores correctores, validación de variabilidad ±30%/±50%, evaluación del límite de snacks al 10% del MER con recálculo de ración principal, y ración diaria exclusivamente ponderal en gramos). Es la **única fuente de verdad** del cálculo en backend; `schedule_service` delega en él. Cubre RF-3, RNF-4.
- **`api/app/api/endpoints/nutrition.py`**: Endpoint de API REST del motor nutricional para clientes del backend. **No lo consume la app móvil** (el cálculo es local). Cubre RF-4.
- **`api/app/services/schedule_service.py`**: `auto_generar_horarios_wsava` delega en `nutrition_service.calculate_nutrition` conservando su contrato externo (firma, respuesta de horarios, advertencias y agua). Elimina la fórmula WSAVA paralela. Cubre RF-3, RNF-4.
- **`api/tests/test_nutrition.py`**: Pruebas unitarias con `pytest` cubriendo todos los casos límite y fórmulas WSAVA. Criterios de finalización.

### Frontend (Flutter - Dart)
- **`app/app_movil_pdam/lib/features/nutrition/domain/entities/`**: Entidades y motor WSAVA puro en Dart (`wsava_engine.dart`), mismo algoritmo y tablas que el backend. Cubre RF-3, RF-4, RNF-4.
- **`app/app_movil_pdam/lib/features/nutrition/domain/usecases/calculate_nutrition_usecase.dart`**: Caso de uso de cálculo nutricional (cálculo local, sin red). Cubre RF-3, RF-4.
- **`app/app_movil_pdam/lib/features/pets/presentation/views/pet_detail_view.dart`**: Sustituye la fórmula WSAVA embebida por el caso de uso/motor de dominio Dart. La vista solo presenta resultados. Cubre RF-3, RNF-2, RNF-4.
- **`app/app_movil_pdam/lib/features/nutrition/presentation/bloc/`**: `NutritionCubit` para la gestión de estado de la calculadora nutricional (separando vista de lógica). Cubre RF-4.
- **`app/app_movil_pdam/lib/features/nutrition/presentation/views/`** y **`widgets/`**: Pantallas y widgets limpios sin lógica de negocio incrustada. Cubre RF-4.
- **`app/app_movil_pdam/lib/core/router/app_router.dart`** y punto de entrada visible (`features/dashboard/presentation/views/dashboard_view.dart` o `core/presentation/widgets/main_navigation_shell.dart`): la ruta `nutrition_calculator` existe pero no es alcanzable; se añade un botón/acción visible que navega a ella. Cubre RF-6.
- **`app/app_movil_pdam/lib/features/dispenser/`**: Módulo unificado de dispensadores que integra aprovisionamiento BLE/WiFi y asociación por QR / dirección MAC sin duplicidades. Cubre RF-5.
- **`app/app_movil_pdam/test/features/nutrition/`** y **`app/app_movil_pdam/test/features/dispenser/`**: Pruebas unitarias, de contrato y de widgets con `flutter test`. Criterios de finalización.

### Prueba de contrato compartida (RF-4)
- **`specs/011-refactorizacion-modular-nutricion-y-specs/fixtures/nutrition_contract_cases.json`**: Fixture canónico con casos de entrada válidos, límites y valores esperados (RER, MER, rango de variabilidad, límite de snacks, alerta, kcal finales y gramos). Es el mismo archivo para ambas suites; backend y app lo resuelven desde la raíz del repositorio.
- **`api/tests/test_nutrition_contract.py`**: Recorre el fixture y compara la salida de `nutrition_service.calculate_nutrition` con los valores esperados (tolerancia decimal explícita).
- **`app/app_movil_pdam/test/features/nutrition/nutrition_contract_test.dart`**: Recorre el mismo fixture y compara la salida del motor Dart, con la misma tolerancia.
- **Resolución del fixture:** cada suite localiza la raíz del repositorio desde su directorio de ejecución (`api/` → `../`, `app/app_movil_pdam/` → `../../`) y lee el JSON con `dart:io` / `json` en Python. No se duplica el archivo.
- Cualquier divergencia de fórmula o tabla rompe una de las dos suites, cumpliendo RF-4 sin llamadas de red.

### Sincronización y Trazabilidad de Specs (Specs 004 & 005)
- Verificación formal de la persistencia local Offline-First con Isar (Spec 004) y cobertura de pruebas de sistema (Spec 005) en los reportes de validación y documentación de memoria.

---

## 2. Funciones Puras y Algoritmo de Cálculo WSAVA

Para garantizar el determinismo (RNF-1), la lógica matemática se encapsulará en funciones puras (aceptando parámetros explícitos como `today` o fecha de referencia cuando aplique):

### A. Funciones de Validación Estricta (Boundary Validation)
- `validate_body_weight(bw: float) -> bool`: Retorna `True` si `bw > 0`.
- `validate_caloric_density(density: float) -> bool`: Retorna `True` si `density > 0`.
- `validate_meals_per_day(meals: int) -> bool`: Retorna `True` si `1 <= meals <= 6`.
- `validate_bcs(bcs: int) -> bool`: Retorna `True` si `1 <= bcs <= 9`.
- `validate_mcs(mcs: str) -> bool`: Retorna `True` si `mcs.lower() in ['normal', 'mild', 'moderate', 'marked']`.
- `validate_activity_level(activity: str) -> bool`: Retorna `True` si `activity.lower() in ['low', 'medium', 'high']`.
- `validate_reproductive_status(status: str) -> bool`: Retorna `True` si `status.lower() in ['entero', 'castrado', 'esterilizado']`.
- `validate_life_stage(stage: str) -> bool`: Retorna `True` si `stage.lower() in ['crecimiento', 'adulto']`.

### B. Motor WSAVA (Funciones Puras)
1. **Cálculo de RER (Requerimiento de Energía en Reposo):**
   $$\text{RER} = 70 \times \text{BW}^{0.75}$$
   (Función pura: `calculate_rer(bw: float) -> float`)

2. **Cálculo de MER (Requerimiento de Energía de Mantenimiento):**
   $$\text{MER} = \text{RER} \times \text{Factor Corrector}$$
   - El factor corrector se determina combinando especie, estatus reproductivo, etapa de vida y nivel de actividad según directrices WSAVA.
   (Función pura: `calculate_mer(rer: float, species: str, reproductive_status: str, life_stage: str, activity_level: str, bcs: int) -> float`)

3. **Notificación de Variabilidad Fisiológica:**
   - Perros: $\pm30\%$ ($\text{MER}_{\min} = \text{MER} \times 0.7$, $\text{MER}_{\max} = \text{MER} \times 1.3$)
   - Gatos: $\pm50\%$ ($\text{MER}_{\min} = \text{MER} \times 0.5$, $\text{MER}_{\max} = \text{MER} \times 1.5$)
   (Función pura: `get_variability_range(species: str, mer: float) -> Tuple[float, float]`)

4. **Evaluación de Límite de Snacks (10% Máximo):**
   - $\text{Snack\_Limit} = \text{MER} \times 0.10$
   - Si $\text{User\_Snacks\_Kcal} > \text{Snack\_Limit}$: se emite únicamente un indicador de **alerta visual** (`exceeds_limit = True`). No se bloquea el cálculo ni el guardado.
   - Recálculo de ración principal:
     $$\text{Final\_Ration\_Kcal} = \max(0.0, \text{MER} - \text{User\_Snacks\_Kcal})$$
   (Función pura: `evaluate_snacks(mer: float, user_snacks_kcal: float) -> Dict[str, Any]`)

5. **Determinación de Ración Diaria (solo ponderal, gramos):**
   $$\text{Ración Base (g/día)} = \frac{\text{Final\_Ration\_Kcal}}{\text{Caloric Density (kcal/kg)} / 1000}$$
   (Función pura: `calculate_daily_ration_grams(final_ration_kcal: float, caloric_density_kcal_per_kg: float) -> float`)

No se contempla conversión volumétrica (tazas) en el motor ni en la interfaz: la única unidad de ración es el gramo (RF-3).

---

## 3. Decisiones Arquitectónicas y Alternativas Descartadas

1. **Motor único con cálculo local y contrato compartido:**
   - *Decisión:* La app calcula siempre en local (Offline-First) y **nunca** pide el cálculo al servidor. La paridad se garantiza con un fixture de contrato único ejecutado por `pytest` y `flutter test`.
   - *Alternativa descartada:* Calcular en el servidor y sincronizar por red (rompe Offline-First y añade latencia/disponibilidad). También se descarta comparar ambos motores solo con tests unitarios separados: dos suites con casos distintos pueden pasar y aun así divergir; el fixture compartido lo impide.
2. **Unificación de fórmulas divergentes en backend:**
   - *Decisión:* `nutrition_service` es la única fuente de verdad; `schedule_service.auto_generar_horarios_wsava` delega en él y conserva su contrato externo (request/response y advertencias), añadiendo tests de regresión sobre los valores generados.
   - *Alternativa descartada:* Mantener la fórmula de `schedule_service` y “ajustarla” a mano (deja dos tablas que volverán a divergir; los factores actuales ya difieren del motor, p. ej. BCS 0.85/1.15 y MCS 1.05/1.10 frente a 0.8/1.2 y 0.95/0.9).
3. **Unificación de fórmulas divergentes en frontend:**
   - *Decisión:* `pet_detail_view.dart` consume el motor/caso de uso de dominio Dart; la vista queda sin fórmulas.
   - *Alternativa descartada:* Dejar el cálculo embebido en la vista (viola la separación lógica-interfaz de la constitución y duplica la fórmula).
4. **Punto de entrada a la calculadora:**
   - *Decisión:* Añadir un acceso visible (acción en dashboard o en la navegación principal) que navegue a la ruta existente `nutrition_calculator`, con prueba de widget que verifique que el acceso existe y navega.
   - *Alternativa descartada:* Dejar la ruta accesible solo por deep link/URL manual (funcionalidad invisible para el usuario, no cumple RF-6).
5. **Unificación del Módulo de Dispensadores en Flutter:**
   - *Decisión:* Consolidar los flujos BLE, WiFi, QR y MAC bajo una única estructura en `lib/features/dispenser/`, eliminando código duplicado legacy y manteniendo interfaces limpias.
   - *Alternativa descartada:* Mantener dos pantallas separadas (una para BLE y otra para QR) con lógica duplicada (generaba inconsistencias de estado y mantenimiento complejo).

---

## 4. Estrategia de Pruebas

- **Backend (`pytest`):**
  - Pruebas unitarias en `api/tests/test_nutrition.py` para cada función pura del motor WSAVA.
  - Pruebas de validación de límites (BW <= 0, densidad calórica negativa, BCS fuera de rango, snacks > 10% que solo alertan y recalculan).
  - Pruebas de integración para el endpoint REST de nutrición (para clientes del backend; la app no lo consume).
  - Pruebas de contrato en `api/tests/test_nutrition_contract.py` contra el fixture compartido.
  - Tests de regresión de `auto_generar_horarios_wsava` verificando que sus gramos/kcal y advertencias coinciden con el motor unificado.
- **Frontend (`flutter test`):**
  - Pruebas unitarias de entidades y casos de uso de nutrición en Dart.
  - Pruebas de contrato en `app/app_movil_pdam/test/features/nutrition/nutrition_contract_test.dart` contra el mismo fixture.
  - Prueba de regresión de `pet_detail_view` comprobando que usa el motor de dominio (mismos valores que el caso de uso, sin fórmula local).
  - Pruebas de `NutritionCubit` y del módulo unificado de dispensadores.
  - Prueba de widget del punto de entrada: el acceso visible existe y navega a `nutrition_calculator`.
  - Pruebas de widgets para asegurar que la interfaz muestra correctamente las alertas de snacks y los resultados de dosificación sin lógica espagueti.
- **Validación de Specs 004 y 005:**
  - Verificación mediante checklist de ejecución de pruebas del sistema y persistencia local Isar.
