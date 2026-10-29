"""Cálculo del stock del servidor (spec 014).

El stock siempre se calcula en el servidor y vive en el intervalo cerrado de 0
a 5000 g (RF-22, RF-23). El descuento al cerrar una orden con éxito es lo medido
acotado entre 0 y el stock disponible, nunca lo solicitado (RF-15). El
reabastecimiento es la única operación que suma, y lo hace con las mismas
garantías de intervalo (RF-11, RF-12).

Módulo puro: recibe el stock como parámetro y no accede a la base de datos.
"""

import math
from typing import Any, Optional

from app.domain.catalogos import ErrorDominio

# Capacidad máxima del depósito, en gramos.
CAPACIDAD_MAXIMA_GRAMOS = 5000.0

# Unidades admitidas en el reabastecimiento: los gramos son la unidad del
# servidor y el kilogramo se convierte antes de validar la capacidad.
UNIDADES_EN_GRAMOS = {"g", "gr", "gramo", "gramos"}
UNIDADES_EN_KILOGRAMOS = {"kg", "kilo", "kilos", "kilogramo", "kilogramos"}


def calcular_descuento(
    medidos: Optional[float], stock_disponible: Optional[float]
) -> tuple[float, float]:
    """Devuelve `(descontados, faltante)` para los gramos medidos.

    Los descontados son lo medido acotado entre 0 y el stock disponible, de modo
    que el stock resultante nunca es negativo. El faltante es lo que salió del
    depósito sin poder descontarse y queda en el contexto del registro, sin
    generar stock negativo (RF-15, RF-22, RF-24).

    Sin medidos (sensor no disponible) no hay descuento; unos medidos negativos
    tampoco descuentan.
    """
    disponible = max(0.0, float(stock_disponible or 0))

    if medidos is None or medidos <= 0:
        return 0.0, 0.0

    if medidos >= disponible:
        return disponible, float(medidos) - disponible

    return float(medidos), 0.0


def stock_fuera_de_rango(stock: object) -> bool:
    """Indica si `stock` sale del intervalo cerrado de 0 a 5000 g (RF-22).

    Un valor no numérico o ausente también cuenta como fuera de rango: el stock
    del servidor siempre es un número dentro de la capacidad del depósito.
    """
    if stock is None:
        return True

    try:
        valor = float(stock)
    except (TypeError, ValueError):
        return True

    return valor < 0.0 or valor > CAPACIDAD_MAXIMA_GRAMOS


def aplicar_descuento_acotado(
    stock_disponible: Optional[float], medidos: Optional[float]
) -> tuple[float, float, float]:
    """Aplica el descuento del cierre y devuelve `(descontados, faltante, stock)`.

    Es la operación con la que una orden cerrada con éxito modifica el stock:
    descuenta lo medido acotado entre 0 y el disponible y devuelve el stock
    resultante. Si el resultante cayera fuera de 0..5000 g, la operación se
    rechaza con `stock_fuera_de_rango` y sin aplicar cambios (RF-22); el llamador
    es quien confirma la transacción, de modo que un rechazo no deja descuento
    parcial (RF-1).
    """
    disponible = float(stock_disponible or 0.0)
    descontados, faltante = calcular_descuento(medidos, disponible)
    resultante = disponible - descontados

    if stock_fuera_de_rango(resultante):
        raise ErrorDominio("stock_fuera_de_rango")

    return descontados, faltante, resultante


def normalizar_gramos(cantidad: Any, unidad: Any = "g") -> float:
    """Convierte la cantidad recibida a gramos o rechaza con `cantidad_invalida`.

    Admitir cualquier tipo de entrada es deliberado: la cantidad se valida en el
    servicio para que un valor cero, negativo o no numérico produzca un 400 del
    catálogo y nunca un 422 del esquema (RF-12). Un booleano no es una cantidad,
    y un número no finito tampoco: ambos son rechazos de negocio.
    """
    if isinstance(cantidad, bool) or cantidad is None:
        raise ErrorDominio("cantidad_invalida")

    if isinstance(cantidad, (int, float)):
        gramos = float(cantidad)
    elif isinstance(cantidad, str):
        try:
            gramos = float(cantidad.strip())
        except ValueError:
            raise ErrorDominio("cantidad_invalida")
    else:
        raise ErrorDominio("cantidad_invalida")

    if not math.isfinite(gramos) or gramos <= 0:
        raise ErrorDominio("cantidad_invalida")

    texto_unidad = unidad.strip().lower() if isinstance(unidad, str) else ""
    if texto_unidad in UNIDADES_EN_KILOGRAMOS:
        gramos *= 1000.0
    elif texto_unidad and texto_unidad not in UNIDADES_EN_GRAMOS:
        # Una unidad desconocida no se interpreta a ciegas: la cantidad no es
        # convertible y el reabastecimiento se rechaza como inválido.
        raise ErrorDominio("cantidad_invalida")

    return gramos


def aplicar_reabastecimiento(
    stock_actual: Optional[float], cantidad: Any, unidad: Any = "g"
) -> float:
    """Suma un reabastecimiento válido y devuelve el stock resultante.

    El resultante debe seguir dentro de 0..5000 g: se acepta el límite exacto y se
    rechaza con `supera_capacidad` cualquier suma que lo supere, sin modificar el
    stock (RF-11, RF-12, RF-22). La cantidad inválida se rechaza con
    `cantidad_invalida` antes de mirar la capacidad.
    """
    gramos = normalizar_gramos(cantidad, unidad)
    disponible = max(0.0, float(stock_actual or 0.0))
    resultante = disponible + gramos

    if stock_fuera_de_rango(resultante):
        raise ErrorDominio("supera_capacidad")

    return resultante
