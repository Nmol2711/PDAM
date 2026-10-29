"""Instantes, plazos y tolerancias del servidor (spec 014).

El servidor trabaja siempre en UTC (RNF-8): los límites del filtro de fechas
llegan como ISO 8601 con desplazamiento explícito o sufijo `Z` y se convierten
aquí; las fechas guardadas son UTC sin zona. El reloj se inyecta como parámetro
en los servicios y solo `ahora_utc` lo lee.

Módulo puro: no usa base de datos ni dependencias externas (RNF-4). La zona
horaria local del servidor solo interviene en `a_local_naive`, que interpreta la
hora de los horarios de comida; el resto de instantes, plazos y registros son
UTC (RNF-8).
"""

from datetime import datetime, timedelta, timezone, tzinfo
from typing import Optional

from app.domain.catalogos import ErrorDominio

# Plazo de una orden de dispensación desde su entrega (RF-19).
PLAZO_ORDEN = timedelta(minutes=5)

# Tolerancia inclusiva después de cumplirse el plazo: un reporte recibido en
# `entregada_en + PLAZO_ORDEN + TOLERANCIA` sigue dentro del plazo (RF-20).
TOLERANCIA = timedelta(seconds=1)

# Periodicidad del barrido de vencimientos (RNF-3).
INTERVALO_BARRIDO = timedelta(seconds=30)

# Ventana en la que una comida programada cuenta como ocurrencia del barrido en
# curso. Conserva el margen de 10 minutos que ya usaba el planificador anterior:
# la ocurrencia de las 08:00 se encola en el primer barrido entre 08:00 y 08:10,
# una sola vez (RF-25).
VENTANA_OCURRENCIA = timedelta(minutes=10)


def ahora_utc() -> datetime:
    """Instante actual del servidor con zona UTC."""
    return datetime.now(timezone.utc)


def a_utc_naive(instante: datetime) -> datetime:
    """Convierte `instante` a UTC y le quita la zona.

    Los instantes con zona se convierten a UTC; los naive se consideran ya en
    UTC, que es como se guardan en SQLite (RNF-8).
    """
    if instante.tzinfo is None or instante.utcoffset() is None:
        return instante
    return instante.astimezone(timezone.utc).replace(tzinfo=None)


def a_local_naive(instante: datetime, zona: Optional[tzinfo] = None) -> datetime:
    """Convierte un instante UTC en la hora local del servidor, sin zona.

    Solo se usa para interpretar la hora de los horarios de comida: esa hora es
    del reloj local del servidor, mientras que las órdenes, los plazos y los
    registros siguen en UTC (RNF-8). Un instante naive se considera UTC, igual
    que en `a_utc_naive`, para que los servicios conserven un único criterio.

    `zona` permite inyectar el desplazamiento de forma explícita en las pruebas
    (por ejemplo, un servidor en UTC-05 o UTC+02) sin depender de la zona del
    equipo que ejecuta la suite. Sin argumento se usa la zona local vigente.
    """
    return (
        a_utc_naive(instante)
        .replace(tzinfo=timezone.utc)
        .astimezone(zona)
        .replace(tzinfo=None)
    )


def a_texto_utc(instante: datetime) -> str:
    """Devuelve `instante` como texto ISO 8601 en UTC con sufijo `Z`.

    Es la forma en que la consulta del historial devuelve `created_at` (RNF-8,
    plan §5.3): el registro se guarda en UTC sin zona y el cliente recibe el
    desplazamiento explícito. Sin fracciones de segundo cuando son cero, para
    que la respuesta sea la del ejemplo del contrato.
    """
    return f"{a_utc_naive(instante).isoformat()}Z"


def parsear_instante_explicito(texto: object) -> datetime:
    """Convierte un instante ISO 8601 con desplazamiento explícito a UTC.

    Acepta `Z` como `+00:00` y cualquier desplazamiento `±HH:MM`, con o sin
    fracciones de segundo. Rechaza un texto sin sufijo `Z` y sin desplazamiento
    —nunca asume una zona— y cualquier instante inválido, con el código
    `rango_fechas_invalido` (RF-30, RF-31). El resultado conserva la zona UTC
    para comparar instantes; `a_utc_naive` lo adapta antes de guardarlo.
    """
    if not isinstance(texto, str) or not texto.strip():
        raise ErrorDominio("rango_fechas_invalido")

    valor = texto.strip()
    if valor.endswith(("Z", "z")):
        valor = f"{valor[:-1]}+00:00"

    try:
        instante = datetime.fromisoformat(valor)
    except ValueError:
        raise ErrorDominio("rango_fechas_invalido") from None

    if instante.tzinfo is None or instante.utcoffset() is None:
        raise ErrorDominio("rango_fechas_invalido")

    return instante.astimezone(timezone.utc)


def limite_del_plazo(entregada_en: datetime) -> datetime:
    """Último instante que todavía cuenta como dentro del plazo (inclusivo)."""
    return a_utc_naive(entregada_en) + PLAZO_ORDEN + TOLERANCIA


def dentro_del_plazo(entregada_en: datetime, ahora: datetime) -> bool:
    """Indica si `ahora` no supera el plazo más la tolerancia (inclusivo)."""
    return a_utc_naive(ahora) <= limite_del_plazo(entregada_en)


def plazo_vencido(entregada_en: datetime, ahora: datetime) -> bool:
    """Indica si `ahora` supera el plazo más la tolerancia (exclusivo).

    Es el complemento exacto de `dentro_del_plazo`: en el límite exacto el
    plazo no está vencido (RF-19, RF-20).
    """
    return a_utc_naive(ahora) > limite_del_plazo(entregada_en)
