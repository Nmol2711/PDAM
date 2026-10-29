"""Normalización y validación de la dirección MAC de un dispensador.

Funciones puras: no acceden a la base de datos ni dependen de otros módulos de
`app`. La forma canónica es la de 12 dígitos hexadecimales en mayúsculas y sin
separadores (`AABBCCDDEEFF`), de modo que todos los formatos equivalentes
(`AA:BB:CC:DD:EE:FF`, `aa-bb-cc-dd-ee-ff`, `aa bb cc dd ee ff`, `aa.bb.cc.dd.ee.ff`)
colapsen en un único valor comparable (RF-02, RNF-08).
"""

import re

from fastapi import HTTPException, status

# Separadores admitidos en la dirección que introduce o envía el hardware.
SEPARADORES = {":", "-", ".", " "}

# Forma canónica: exactamente 12 dígitos hexadecimales en mayúsculas.
PATRON_MAC_NORMALIZADA = r"[0-9A-F]{12}"

# Prefijo literal de la MAC parcial: exactamente dos asteriscos, idéntico para
# cualquier dirección sin importar cuántos octetos tenga la original.
PREFIJO_MAC_PARCIAL = "**"

# Solo dígitos hexadecimales en mayúsculas: lo que deja `normalize_mac`.
PATRON_HEXADECIMAL = r"[0-9A-F]+"

# Forma de una MAC ya enmascarada: el prefijo literal y los dos últimos octetos,
# o el prefijo suelto cuando no había octetos que conservar.
PATRON_MAC_PARCIAL = r"\*\*(?::[0-9A-F]{2}:[0-9A-F]{2})?"

# Códigos de error estables del contrato de la API (AC-4). El cliente clasifica
# por `detail.code`, nunca por el texto del mensaje.
CODE_MAC_ALREADY_REGISTERED = "mac_already_registered"
CODE_MAC_IN_USE = "mac_in_use"
CODE_MAC_INVALID_FORMAT = "mac_invalid_format"
CODE_PET_ALREADY_HAS_DISPENSER = "pet_already_has_dispenser"

# Copy en español de los rechazos (RF-16). Los mensajes de conflicto son
# genéricos: no mencionan mascota, usuario ni identificador del dispensador.
MENSAJE_MAC_ALREADY_REGISTERED = (
    "Este dispensador ya está registrado en el sistema. Escanea el código QR "
    "del dispensador correcto o revisa con qué cuenta está vinculado."
)
MENSAJE_MAC_IN_USE = (
    "La dirección indicada ya está siendo usada por otro dispensador. "
    "Verifica la dirección e inténtalo de nuevo."
)
MENSAJE_MAC_INVALID_FORMAT = (
    "La dirección del dispensador no tiene un formato válido. Debe tener 12 "
    "caracteres hexadecimales, por ejemplo AA:BB:CC:DD:EE:FF."
)
MENSAJE_PET_ALREADY_HAS_DISPENSER = "Esta mascota ya posee un dispensador registrado."


def normalize_mac(raw: str | None) -> str:
    """Devuelve la forma canónica de `raw` sin separadores y en mayúsculas.

    Tolera `None`, la cadena vacía y valores que no son `str`: en esos casos
    devuelve una cadena vacía, que `is_valid_normalized_mac` rechaza.
    """
    if not raw:
        return ""

    return "".join(caracter for caracter in str(raw) if caracter not in SEPARADORES).upper()


def is_valid_normalized_mac(valor: str | None) -> bool:
    """Indica si `valor` ya está en la forma canónica.

    No normaliza: exige 12 hexadecimales en mayúsculas sin separadores, por eso
    hay que pasar antes por `normalize_mac`.
    """
    if not isinstance(valor, str):
        return False

    return re.fullmatch(PATRON_MAC_NORMALIZADA, valor) is not None


def es_mac_parcial(valor: str | None) -> bool:
    """Indica si `valor` ya está en la forma enmascarada `**:AB:1F` (o `**`).

    Se usa para no volver a enmascarar una instantánea que ya guarda la MAC
    parcial: `mask_mac` es idempotente y una segunda pasada la conserva tal cual
    en lugar de degradarla al prefijo suelto (RF-3, RNF-1).
    """
    if not isinstance(valor, str):
        return False

    return (
        re.fullmatch(PATRON_MAC_PARCIAL, valor.strip(), re.IGNORECASE) is not None
    )


def mask_mac(raw: str | None) -> str:
    """Devuelve la MAC parcial de `raw`, con el formato `**:AB:1F`.

    Normaliza primero con el mismo criterio que el resto del sistema y conserva
    solo los dos últimos octetos, en mayúsculas y separados por dos puntos. El
    prefijo es siempre el literal `**`, aunque la dirección original tenga más
    octetos, de modo que la MAC completa nunca se guarda ni se devuelve
    (RF-3, RNF-1).

    Si no hay al menos dos octetos hexadecimales no hay nada que mostrar y
    devuelve solo el prefijo, sin inventar octetos. La operación es idempotente:
    una dirección ya enmascarada se devuelve tal cual, de modo que una
    instantánea parcial (la de una orden cuyo dispensador se eliminó) no se
    convierte en el prefijo suelto al registrarla otra vez.
    """
    if es_mac_parcial(raw):
        return raw.strip().upper()

    normalizada = normalize_mac(raw)

    if len(normalizada) < 4 or re.fullmatch(PATRON_HEXADECIMAL, normalizada) is None:
        return PREFIJO_MAC_PARCIAL

    return f"{PREFIJO_MAC_PARCIAL}:{normalizada[-4:-2]}:{normalizada[-2:]}"


def validate_mac_or_raise(raw: str | None) -> str:
    """Normaliza `raw` y devuelve la forma canónica.

    Si el formato no es válido lanza `HTTPException` 400 con
    `detail={"code": "mac_invalid_format", "message": ...}` (RF-06, AC-2), que es
    distinguible del 409 de los conflictos de MAC (DO-5).
    """
    normalizada = normalize_mac(raw)

    if not is_valid_normalized_mac(normalizada):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": CODE_MAC_INVALID_FORMAT,
                "message": MENSAJE_MAC_INVALID_FORMAT,
            },
        )

    return normalizada