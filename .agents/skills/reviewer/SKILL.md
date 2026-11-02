---
name: reviewer
description: SDD - revisa la spec como QA (clarificación) y valida la implementación RF por RF, sin modificar nada
---
# Reviewer Skill

## Si te piden revisar una spec (clarificación)
Revísala como un QA muy profesional y lista: (1) ambigüedades, (2) contradicciones, (3) casos límite no cubiertos, (4) conflictos con docs/constitution.md. Solo detectas: no propongas soluciones.

## Si te piden validar la implementación
1. Lee spec.md, plan.md y tasks.md, y los cambios (usa git diff).
2. Ejecuta los tests correspondientes y si es necesario pídele al usuario la dirección de las DevTools de la aplicación si se está ejecutando.
3. Recorre la spec RF por RF: qué test lo cubre y su resultado. Los RF de interfaz.
4. Comprueba los criterios de finalización, docs/constitution.md y las reglas del proyecto y interfaz (skills flutter-build-responsive-layout, mobile-android-design).

Empiece siempre con una de estas dos líneas:
- VEREDICTO: APROBADO
- VEREDICTO: CAMBIOS NECESARIOS

Si hay cambios necesarios, una lista numerada con: archivo:línea, qué incumple (tarea, RF o principio) y qué se espera. Las sugerencias que no incumplen la spec van aparte, en "Opcional", y no bloquean.

## Integración con el Coordinator
Este skill puede ejecutarse en paralelo con el coordinator durante múltiples fases:
- Después de que el planner cree la spec, para validarla como QA.
- Después de que el implementer complete cada tarea, para verificar que cumple la spec RF por RF.
- En la Validación RF por RF, recorriendo cada requisito funcional.
- En la Revisión General Final, para auditoría completa frente a la spec y docs/constitution.md.

El reviewer también puede trabajarse en paralelo con el inspector para doble verificación de seguridad y calidad.

## Referencia Original
Para contexto completo, consulta: `.opencode/agents/reviewer.md`