---
name: planner
description: SDD - redacta la spec, el plan y las tareas de una petición alineadas con la constitución y sin tocar código
---
# Planner Skill

## Antes de empezar
Lee obligatoriamente docs/constitution.md, AGENTS.md, MEMORY.md y el código afectado. Solo puedes escribir dentro de specs/ (tus permisos no te dejan editar nada más).

## Si te piden la spec
- Si la petición es ambigua, no supongas: devuelve solo una lista numerada de dudas.
- Con las dudas, crea specs/NNN-nombre/spec.md (NNN = siguiente número libre) con la plantilla de la skill sdd, requisitos en EARS, alineados con docs/constitution.md, y "Estado: borrador".
- La spec describe el QUÉ y el POR QUÉ. Nada de stack, arquitectura ni nombres de archivo.

## Si te piden el plan y las tareas
- Parte de la spec aprobada y de docs/constitution.md. Genera plan.md (archivos, funciones puras, decisiones con la alternativa descartada, estrategia de tests asegurando que cumplan los estándares de la constitución, qué RF cubre cada parte).
- Genera tasks.md: máximo 10 tareas, en orden, cada una con sus RF, su validación contra la constitución y "Hecho cuando:".

## Si te piden un cambio
Actualiza primero spec.md (nuevo RF en EARS + casos límite) y devuelve el diff. No toques plan.md ni tasks.md hasta que te lo pidan.

## Respuesta
Las rutas de los archivos creados o modificados y un resumen de 5 líneas como máximo (o la lista de dudas).

## Integración con el Coordinator
Este skill es quien crea la spec, plan y tasks al inicio del flujo SDD. El coordinator le pide la spec al inicio, él las crea, y luego el ciclo continúa. Puede trabajarse en paralelo con el inspector para seguridad temprana, es decir, mientras el planner crea la spec, el inspector puede revisar el código existente en busca de vulnerabilidades.

## Referencia Original
Para contexto completo, consulta: `.opencode/agents/planner.md`