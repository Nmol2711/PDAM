"""Escritura del registro de actividad de la spec 014.

Un único punto para crear filas de `logs`: valida los códigos contra los
catálogos cerrados, enmascara la MAC y serializa el contexto en español. No
decide el resultado de ninguna operación ni aplica cambios de estado.

`registrar` **no** confirma la transacción: el llamador hace el `commit` de su
propia operación, de modo que el registro y el cambio que lo origina son
atómicos (RF-1). `registrar_rechazo` es la excepción que exigen RF-12 y RF-21:
escribe en una sesión independiente y confirma, para que el rechazo persista
aunque la operación rechazada no se confirme.

`a_item` es la lectura simétrica: convierte una fila en el ítem del contrato de
consulta con sus etiquetas en español (T7).
"""

import json
from datetime import datetime
from typing import Any, Optional

from sqlalchemy.orm import Session

from app.db.database import SessionLocal
from app.domain import catalogos, tiempo
from app.models import models
from app.schemas import logs as schemas_logs
from app.services.mac_service import mask_mac

# Texto con el que se registra un dato que no está disponible, en lugar de
# omitirlo del contexto (RF-24).
NO_DISPONIBLE = "no disponible"


def texto_de_contexto(contexto: Optional[dict[str, Any]]) -> Optional[str]:
    """Serializa el contexto del evento como JSON con claves en español."""
    if contexto is None:
        return None
    return json.dumps(contexto, ensure_ascii=False, default=float)


def contexto_desde_texto(texto: Optional[str]) -> Optional[dict[str, Any]]:
    """Recupera el contexto guardado; `None` o un JSON ilegible quedan vacíos."""
    if not texto:
        return None
    try:
        datos = json.loads(texto)
    except (TypeError, ValueError):
        return None
    return datos if isinstance(datos, dict) else None


def a_item(registro: models.ActivityLog) -> schemas_logs.ActivityLogItem:
    """Serializa un registro con sus etiquetas en español (RF-26, RF-41, RNF-8).

    Los históricos sin tipo reciben «Sin clasificar» como etiqueta de evento y
    dejan sus etiquetas de resultado y causa en `None`; la fecha se devuelve en
    UTC con sufijo `Z`. La MAC completa nunca sale de aquí porque la columna ya
    guarda solo la forma parcial (RF-3, RNF-1).
    """
    contexto = contexto_desde_texto(registro.context)

    return schemas_logs.ActivityLogItem(
        id=registro.id,
        created_at=tiempo.a_texto_utc(registro.created_at),
        event_type=registro.event_type,
        event_label=catalogos.etiqueta_tipo_evento(registro.event_type),
        outcome=registro.outcome,
        outcome_label=catalogos.etiqueta_resultado(registro.outcome),
        cause=registro.cause,
        cause_label=catalogos.etiqueta_causa(registro.cause),
        description=registro.description,
        pet_id=registro.pet_id,
        pet_name=registro.pet_name,
        dispenser_mac_masked=registro.dispenser_mac_masked,
        order_id=registro.order_id,
        requested_grams=registro.requested_grams,
        measured_grams=registro.measured_grams,
        discounted_grams=registro.discounted_grams,
        resulting_stock=registro.resulting_stock,
        retry_count=registro.retry_count,
        context=contexto,
    )


def registrar(
    db: Session,
    *,
    event_type: str,
    outcome: str,
    description: str,
    user_id: Optional[int] = None,
    pet_id: Optional[int] = None,
    pet_name: Optional[str] = None,
    dispenser_id: Optional[int] = None,
    dispenser_mac: Optional[str] = None,
    cause: Optional[str] = None,
    context: Optional[dict[str, Any]] = None,
    order_id: Optional[int] = None,
    requested_grams: Optional[float] = None,
    measured_grams: Optional[float] = None,
    discounted_grams: Optional[float] = None,
    resulting_stock: Optional[float] = None,
    retry_count: Optional[int] = None,
    created_at: Optional[datetime] = None,
) -> models.ActivityLog:
    """Añade el registro a la sesión (con `flush`) y lo devuelve sin confirmar.

    Lanza `ValueError` si un código no pertenece a su catálogo cerrado: sería un
    fallo de programación, no un rechazo de negocio (RNF-7). La MAC se guarda
    siempre en su forma parcial y la fecha es la del servidor en UTC naive
    (RF-3, RNF-1, RNF-8).
    """
    if not catalogos.es_tipo_valido(event_type):
        raise ValueError(f"Tipo de evento fuera del catálogo: {event_type!r}")
    if not catalogos.es_resultado_valido(outcome):
        raise ValueError(f"Resultado fuera del catálogo: {outcome!r}")
    if cause is not None and not catalogos.es_causa_valida(cause):
        raise ValueError(f"Causa fuera del catálogo: {cause!r}")
    if not isinstance(description, str) or not description.strip():
        raise ValueError("La descripción del registro no puede estar vacía")

    instante = tiempo.a_utc_naive(created_at or tiempo.ahora_utc())

    registro = models.ActivityLog(
        user_id=user_id,
        pet_id=pet_id,
        pet_name=pet_name,
        dispenser_id=dispenser_id,
        # Sin dispensador afectado no hay MAC que mostrar: el campo queda vacío en
        # lugar de guardar el prefijo suelto de una MAC inexistente.
        dispenser_mac_masked=mask_mac(dispenser_mac) if dispenser_mac else None,
        event_type=event_type,
        outcome=outcome,
        cause=cause,
        description=description,
        context=texto_de_contexto(context),
        order_id=order_id,
        requested_grams=requested_grams,
        measured_grams=measured_grams,
        discounted_grams=discounted_grams,
        resulting_stock=resulting_stock,
        retry_count=retry_count,
        created_at=instante,
    )

    db.add(registro)
    # `flush` entrega el identificador al llamador sin confirmar la transacción.
    db.flush()
    return registro


def registrar_rechazo(**kwargs: Any) -> models.ActivityLog:
    """Escribe y confirma un registro de rechazo en una sesión independiente.

    Se usa para los rechazos que sí deben quedar registrados aunque la operación
    no se confirme: el reabastecimiento rechazado (RF-12) y el reporte de una
    orden desconocida (RF-21). Acepta los mismos argumentos que `registrar`.
    """
    db = SessionLocal()
    try:
        registro = registrar(db, **kwargs)
        db.commit()
        db.refresh(registro)
        return registro
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
