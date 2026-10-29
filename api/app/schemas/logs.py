"""Contrato de la consulta del historial (spec 014, plan §5.3 y §5.4).

`GET /logs/` devuelve el sobre `{items,total,page,page_size}` con cada registro
ya etiquetado en español: las etiquetas se resuelven en el servidor a partir de
`domain/catalogos`, de modo que la app no duplica el catálogo cerrado (RNF-7) y
«Sin clasificar» tiene una única definición para los históricos (RF-41).

`GET /logs/catalog` publica solo tipos y resultados, que son los valores de los
filtros de la pantalla; las causas se muestran desde la etiqueta de cada ítem.

El instante `created_at` viaja como texto ISO 8601 en UTC con sufijo `Z`
(RNF-8): un tipo `str` describe exactamente lo que el cliente recibe.
"""

from typing import Any, List, Optional

from pydantic import BaseModel, Field, RootModel


class ActivityLogContext(RootModel[dict[str, Any]]):
    """Contexto del evento con claves en español (RF-24).

    Es un objeto libre a propósito: cada tipo de registro guarda sus propios
    datos (mascota, MAC parcial, campos modificados, gramos, faltante, origen) y
    una lista cerrada de claves obligaría a inventar campos vacíos. Los valores
    nunca contienen credenciales, tokens, SSID, correos ni la MAC completa
    (RF-3, RNF-1).
    """


class ActivityLogItem(BaseModel):
    """Registro del historial tal como lo consume la app móvil (RF-26, RF-33)."""

    id: int
    # Instante del servidor en UTC con sufijo `Z`, por ejemplo
    # `2026-10-01T17:00:00Z` (RNF-8).
    created_at: str
    event_type: Optional[str] = None
    # «Sin clasificar» cuando el registro histórico no tiene tipo (RF-41).
    event_label: str
    outcome: Optional[str] = None
    outcome_label: Optional[str] = None
    cause: Optional[str] = None
    cause_label: Optional[str] = None
    description: str
    pet_id: Optional[int] = None
    pet_name: Optional[str] = None
    # Forma parcial `**:AB:1F`; nunca la MAC completa (RNF-1).
    dispenser_mac_masked: Optional[str] = None
    order_id: Optional[int] = None
    requested_grams: Optional[float] = None
    measured_grams: Optional[float] = None
    discounted_grams: Optional[float] = None
    resulting_stock: Optional[float] = None
    retry_count: Optional[int] = None
    context: Optional[ActivityLogContext] = None


class ActivityLogPage(BaseModel):
    """Sobre paginado de la consulta (RF-32)."""

    items: List[ActivityLogItem] = Field(default_factory=list)
    total: int
    page: int
    page_size: int


class ActivityLogCatalogEntry(BaseModel):
    """Entrada del catálogo de filtros: código estable y etiqueta visible."""

    code: str
    label: str


class ActivityLogCatalog(BaseModel):
    """Catálogo de filtros de la pantalla de historial (plan §5.4, RF-31)."""

    event_types: List[ActivityLogCatalogEntry]
    outcomes: List[ActivityLogCatalogEntry]
