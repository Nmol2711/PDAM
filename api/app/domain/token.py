"""Dominio puro de los claims del token de sesión (spec 015).

Construye y valida los claims del token sin firmar ni verificar la firma: eso
ocurre en `app/core/security.py` y en la dependencia de identidad. Aquí solo se
decide qué lleva el token (`sub` con la identidad estable de la cuenta, `jti`,
`iat` y `exp`) y si un token ya decodificado sigue siendo utilizable (RF-10,
RF-19).

Módulo puro: el instante se recibe como parámetro, la vigencia la inyecta el
llamador desde su configuración y no se lee ningún secreto ni variable de
entorno (RNF-04, RNF-06).
"""

from datetime import datetime, timezone
from typing import Iterable, Mapping, Optional
from uuid import uuid4

from app.domain.cuenta import normalizar_correo
from app.domain.tiempo import a_utc_naive

# Minutos de vigencia por defecto del token de sesión. Es solo el valor de
# partida del dominio: el llamador inyecta el real desde su configuración, de
# modo que este módulo no lee la configuración de la aplicación.
MINUTOS_TOKEN = 60 * 24 * 30


def nuevo_jti() -> str:
    """Devuelve un identificador irrepetible para el token (RF-10).

    El `jti` es lo que permite revocar solo el token de una petición sin cerrar
    las demás sesiones de la cuenta.
    """
    return uuid4().hex


def _a_epoch(instante: datetime) -> int:
    """Segundos desde la época de un instante UTC (naive o con zona)."""
    return int(a_utc_naive(instante).replace(tzinfo=timezone.utc).timestamp())


def construir_claims(
    public_id: str,
    jti: str,
    ahora: datetime,
    minutos: int = MINUTOS_TOKEN,
) -> dict:
    """Devuelve los claims del token emitido en `ahora` con vigencia `minutos`.

    `sub` es la identidad estable de la cuenta, no su correo, para que liberar y
    volver a registrar el mismo correo no rehabilite un token anterior (RF-19).
    `iat` y `exp` son segundos desde la época calculados desde el instante
    recibido: el dominio nunca lee el reloj.
    """
    emision = _a_epoch(ahora)
    return {
        "sub": public_id,
        "jti": jti,
        "iat": emision,
        "exp": emision + int(minutos * 60),
    }


def claims_utilizables(
    payload: Optional[Mapping],
    ahora: datetime,
    revocados: Optional[Iterable[str]] = None,
) -> bool:
    """Indica si un token ya decodificado sigue siendo utilizable (RF-05, RF-19).

    La firma se verifica fuera. Aquí se exige identidad (`sub`) y `jti`, que
    `exp` no haya llegado —en el instante exacto de caducidad el token ya no
    vale— y que el `jti` no esté en el conjunto de revocados. Cualquier payload
    con forma inesperada se rechaza en vez de lanzar una excepción. Un `str` no
    es una colección de revocados: `frozenset("abc")` lo trocearía en caracteres,
    así que se falla cerrado y el token no se da por utilizable.
    """
    if not isinstance(payload, Mapping):
        return False

    if isinstance(revocados, str):
        return False

    sub = payload.get("sub")
    jti = payload.get("jti")
    if not isinstance(sub, str) or not sub.strip():
        return False
    if not isinstance(jti, str) or not jti.strip():
        return False

    exp = payload.get("exp")
    # Un booleano es un entero en Python y no es un instante válido.
    if isinstance(exp, bool) or not isinstance(exp, (int, float)):
        return False
    if exp <= _a_epoch(ahora):
        return False

    return jti not in frozenset(revocados or ())


def debe_revocar_token_anterior(correo_actual: object, correo_nuevo: object) -> bool:
    """Indica si el cambio de perfil obliga a revocar el token usado (RF-10).

    Solo se revoca cuando el correo cambia comparado en forma normalizada: un
    cambio que únicamente afecta a mayúsculas o a espacios exteriores es el
    mismo correo y conserva el token. Un correo nuevo vacío no es un cambio
    aplicable.
    """
    nuevo = normalizar_correo(correo_nuevo)
    if not nuevo:
        return False
    return nuevo != normalizar_correo(correo_actual)
