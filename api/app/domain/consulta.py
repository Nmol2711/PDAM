"""Validación de la consulta del historial (spec 014).

Filtros combinables en conjunción, paginación sin recortes silenciosos y un
orden estable. Los parámetros llegan de la API como texto y se validan aquí,
en dominio, para que cualquier rechazo sea un error del catálogo (HTTP 400) y
nunca un 422 (RF-30, RF-31, RF-32, RNF-7).

Módulo puro: no construye consultas ni conoce SQLAlchemy.
"""

from datetime import datetime
from typing import NamedTuple, Optional

from app.domain.catalogos import ErrorDominio, es_resultado_valido, es_tipo_valido
from app.domain.tiempo import a_utc_naive, parsear_instante_explicito

PAGINA_POR_DEFECTO = 1
TAMANO_POR_DEFECTO = 50
TAMANO_MAXIMO = 100

# Orden de presentación: del más reciente al más antiguo, con desempate por
# identificador para que la paginación sea estable (RF-26).
ORDEN_ESTABLE = "created_at DESC, id DESC"


class ConsultaValidada(NamedTuple):
    """Consulta del historial ya validada y lista para el servicio."""

    tipo_evento: Optional[str]
    resultado: Optional[str]
    desde: Optional[datetime]
    hasta: Optional[datetime]
    pagina: int
    tamano: int


def validar_consulta(
    tipo_evento: object = None,
    resultado: object = None,
    desde: object = None,
    hasta: object = None,
    pagina: object = None,
    tamano: object = None,
) -> ConsultaValidada:
    """Valida la consulta completa en el orden de rechazo del contrato §5.3.

    Precedencia: `rango_fechas_invalido` → `tipo_evento_invalido` →
    `resultado_invalido` → `pagina_invalida` → `tamano_pagina_invalido`. Así el
    cliente recibe siempre el mismo código para la misma combinación inválida.
    """
    desde_utc, hasta_utc = validar_filtros(tipo_evento, resultado, desde, hasta)
    pagina_validada, tamano_validado = normalizar_paginacion(pagina, tamano)
    return ConsultaValidada(
        tipo_evento=tipo_evento,
        resultado=resultado,
        desde=desde_utc,
        hasta=hasta_utc,
        pagina=pagina_validada,
        tamano=tamano_validado,
    )


def validar_filtros(
    tipo_evento: object = None,
    resultado: object = None,
    desde: object = None,
    hasta: object = None,
) -> tuple[Optional[datetime], Optional[datetime]]:
    """Valida tipo, resultado y rango; devuelve los límites en UTC naive.

    Un límite sin sufijo `Z` y sin desplazamiento, o un instante inválido, se
    rechaza con `rango_fechas_invalido`; la fecha final anterior a la inicial,
    también (RF-30, RF-31). Los filtros de catálogo se aplican en conjunción y
    nunca corrigen el valor recibido.
    """
    desde_utc = _limite(desde)
    hasta_utc = _limite(hasta)

    if desde_utc is not None and hasta_utc is not None and hasta_utc < desde_utc:
        raise ErrorDominio("rango_fechas_invalido")

    if tipo_evento is not None and not es_tipo_valido(tipo_evento):
        raise ErrorDominio("tipo_evento_invalido")

    if resultado is not None and not es_resultado_valido(resultado):
        raise ErrorDominio("resultado_invalido")

    return desde_utc, hasta_utc


def normalizar_paginacion(
    pagina: object = None, tamano: object = None
) -> tuple[int, int]:
    """Devuelve `(pagina, tamano)` o rechaza los valores fuera de rango.

    Por defecto 50 ítems por página y un máximo de 100. Una página menor que 1
    responde `pagina_invalida` y un tamaño fuera de 1 a 100 responde
    `tamano_pagina_invalido`; nunca se recorta el valor en silencio (RF-32).
    """
    pagina_validada = (
        PAGINA_POR_DEFECTO if pagina is None else _entero(pagina, "pagina_invalida")
    )
    if pagina_validada < 1:
        raise ErrorDominio("pagina_invalida")

    tamano_validado = (
        TAMANO_POR_DEFECTO if tamano is None else _entero(tamano, "tamano_pagina_invalido")
    )
    if not 1 <= tamano_validado <= TAMANO_MAXIMO:
        raise ErrorDominio("tamano_pagina_invalido")

    return pagina_validada, tamano_validado


def total_paginas(total: int, tamano: int) -> int:
    """Número de páginas para `total` ítems, al menos una (RF-32, RF-33).

    Con cero resultados se informa «Página 1 de 1», nunca «1 de 0», para que la
    interfaz y la caché local compartan la misma regla.
    """
    if total <= 0:
        return 1
    return max(1, (total + tamano - 1) // tamano)


def orden_estable() -> str:
    """Cláusula de orden estable de la consulta (RF-26)."""
    return ORDEN_ESTABLE


def _limite(valor: object) -> Optional[datetime]:
    """Convierte un límite recibido a UTC naive, exigiendo desplazamiento."""
    if valor is None:
        return None
    if isinstance(valor, datetime):
        if valor.tzinfo is None or valor.utcoffset() is None:
            raise ErrorDominio("rango_fechas_invalido")
        return a_utc_naive(valor)
    return a_utc_naive(parsear_instante_explicito(valor))


def _entero(valor: object, codigo_error: str) -> int:
    """Convierte un parámetro de paginación sin aceptar truncamientos."""
    try:
        return int(str(valor).strip())
    except (TypeError, ValueError):
        raise ErrorDominio(codigo_error) from None
