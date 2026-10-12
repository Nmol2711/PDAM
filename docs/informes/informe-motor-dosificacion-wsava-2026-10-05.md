# Informe — Motor de dosificación nutricional (WSAVA)

**Fecha:** 2026-10-05
**Alcance:** Cómo el sistema decide cuántos gramos debe consumir una mascota y a qué horas, partiendo de las nueve variables disponibles.
**Ubicación del cálculo:** `api/app/services/schedule_service.py:114` — `auto_generar_horarios_wsava()`
**Expuesto por:** `POST /api/v1/schedules/auto-generate/{pet_id}` (`api/app/api/endpoints/schedules.py:78`)
**UI que lo dispara:** `app/app_movil_pdam/lib/features/pets/presentation/views/guided_schedule_form_view.dart`

> **Este documento no corrige nada.** Describe el comportamiento existente verificado contra el código y documenta los límites que tiene. No propone ni ejecuta cambios.

---

## 1. Método de verificación

- Las nueve entradas se leyeron de la definición real del request (`api/app/schemas/schemas.py:134`) y del modelo `Pet` (`api/app/models/models.py:19`).
- Todas las cifras de los ejemplos de la sección 5 se obtuvieron **ejecutando la fórmula tal como está escrita en el servicio**, replicada paso a paso en Python. No son estimaciones de escritorio.
- No se ejecutó la API ni el firmware; la verificación es de código y de aritmética.

---

## 2. Las nueve entradas: qué se hace con cada una

### 2.1 Las cinco que pide el cliente

Definidas en `schemas.AutoScheduleRequest` (`api/app/schemas/schemas.py:134`). Todas llegan por el body del POST.

| # | Entrada | Tipo | Default | Papel en el cálculo | ¿Se persiste? |
|---|---|---|---|---|---|
| 1 | `food_kcal_per_kg` | `float` | — (obligatorio) | **Divisor de la ración.** Define cuántos gramos equivalen a 1 kcal de alimento | No |
| 2 | `bcs` | `int` | `5` | Corrector multiplicativo, **solo en extremos** (`:148-151`) | No |
| 3 | `mcs` | `str` | `"normal"` | Corrector multiplicativo, **solo `moderate` y `marked`** (`:153-157`) | No |
| 4 | `activity_level` | `str` | `"medium"` | Solo se lee para distinguir `"low"` del resto (`:136`, `:144`) | No |
| 5 | `meals_per_day` | `int` | `2` | Nº de horarios a crear y divisor de los gramos por comida (`:180`) | No |

Los valores admitidos de `mcs` (`normal`, `mild`, `moderate`, `marked`) y de `activity_level` (`low`, `medium`, `high`) los restringe únicamente el dropdown de la app (`guided_schedule_form_view.dart:158-163` y `:178-182`). El backend acepta cualquier string: no hay enum ni validador.

El móvil además **preselecciona** `meals_per_day`: 4 si la especie es felino, 2 en cualquier otro caso (`guided_schedule_form_view.dart:31-39`).

### 2.2 Las cuatro que salen de la base de datos

Modelo `Pet` (`api/app/models/models.py:19`). El servicio consulta una fila y toma estos cuatro campos:

| # | Campo | Tipo | Transformación | Peso real en la prescripción |
|---|---|---|---|---|
| 6 | `weight` | `Float` | Directo → exponente 0,75 | **Determinante.** Único valor realmente continuo de todo el modelo |
| 7 | `species` | `String` | `in` sobre el texto en minúsculas (`:131`, `:139`) | Decide qué tabla de factores se aplica |
| 8 | `birth_date` | `Date` | `días / 30.44` → meses (`:120-121`) | Solo decide si se cruza el umbral de 12 meses |
| 9 | `reproductive_status` | `Boolean` | Directo | True = castrado/esterilizado (`:127`) |

`name` y `path_url` se cargan en memoria pero no participan en ningún cálculo.

**No existe ningún otro dato.** La tabla `pets` no tiene raza, ni peso objetivo o ideal, ni fecha de castración, ni historial de peso, ni unidad de medida del peso, ni BCS/MCS almacenados, ni variedad de alimento. La lista blanca de variables de `AGENTS.md` está completa **por falta de datos disponibles**, no por descarte deliberado.

---

## 3. Datos que se estiman

Ninguno de los cinco campos del cliente se guarda. Lo que el motor **no recibe y se inventa** se divide en tres categorías.

### 3.1 Valores derivados (calculados, no supuestos)

| Derivado | Fórmula | Línea |
|---|---|---|
| Edad en meses | `(hoy − birth_date).days / 30.44` | `:120-121` |
| ¿En crecimiento? | `edad_meses < 12` → dos tramos: `< 4` y `4–12` | `:128`, `:133` |

### 3.2 Constantes y tablas fijas escritas en el código

Ninguna proviene de un documento WSAVA cargado en runtime; están literales en la función.

**Factores correctores del MER** (`:130-146`), valor por defecto `1.6` si la especie no coincide con ninguno de los patrones:

| Especie | Segmento | Factor |
|---|---|---|
| `canino` / contiene `dog` | < 4 meses | 3.0 |
| `canino` / contiene `dog` | 4–12 meses | 2.0 |
| `canino` / contiene `dog` | Adulto castrado, actividad `low` | 1.4 |
| `canino` / contiene `dog` | Adulto castrado, resto | 1.6 |
| `canino` / contiene `dog` | Adulto **entero** | 1.8 |
| `felino` / contiene `cat` | < 12 meses | 2.5 |
| `felino` / contiene `cat` | Adulto castrado, actividad `low` | 1.0 |
| `felino` / contiene `cat` | Adulto castrado, resto | 1.2 |
| `felino` / contiene `cat` | Adulto **entero** | 1.4 |

**Corrección por BCS** (`:148-151`): `bcs >= 7` → ×0.85 · `bcs <= 3` → ×1.15 · BCS 4, 5 y 6 → sin cambio.

**Corrección por MCS** (`:153-157`): `moderate` → ×1.05 · `marked` → ×1.10 · `normal` y `mild` → sin cambio.

**Requerimiento de agua** (`:163-165`): `peso × 44` a `peso × 66` ml/día. Es informativo; **no entra en la ración** y el backend no o usa para nada más.

**Tabla de horas** (`:182-194`): lista literal de horarios clock según el número de comidas.

| Comidas | Horarios generados |
|---|---|
| 1 | 08:00 |
| 2 | 08:00, 20:00 |
| 3 | 08:00, 14:00, 20:00 |
| 4 | 07:00, 12:00, 17:00, 21:00 |
| 5 | 07:00, 11:00, 15:00, 19:00, 22:00 |
| > 5 | 06:00, 09:30, 13:00, 16:30, 20:00, 23:00 |

### 3.3 Supuestos implícitos (decisiones no documentadas en el código)

1. **División equitativa.** Los gramos se reparten en partes iguales entre las comidas (`:180`). No pondera que la comida de la mañana sea mayor que la de la noche, ni que un felino coma menos por comida.
2. **`medium` y `high` son la misma cosa.** Solo existe una rama que compara con `"low"`; un perro de actividad alta recibe el mismo MER que uno moderado (`:136`, `:144`).
3. **`mcs: "mild"` no penaliza nada.** La escala de cuatro niveles de `AGENTS.md` está implementada a medias: el nivel más leve es el único sin efecto.
4. **BCS solo corrige en los extremos.** El rango 4–6, que incluye el ideal, no genera ninguna corrección ni ninguna distinction entre 4, 5 y 6.
5. **El umbral de crecimiento es 12 meses para las dos especies.** Un gato de 13 meses ya entra en la rama de adulto con factor 1.0–1.4; no hay tramo juvenil felino equivalente al de 4–12 meses del perro.
6. **`30.44` días por mes** es una convención astronómica, no veterinaria. Solo decide el salto del umbral de 12 meses, así que el error es de días en animales que están justo en el borde.
7. **La especie se resuelve por búsqueda de texto.** `species` es un `String` libre; el enum del móvil es `canino | felino | otros` (`app/app_movil_pdam/lib/core/constant/app_aplicacion.dart:3`). Un usuario que escriba `"Perro"` en la API no matchea `"canino"` ni `"dog"` y cae en el factor por defecto 1.6.
8. **Una sola densidad calórica para todo el día.** Se asume que el usuario consume un único alimento y que es igual en todas las comidas.
9. **Sin ajuste por temperatura, esterilización tardía, raza, pelo, enfermedad o medicación.** Ninguno de estos factores está en el modelo.
10. **Sin margen de seguridad.** El MER devuelto es el valor central exacto; no se aplica ni un porcentaje de vigencia ni un rango. La variabilidad se comunica como texto de advertencia, no como intervalo numérico (`:172-175`).
11. **El peso es una foto fija y sin fecha.** Si el usuario no actualiza `pets.weight`, el RER sigue calculándose sobre el peso antiguo y ningún aviso lo revela: no existe `weight_updated_at` con el que detectar la obsolescencia.

---

## 4. El cálculo, paso a paso

Con `w` = peso en kg, `d` = densidad calórica en kcal/kg, `n` = comidas/día, `f` = factor corrector final.

```
1.  edad_meses = (hoy − birth_date).days / 30.44              :120-121
2.  RER = 70 × w^0.75                                        :124
3.  f = factor_por_especie_edad_castración_actividad          :130-146
4.  si bcs >= 7  →  f ×= 0.85                                :149
    si bcs <= 3  →  f ×= 1.15                                :151
5.  si mcs == "moderate" → f ×= 1.05                        :155
    si mcs == "marked"   → f ×= 1.10                        :157
6.  MER = RER × f                                            :159
7.  gramos_día = (MER / d) × 1000                           :161
8.  agua = w × 44 … w × 66 ml                               :164-165
9.  warnings = [MCS anormal?, BCS fuera de 4-5?, ±30%/±50%]  :167-175
10. DELETE FROM schedules WHERE pet_id = ?                   :177
11. gramos_comida = round(gramos_día / n, 2)                 :180
12. INSERT (hora, gramos_comida) por cada hora de la tabla    :196-204
```

**Lo que significa cada bloque en términos prácticos:**

- **Paso 2** es el requerimiento en reposo puro: energía mínima del organismo en neutralidad termoneutral, con el exponente alométrico 0,75. No depende de nada que el usuario haya elegido.
- **Pasos 3-5** son multiplicadores que se acumulan. El orden importa: primero el factor de especie/edad, luego el cuerpo, luego el músculo.
- **Paso 7** es el paso donde el alimento entra al sistema. Todo el resto del cálculo es independiente del producto; la densidad calórica solo convierte energía en masa.
- **Paso 11** reparte. La suma de las comidas es exactamente `gramos_día` salvo el redondeo a 2 decimales.
- **Paso 12** es donde la prescripción se convierte en filas de la tabla `schedules`. A partir de ahí, el sistema ya no tiene idea de que hubo una fórmula: guarda solo `(time, amount)` en gramos.

**Estructura del resultado devuelto** (`schedule_service.py:210-218`, esquema en `schemas.py:141-151`): `rer`, `mer`, `daily_grams`, `water_min_ml`, `water_max_ml`, `warnings[]`, `schedules[]`.

---

## 5. Escenarios numéricos verificados

Todos calculados ejecutando la fórmula del servicio. `d = 3850 kcal/kg` salvo el caso J.

| Caso | Animal y entradas | RER | Factor | MER | g/día | g/comida | Agua ml/día |
|---|---|---|---|---|---|---|---|
| **A** | Canino 20 kg, 36 m, castrado, medium, BCS 5, normal, 2 comidas | 662,02 | 1,600 | 1059,23 | **275,12** | 137,56 (×2) | 880–1320 |
| B | *igual que A pero `activity_level = low`* | 662,02 | 1,400 | 926,83 | **240,73** | 120,37 (×2) | 880–1320 |
| C | *igual que A pero entero (no castrado)* | 662,02 | 1,800 | 1191,63 | **309,52** | 154,76 (×2) | 880–1320 |
| D | *igual que A pero BCS 9* | 662,02 | 1,360 | 900,35 | **233,86** | 116,93 (×2) | 880–1320 |
| E | *igual que A pero BCS 2 y MCS `marked`* | 662,02 | 2,024 | 1339,93 | **348,03** | 174,02 (×2) | 880–1320 |
| F | Felino 4 kg, 36 m, castrado, medium, BCS 5, normal, 4 comidas | 197,99 | 1,200 | 237,59 | **61,71** | 15,43 (×4) | 176–264 |
| G | *igual que F pero `activity_level = low`* | 197,99 | 1,000 | 197,99 | **51,43** | 12,86 (×4) | 176–264 |
| H | Canino 5 kg, 3 meses, medium, BCS 5, normal, 3900 kcal/kg, 3 comidas | 234,06 | 3,000 | 702,18 | **180,05** | 60,02 (×3) | 220–330 |
| I | Especie `"otros"`, 20 kg, 36 m, castrado, medium, BCS 5 | 662,02 | 1,600 | 1059,23 | **275,12** | 137,56 | 880–1320 |
| J | *igual que A pero `d = 3500 kcal/kg`* | 662,02 | 1,600 | 1059,23 | **302,64** | 151,32 | 880–1320 |

Lecturas relevantes:

- **A → B**: el nivel de actividad es la palanca más sensible del bloque canino adulto: 34,39 g/día de diferencia, un 12,5% sobre el total.
- **A → J**: un 9% menos de densidad calórica en la etiqueta produce 27,52 g/día **más** de alimento. La densidad es la palanca más potente de todas, y es el único campo de la lista blanca que el usuario teclea a mano sin ninguna ayuda ni validación de rango.
- **A → E**: el peor caso (BCS 2 + caquexia marcada) llega a 348,03 g/día, un 26,5% por encima de A.
- **H**: un cachorro de 5 kg y 3 meses con factor 3.0 recibe 180,05 g repartidos en 3 comidas de 60,02 g.
- **I**: el fallback de especie desconocida coincide exactamente con el canino adulto castrado.

---

## 6. Recorrido del caso A (ejemplo completo)

Mascota: canino, 20 kg, 3 años, castrado. Usuario: densidad 3850 kcal/kg, BCS 5, MCS normal, actividad medium, 2 comidas/día.

```
1. edad = 1095 días → 1095 / 30.44 = 35,98 meses   → no está en crecimiento
2. RER = 70 × 20^0.75 = 70 × 9,4574 = 662,02 kcal/día
3. canino + adulto + castrado + medium  →  f = 1,6
4. BCS 5 → ni >= 7 ni <= 3 →  f = 1,6
5. MCS normal → f = 1,6
6. MER = 662,02 × 1,6 = 1059,23 kcal/día
7. gramos = (1059,23 / 3850) × 1000 = 275,12 g/día
8. agua = 20 × 44 = 880 ml   ·   20 × 66 = 1320 ml
9. warnings = ["Nota: El MER en perros puede variar ±30% según metabolismo individual."]
```

Resultado en base de datos, tras borrar los horarios previos de la mascota:

| `time` | `amount` |
|---|---|
| 08:00 | 137,56 g |
| 20:00 | 137,56 g |

El ESP32 no ve nada de esto: cuando su ciclo de sondeo llega a hora de comida, el backend le devuelve únicamente el gramaje de esa comida (`api/app/api/endpoints/schedules.py:49`).

---

## 7. La fórmula existe en dos sitios y no coinciden

Además del backend, la app móvil recalcula una versión local para validar los horarios que el usuario teclea a mano (`app/app_movil_pdam/lib/features/pets/presentation/views/pet_detail_view.dart:406-445`).

**Diferencias:**

| Aspecto | Backend (`schedule_service.py`) | Cliente (`pet_detail_view.dart:406`) |
|---|---|---|
| Actividad | `low` baja el factor | **No la considera** (`:418-439`) |
| BCS | ×0.85 / ×1.15 | **No lo considera** |
| MCS | ×1.05 / ×1.10 | **No lo considera** |
| Densidad calórica | La envía el usuario | **Fija en 3850** (`:569`) |
| Castración | Distingue 1.4 / 1.6 / 1.8 | Distingue 1.6 / 1.8 |

Consecuencia medible sobre el mismo canino de 20 kg del caso A: el diálogo de validación manual siempre muestra 275,12 g como "límite WSAVA recomendado", y

| Situación real | Límite correcto (backend) | Límite que muestra la app | Error de la app |
|---|---|---|---|
| Castrado, actividad `low` (caso B) | 240,73 g | 275,12 g | **+14,3%** |
| Adulto entero (caso C) | 309,52 g | 275,12 g | **−11,1%** |
| BCS 9 (caso D) | 233,86 g | 275,12 g | **+17,6%** |
| BCS 2 + MCS `marked` (caso E) | 348,03 g | 275,12 g | **−20,9%** |

Ese valor se usa para bloquear la creación del horario si el total planeado lo supera en más de 50 g (`:572`) o para mostrar una advertencia si lo supera en cualquier cantidad (`:595`). Es decir, la validación manual de la app puede bloquear un horario que el motor automático generaría sin problema, o permitir uno que excede el cálculo real.

---

## 8. Qué se informa al usuario y qué se descarta

**El backend sí comunica** (`:167-175`) tres advertencias:

- MCS distinto de `normal` → riesgo de desequilibrio metabólico, sugiere evaluación veterinaria.
- BCS ≥ 7 o ≤ 3 → condición fuera del rango ideal 4-5, y se ajustó el requerimiento.
- **Variabilidad ±30% en perros y ±50% en gatos**, según especie. Es el único punto del módulo que cumple el requisito de variabilidad de `AGENTS.md`, y se cumple como cadena de texto.

**El cliente las descarta todas.** El datasource solo lee la clave `schedules` de la respuesta (`app/app_movil_pdam/lib/features/pets/data/datasource/remote/schedule_remote_datasource.dart:110-113`). Ni `rer`, ni `mer`, ni `daily_grams`, ni `warnings` llegan a la UI.

La tarjeta que el móvil muestra al terminar (`generated_schedules_list_widget.dart:46-66`) solo lista hora y gramos, más una línea de agua recalculada **en local** con `peso × 44/66` (`guided_schedule_form_view.dart:68-69`) en lugar de usar los valores del servidor.

**Trazabilidad: nula.** De un plan generado no queda registro de qué se usó. La tabla `schedules` solo guarda `time` y `amount` en gramos (`api/app/models/models.py:61`); no hay RER, ni MER, ni densidad, ni BCS/MCS, ni fecha de generación. Regenerar el mismo plan mañana parte de los valores tecleados hoy, no de lo que realmente se dispensó.

---

## 9. Límites del cálculo en ejecución

Hallazgos que afectan directamente a la fiable del resultado, todos verificados en el código:

1. **`food_kcal_per_kg = 0` → división por cero** en `:161`. No hay validador en el schema.
2. **`meals_per_day = 0` → división por cero** en `:180`.
3. **`meals_per_day` sin cota superior.** El schema acepta `7`; la tabla de horas solo tiene 6 entradas y el slicing `horas_sugeridas[:meals]` (`:197`) crea **6 comidas** mientras los gramos se dividen entre **7**. El plan queda subalimentado de forma silenciosa.
4. **`bcs` sin cota 1–9.** `AutoScheduleRequest` no valida el rango; un `bcs = 50` aplicaría la corrección de sobrepeso sin contexto.
5. **`mcs` y `activity_level` sin enum.** Cualquier string que no sea `moderate`, `marked` o `low` cae en la rama por defecto sin avisar.
6. **Destrucción previa sin copia de seguridad** (`:177`): se borran todos los horarios de la mascota antes de insertar los nuevos. Jeżeli la inserción falla, el plan anterior ya no existe.
7. **Sin validación en backend del horario manual.** El límite de 50 g de la app solo existe en el cliente; cualquiera que llame a `POST /schedules/` puede registrar la porción que quiera.

---

## 10. Corrección al informe de auditoría de 2026-10-04

El hallazgo **V-01** de `docs/informes/informe-auditoria-2026-10-04.md:31` afirma que "no existe ninguna implementación de RER/MER, ni de densidad calórica, ni de BCS/MCS". **Esa verificación es incorrecta.** El módulo existe desde los primeros commits del backend (`git log -- api/app/services/schedule_service.py` → `9a25dd2`, `37b2dc5`) y calcula RER, MER, densidad calórica, BCS y MCS en `schedule_service.py:114-218`.

Lo que sí es cierto del hallazgo es lo que sigue en pie, y este informe lo confirma:

- El **techo de snacks del 10% del MER con bloqueo o alerta no existe en ninguna capa**, y no es solo un bug de implementación: el campo de entrada `snack_kcal` tampoco existe, así que la regla de negocio no tiene insumo posible. El `MER × 0.10` de `AGENTS.md` es hoy una especificación sin datos que consumir.
- La **estandarización volumétrica a 8 oz / 237 ml** no está implementada; el sistema solo trabaja en gramos.
- El módulo **no tiene tests**. `api/tests/` no contiene ningún caso que ejercite `auto_generar_horarios_wsava`.

V-01 debería reformularse como "módulo nutricional implementado y sin cobertura de tests, con la regla de snacks del 10% sin insumo de datos".

---

## 11. Fuentes

- Backend: `api/app/services/schedule_service.py:114-218`, `api/app/schemas/schemas.py:134-151`, `api/app/models/models.py:19-35`, `api/app/api/endpoints/schedules.py:78-85`
- Móvil: `guided_schedule_form_view.dart`, `pet_detail_view.dart:406-445` y `:562-624`, `generated_schedules_list_widget.dart`, `schedule_remote_datasource.dart:110-113`, `schedule_repository_impl.dart:110-139`, `core/constant/app_aplicacion.dart:3`
- Normativa interna: `AGENTS.md`, sección "Módulo de Dosificación Nutricional"
- Auditoría previa: `docs/informes/informe-auditoria-2026-10-04.md`
