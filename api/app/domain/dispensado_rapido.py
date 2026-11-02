"""Reglas puras de la dispensación rápida manual (spec 020).

La cantidad rápida no pasa por el cálculo nutricional: solo se valida el límite
de seguridad, el stock y el estado del dispensador. La ventana de coincidencia
reutiliza el mismo criterio del planificador (10 minutos anteriores, extremo
izquierdo exclusivo y derecho inclusivo) para cubrir las ocurrencias que la
solicitud manual sustituye.

Módulo puro: no usa base de datos, ni FastAPI, ni lee el reloj. El instante y el
stock llegan como parámetros.
"""

import math
from datetime import datetime, time, timedelta
from typing import Any, Iterable, Optional

from app.domain import tiempo
from app.domain.catalogos import ErrorDominio

# Límite de seguridad de la cantidad rápida (RF-1, RF-2).
LIMITE_RAPIDO_GRAMOS = 200.0

# Longitud máxima del identificador de operación que genera la app (RF-14).
LIMITE_OPERACION_ID = 128

# Misma ventana que usa el planificador para encolar una ocurrencia (RF-7).
VENTANA_COINCIDENCIA = tiempo.VENTANA_OCURRENCIA


def _numero(valor: Any) -> Optional[float]:
    """Convierte el valor en un número finito o devuelve `None`."""
    if valor is None or isinstance(valor, bool):
        return None

    if isinstance(valor, (int, float)):
        numero = float(valor)
    elif isinstance(valor, str):
        try:
            numero = float(valor.strip())
        except ValueError:
            return None
    else:
        return None

    return numero if math.isfinite(numero) else None


def normalizar_cantidad_rapida(valor: Any) -> float:
    """Devuelve la cantidad en gramos o rechaza con `cantidad_rapida_invalida`.

    Rechaza texto no numérico, `NaN`, infinitos, booleanos, cero, negativos y
    cualquier valor mayor que 200 g (RF-2).
    """
    numero = _numero(valor)
    if numero is None or numero <= 0 or numero > LIMITE_RAPIDO_GRAMOS:
        raise ErrorDominio("cantidad_rapida_invalida")
    return numero


def normalizar_operation_id(valor: Any) -> str:
    """Devuelve el identificador de operación limpio o lo rechaza (RF-14).

    Exige una cadena no vacía, sin espacios y de hasta 128 caracteres; recorta
    los espacios externos para devolver el texto limpio. No genera el
    identificador: eso es responsabilidad de la app, que lo reutiliza mientras la
    cantidad no cambie.
    """
    if not isinstance(valor, str):
        raise ErrorDominio("operacion_invalida")

    texto = valor.strip()
    if (
        not texto
        or len(texto) > LIMITE_OPERACION_ID
        or any(caracter.isspace() for caracter in texto)
    ):
        raise ErrorDominio("operacion_invalida")
    return texto


def stock_reservado(stock: float, pendientes: Iterable[float]) -> float:
    """Stock actual menos la suma de las solicitudes pendientes (RF-3, RNF-9).

    Nunca devuelve un valor negativo: si las solicitudes pendientes ya suman más
    que el stock, el disponible para una nueva solicitud es 0. El llamador trae
    las cantidades pendientes de la base de datos.
    """
    total = float(stock or 0.0)
    return max(0.0, total - sum(float(cantidad) for cantidad in (pendientes or ())))


def codigo_rechazo(
    cantidad: float,
    stock_reservado: float,
    activo: bool,
    orden_en_curso: bool,
) -> Optional[str]:
    """Primer código de rechazo aplicable, o `None` si la solicitud es válida.

    La cantidad llega ya normalizada: esta función no evalúa su formato (RF-2),
    solo el stock reservado, el estado del dispensador y la orden en curso, en
    ese orden (RF-3 a RF-5).
    """
    if cantidad > stock_reservado:
        return "stock_insuficiente"
    if not activo:
        return "dispensador_desactivado"
    if orden_en_curso:
        return "dispensacion_en_curso"
    return None


def en_ventana_coincidencia(
    ocurrencia: datetime,
    instante_local: datetime,
    ventana: timedelta = VENTANA_COINCIDENCIA,
) -> bool:
    """Indica si la ocurrencia está en `(instante − ventana, instante]`."""
    return instante_local - ventana < ocurrencia <= instante_local


def ocurrencias_en_ventana(
    hora_texto: Any,
    instante_local: datetime,
    ventana: timedelta = VENTANA_COINCIDENCIA,
) -> list[datetime]:
    """Ocurrencias de un horario `HH:MM` dentro de la ventana de coincidencia.

    Se consideran el día en curso y el anterior para cubrir la ventana que cruza
    medianoche. La hora del horario es la hora local del servidor, igual que en
    la spec 014.
    """
    try:
        hora, minuto = (int(parte) for parte in str(hora_texto).split(":")[:2])
        hora_base = time(hour=hora, minute=minuto)
    except (TypeError, ValueError):
        return []

    ocurrencias: list[datetime] = []
    for dia in (instante_local.date(), instante_local.date() - timedelta(days=1)):
        ocurrencia = datetime.combine(dia, hora_base)
        if en_ventana_coincidencia(ocurrencia, instante_local, ventana):
            ocurrencias.append(ocurrencia)
    return ocurrencias
