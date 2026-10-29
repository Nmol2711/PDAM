"""Endpoints del historial de actividad (spec 014, plan §2.4 y §5.3, §5.4).

`GET /logs/` consulta el historial del usuario autenticado con cuatro filtros
combinables y paginación; `GET /logs/catalog` publica los tipos de evento y los
resultados con sus etiquetas para poblar los filtros de la app.

Los parámetros de consulta se declaran como texto a propósito: la validación de
negocio se hace en el servicio, así que un valor inválido responde 400 con el
código del catálogo de errores y nunca un 422 (RF-31, RF-32, RNF-7). El alta
libre de registros se retiró en T6: el historial solo lo escribe el servidor en
la transacción de cada operación (RF-2).
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser
from app.db.database import get_db
from app.domain.catalogos import ErrorDominio
from app.schemas.logs import ActivityLogCatalog, ActivityLogPage
from app.services import logs_service

router = APIRouter()


def _error_de_negocio(error: ErrorDominio) -> HTTPException:
    """Convierte un rechazo de dominio en el 400 del catálogo de errores."""
    return HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=error.detail)


@router.get("/", response_model=ActivityLogPage)
def obtener_mis_logs(
    current_user: CurrentUser,
    db: Session = Depends(get_db),
    pet_id: Optional[str] = Query(None, description="Filtro por mascota."),
    event_type: Optional[str] = Query(
        None, description="Tipo de evento del catálogo cerrado."
    ),
    outcome: Optional[str] = Query(
        None, description="Resultado del catálogo cerrado."
    ),
    desde: Optional[str] = Query(
        None, alias="from", description="Instante inicial ISO 8601 con desplazamiento."
    ),
    hasta: Optional[str] = Query(
        None, alias="to", description="Instante final ISO 8601 con desplazamiento."
    ),
    page: Optional[str] = Query(None, description="Página, desde 1."),
    page_size: Optional[str] = Query(
        None, description="Tamaño de página, entre 1 y 100."
    ),
):
    """Historial del usuario autenticado, con filtros y paginación (RF-26 a RF-32)."""
    try:
        return logs_service.consultar(
            db,
            user_id=current_user.id,
            pet_id=pet_id,
            tipo_evento=event_type,
            resultado=outcome,
            desde=desde,
            hasta=hasta,
            pagina=page,
            tamano=page_size,
        )
    except ErrorDominio as error:
        raise _error_de_negocio(error) from None


@router.get("/catalog", response_model=ActivityLogCatalog)
def obtener_catalogo(current_user: CurrentUser):
    """Tipos de evento y resultados con etiqueta para los filtros (RF-31)."""
    return logs_service.catalogo()
