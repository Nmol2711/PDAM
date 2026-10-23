# Spec 011 — Refactorización Modular, Motor Nutricional WSAVA y Sincronización de Especificaciones
Estado: implementada

## Contexto y objetivo
El sistema PDAM gestiona la dosificación nutricional para mascotas (perros y gatos) basada en estándares WSAVA, así como la gestión y aprovisionamiento de dispositivos dispensadores y la persistencia local. Actualmente, existen riesgos técnicos como la falta de validación de rangos numéricos en los parámetros de entrada del motor nutricional, divergencias en la fórmula de dosificación entre el servidor y la interfaz móvil, duplicidad en los módulos de dispensadores en el cliente (módulos legacy y de aprovisionamiento BLE/WiFi), y tareas pendientes en las especificaciones 004 y 005.

El objetivo de esta especificación es consolidar el motor de cálculo nutricional con validaciones estrictas y reglas WSAVA (límite de snacks al 10% del MER con alerta visual y recálculo, estatus reproductivo, etapa de vida y notificación de variabilidad), unificar la lógica de dosificación y la gestión de dispensadores (integrando asociación por código QR/MAC y aprovisionamiento BLE/WiFi sin duplicidades), y actualizar formalmente las tareas de validación en las especificaciones previas.

## Usuarios
- **Dueño de mascota / Usuario final:** Requiere cálculos nutricionales seguros basados en normas WSAVA, sin errores por entradas inválidas, y una interfaz de gestión de dispensadores unificada y fluida.
- **Desarrollador / Mantenedor del sistema:** Requiere código mantenible, sin duplicidades lógicas entre módulos de cliente, con validaciones robustas y trazabilidad completa de especificaciones.

## Historias de usuario
- HU-1. Como usuario del sistema, quiero que el motor de cálculo nutricional valide estrictamente todos los parámetros de entrada según los rangos permitidos y reglas WSAVA, para prevenir cálculos inconsistentes o riesgos nutricionales.
- HU-2. Como usuario de la aplicación móvil, quiero que la dosificación mostrada en la interfaz coincida exactamente con la lógica oficial del motor nutricional, para evitar discrepancias en la ración diaria de mi mascota.
- HU-3. Como usuario móvil, quiero gestionar mis dispensadores desde una interfaz unificada que integre asociación por código QR/MAC y aprovisionamiento BLE/WiFi, conservando todas las funciones sin duplicidades ni fallos de navegación.
- HU-4. Como mantenedor del proyecto, quiero verificar y cerrar formalmente las tareas pendientes en las especificaciones 004 y 005, asegurando la trazabilidad de la persistencia local y las pruebas del sistema.

## Definiciones
- **Motor WSAVA:** Algoritmo estandarizado para calcular los requerimientos energéticos de reposo (RER), mantenimiento (MER) incorporando factores correctores por estatus reproductivo (entero vs castrado/esterilizado) y etapa de vida (crecimiento <12 meses vs adulto), ración base exclusivamente en gramos (medición ponderal) y ajuste por snacks (máximo 10% del MER, que genera alerta visual y recálculo de la ración principal sin impedir el guardado), considerando la variabilidad fisiológica estimada (±30% en perros y ±50% en gatos).
- **Rangos de Parámetros Nutricionales:** 
  - Especie: Canino / Perro, Felino / Gato.
  - Peso Corporal (BW): Valor numérico estrictamente mayor a 0 (kg).
  - Condición Corporal (BCS): Escala numérica de 1 a 9.
  - Masa Muscular (MCS): Valores permitidos: normal, leve (mild), moderada (moderate), marcada (marked).
  - Nivel de Actividad: Valores permitidos: bajo (low), medio (medium), alto (high).
  - Estatus Reproductivo: Entero, Castrado / Esterilizado.
  - Etapa de Vida: Crecimiento (<12 meses), Adulto.
  - Comidas Diarias: Cota estricta `1 <= meals_per_day <= 6`.
- **Módulo Unificado de Dispensadores:** Estructura consolidada en la aplicación móvil que integra el aprovisionamiento BLE/WiFi y la asociación mediante códigos QR o dirección MAC, preservando todas las capacidades de activación, desactivación y borrado de dispositivos.
- **Trazabilidad de Especificaciones:** Alineación verificable entre el estado real del código y el cumplimiento de las tareas en las especificaciones históricas.

## Requisitos funcionales (EARS)
- RF-1: SI la densidad calórica es menor o igual a cero, las comidas diarias están fuera del rango `1 <= meals_per_day <= 6`, o el peso corporal (BW) es ausente, cero, negativo o no numérico, ENTONCES EL SISTEMA rechazará el cálculo de dosificación nutricional y retornará un error descriptivo.
- RF-2: SI la especie es vacía, desconocida o no corresponde a canino/perro o felino/gato, BCS está fuera de 1-9, MCS está fuera de los valores permitidos, el nivel de actividad está fuera de los valores permitidos, o el estatus reproductivo y etapa de vida son inválidos, ENTONCES EL SISTEMA validará y rechazará dichos valores con un mensaje de error explícito.
- RF-3: CUANDO el sistema reciba los parámetros válidos de especie, peso (BW), estatus reproductivo, etapa de vida, BCS, MCS, actividad, densidad calórica, comidas diarias y opcionalmente calorías por snacks, EL SISTEMA calculará el RER, el MER aplicando los factores correctores obligatorios por estatus reproductivo, etapa de vida y actividad, notificará el rango de variabilidad esperada (±30% perros / ±50% gatos), evaluará el límite de snacks al 10% máximo del MER emitiendo únicamente una alerta visual cuando se exceda (sin impedir el guardado de los datos), recalculará la ración principal restando el aporte calórico de los snacks (`Final_Ration_Kcal = MER - Snack_Kcal`) y determinará la ración diaria exclusivamente en gramos (medición ponderal).
- RF-4: EL SISTEMA calculará la dosificación nutricional localmente en la aplicación móvil (Offline-First), sin solicitar el cálculo al servidor; el motor del backend y el motor de la aplicación aplicarán las mismas fórmulas y tablas, y una prueba de contrato compartida (fixture de casos esperados consumido por las suites de backend y de la aplicación) detectará cualquier divergencia de resultados entre ambos.
- RF-5: CUANDO el usuario interactúe con la gestión de dispensadores en la aplicación móvil, EL SISTEMA proveerá un flujo unificado que integre tanto el aprovisionamiento BLE/WiFi como la asociación por código QR / dirección MAC, permitiendo asociar, activar, desactivar, borrar dispositivos y registrar equipos sin duplicidades funcionales.
- RF-6: EL SISTEMA ofrecerá un punto de entrada visible en la navegación de la aplicación móvil que permita al usuario acceder a la calculadora nutricional sin conocer rutas internas.

## Requisitos no funcionales
- RNF-1: **Estabilidad matemática y determinismo:** Ante idénticas entradas válidas, el motor nutricional producirá siempre el mismo resultado matemático exacto de manera determinista, previniendo excepciones no controladas.
- RNF-2: **Modularidad y Separación de Responsabilidades:** La unificación del módulo de dispensadores y del motor nutricional mantendrá una estricta separación entre la lógica de negocio y la interfaz visual, garantizando un código limpio y mantenible.
- RNF-3: **Trazabilidad y Cumplimiento Constitucional:** Todos los textos visibles y la interfaz cumplirán con el idioma español, y la documentación mantendrá una trazabilidad estricta conforme a la constitución del proyecto.
- RNF-4: **Fuente única de verdad nutricional:** Toda ruta del sistema que calcule dosificación (incluidos la generación automática de horarios y el detalle de mascota) usará el mismo motor y las mismas reglas, sin fórmulas paralelas ni valores duplicados.

## Casos límite
- Peso corporal (BW) ausente, en cero, negativo o no numérico.
- Especie vacía, desconocida o con valores fuera de canino/perro y felino/gato.
- Densidad calórica ausente, en cero o negativa.
- Frecuencia de comidas diarias en cero, número negativo o superior al límite de 6.
- Valores de BCS en 0, 10 o caracteres no numéricos.
- Valores de MCS, nivel de actividad, estatus reproductivo o etapa de vida con variaciones de texto no reconocidas o vacías.
- Aporte calórico de snacks superior al 10% del MER (debe emitir una alerta visual explícita y recalcular la ración principal, sin bloquear el guardado).

## Fuera de alcance
- Modificaciones estructurales al firmware del ESP32 más allá de la ejecución y verificación de pruebas del sistema. Se exceptúa explícitamente la extracción de lógica pura a utilidades testeables (sin cambios de comportamiento observable en el dispositivo).
- Migración del motor de base de datos de SQLite a PostgreSQL en el backend.

## Criterios de finalización
- Suite de pruebas unitarias del motor nutricional implementada y pasando al 100% con 0 errores de compilación o linter.
- Pruebas que validan explícitamente todos los casos límite (peso inválido, especie desconocida, densidad cero, BCS inválido, MCS/actividad/reproducción/etapa atípicos, snacks >10% con alerta y recálculo) superadas con éxito.
- Paridad de la fórmula y de los resultados entre el motor del backend y el de la aplicación verificada con una prueba de contrato compartida (mismo fixture ejecutado por `pytest` y `flutter test`) en verde.
- Módulo unificado de dispensadores funcional en la aplicación móvil integrando aprovisionamiento BLE/WiFi y asociación por QR/MAC con soporte verificado de asociación, activación, desactivación y borrado sin duplicidades.
- Punto de entrada visible que permite llegar a la calculadora nutricional desde la navegación, cubierto por una prueba de widget.
- Verificación formal de que las tareas de persistencia local (Spec 004) y pruebas del sistema (Spec 005) están ejecutadas y validadas exitosamente.

## Dudas abiertas
Ninguna.
