"""Catálogos cerrados del registro de actividad (spec 014).

Una sola fuente para los códigos que se guardan en `logs`, las etiquetas que se
muestran en español y los mensajes de error visibles. Cualquier valor fuera de
estos catálogos se rechaza (RNF-7): ampliarlos exige modificar la spec.

Módulo puro: sin base de datos, sin FastAPI y sin lectura del reloj.
"""

from dataclasses import dataclass
from typing import Optional

# Resultados posibles de un registro.
EXITO = "success"
FALLO = "failure"

# Origen de una causa: la declara el dispositivo en su reporte o la asigna el
# servidor al cerrar la orden.
ORIGEN_REPORTE = "reporte"
ORIGEN_SERVIDOR = "servidor"

# Etiqueta de presentación de los registros históricos sin tipo, resultado ni
# causa. No es un tipo del catálogo y no es filtrable (RF-41).
ETIQUETA_SIN_CLASIFICAR = "Sin clasificar"

RESULTADOS: dict[str, str] = {
    EXITO: "Éxito",
    FALLO: "Fallo",
}

TIPOS_EVENTO: dict[str, str] = {
    "pet_created": "Mascota creada",
    "pet_updated": "Mascota modificada",
    "pet_deleted": "Mascota eliminada",
    "dispenser_linked": "Dispensador vinculado",
    "dispenser_updated": "Dispensador modificado",
    "dispenser_unlinked": "Dispensador desvinculado",
    "dispenser_wifi_reset": "WiFi del dispensador reiniciado",
    "feeding_dispensed": "Comida dispensada",
    "dispenser_refilled": "Dispensador reabastecido",
}


@dataclass(frozen=True)
class Causa:
    """Causa del catálogo con su etiqueta, su resultado y quién la asigna."""

    etiqueta: str
    resultado: str
    origen: str


CAUSAS: dict[str, Causa] = {
    "objetivo_alcanzado": Causa("Objetivo alcanzado", EXITO, ORIGEN_REPORTE),
    "objetivo_no_alcanzado": Causa("Objetivo no alcanzado", FALLO, ORIGEN_REPORTE),
    "atasco_no_resuelto": Causa("Atasco no resuelto", FALLO, ORIGEN_REPORTE),
    "sensor_no_disponible": Causa("Sensor no disponible", FALLO, ORIGEN_REPORTE),
    "fallo_sensor_dispensacion": Causa(
        "Fallo del sensor durante la dispensación", FALLO, ORIGEN_REPORTE
    ),
    "orden_invalida": Causa("Orden inválida", FALLO, ORIGEN_REPORTE),
    "entrega_incompleta": Causa("Entrega incompleta", FALLO, ORIGEN_SERVIDOR),
    "sin_reporte": Causa("Sin reporte", FALLO, ORIGEN_SERVIDOR),
    "orden_cerrada": Causa("Orden cerrada", FALLO, ORIGEN_SERVIDOR),
    "orden_desconocida": Causa("Orden desconocida", FALLO, ORIGEN_SERVIDOR),
    "supera_capacidad": Causa("Supera la capacidad", FALLO, ORIGEN_SERVIDOR),
    "cantidad_invalida": Causa("Cantidad inválida", FALLO, ORIGEN_SERVIDOR),
}

# Subconjunto de causas que el dispositivo puede declarar como motivo de su
# reporte de fin de ciclo (RF-14, RF-21). Las causas del servidor nunca llegan
# desde el dispositivo.
MOTIVOS_REPORTE: frozenset[str] = frozenset(
    codigo
    for codigo, causa in CAUSAS.items()
    if causa.origen == ORIGEN_REPORTE
)

# Catálogo de errores de negocio: código estable y mensaje visible exacto. Se
# devuelven con HTTP 400 en `detail={code,message}`; el 5xx queda reservado a
# los fallos de escritura (RF-1).
MENSAJES_ERROR: dict[str, str] = {
    "cantidad_invalida": "La cantidad debe ser un número mayor que cero.",
    "supera_capacidad": (
        "La cantidad supera la capacidad máxima de 5000 g del dispensador."
    ),
    "tipo_evento_invalido": "El tipo de evento no pertenece al catálogo.",
    "resultado_invalido": "El resultado no pertenece al catálogo.",
    "rango_fechas_invalido": (
        "El rango de fechas no es válido: revise el orden de los límites y el "
        "desplazamiento horario."
    ),
    "pagina_invalida": "El número de página debe ser 1 o mayor.",
    "tamano_pagina_invalido": "El tamaño de página debe estar entre 1 y 100.",
    "motivo_invalido": "El motivo del reporte no pertenece al catálogo.",
    "mac_no_registrada": "El dispensador no está registrado.",
    "orden_desconocida": (
        "La orden indicada no existe para el dispensador que reporta."
    ),
    "stock_fuera_de_rango": (
        "El stock resultante quedaría fuera del intervalo de 0 a 5000 g."
    ),
}


class ErrorDominio(Exception):
    """Rechazo de negocio expresado con el código y el mensaje del catálogo.

    Los servicios lo convierten en HTTP 400 con `detail=error.detail`, de modo
    que ningún rechazo de negocio responde 422 (RF-12, RF-21, RF-31, RF-32).
    """

    def __init__(self, code: str):
        if code not in MENSAJES_ERROR:
            # Un código desconocido es un fallo de programación, no de negocio:
            # nunca debe llegar al cliente como rechazo del catálogo.
            raise ValueError(f"Código de error fuera del catálogo: {code!r}")

        self.code = code
        self.message = MENSAJES_ERROR[code]
        super().__init__(self.message)

    @property
    def detail(self) -> dict[str, str]:
        """Cuerpo del error para la respuesta HTTP 400."""
        return {"code": self.code, "message": self.message}


def es_tipo_valido(codigo: object) -> bool:
    """Indica si `codigo` es un tipo de evento del catálogo (RF-31, RNF-7)."""
    return isinstance(codigo, str) and codigo in TIPOS_EVENTO


def es_resultado_valido(codigo: object) -> bool:
    """Indica si `codigo` es un resultado del catálogo (RF-31, RNF-7)."""
    return isinstance(codigo, str) and codigo in RESULTADOS


def es_causa_valida(codigo: object) -> bool:
    """Indica si `codigo` es una causa del catálogo, de cualquier origen."""
    return isinstance(codigo, str) and codigo in CAUSAS


def es_causa_de_reporte(codigo: object) -> bool:
    """Indica si `codigo` puede llegar como motivo de un reporte (RF-21)."""
    return isinstance(codigo, str) and codigo in MOTIVOS_REPORTE


def etiqueta_tipo_evento(codigo: Optional[str]) -> str:
    """Etiqueta visible del tipo; `None` es un registro histórico (RF-41)."""
    if codigo is None:
        return ETIQUETA_SIN_CLASIFICAR
    return TIPOS_EVENTO[codigo]


def etiqueta_resultado(codigo: Optional[str]) -> Optional[str]:
    """Etiqueta visible del resultado; `None` si el registro no lo tiene."""
    if codigo is None:
        return None
    return RESULTADOS[codigo]


def etiqueta_causa(codigo: Optional[str]) -> Optional[str]:
    """Etiqueta visible de la causa; `None` si el registro no la tiene."""
    if codigo is None:
        return None
    return CAUSAS[codigo].etiqueta


def resultado_para_motivo(
    motivo: str,
    medidos: Optional[float] = None,
    solicitados: Optional[float] = None,
) -> tuple[str, str]:
    """Traduce el motivo de un reporte a `(resultado, causa)`.

    `objetivo_alcanzado` solo produce éxito si los medidos alcanzan los
    solicitados guardados en la orden; si faltan o son menores, el cierre es
    fallo con causa `entrega_incompleta` (RF-15, RF-16). Cualquier otro motivo
    del reporte produce fallo con la causa homónima (RF-17). Un motivo fuera
    del catálogo se rechaza con `motivo_invalido` (RF-21, RNF-7).
    """
    if not es_causa_de_reporte(motivo):
        raise ErrorDominio("motivo_invalido")

    if motivo == "objetivo_alcanzado":
        alcanzado = (
            medidos is not None
            and solicitados is not None
            and medidos >= solicitados
        )
        return (EXITO, motivo) if alcanzado else (FALLO, "entrega_incompleta")

    return FALLO, motivo
