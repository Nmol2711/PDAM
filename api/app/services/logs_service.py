"""Consulta del historial de actividad (spec 014, T7).

Solo lectura y serialización: el historial lo escriben los servicios de cada
operación, nunca este módulo (RF-2). La validación de los filtros y de la
paginación se delega en `domain/consulta`, de modo que cualquier valor inválido
es un error del catálogo (HTTP 400) y nunca un 422 de FastAPI (RF-31, RF-32).

La consulta devuelve únicamente los registros del usuario autenticado, del más
reciente al más antiguo y con desempate por identificador para que la paginación
sea estable (RF-26). Los cuatro filtros se aplican en conjunción y los dos
extremos del rango son inclusivos (RF-27 a RF-31). Los registros históricos sin
tipo ni resultado se incluyen sin filtros y quedan fuera al filtrar por tipo o
resultado, porque `NULL` nunca coincide con un valor del catálogo (RF-41).
"""

from typing import Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.domain import catalogos, consulta
from app.models import models
from app.schemas.logs import (
    ActivityLogCatalog,
    ActivityLogCatalogEntry,
    ActivityLogPage,
)
from app.services import activity_service


def consultar(
    db: Session,
    *,
    user_id: int,
    pet_id: object = None,
    tipo_evento: object = None,
    resultado: object = None,
    desde: object = None,
    hasta: object = None,
    pagina: object = None,
    tamano: object = None,
) -> ActivityLogPage:
    """Consulta paginada del historial del usuario, con los cuatro filtros.

    Los parámetros llegan como texto desde la API y se validan aquí en el orden
    de rechazo del plan §5.3: `rango_fechas_invalido` → `tipo_evento_invalido` →
    `resultado_invalido` → `pagina_invalida` → `tamano_pagina_invalido`. Lanza
    `ErrorDominio` con el código del catálogo; el endpoint lo convierte en 400.

    `pet_id` no tiene código de error propio en el catálogo y no se inventa uno:
    un valor no numérico no puede corresponder a ninguna mascota, así que la
    consulta devuelve una página vacía con el total en 0 en lugar de ignorar el
    filtro en silencio.
    """
    validada = consulta.validar_consulta(
        tipo_evento=tipo_evento,
        resultado=resultado,
        desde=desde,
        hasta=hasta,
        pagina=pagina,
        tamano=tamano,
    )

    se_filtra_por_mascota, mascota = _filtro_por_mascota(pet_id)
    if se_filtra_por_mascota and mascota is None:
        return ActivityLogPage(
            items=[],
            total=0,
            page=validada.pagina,
            page_size=validada.tamano,
        )

    consulta_bd = db.query(models.ActivityLog).filter(
        models.ActivityLog.user_id == user_id
    )

    if mascota is not None:
        # Instantánea sin clave foránea: sigue filtrando tras borrar la mascota
        # (RF-27).
        consulta_bd = consulta_bd.filter(models.ActivityLog.pet_id == mascota)
    if validada.tipo_evento is not None:
        # `NULL` no coincide con ningún tipo: los históricos quedan fuera (RF-28).
        consulta_bd = consulta_bd.filter(
            models.ActivityLog.event_type == validada.tipo_evento
        )
    if validada.resultado is not None:
        # Igual con el resultado (RF-29).
        consulta_bd = consulta_bd.filter(
            models.ActivityLog.outcome == validada.resultado
        )
    if validada.desde is not None:
        consulta_bd = consulta_bd.filter(
            models.ActivityLog.created_at >= validada.desde
        )
    if validada.hasta is not None:
        # Extremo final inclusivo (RF-30).
        consulta_bd = consulta_bd.filter(
            models.ActivityLog.created_at <= validada.hasta
        )

    total = consulta_bd.count()

    registros = (
        consulta_bd.order_by(text(consulta.orden_estable()))
        .offset((validada.pagina - 1) * validada.tamano)
        .limit(validada.tamano)
        .all()
    )

    return ActivityLogPage(
        items=[activity_service.a_item(registro) for registro in registros],
        total=total,
        page=validada.pagina,
        page_size=validada.tamano,
    )


def catalogo() -> ActivityLogCatalog:
    """Catálogo cerrado de los filtros: tipos de evento y resultados (plan §5.4).

    No incluye causas: se muestran desde la etiqueta de cada registro. Servir el
    catálogo desde el servidor evita duplicar los códigos en la app (RNF-7).
    """
    return ActivityLogCatalog(
        event_types=[
            ActivityLogCatalogEntry(code=codigo, label=etiqueta)
            for codigo, etiqueta in catalogos.TIPOS_EVENTO.items()
        ],
        outcomes=[
            ActivityLogCatalogEntry(code=codigo, label=etiqueta)
            for codigo, etiqueta in catalogos.RESULTADOS.items()
        ],
    )


def _filtro_por_mascota(valor: object) -> tuple[bool, Optional[int]]:
    """Interpreta el filtro de mascota sin rechazar ni corregir el valor.

    Devuelve `(se_filtra, pet_id)`: sin valor no se filtra; con un entero se
    filtra por esa mascota; con cualquier otra cosa se filtra por una mascota
    inexistente, que se traduce en una página vacía. No hay código de error para
    este filtro y el catálogo no se amplía fuera de la spec (RNF-7).
    """
    if valor is None:
        return False, None
    if isinstance(valor, bool):
        return True, None
    if isinstance(valor, int):
        return True, valor

    texto = str(valor).strip()
    if not texto:
        return False, None
    try:
        return True, int(texto)
    except ValueError:
        return True, None
