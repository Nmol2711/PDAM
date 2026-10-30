"""Dominio puro de la cuenta de usuario (spec 015).

Reúne el catálogo de errores de la cuenta, la normalización y el formato del
correo, los límites de la contraseña nueva y el plan de actualización del
perfil. Es la fuente única de validación: los servicios y los endpoints no
duplican ni los textos ni el orden de precedencia (RF-11, RF-12, RF-17, RF-21,
RNF-01).

Módulo puro: sin FastAPI, sin SQLAlchemy, sin red y sin leer variables de
entorno; el instante y la configuración los inyecta el llamador (RNF-04). No
contiene contraseñas, secretos ni claves (RNF-06).
"""

from dataclasses import dataclass
from typing import Optional

# Límites de la contraseña nueva (RF-11): el mínimo se cuenta en caracteres y el
# máximo en bytes UTF-8, que es el límite real del almacenamiento de contraseñas.
MINIMO_CARACTERES_PASSWORD = 8
MAXIMO_BYTES_PASSWORD = 72

# Catálogo de errores de la cuenta: código estable y mensaje visible exacto.
# Los textos son literales de la spec y no admiten variantes (RNF-01);
# `invalid_credentials` es el único mensaje sin punto final.
ERRORES_CUENTA: dict[str, str] = {
    "invalid_email": "Introduce un correo electrónico válido.",
    "weak_password": "La contraseña debe tener al menos 8 caracteres.",
    "password_too_long": "La contraseña es demasiado larga.",
    "empty_update": (
        "No has modificado ningún dato. Escribe un correo nuevo o una "
        "contraseña nueva."
    ),
    "email_already_registered": "El correo electrónico ya está registrado.",
    "invalid_password": "La contraseña no es correcta.",
    "invalid_credentials": "Correo o contraseña incorrectos",
    "unauthorized": "La sesión no es válida. Vuelve a iniciar sesión.",
    "conflict": "No se pudo completar la operación. Inténtalo de nuevo.",
    "server_error": "No se pudo completar la operación. Inténtalo de nuevo.",
}

# Catálogo de estados de la cuenta (RF-06). Es informativo: no habilita ni
# impide ninguna acción de la spec.
ETIQUETA_ACTIVA = "Activa"
ETIQUETA_INACTIVA = "Inactiva"


def normalizar_correo(texto: object) -> str:
    """Devuelve el correo en su forma canónica: sin espacios exteriores y en minúsculas.

    Los espacios interiores se conservan a propósito: un correo con un espacio
    dentro no es válido y la normalización no debe ocultarlo (RF-11, RF-12,
    RF-19). Un valor que no es texto se normaliza a cadena vacía, de modo que
    nunca se propaga un correo inventado.
    """
    if not isinstance(texto, str):
        return ""
    return texto.strip().lower()


def es_correo_valido(correo: object) -> bool:
    """Indica si `correo` tiene formato de correo electrónico (RF-11).

    Las reglas son las de la spec y se resuelven sin dependencias externas
    (RNF-07): exactamente una `@`, parte local no vacía, dominio con al menos
    dos etiquetas separadas por punto y ningún espacio interior. El valor se
    normaliza antes de comprobarlo, así que las mayúsculas y los espacios
    exteriores no afectan al resultado.
    """
    if not isinstance(correo, str):
        return False

    valor = normalizar_correo(correo)
    if not valor or any(caracter.isspace() for caracter in valor):
        return False

    partes = valor.split("@")
    if len(partes) != 2:
        return False

    local, dominio = partes
    if not local or not dominio:
        return False

    # El dominio necesita al menos dos etiquetas y ninguna vacía: ni empieza ni
    # acaba en punto ni contiene puntos consecutivos.
    etiquetas = dominio.split(".")
    return len(etiquetas) >= 2 and all(etiquetas)


def longitud_en_bytes(texto: object) -> int:
    """Devuelve los bytes UTF-8 de `texto` (RF-11, RNF-06).

    El límite de la contraseña se mide en bytes porque es lo que el
    almacenamiento trunca; medirlo en caracteres dejaría pasar contraseñas que
    comparten los primeros 72 bytes.
    """
    if not isinstance(texto, str):
        return 0
    return len(texto.encode("utf-8"))


def validar_password_nueva(password: object) -> Optional[str]:
    """Devuelve el código del catálogo que rechaza la contraseña, o `None`.

    El mínimo de 8 caracteres se comprueba antes que el máximo de 72 bytes
    (RF-11). Una contraseña vacía o ausente es débil: el registro y la
    actualización exigen siempre una contraseña nueva válida.
    """
    if not isinstance(password, str) or len(password) < MINIMO_CARACTERES_PASSWORD:
        return "weak_password"

    if longitud_en_bytes(password) > MAXIMO_BYTES_PASSWORD:
        return "password_too_long"

    return None


@dataclass(frozen=True)
class PlanActualizacion:
    """Resultado de validar una actualización de perfil.

    `error` es el código del catálogo que impide aplicar el cambio (incluido
    `empty_update`) o `None` si la actualización es aplicable. `correo_nuevo` es
    siempre el correo normalizado, también cuando hay error, para que el
    llamador no tenga que volver a normalizarlo. Con error, `cambia_correo` y
    `cambia_password` son falsos: no se aplica nada.
    """

    error: Optional[str]
    correo_nuevo: str
    cambia_correo: bool
    cambia_password: bool

    @property
    def valido(self) -> bool:
        """Indica si la actualización se puede aplicar."""
        return self.error is None


def resolver_actualizacion(
    correo_actual: object,
    correo_nuevo: object,
    password_nueva: object,
) -> PlanActualizacion:
    """Decide qué cambia en el perfil y con qué error, si lo hay (RF-11).

    El orden de precedencia es `invalid_email` → `empty_update` →
    `weak_password` → `password_too_long`, el mismo de la matriz de la spec. La
    confirmación de la contraseña no viaja al servidor y por eso no forma parte
    de la firma. Un correo que solo difiere del actual en mayúsculas o en
    espacios exteriores cuenta como igual, porque ambos se comparan
    normalizados. La unicidad del correo no se resuelve aquí: depende de la base
    de datos y la comprueba el servicio (RF-12).
    """
    actual = normalizar_correo(correo_actual)
    nuevo = normalizar_correo(correo_nuevo)

    if not es_correo_valido(nuevo):
        return PlanActualizacion("invalid_email", nuevo, False, False)

    cambia_correo = nuevo != actual
    cambia_password = password_nueva is not None and password_nueva != ""

    if not cambia_correo and not cambia_password:
        return PlanActualizacion("empty_update", nuevo, False, False)

    if cambia_password:
        error = validar_password_nueva(password_nueva)
        if error is not None:
            return PlanActualizacion(error, nuevo, False, False)

    return PlanActualizacion(None, nuevo, cambia_correo, cambia_password)


def etiqueta_estado(is_active: object) -> str:
    """Etiqueta visible del estado de la cuenta a partir de `is_active` (RF-06)."""
    return ETIQUETA_ACTIVA if is_active else ETIQUETA_INACTIVA


def inicial_de_correo(correo: object) -> str:
    """Inicial del avatar: primera letra del correo normalizado, en mayúsculas.

    Sin correo devuelve cadena vacía y no lanza excepción: el avatar queda vacío
    antes que mostrar un dato de relleno, que la spec prohíbe (RF-07).
    """
    valor = normalizar_correo(correo)
    if not valor:
        return ""
    return valor[0].upper()
